import Foundation

/// Parses typed durations into whole minutes: "2", "2m", "45 min", "1h", "1.5h", "1h30",
/// "1h 30m", "1:30", "90 minutes", "1 hour and 30 minutes".
public enum DurationParser {
    public static let minimumMinutes = Int(StryvConstants.minimumBlockDuration / 60)
    public static let maximumMinutes = Int(StryvConstants.maximumBlockDuration / 60)

    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"(\d+(?:\.\d+)?)\s*(hours|hour|hrs|hr|h|minutes|minute|mins|min|m)?"#
    )

    /// Phrases meaning "until midnight tonight".
    public static let restOfDayPhrases: Set<String> = ["rest of day", "rest of the day", "today", "until midnight", "eod", "end of day"]

    public static func isRestOfDay(_ text: String) -> Bool {
        restOfDayPhrases.contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Minutes within the allowed block range, or nil when the text isn't a valid duration.
    /// "Rest of day" means until midnight tonight, measured from `now`.
    public static func minutes(from text: String, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        let minutes: Int?
        if isRestOfDay(text) {
            minutes = minutesUntilMidnight(from: now, calendar: calendar)
        } else {
            minutes = parse(text)
        }
        guard let minutes, (minimumMinutes...maximumMinutes).contains(minutes) else { return nil }
        return minutes
    }

    /// Whole minutes until the start of tomorrow (at least 1).
    public static func minutesUntilMidnight(from now: Date, calendar: Calendar = .current) -> Int {
        let startOfToday = calendar.startOfDay(for: now)
        let midnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
        return max(1, Int((midnight.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// Any positive duration in minutes, ignoring the allowed range.
    public static func parse(_ text: String) -> Int? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !input.isEmpty else { return nil }

        // "1:30" means hours and minutes.
        let clock = input.split(separator: ":", omittingEmptySubsequences: false)
        if clock.count == 2 {
            guard let hours = Int(clock[0]), clock[1].count == 2, let minutes = Int(clock[1]), minutes < 60 else { return nil }
            let total = hours * 60 + minutes
            return total > 0 ? total : nil
        }

        let nsInput = input as NSString
        var total = 0.0
        var leftover = input
        for match in tokenPattern.matches(in: input, range: NSRange(location: 0, length: nsInput.length)) {
            guard let value = Double(nsInput.substring(with: match.range(at: 1))) else { return nil }
            let unit = match.range(at: 2).location == NSNotFound ? "" : nsInput.substring(with: match.range(at: 2))
            // Hours count as 60 minutes; minutes, and bare numbers ("90", the "30" in "1h30"), as minutes.
            total += unit.hasPrefix("h") ? value * 60 : value
            leftover = leftover.replacingOccurrences(of: nsInput.substring(with: match.range), with: " ")
        }

        // Nothing else may remain except spacing, commas and "and".
        let remainder = leftover.replacingOccurrences(of: "and", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",")))
        guard remainder.isEmpty, total > 0 else { return nil }
        return Int(total.rounded())
    }
}
