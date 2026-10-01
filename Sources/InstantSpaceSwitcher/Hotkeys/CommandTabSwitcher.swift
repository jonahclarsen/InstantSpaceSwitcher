import AppKit
import ApplicationServices
import Carbon
import ISS

@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// The native chooser receives every key except its final commit event. Keeping
// this routing separate makes it possible to verify that we preserve its controls.
struct NativeCommandTabInput {
  enum Action: Equatable { case pass, holdRelease, buffer, flushAndPass }
  private(set) var choosing = false
  private(set) var deferring = false

  mutating func route(_ type: CGEventType, key: Int64, flags: CGEventFlags) -> Action {
    if deferring {
      if [.keyDown, .keyUp, .flagsChanged].contains(type) { return .buffer }
      if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
        reset()
        return .flushAndPass
      }
      return .pass
    }
    if type == .keyDown, key == kVK_Tab, flags.contains(.maskCommand),
      !flags.contains(.maskAlternate), !flags.contains(.maskControl) {
      choosing = true
    } else if type == .keyDown, key == kVK_Escape {
      choosing = false
    } else if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
      choosing = false // Native mouse selection proceeds normally.
    } else if type == .flagsChanged, !flags.contains(.maskCommand) {
      // Option-on-release has special native minimized-window behavior.
      let shouldHold = choosing && !flags.contains(.maskAlternate) && !flags.contains(.maskControl)
      choosing = false
      if shouldHold {
        deferring = true
        return .holdRelease
      }
    }
    return .pass
  }

  mutating func reset() {
    choosing = false
    deferring = false
  }
}

@MainActor
final class CommandTabSwitcher {
  static let shared = CommandTabSwitcher()
  private static let replayTag: Int64 = 0x495353434D445442
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var retry: DispatchWorkItem?
  private var input = NativeCommandTabInput()
  private var release: CGEvent?
  private var buffered: [CGEvent] = []
  private var destination: NSRunningApplication?
  private var generation = 0

  func start() {
    setEnabled(UserDefaults.standard.object(forKey: "commandTabOverride") as? Bool ?? true)
  }

  func stop() { setEnabled(false) }

  func setEnabled(_ enabled: Bool) {
    retry?.cancel()
    retry = nil
    flushRelease()
    if let tap { CFMachPortInvalidate(tap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
    guard enabled else { return }
    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
      eventsOfInterest: mask,
      callback: { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        return MainActor.assumeIsolated {
          Unmanaged<CommandTabSwitcher>.fromOpaque(context).takeUnretainedValue().handle(type, event)
        }
      }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    guard let tap else {
      let work = DispatchWorkItem { [weak self] in self?.setEnabled(true) }
      retry = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
      return
    }
    source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if event.getIntegerValueField(.eventSourceUserData) == Self.replayTag {
      return Unmanaged.passUnretained(event)
    }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      flushRelease()
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    if ShortcutRecorderControl.isAnyRecording {
      flushRelease()
      return Unmanaged.passUnretained(event)
    }
    switch input.route(type, key: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags) {
    case .pass:
      return Unmanaged.passUnretained(event)
    case .holdRelease:
      guard let copy = event.copy() else {
        input.reset()
        return Unmanaged.passUnretained(event)
      }
      release = copy
      generation += 1
      let ticket = generation
      // AX calls must never block the event-tap callback. Dock still sees
      // Command as held, so its actual selection remains available to query.
      DispatchQueue.main.async { self.prepareRelease(ticket: ticket) }
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        if ticket == self.generation { self.flushRelease() }
      }
      return nil
    case .buffer:
      guard buffered.count < 128, let copy = event.copy() else {
        flushRelease()
        return Unmanaged.passUnretained(event)
      }
      buffered.append(copy)
      return nil
    case .flushAndPass:
      flushRelease()
      return Unmanaged.passUnretained(event)
    }
  }

  private func flushRelease() {
    let app = destination
    destination = nil
    let events = (release.map { [$0] } ?? []) + buffered
    release = nil
    buffered = []
    input.reset()
    generation += 1
    // The same app selected in the native chooser receives the final focus.
    // Unresolved selections leave the chooser open for the real release instead.
    app?.activate(options: [.activateIgnoringOtherApps])
    // Replay the real release and any following typing in its original order.
    for event in events {
      event.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
      event.timestamp = DispatchTime.now().uptimeNanoseconds
      event.post(tap: .cgSessionEventTap)
    }
  }

  private func prepareRelease(ticket: Int, selectionDeadline: TimeInterval? = nil) {
    guard ticket == generation, release != nil else { return }
    guard AXIsProcessTrusted() else { flushRelease(); return }
    // A quick tap may release Command before Dock has created its AX list.
    // Holding the release gives the native chooser a short chance to expose it.
    let deadline = selectionDeadline ?? (ProcessInfo.processInfo.systemUptime + 0.12)
    guard let selected = selectedDestination() else {
      if ProcessInfo.processInfo.systemUptime < deadline {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
          self.prepareRelease(ticket: ticket, selectionDeadline: deadline)
        }
      } else {
        flushRelease()
      }
      return
    }
    let windowID = selected.windowID
    if !iss_has_pending_switch(), iss_window_is_on_active_space(windowID) {
      flushRelease()
      return
    }
    // Close the native chooser only after the user has released Command and
    // its exact selection has been read. Dock can then accept Space gestures.
    // Never synthesize Escape when selection lookup failed.
    guard let escapeDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Escape), keyDown: true),
      let escapeUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Escape), keyDown: false) else {
      flushRelease()
      return
    }
    destination = selected.app
    for escape in [escapeDown, escapeUp] {
      escape.flags = .maskCommand
      escape.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
      escape.post(tap: .cgSessionEventTap)
    }
    guard iss_switch_to_window(windowID) else { flushRelease(); return }
    waitForSpace(windowID: windowID, ticket: ticket)
  }

  private func waitForSpace(windowID: CGWindowID, ticket: Int) {
    guard ticket == generation, release != nil else { return }
    if !iss_has_pending_switch(), iss_window_is_on_active_space(windowID) {
      // Let Dock consume the gesture release before requesting window focus.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        if ticket == self.generation { self.flushRelease() }
      }
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        self.waitForSpace(windowID: windowID, ticket: ticket)
      }
    }
  }

  private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
  }

  private func selectedDestination() -> (app: NSRunningApplication, windowID: CGWindowID)? {
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let element = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.05)
    // Inspect the real process switcher list, never infer its MRU order. Prefer
    // direct children before examining containers so the Dock icon list is cheap.
    var level = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    var switcher: AXUIElement?
    let deadline = ProcessInfo.processInfo.systemUptime + 0.15
    for _ in 0..<3 {
      for child in level {
        if attribute(child, kAXSubroleAttribute) as? String == kAXProcessSwitcherListSubrole {
          switcher = child
          break
        }
        if ProcessInfo.processInfo.systemUptime > deadline { return nil }
      }
      if switcher != nil { break }
      var children: [AXUIElement] = []
      for child in level {
        if ProcessInfo.processInfo.systemUptime > deadline { return nil }
        children += attribute(child, kAXChildrenAttribute) as? [AXUIElement] ?? []
        if children.count > 128 { return nil }
      }
      level = children
      if ProcessInfo.processInfo.systemUptime > deadline { return nil }
    }
    guard let switcher,
      let selected = (attribute(switcher, kAXSelectedChildrenAttribute) as? [AXUIElement])?.first,
      let url = attribute(selected, kAXURLAttribute) as? URL else { return nil }
    // Exact URL matching handles multiple running copies without guessing names.
    let matches = NSWorkspace.shared.runningApplications.filter {
      $0.bundleURL?.standardizedFileURL == url.standardizedFileURL && !$0.isTerminated
    }
    guard matches.count == 1, let app = matches.first else { return nil }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 0.1)
    for name in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
      if let value = attribute(appElement, name), CFGetTypeID(value) == AXUIElementGetTypeID() {
        var windowID: CGWindowID = 0
        if axWindowID(value as! AXUIElement, &windowID) == .success, windowID != 0 { return (app, windowID) }
      }
    }
    return nil
  }
}
