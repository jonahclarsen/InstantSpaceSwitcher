import AppKit
import ApplicationServices
import Carbon
import ISS

@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

// Snapshot the order for the entire Command hold; activation changes cannot
// reshuffle it while the user is cycling.
struct CommandTabSelection {
  let count: Int
  private(set) var index = 0

  mutating func advance(backward: Bool) {
    guard count > 0 else { return }
    index = (index + (backward ? count - 1 : 1)) % count
  }
}

@MainActor
final class CommandTabSwitcher {
  static let shared = CommandTabSwitcher()
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var observer: Any?
  private var retry: DispatchWorkItem?
  private var recent: [pid_t] = []
  private var apps: [NSRunningApplication] = []
  private var selection: CommandTabSelection?
  private var holdingCommand = false
  private var cancelledHold = false
  private var generation = 0
  private var panel: NSPanel?

  func start() {
    if observer == nil {
      if let front = NSWorkspace.shared.frontmostApplication { remember(front) }
      observer = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
      ) { [weak self] notification in
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        MainActor.assumeIsolated { self?.remember(app) }
      }
    }
    setEnabled(UserDefaults.standard.object(forKey: "commandTabOverride") as? Bool ?? true)
  }

  func stop() {
    setEnabled(false)
    if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    observer = nil
  }

  func setEnabled(_ enabled: Bool) {
    retry?.cancel()
    retry = nil
    cancel()
    if let tap { CFMachPortInvalidate(tap) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
    guard enabled else { return }
    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown]
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
      // Accessibility may be granted after launch. Native Command-Tab remains
      // available until a tap can actually be installed.
      let work = DispatchWorkItem { [weak self] in self?.setEnabled(true) }
      retry = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
      return
    }
    source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
  }

  private func remember(_ app: NSRunningApplication) {
    guard app.activationPolicy == .regular else { return }
    recent.removeAll { $0 == app.processIdentifier }
    recent.insert(app.processIdentifier, at: 0)
    let running = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
    recent.removeAll { !running.contains($0) }
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      cancel()
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    guard !ShortcutRecorderControl.isAnyRecording else { return Unmanaged.passUnretained(event) }
    let key = event.getIntegerValueField(.keyboardEventKeycode)
    if type == .keyDown, key == kVK_Tab, event.flags.contains(.maskCommand),
      !event.flags.contains(.maskAlternate), !event.flags.contains(.maskControl) {
      holdingCommand = true
      if cancelledHold { return nil }
      let backward = event.flags.contains(.maskShift)
      // Keep all AppKit/AX work outside the event-tap callback.
      DispatchQueue.main.async { self.advance(backward: backward) }
      return nil
    }
    if type == .keyUp, key == kVK_Tab, holdingCommand { return nil }
    if type == .flagsChanged, holdingCommand, !event.flags.contains(.maskCommand) {
      holdingCommand = false
      cancelledHold = false
      DispatchQueue.main.async { self.commit() }
    } else if holdingCommand, type == .keyDown, key == kVK_Escape {
      cancelledHold = true
      // Consume Tab until Command is released, even after cancelling.
      DispatchQueue.main.async { self.cancel(keepCommand: true) }
      return nil
    } else if type == .leftMouseDown || type == .rightMouseDown {
      DispatchQueue.main.async { self.cancel() }
    }
    // Unsupported chooser shortcuts must not reach the previous application
    // (for example Command-Q must not accidentally quit it).
    if holdingCommand, type == .keyDown || type == .keyUp { return nil }
    return Unmanaged.passUnretained(event)
  }

  private func advance(backward: Bool) {
    if selection == nil {
      generation += 1 // Cancel any pending activation from an earlier switch.
      if let front = NSWorkspace.shared.frontmostApplication { remember(front) }
      apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
      apps.sort {
        let left = recent.firstIndex(of: $0.processIdentifier) ?? Int.max
        let right = recent.firstIndex(of: $1.processIdentifier) ?? Int.max
        if left != right { return left < right }
        return ($0.localizedName ?? "") < ($1.localizedName ?? "")
      }
      selection = CommandTabSelection(count: apps.count)
    }
    selection?.advance(backward: backward)
    showChooser()
  }

  private func cancel(keepCommand: Bool = false) {
    generation += 1
    selection = nil
    apps = []
    if !keepCommand {
      holdingCommand = false
      cancelledHold = false
    }
    panel?.orderOut(nil)
  }

  private func commit() {
    guard let selection, apps.indices.contains(selection.index) else { cancel(); return }
    let app = apps[selection.index]
    cancel()
    guard !app.isTerminated else { return }
    let ticket = generation
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.2)
    var window: CFTypeRef?
    var windowID: CGWindowID = 0
    for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
      if AXUIElementCopyAttributeValue(element, attribute as CFString, &window) == .success,
        let window, CFGetTypeID(window) == AXUIElementGetTypeID(),
        axWindowID(window as! AXUIElement, &windowID) == .success { break }
    }
    // Windowless apps and unsupported AX implementations retain normal activation.
    guard windowID != 0 else {
      app.activate(options: [.activateIgnoringOtherApps])
      return
    }
    if !iss_has_pending_switch(), iss_window_is_on_active_space(windowID) {
      app.activate(options: [.activateIgnoringOtherApps])
      return
    }
    guard iss_switch_to_window(windowID) else {
      app.activate(options: [.activateIgnoringOtherApps])
      return
    }
    finishActivation(app, windowID: windowID, ticket: ticket,
                     deadline: ProcessInfo.processInfo.systemUptime + 2)
  }

  private func finishActivation(_ app: NSRunningApplication, windowID: CGWindowID,
                                ticket: Int, deadline: TimeInterval) {
    guard ticket == generation, !app.isTerminated else { return }
    if !iss_has_pending_switch(), iss_window_is_on_active_space(windowID) {
      // Let Dock consume the gesture release before requesting window focus.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        guard ticket == self.generation else { return }
        app.activate(options: [.activateIgnoringOtherApps])
      }
    } else if ProcessInfo.processInfo.systemUptime >= deadline {
      app.activate(options: [.activateIgnoringOtherApps])
    } else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        self.finishActivation(app, windowID: windowID, ticket: ticket, deadline: deadline)
      }
    }
  }

  private func showChooser() {
    guard let selection, !apps.isEmpty else { return }
    let screen = NSScreen.main ?? NSScreen.screens.first
    let width = min(CGFloat(apps.count) * 84 + 32, (screen?.visibleFrame.width ?? 900) - 80)
    if panel == nil {
      panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel?.level = .popUpMenu
      panel?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel?.isOpaque = false
      panel?.backgroundColor = .clear
      panel?.hasShadow = true
      panel?.hidesOnDeactivate = false
    }
    let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 132))
    background.material = .hudWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 18
    background.layer?.masksToBounds = true
    let scroll = NSScrollView(frame: NSRect(x: 16, y: 40, width: width - 32, height: 80))
    scroll.drawsBackground = false
    let row = NSView(frame: NSRect(x: 0, y: 0, width: CGFloat(apps.count) * 84, height: 80))
    for (index, app) in apps.enumerated() {
      let cell = NSView(frame: NSRect(x: CGFloat(index) * 84, y: 0, width: 80, height: 80))
      cell.wantsLayer = true
      cell.layer?.cornerRadius = 12
      if index == selection.index { cell.layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.65).cgColor }
      let icon = NSImageView(frame: NSRect(x: 10, y: 10, width: 60, height: 60))
      icon.image = app.icon
      icon.imageScaling = .scaleProportionallyUpOrDown
      cell.addSubview(icon)
      row.addSubview(cell)
    }
    scroll.documentView = row
    row.scrollToVisible(NSRect(x: CGFloat(selection.index) * 84, y: 0, width: 80, height: 80))
    background.addSubview(scroll)
    let label = NSTextField(labelWithString: apps[selection.index].localizedName ?? "Application")
    label.frame = NSRect(x: 16, y: 12, width: width - 32, height: 20)
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    background.addSubview(label)
    panel?.contentView = background
    let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 600)
    panel?.setFrame(NSRect(x: frame.midX - width / 2, y: frame.midY - 66, width: width, height: 132), display: true)
    panel?.orderFrontRegardless()
  }
}
