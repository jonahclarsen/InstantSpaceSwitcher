import AppKit
import Carbon
import Foundation

enum OptionKeyKind: String, Codable {
  case any
  case right
}

struct HotkeyCombination: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var displayKey: String
  var keyEquivalent: String
  var optionKeyKind: OptionKeyKind

  init(
    keyCode: UInt32, modifiers: UInt32, displayKey: String, keyEquivalent: String,
    optionKeyKind: OptionKeyKind = .any
  ) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.displayKey = displayKey
    self.keyEquivalent = keyEquivalent
    self.optionKeyKind = optionKeyKind
  }

  var displayString: String {
    let modifierSymbols = HotkeyCombination.symbols(for: modifiers, optionKeyKind: optionKeyKind)
    return modifierSymbols + displayKey
  }

  var cocoaModifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
    if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
    if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
    if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
    return flags
  }

  var isValid: Bool {
    !displayKey.isEmpty
  }

  var registrationModifiers: UInt32 {
    modifiers
  }

  func matches(eventModifierFlags flags: UInt64) -> Bool {
    guard modifiers == HotkeyModifierState.carbonMask(fromRawFlags: flags) else {
      return false
    }

    if optionKeyKind == .right {
      return HotkeyModifierState.isRightOptionPressed(rawFlags: flags)
    }

    if modifiers & UInt32(optionKey) != 0 {
      return !HotkeyModifierState.isRightOptionPressed(rawFlags: flags)
    }

    return true
  }

  enum CodingKeys: String, CodingKey {
    case keyCode
    case modifiers
    case displayKey
    case keyEquivalent
    case optionKeyKind
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    keyCode = try container.decode(UInt32.self, forKey: .keyCode)
    modifiers = try container.decode(UInt32.self, forKey: .modifiers)
    displayKey = try container.decode(String.self, forKey: .displayKey)
    keyEquivalent = try container.decode(String.self, forKey: .keyEquivalent)
    optionKeyKind = try container.decodeIfPresent(OptionKeyKind.self, forKey: .optionKeyKind) ?? .any
  }

  static let defaultLeft = HotkeyCombination(
    keyCode: UInt32(kVK_LeftArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "←",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.leftArrow)
  )

  static let defaultRight = HotkeyCombination(
    keyCode: UInt32(kVK_RightArrow),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "→",
    keyEquivalent: HotkeyCombination.arrowKeyEquivalent(.rightArrow)
  )

  static let defaultLastSpace = HotkeyCombination(
    keyCode: UInt32(kVK_ANSI_KeypadPlus),
    modifiers: HotkeyCombination.defaultModifierMask,
    displayKey: "↩",
    keyEquivalent: "-" 
  )

  static func defaultForSpace(_ number: Int) -> HotkeyCombination {
    let keyCode: UInt32
    let displayKey: String
    let keyEquivalent: String

    switch number {
    case 1:
      keyCode = UInt32(kVK_ANSI_1)
      displayKey = "1"
      keyEquivalent = "1"
    case 2:
      keyCode = UInt32(kVK_ANSI_2)
      displayKey = "2"
      keyEquivalent = "2"
    case 3:
      keyCode = UInt32(kVK_ANSI_3)
      displayKey = "3"
      keyEquivalent = "3"
    case 4:
      keyCode = UInt32(kVK_ANSI_4)
      displayKey = "4"
      keyEquivalent = "4"
    case 5:
      keyCode = UInt32(kVK_ANSI_5)
      displayKey = "5"
      keyEquivalent = "5"
    case 6:
      keyCode = UInt32(kVK_ANSI_6)
      displayKey = "6"
      keyEquivalent = "6"
    case 7:
      keyCode = UInt32(kVK_ANSI_7)
      displayKey = "7"
      keyEquivalent = "7"
    case 8:
      keyCode = UInt32(kVK_ANSI_8)
      displayKey = "8"
      keyEquivalent = "8"
    case 9:
      keyCode = UInt32(kVK_ANSI_9)
      displayKey = "9"
      keyEquivalent = "9"
    case 10:
      keyCode = UInt32(kVK_ANSI_0)
      displayKey = "0"
      keyEquivalent = "0"
    case 11...16:
      let functionKey = number - 11
      let functionKeyCodes = [
        UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3),
        UInt32(kVK_F4), UInt32(kVK_F5), UInt32(kVK_F6),
      ]
      keyCode = functionKeyCodes[functionKey]
      displayKey = "F\(functionKey + 1)"
      keyEquivalent = String(Character(UnicodeScalar(NSF1FunctionKey + functionKey)!))
    default: fatalError("Invalid space number")
    }

    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: defaultModifierMask,
      displayKey: displayKey,
      keyEquivalent: keyEquivalent
    )
  }

  static func from(event: NSEvent) -> HotkeyCombination? {
    let modifiers = event.modifierFlags.carbonMask
    let keyCode = UInt32(event.keyCode)
    let optionKeyKind = HotkeyModifierState.optionKeyKind(
      fromRawFlags: UInt64(event.modifierFlags.rawValue))
    
    // Handle arrow keys
    if let special = event.specialKey, let symbol = arrowSymbol(for: special) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: symbol,
        keyEquivalent: arrowKeyEquivalent(special),
        optionKeyKind: optionKeyKind
      )
    }
    
    // Handle special keys (Enter, F-keys, etc.)
    if let (displayKey, keyEquiv) = specialKeyInfo(for: Int(event.keyCode)) {
      return HotkeyCombination(
        keyCode: keyCode,
        modifiers: modifiers,
        displayKey: displayKey,
        keyEquivalent: keyEquiv,
        optionKeyKind: optionKeyKind
      )
    }

    guard let characters = event.charactersIgnoringModifiers, let first = characters.first,
          first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol else {
      return nil
    }

    let upper = String(first).uppercased()
    return HotkeyCombination(
      keyCode: keyCode,
      modifiers: modifiers,
      displayKey: upper,
      keyEquivalent: String(first).lowercased(),
      optionKeyKind: optionKeyKind
    )
  }

  static func arrowSymbol(for specialKey: NSEvent.SpecialKey) -> String? {
    switch specialKey {
    case .leftArrow: return "←"
    case .rightArrow: return "→"
    case .upArrow: return "↑"
    case .downArrow: return "↓"
    default: return nil
    }
  }
  
  private static func specialKeyInfo(for keyCode: Int) -> (displayKey: String, keyEquivalent: String)? {
    switch keyCode {
    // Enter/Return
    case kVK_Return:
      return ("↩", String(Character(UnicodeScalar(NSCarriageReturnCharacter)!)))
    case kVK_ANSI_KeypadEnter:
      return ("⌅", String(Character(UnicodeScalar(NSEnterCharacter)!)))
    // Tab
    case kVK_Tab:
      return ("⇥", String(Character(UnicodeScalar(NSTabCharacter)!)))
    // Delete/Backspace
    case kVK_Delete:
      return ("⌫", String(Character(UnicodeScalar(NSBackspaceCharacter)!)))
    case kVK_ForwardDelete:
      return ("⌦", String(Character(UnicodeScalar(NSDeleteCharacter)!)))
    // Space
    case kVK_Space:
      return ("Space", " ")
    // F-keys
    case kVK_F1:
      return ("F1", String(Character(UnicodeScalar(NSF1FunctionKey)!)))
    case kVK_F2:
      return ("F2", String(Character(UnicodeScalar(NSF2FunctionKey)!)))
    case kVK_F3:
      return ("F3", String(Character(UnicodeScalar(NSF3FunctionKey)!)))
    case kVK_F4:
      return ("F4", String(Character(UnicodeScalar(NSF4FunctionKey)!)))
    case kVK_F5:
      return ("F5", String(Character(UnicodeScalar(NSF5FunctionKey)!)))
    case kVK_F6:
      return ("F6", String(Character(UnicodeScalar(NSF6FunctionKey)!)))
    case kVK_F7:
      return ("F7", String(Character(UnicodeScalar(NSF7FunctionKey)!)))
    case kVK_F8:
      return ("F8", String(Character(UnicodeScalar(NSF8FunctionKey)!)))
    case kVK_F9:
      return ("F9", String(Character(UnicodeScalar(NSF9FunctionKey)!)))
    case kVK_F10:
      return ("F10", String(Character(UnicodeScalar(NSF10FunctionKey)!)))
    case kVK_F11:
      return ("F11", String(Character(UnicodeScalar(NSF11FunctionKey)!)))
    case kVK_F12:
      return ("F12", String(Character(UnicodeScalar(NSF12FunctionKey)!)))
    // Home/End/Page
    case kVK_Home:
      return ("↖", String(Character(UnicodeScalar(NSHomeFunctionKey)!)))
    case kVK_End:
      return ("↘", String(Character(UnicodeScalar(NSEndFunctionKey)!)))
    case kVK_PageUp:
      return ("⇞", String(Character(UnicodeScalar(NSPageUpFunctionKey)!)))
    case kVK_PageDown:
      return ("⇟", String(Character(UnicodeScalar(NSPageDownFunctionKey)!)))
    default:
      return nil
    }
  }

  private static func arrowKeyEquivalent(_ specialKey: NSEvent.SpecialKey) -> String {
    switch specialKey {
    case .leftArrow:
      return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    case .rightArrow:
      return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
    case .upArrow:
      return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    case .downArrow:
      return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    default:
      return ""
    }
  }

  private static func symbols(for modifiers: UInt32, optionKeyKind: OptionKeyKind) -> String {
    var result = ""
    if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if modifiers & UInt32(optionKey) != 0 {
      result += optionKeyKind == .right ? "AltGr" : "⌥"
    }
    if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
    return result
  }

  private static var defaultModifierMask: UInt32 {
    UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey)
  }
}

enum HotkeyModifierState {
  private static let deviceRightOptionMask: UInt64 = 0x00000040

  static func optionKeyKind(fromRawFlags flags: UInt64) -> OptionKeyKind {
    isRightOptionPressed(rawFlags: flags) ? .right : .any
  }

  static func isRightOptionPressed(rawFlags flags: UInt64) -> Bool {
    flags & deviceRightOptionMask != 0
  }

  static func carbonMask(fromRawFlags flags: UInt64) -> UInt32 {
    NSEvent.ModifierFlags(rawValue: UInt(flags)).carbonMask
  }
}

enum HotkeyIdentifier: String, CaseIterable {
  case left
  case right
  case space1, space2, space3, space4, space5
  case space6, space7, space8, space9, space10
  case space11, space12, space13, space14, space15, space16
  case lastSpace
  
  var displayName: String {
    switch self {
    case .left: return "Switch to space on the left"
    case .right: return "Switch to space on the right"
    case .space1: return "Switch to space 1"
    case .space2: return "Switch to space 2"
    case .space3: return "Switch to space 3"
    case .space4: return "Switch to space 4"
    case .space5: return "Switch to space 5"
    case .space6: return "Switch to space 6"
    case .space7: return "Switch to space 7"
    case .space8: return "Switch to space 8"
    case .space9: return "Switch to space 9"
    case .space10: return "Switch to space 10"
    case .space11: return "Switch to space 11"
    case .space12: return "Switch to space 12"
    case .space13: return "Switch to space 13"
    case .space14: return "Switch to space 14"
    case .space15: return "Switch to space 15"
    case .space16: return "Switch to space 16"
    case .lastSpace: return "Switch to last used space"
    }
  }
}

final class HotkeyStore: ObservableObject {
  static let shared = HotkeyStore()

  @Published private(set) var leftHotkey: HotkeyCombination
  @Published private(set) var rightHotkey: HotkeyCombination
  @Published private(set) var space1Hotkey: HotkeyCombination
  @Published private(set) var space2Hotkey: HotkeyCombination
  @Published private(set) var space3Hotkey: HotkeyCombination
  @Published private(set) var space4Hotkey: HotkeyCombination
  @Published private(set) var space5Hotkey: HotkeyCombination
  @Published private(set) var space6Hotkey: HotkeyCombination
  @Published private(set) var space7Hotkey: HotkeyCombination
  @Published private(set) var space8Hotkey: HotkeyCombination
  @Published private(set) var space9Hotkey: HotkeyCombination
  @Published private(set) var space10Hotkey: HotkeyCombination
  @Published private(set) var space11Hotkey: HotkeyCombination
  @Published private(set) var space12Hotkey: HotkeyCombination
  @Published private(set) var space13Hotkey: HotkeyCombination
  @Published private(set) var space14Hotkey: HotkeyCombination
  @Published private(set) var space15Hotkey: HotkeyCombination
  @Published private(set) var space16Hotkey: HotkeyCombination
  @Published private(set) var spaceLastSpaceHotkey: HotkeyCombination
  @Published private(set) var enabledStates: [HotkeyIdentifier: Bool] = [:]

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    leftHotkey = defaults.hotkey(forKey: DefaultsKey.left.rawValue) ?? .defaultLeft
    rightHotkey = defaults.hotkey(forKey: DefaultsKey.right.rawValue) ?? .defaultRight
    space1Hotkey = defaults.hotkey(forKey: DefaultsKey.space1.rawValue) ?? .defaultForSpace(1)
    space2Hotkey = defaults.hotkey(forKey: DefaultsKey.space2.rawValue) ?? .defaultForSpace(2)
    space3Hotkey = defaults.hotkey(forKey: DefaultsKey.space3.rawValue) ?? .defaultForSpace(3)
    space4Hotkey = defaults.hotkey(forKey: DefaultsKey.space4.rawValue) ?? .defaultForSpace(4)
    space5Hotkey = defaults.hotkey(forKey: DefaultsKey.space5.rawValue) ?? .defaultForSpace(5)
    space6Hotkey = defaults.hotkey(forKey: DefaultsKey.space6.rawValue) ?? .defaultForSpace(6)
    space7Hotkey = defaults.hotkey(forKey: DefaultsKey.space7.rawValue) ?? .defaultForSpace(7)
    space8Hotkey = defaults.hotkey(forKey: DefaultsKey.space8.rawValue) ?? .defaultForSpace(8)
    space9Hotkey = defaults.hotkey(forKey: DefaultsKey.space9.rawValue) ?? .defaultForSpace(9)
    space10Hotkey = defaults.hotkey(forKey: DefaultsKey.space10.rawValue) ?? .defaultForSpace(10)
    space11Hotkey = defaults.hotkey(forKey: DefaultsKey.space11.rawValue) ?? .defaultForSpace(11)
    space12Hotkey = defaults.hotkey(forKey: DefaultsKey.space12.rawValue) ?? .defaultForSpace(12)
    space13Hotkey = defaults.hotkey(forKey: DefaultsKey.space13.rawValue) ?? .defaultForSpace(13)
    space14Hotkey = defaults.hotkey(forKey: DefaultsKey.space14.rawValue) ?? .defaultForSpace(14)
    space15Hotkey = defaults.hotkey(forKey: DefaultsKey.space15.rawValue) ?? .defaultForSpace(15)
    space16Hotkey = defaults.hotkey(forKey: DefaultsKey.space16.rawValue) ?? .defaultForSpace(16)
    spaceLastSpaceHotkey = defaults.hotkey(forKey: DefaultsKey.lastSpace.rawValue) ?? .defaultLastSpace

    for identifier in HotkeyIdentifier.allCases {
      let key = "enabled.\(identifier.rawValue)"
      enabledStates[identifier] = defaults.object(forKey: key) as? Bool ?? true
    }
  }

  func update(_ combination: HotkeyCombination, for identifier: HotkeyIdentifier) {
    switch identifier {
    case .left:
      guard combination != leftHotkey else { return }
      leftHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.left.rawValue)
    case .right:
      guard combination != rightHotkey else { return }
      rightHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.right.rawValue)
    case .space1:
      guard combination != space1Hotkey else { return }
      space1Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space1.rawValue)
    case .space2:
      guard combination != space2Hotkey else { return }
      space2Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space2.rawValue)
    case .space3:
      guard combination != space3Hotkey else { return }
      space3Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space3.rawValue)
    case .space4:
      guard combination != space4Hotkey else { return }
      space4Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space4.rawValue)
    case .space5:
      guard combination != space5Hotkey else { return }
      space5Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space5.rawValue)
    case .space6:
      guard combination != space6Hotkey else { return }
      space6Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space6.rawValue)
    case .space7:
      guard combination != space7Hotkey else { return }
      space7Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space7.rawValue)
    case .space8:
      guard combination != space8Hotkey else { return }
      space8Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space8.rawValue)
    case .space9:
      guard combination != space9Hotkey else { return }
      space9Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space9.rawValue)
    case .space10:
      guard combination != space10Hotkey else { return }
      space10Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space10.rawValue)
    case .space11:
      guard combination != space11Hotkey else { return }
      space11Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space11.rawValue)
    case .space12:
      guard combination != space12Hotkey else { return }
      space12Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space12.rawValue)
    case .space13:
      guard combination != space13Hotkey else { return }
      space13Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space13.rawValue)
    case .space14:
      guard combination != space14Hotkey else { return }
      space14Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space14.rawValue)
    case .space15:
      guard combination != space15Hotkey else { return }
      space15Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space15.rawValue)
    case .space16:
      guard combination != space16Hotkey else { return }
      space16Hotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.space16.rawValue)
    case .lastSpace:
      guard combination != spaceLastSpaceHotkey else { return }
      spaceLastSpaceHotkey = combination
      defaults.setHotkey(combination, forKey: DefaultsKey.lastSpace.rawValue)
    }
  }

  func resetToDefaults() {
    leftHotkey = .defaultLeft
    rightHotkey = .defaultRight
    space1Hotkey = .defaultForSpace(1)
    space2Hotkey = .defaultForSpace(2)
    space3Hotkey = .defaultForSpace(3)
    space4Hotkey = .defaultForSpace(4)
    space5Hotkey = .defaultForSpace(5)
    space6Hotkey = .defaultForSpace(6)
    space7Hotkey = .defaultForSpace(7)
    space8Hotkey = .defaultForSpace(8)
    space9Hotkey = .defaultForSpace(9)
    space10Hotkey = .defaultForSpace(10)
    space11Hotkey = .defaultForSpace(11)
    space12Hotkey = .defaultForSpace(12)
    space13Hotkey = .defaultForSpace(13)
    space14Hotkey = .defaultForSpace(14)
    space15Hotkey = .defaultForSpace(15)
    space16Hotkey = .defaultForSpace(16)
    spaceLastSpaceHotkey = .defaultLastSpace

    defaults.setHotkey(leftHotkey, forKey: DefaultsKey.left.rawValue)
    defaults.setHotkey(rightHotkey, forKey: DefaultsKey.right.rawValue)
    defaults.setHotkey(space1Hotkey, forKey: DefaultsKey.space1.rawValue)
    defaults.setHotkey(space2Hotkey, forKey: DefaultsKey.space2.rawValue)
    defaults.setHotkey(space3Hotkey, forKey: DefaultsKey.space3.rawValue)
    defaults.setHotkey(space4Hotkey, forKey: DefaultsKey.space4.rawValue)
    defaults.setHotkey(space5Hotkey, forKey: DefaultsKey.space5.rawValue)
    defaults.setHotkey(space6Hotkey, forKey: DefaultsKey.space6.rawValue)
    defaults.setHotkey(space7Hotkey, forKey: DefaultsKey.space7.rawValue)
    defaults.setHotkey(space8Hotkey, forKey: DefaultsKey.space8.rawValue)
    defaults.setHotkey(space9Hotkey, forKey: DefaultsKey.space9.rawValue)
    defaults.setHotkey(space10Hotkey, forKey: DefaultsKey.space10.rawValue)
    defaults.setHotkey(space11Hotkey, forKey: DefaultsKey.space11.rawValue)
    defaults.setHotkey(space12Hotkey, forKey: DefaultsKey.space12.rawValue)
    defaults.setHotkey(space13Hotkey, forKey: DefaultsKey.space13.rawValue)
    defaults.setHotkey(space14Hotkey, forKey: DefaultsKey.space14.rawValue)
    defaults.setHotkey(space15Hotkey, forKey: DefaultsKey.space15.rawValue)
    defaults.setHotkey(space16Hotkey, forKey: DefaultsKey.space16.rawValue)
    defaults.setHotkey(spaceLastSpaceHotkey, forKey: DefaultsKey.lastSpace.rawValue)
  }

  func combination(for identifier: HotkeyIdentifier) -> HotkeyCombination {
    switch identifier {
    case .left: return leftHotkey
    case .right: return rightHotkey
    case .space1: return space1Hotkey
    case .space2: return space2Hotkey
    case .space3: return space3Hotkey
    case .space4: return space4Hotkey
    case .space5: return space5Hotkey
    case .space6: return space6Hotkey
    case .space7: return space7Hotkey
    case .space8: return space8Hotkey
    case .space9: return space9Hotkey
    case .space10: return space10Hotkey
    case .space11: return space11Hotkey
    case .space12: return space12Hotkey
    case .space13: return space13Hotkey
    case .space14: return space14Hotkey
    case .space15: return space15Hotkey
    case .space16: return space16Hotkey
    case .lastSpace: return spaceLastSpaceHotkey
    }
  }

  func isEnabled(_ identifier: HotkeyIdentifier) -> Bool {
    return enabledStates[identifier] ?? true
  }

  func setEnabled(_ enabled: Bool, for identifier: HotkeyIdentifier) {
    enabledStates[identifier] = enabled
    let key = "enabled.\(identifier.rawValue)"
    defaults.set(enabled, forKey: key)
  }

  private enum DefaultsKey: String {
    case left = "hotkey.left"
    case right = "hotkey.right"
    case space1 = "hotkey.space1"
    case space2 = "hotkey.space2"
    case space3 = "hotkey.space3"
    case space4 = "hotkey.space4"
    case space5 = "hotkey.space5"
    case space6 = "hotkey.space6"
    case space7 = "hotkey.space7"
    case space8 = "hotkey.space8"
    case space9 = "hotkey.space9"
    case space10 = "hotkey.space10"
    case space11 = "hotkey.space11"
    case space12 = "hotkey.space12"
    case space13 = "hotkey.space13"
    case space14 = "hotkey.space14"
    case space15 = "hotkey.space15"
    case space16 = "hotkey.space16"
    case lastSpace = "hotkey.lastSpace"
  }
}

extension UserDefaults {
  fileprivate func hotkey(forKey key: String) -> HotkeyCombination? {
    guard let data = data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(HotkeyCombination.self, from: data)
  }

  fileprivate func setHotkey(_ hotkey: HotkeyCombination, forKey key: String) {
    if let data = try? JSONEncoder().encode(hotkey) {
      set(data, forKey: key)
    }
  }
}

extension NSEvent.ModifierFlags {
  var carbonMask: UInt32 {
    var mask: UInt32 = 0
    if contains(.command) { mask |= UInt32(cmdKey) }
    if contains(.option) { mask |= UInt32(optionKey) }
    if contains(.control) { mask |= UInt32(controlKey) }
    if contains(.shift) { mask |= UInt32(shiftKey) }
    return mask
  }
}
