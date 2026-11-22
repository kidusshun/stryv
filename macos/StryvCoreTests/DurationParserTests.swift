import Foundation
import Testing
@testable import StryvCore

struct DurationParserTests {
    @Test(arguments: [
        ("2", 2),
        ("2m", 2),
        ("2 min", 2),
        ("2 minutes", 2),
        ("45m", 45),
        ("90", 90),
        ("1h", 60),
        ("1 hour", 60),
        ("1.5h", 90),
        ("1h30", 90),
        ("1h 30m", 90),
        ("1 hour and 30 minutes", 90),
        ("2 hours, 15 min", 135),
        ("1:30", 90),
        ("0:05", 5),
        ("24h", 1440),
        ("  3M ", 3),
    ])
    func parsesDurations(text: String, expected: Int) {
        #expect(DurationParser.minutes(from: text) == expected)
    }

    @Test func restOfDayRunsUntilMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Africa/Addis_Ababa"))
        let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 22, minute: 30)))
        #expect(DurationParser.minutes(from: "Rest of day", now: evening, calendar: calendar) == 90)
        #expect(DurationParser.minutes(from: "today", now: evening, calendar: calendar) == 90)
        #expect(DurationParser.minutes(from: "EOD", now: evening, calendar: calendar) == 90)

        let lastSeconds = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23, minute: 59, second: 30)))
        #expect(DurationParser.minutes(from: "rest of the day", now: lastSeconds, calendar: calendar) == 1)

        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 8, minute: 0)))
        #expect(DurationParser.minutes(from: "rest of day", now: morning, calendar: calendar) == 16 * 60)
        #expect(DurationParser.minutes(from: "8h", now: morning, calendar: calendar) == 480)
    }

    @Test(arguments: ["", "0", "0m", "abc", "2 days", "1:5", "1:75", "25h", "-5", "m", "2 m x"])
    func rejectsInvalidOrOutOfRange(text: String) {
        #expect(DurationParser.minutes(from: text) == nil)
    }
}
