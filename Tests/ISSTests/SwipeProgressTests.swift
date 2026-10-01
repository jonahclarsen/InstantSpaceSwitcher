import XCTest
import ISS

// Unit tests for iss_swipe_progress_for_phase.
// Access the non-exported C function via @_silgen_name (same approach as
// ExposeMcDetectTests). No events are posted; no permissions required.

// CGSGesturePhase is uint8_t in ISS.c; ISSDirection is a C enum (int).
@_silgen_name("iss_swipe_progress_for_phase")
private func iss_swipe_progress_for_phase(_ phase: UInt8, _ direction: ISSDirection) -> Double

private let phaseBegan: UInt8 = 1
private let phaseChanged: UInt8 = 2
private let phaseEnded: UInt8 = 4

final class SwipeProgressTests: XCTestCase {

  /// Began must stay near zero so no intermediate frame is drawn, but
  /// non-zero so the direction survives.
  func testBeganIsNearZeroButSigned() {
    let right = iss_swipe_progress_for_phase(phaseBegan, ISSDirectionRight)
    let left = iss_swipe_progress_for_phase(phaseBegan, ISSDirectionLeft)
    XCTAssertGreaterThan(right, 0)
    XCTAssertLessThan(left, 0)
    XCTAssertLessThan(abs(right), 1e-30)
    XCTAssertLessThan(abs(left), 1e-30)
  }

  /// Changed and Ended must carry the full travel. A commit with ~zero
  /// progress lands on a space whose compositing surfaces WindowServer never
  /// built, leaving every window blank until Mission Control forces a redraw.
  func testChangedAndEndedCarryFullTravel() {
    XCTAssertEqual(iss_swipe_progress_for_phase(phaseChanged, ISSDirectionRight), 1.0)
    XCTAssertEqual(iss_swipe_progress_for_phase(phaseEnded, ISSDirectionRight), 1.0)
    XCTAssertEqual(iss_swipe_progress_for_phase(phaseChanged, ISSDirectionLeft), -1.0)
    XCTAssertEqual(iss_swipe_progress_for_phase(phaseEnded, ISSDirectionLeft), -1.0)
  }

  /// All phases of one gesture must agree on direction.
  func testSignIsConsistentAcrossPhases() {
    for direction in [ISSDirectionLeft, ISSDirectionRight] {
      let signs = [phaseBegan, phaseChanged, phaseEnded].map {
        iss_swipe_progress_for_phase($0, direction).sign
      }
      XCTAssertEqual(Set(signs).count, 1, "phases disagree on direction for \(direction)")
    }
  }
}
