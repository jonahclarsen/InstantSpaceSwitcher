import AppKit
import Carbon
@testable import InstantSpaceSwitcher
import XCTest

final class HotkeyCombinationTests: XCTestCase {
    private let optionFlags = UInt64(NSEvent.ModifierFlags.option.rawValue)
    private let controlOptionFlags =
        UInt64(NSEvent.ModifierFlags([.control, .option]).rawValue)
    private let rightOptionDeviceFlag: UInt64 = 0x00000040

    func testGenericOptionDoesNotMatchAdditionalControl() {
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )

        XCTAssertTrue(combination.matches(eventModifierFlags: optionFlags))
        XCTAssertFalse(combination.matches(eventModifierFlags: controlOptionFlags))
    }

    func testGenericOptionDoesNotMatchRightOption() {
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )

        XCTAssertFalse(combination.matches(eventModifierFlags: optionFlags | rightOptionDeviceFlag))
    }

    func testAltGrRequiresRightOption() {
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1",
            optionKeyKind: .right
        )

        XCTAssertFalse(combination.matches(eventModifierFlags: optionFlags))
        XCTAssertTrue(combination.matches(eventModifierFlags: optionFlags | rightOptionDeviceFlag))
    }

    func testLegacyDecodedShortcutDefaultsToGenericOption() throws {
        let json = """
        {
          "keyCode": \(kVK_ANSI_1),
          "modifiers": \(optionKey),
          "displayKey": "1",
          "keyEquivalent": "1"
        }
        """

        let decoded = try JSONDecoder().decode(
            HotkeyCombination.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.optionKeyKind, .any)
        XCTAssertFalse(decoded.matches(eventModifierFlags: optionFlags | rightOptionDeviceFlag))
    }

    func testAltGrDisplayIsDistinctFromGenericOption() {
        let generic = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )
        let altGr = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1",
            optionKeyKind: .right
        )

        XCTAssertEqual(generic.displayString, "⌥1")
        XCTAssertEqual(altGr.displayString, "AltGr1")
        XCTAssertNotEqual(generic, altGr)
    }

    func testAltGrSpecificShortcutWinsOverGenericOption() {
        let generic = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )
        let altGr = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1",
            optionKeyKind: .right
        )

        XCTAssertEqual(
            HotKeyManager.preferredCombination(
                from: [generic, altGr],
                keyCode: UInt32(kVK_ANSI_1),
                eventModifierFlags: optionFlags | rightOptionDeviceFlag),
            altGr
        )
    }

    func testNoShortcutSelectedForWrongKeyCode() {
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_1),
            modifiers: UInt32(optionKey),
            displayKey: "1",
            keyEquivalent: "1"
        )

        XCTAssertNil(
            HotKeyManager.preferredCombination(
                from: [combination],
                keyCode: UInt32(kVK_ANSI_2),
                eventModifierFlags: optionFlags)
        )
    }

    func testSpacesOneThroughSixteenHaveDefaultHotkeys() {
        let expectedKeyCodes: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
            UInt32(kVK_ANSI_0), UInt32(kVK_F1), UInt32(kVK_F2),
            UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5), UInt32(kVK_F6),
        ]
        let expectedDisplayKeys = (1...9).map { String($0) } + ["0"]
            + (1...6).map { "F\($0)" }

        for number in 1...16 {
            let combination = HotkeyCombination.defaultForSpace(number)
            let expectedKeyEquivalent = number <= 10
                ? expectedDisplayKeys[number - 1]
                : String(Character(UnicodeScalar(NSF1FunctionKey + number - 11)!))

            XCTAssertEqual(combination.keyCode, expectedKeyCodes[number - 1])
            XCTAssertEqual(combination.displayKey, expectedDisplayKeys[number - 1])
            XCTAssertEqual(combination.keyEquivalent, expectedKeyEquivalent)
        }
    }

    func testSpaceSixteenHotkeyCanBeSavedAndLoaded() {
        let suiteName = "HotkeyStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = HotkeyStore(defaults: defaults)
        let combination = HotkeyCombination(
            keyCode: UInt32(kVK_ANSI_A),
            modifiers: UInt32(cmdKey),
            displayKey: "A",
            keyEquivalent: "a"
        )

        store.update(combination, for: .space16)
        let loadedStore = HotkeyStore(defaults: defaults)

        XCTAssertEqual(loadedStore.combination(for: .space16), combination)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
