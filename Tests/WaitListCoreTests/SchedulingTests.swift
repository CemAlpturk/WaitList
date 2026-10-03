import XCTest
@testable import WaitListCore

final class SchedulingTests: XCTestCase {
    private let calendar = TestDates.stockholm
    private let nineAM = DateComponents(hour: 9, minute: 0)

    func testDecideDateAddsDaysAndSetsTimeOfDay() {
        let now = TestDates.date(2026, 10, 3, 15, 42, 17)
        let result = Scheduling.decideDate(from: now, waitDays: 14, time: nineAM, calendar: calendar)
        XCTAssertEqual(result, TestDates.date(2026, 10, 17, 9, 0, 0))
    }

    func testDecideDateUsesMinutes() {
        let now = TestDates.date(2026, 10, 3, 8, 0)
        let result = Scheduling.decideDate(from: now, waitDays: 1,
                                           time: DateComponents(hour: 18, minute: 30), calendar: calendar)
        XCTAssertEqual(result, TestDates.date(2026, 10, 4, 18, 30))
    }

    func testDecideDateClampsWaitDays() {
        let now = TestDates.date(2026, 10, 3, 12, 0)
        XCTAssertEqual(Scheduling.decideDate(from: now, waitDays: 0, time: nineAM, calendar: calendar),
                       TestDates.date(2026, 10, 4, 9, 0))
        XCTAssertEqual(Scheduling.decideDate(from: now, waitDays: -5, time: nineAM, calendar: calendar),
                       TestDates.date(2026, 10, 4, 9, 0))
        XCTAssertEqual(Scheduling.decideDate(from: now, waitDays: 1_000, time: nineAM, calendar: calendar),
                       TestDates.date(2027, 10, 3, 9, 0))
        XCTAssertEqual(Scheduling.decideDate(from: now, waitDays: 365, time: nineAM, calendar: calendar),
                       TestDates.date(2027, 10, 3, 9, 0))
    }

    func testRetimedKeepsTheDay() {
        // Later in the day than the target time: must stay on the same day, not jump forward.
        XCTAssertEqual(Scheduling.retimed(TestDates.date(2026, 3, 10, 23, 30), to: nineAM, calendar: calendar),
                       TestDates.date(2026, 3, 10, 9, 0))
        // Earlier in the day than the target time.
        XCTAssertEqual(Scheduling.retimed(TestDates.date(2026, 3, 10, 0, 15),
                                          to: DateComponents(hour: 21, minute: 45), calendar: calendar),
                       TestDates.date(2026, 3, 10, 21, 45))
    }

    func testRetimedTreatsMissingComponentsAsZeroAndClampsOutOfRange() {
        XCTAssertEqual(Scheduling.retimed(TestDates.date(2026, 3, 10, 14, 0), to: DateComponents(), calendar: calendar),
                       TestDates.date(2026, 3, 10, 0, 0))
        XCTAssertEqual(Scheduling.retimed(TestDates.date(2026, 3, 10, 14, 0),
                                          to: DateComponents(hour: 99, minute: 99), calendar: calendar),
                       TestDates.date(2026, 3, 10, 23, 59))
    }

    func testDecideDateAcrossAutumnDSTStaysAtNineLocal() {
        // Summer time ends in Stockholm on 2026-10-25.
        let now = TestDates.date(2026, 10, 20, 9, 0)
        let result = Scheduling.decideDate(from: now, waitDays: 14, time: nineAM, calendar: calendar)

        XCTAssertEqual(TestDates.parts(result), [2026, 11, 3, 9, 0])
        // Proof that this crossed a DST change: the gap is one hour longer than 14 * 24 hours.
        XCTAssertEqual(result.timeIntervalSince(now), 14 * 86_400 + 3_600)
    }

    func testDecideDateAcrossSpringDSTStaysAtNineLocal() {
        // Summer time starts in Stockholm on 2026-03-29.
        let now = TestDates.date(2026, 3, 25, 9, 0)
        let result = Scheduling.decideDate(from: now, waitDays: 7, time: nineAM, calendar: calendar)

        XCTAssertEqual(TestDates.parts(result), [2026, 4, 1, 9, 0])
        XCTAssertEqual(result.timeIntervalSince(now), 7 * 86_400 - 3_600)
    }
}
