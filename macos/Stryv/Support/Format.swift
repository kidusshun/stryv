import Foundation

enum Format {
    /// "1:23:45" or "4:05".
    static func countdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Media-player time: "3:07", "1:02:45".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Compact remaining time for the menu bar: "1h 23m", "12m", "<1m".
    static func menuBarRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "<1m" }
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// "25m", "1h", "1h 30m".
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest)m"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(rest)m"
        }
    }

    /// "2 minutes", "1 hour", "1 hour 30 minutes".
    static func spokenDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
        let minuteText = rest == 1 ? "1 minute" : "\(rest) minutes"
        switch (hours, rest) {
        case (0, _): return minuteText
        case (_, 0): return hourText
        default: return "\(hourText) \(minuteText)"
        }
    }

    /// "4:30 PM", "midnight", or "Tue 4:30 PM" when it isn't today.
    static func endTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if Calendar.current.isDateInTomorrow(date), date.timeIntervalSince(calendar.startOfDay(for: date)) < 60 {
            return "midnight"
        }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
