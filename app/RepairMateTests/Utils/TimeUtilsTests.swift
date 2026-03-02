/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import RepairMate

final class TimeUtilsTests: XCTestCase {

  // MARK: - StreamTimeLimit Tests

  func testAllCasesExist() {
    let allCases = StreamTimeLimit.allCases
    XCTAssertEqual(allCases.count, 5)
    XCTAssertTrue(allCases.contains(.oneMinute))
    XCTAssertTrue(allCases.contains(.fiveMinutes))
    XCTAssertTrue(allCases.contains(.tenMinutes))
    XCTAssertTrue(allCases.contains(.fifteenMinutes))
    XCTAssertTrue(allCases.contains(.noLimit))
  }

  func testRawValues() {
    XCTAssertEqual(StreamTimeLimit.oneMinute.rawValue, "1min")
    XCTAssertEqual(StreamTimeLimit.fiveMinutes.rawValue, "5min")
    XCTAssertEqual(StreamTimeLimit.tenMinutes.rawValue, "10min")
    XCTAssertEqual(StreamTimeLimit.fifteenMinutes.rawValue, "15min")
    XCTAssertEqual(StreamTimeLimit.noLimit.rawValue, "noLimit")
  }

  func testDisplayText() {
    XCTAssertEqual(StreamTimeLimit.oneMinute.displayText, "1m")
    XCTAssertEqual(StreamTimeLimit.fiveMinutes.displayText, "5m")
    XCTAssertEqual(StreamTimeLimit.tenMinutes.displayText, "10m")
    XCTAssertEqual(StreamTimeLimit.fifteenMinutes.displayText, "15m")
    XCTAssertEqual(StreamTimeLimit.noLimit.displayText, "No limit")
  }

  func testDurationInSeconds() {
    XCTAssertEqual(StreamTimeLimit.oneMinute.durationInSeconds, 60)
    XCTAssertEqual(StreamTimeLimit.fiveMinutes.durationInSeconds, 300)
    XCTAssertEqual(StreamTimeLimit.tenMinutes.durationInSeconds, 600)
    XCTAssertEqual(StreamTimeLimit.fifteenMinutes.durationInSeconds, 900)
    XCTAssertNil(StreamTimeLimit.noLimit.durationInSeconds)
  }

  func testIsTimeLimited() {
    XCTAssertTrue(StreamTimeLimit.oneMinute.isTimeLimited)
    XCTAssertTrue(StreamTimeLimit.fiveMinutes.isTimeLimited)
    XCTAssertTrue(StreamTimeLimit.tenMinutes.isTimeLimited)
    XCTAssertTrue(StreamTimeLimit.fifteenMinutes.isTimeLimited)
    XCTAssertFalse(StreamTimeLimit.noLimit.isTimeLimited)
  }

  func testNextCyclesThroughAllCases() {
    XCTAssertEqual(StreamTimeLimit.oneMinute.next, .fiveMinutes)
    XCTAssertEqual(StreamTimeLimit.fiveMinutes.next, .tenMinutes)
    XCTAssertEqual(StreamTimeLimit.tenMinutes.next, .fifteenMinutes)
    XCTAssertEqual(StreamTimeLimit.fifteenMinutes.next, .noLimit)
    XCTAssertEqual(StreamTimeLimit.noLimit.next, .oneMinute)
  }

  func testNextCyclesBackToStart() {
    var current: StreamTimeLimit = .oneMinute
    for _ in 0..<5 {
      current = current.next
    }
    XCTAssertEqual(current, .oneMinute)
  }

  // MARK: - TimeInterval Extension Tests

  func testFormattedCountdownZero() {
    let interval: TimeInterval = 0
    XCTAssertEqual(interval.formattedCountdown, "0:00")
  }

  func testFormattedCountdownLessThanOneMinute() {
    let interval: TimeInterval = 45
    XCTAssertEqual(interval.formattedCountdown, "0:45")
  }

  func testFormattedCountdownExactlyOneMinute() {
    let interval: TimeInterval = 60
    XCTAssertEqual(interval.formattedCountdown, "1:00")
  }

  func testFormattedCountdownMultipleMinutes() {
    let interval: TimeInterval = 125
    XCTAssertEqual(interval.formattedCountdown, "2:05")
  }

  func testFormattedCountdownLargeValue() {
    let interval: TimeInterval = 3661 // 1 hour, 1 minute, 1 second
    XCTAssertEqual(interval.formattedCountdown, "61:01")
  }

  func testFormattedCountdownPadsSeconds() {
    let interval: TimeInterval = 301 // 5 minutes, 1 second
    XCTAssertEqual(interval.formattedCountdown, "5:01")
  }

  func testFormattedCountdownNegativeValue() {
    let interval: TimeInterval = -30
    XCTAssertEqual(interval.formattedCountdown, "0:30") // abs value
  }
}
