import XCTest
@testable import InstantSpaceSwitcher

final class CommandTabSelectionTests: XCTestCase {
  func testForwardStartsAtPreviousAppAndWraps() {
    var selection = CommandTabSelection(count: 3)
    selection.advance(backward: false)
    XCTAssertEqual(selection.index, 1)
    selection.advance(backward: false)
    XCTAssertEqual(selection.index, 2)
    selection.advance(backward: false)
    XCTAssertEqual(selection.index, 0)
  }

  func testReverseStartsAtLastAppAndCanChangeDirection() {
    var selection = CommandTabSelection(count: 3)
    selection.advance(backward: true)
    XCTAssertEqual(selection.index, 2)
    selection.advance(backward: true)
    XCTAssertEqual(selection.index, 1)
    selection.advance(backward: false)
    XCTAssertEqual(selection.index, 2)
  }

  func testEmptyAndSingleAppAreSafe() {
    for count in [0, 1] {
      var selection = CommandTabSelection(count: count)
      selection.advance(backward: false)
      selection.advance(backward: true)
      XCTAssertEqual(selection.index, 0)
    }
  }
}
