import Carbon
import CoreGraphics
import XCTest
@testable import InstantSpaceSwitcher

final class NativeCommandTabInputTests: XCTestCase {
  func testNativeChooserReceivesTabAndReverseTab() {
    var input = NativeCommandTabInput()
    XCTAssertEqual(input.route(.keyDown, key: Int64(kVK_Tab), flags: .maskCommand), .pass)
    XCTAssertEqual(input.route(.keyUp, key: Int64(kVK_Tab), flags: .maskCommand), .pass)
    XCTAssertEqual(input.route(.keyDown, key: Int64(kVK_Tab), flags: [.maskCommand, .maskShift]), .pass)
    XCTAssertTrue(input.choosing)
    XCTAssertEqual(input.route(.flagsChanged, key: Int64(kVK_Command), flags: []), .holdRelease)
    XCTAssertTrue(input.deferring)
  }

  func testEscapeCancelsWithoutInterceptingRelease() {
    var input = NativeCommandTabInput()
    _ = input.route(.keyDown, key: Int64(kVK_Tab), flags: .maskCommand)
    XCTAssertEqual(input.route(.keyDown, key: Int64(kVK_Escape), flags: .maskCommand), .pass)
    XCTAssertEqual(input.route(.flagsChanged, key: Int64(kVK_Command), flags: []), .pass)
    XCTAssertFalse(input.deferring)
  }

  func testOptionOnReleaseKeepsNativeMinimizedWindowBehavior() {
    var input = NativeCommandTabInput()
    _ = input.route(.keyDown, key: Int64(kVK_Tab), flags: .maskCommand)
    XCTAssertEqual(input.route(.flagsChanged, key: Int64(kVK_Command), flags: .maskAlternate), .pass)
    XCTAssertFalse(input.deferring)
  }

  func testNativeQuitHideAndArrowControlsPassThrough() {
    var input = NativeCommandTabInput()
    _ = input.route(.keyDown, key: Int64(kVK_Tab), flags: .maskCommand)
    for key in [kVK_ANSI_Q, kVK_ANSI_H, kVK_LeftArrow, kVK_RightArrow, kVK_Return] {
      XCTAssertEqual(input.route(.keyDown, key: Int64(key), flags: .maskCommand), .pass)
      XCTAssertEqual(input.route(.keyUp, key: Int64(key), flags: .maskCommand), .pass)
    }
  }

  func testOnlyCommandTabStartsSessionAndBothCommandKeysMustBeReleased() {
    var input = NativeCommandTabInput()
    for flags: CGEventFlags in [[], .maskShift, [.maskCommand, .maskAlternate], [.maskCommand, .maskControl]] {
      XCTAssertEqual(input.route(.keyDown, key: Int64(kVK_Tab), flags: flags), .pass)
      XCTAssertFalse(input.choosing)
    }
    _ = input.route(.keyDown, key: Int64(kVK_Tab), flags: .maskCommand)
    XCTAssertEqual(input.route(.flagsChanged, key: Int64(kVK_RightCommand), flags: .maskCommand), .pass)
    XCTAssertEqual(input.route(.flagsChanged, key: Int64(kVK_Command), flags: []), .holdRelease)
  }

  func testTypingIsBufferedUntilReleaseThenSessionResets() {
    var input = NativeCommandTabInput()
    _ = input.route(.keyDown, key: Int64(kVK_Tab), flags: .maskCommand)
    _ = input.route(.flagsChanged, key: Int64(kVK_Command), flags: [])
    for type: CGEventType in [.keyDown, .keyUp, .flagsChanged] {
      XCTAssertEqual(input.route(type, key: Int64(kVK_ANSI_A), flags: []), .buffer)
    }
    input.reset()
    XCTAssertEqual(input.route(.keyDown, key: Int64(kVK_ANSI_A), flags: []), .pass)
    XCTAssertFalse(input.deferring)
  }

  func testMouseSelectionPassesThroughAndClickFlushesPendingRelease() {
    var input = NativeCommandTabInput()
    _ = input.route(.keyDown, key: Int64(kVK_Tab), flags: .maskCommand)
    XCTAssertEqual(input.route(.leftMouseDown, key: 0, flags: .maskCommand), .pass)
    XCTAssertEqual(input.route(.flagsChanged, key: Int64(kVK_Command), flags: []), .pass)
    _ = input.route(.keyDown, key: Int64(kVK_Tab), flags: .maskCommand)
    _ = input.route(.flagsChanged, key: Int64(kVK_Command), flags: [])
    XCTAssertEqual(input.route(.otherMouseDown, key: 0, flags: []), .flushAndPass)
    XCTAssertFalse(input.deferring)
  }
}
