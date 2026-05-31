import XCTest

@testable import KeepAliveCore

@MainActor
final class HoldStackTests: XCTestCase {
  func testPushPopActive() {
    let s = HoldStack()
    XCTAssertFalse(s.active)

    s.push(minutes: 60, now: 0)
    XCTAssertTrue(s.active)
    XCTAssertEqual(s.count, 1)

    s.push(minutes: 60, now: 0)
    XCTAssertEqual(s.count, 2)

    s.pop()
    XCTAssertEqual(s.count, 1)
    XCTAssertTrue(s.active)

    s.pop()
    XCTAssertFalse(s.active)

    // pop on empty is safe
    s.pop()
    XCTAssertEqual(s.count, 0)
  }

  func testSweepRemovesExpiredHoldsOnly() {
    let s = HoldStack()
    s.push(minutes: 1, now: 0)  // expires at 60s
    s.push(minutes: 10, now: 0)  // expires at 600s

    XCTAssertTrue(s.sweep(now: 120))  // first expired -> changed
    XCTAssertEqual(s.count, 1)
    XCTAssertTrue(s.active)

    XCTAssertFalse(s.sweep(now: 300))  // nothing newly expired
    XCTAssertEqual(s.count, 1)

    XCTAssertTrue(s.sweep(now: 700))  // last expired
    XCTAssertFalse(s.active)
  }

  func testNextExpiryIsTheSoonest() {
    let s = HoldStack()
    XCTAssertNil(s.nextExpiry)

    s.push(minutes: 10, now: 0)  // 600
    s.push(minutes: 1, now: 0)  // 60
    XCTAssertEqual(s.nextExpiry, 60)
  }
}
