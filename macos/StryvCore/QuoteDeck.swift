import Foundation

/// Deals quotes in a shuffled order: every quote appears once before any repeats, and the
/// same quote never shows twice in a row, even when the deck reshuffles.
public struct QuoteDeck: Sendable {
    public let quotes: [String]
    private var remaining: [String] = []
    private var last: String?

    public init(quotes: [String]) {
        self.quotes = quotes
    }

    public mutating func next() -> String {
        guard !quotes.isEmpty else { return "" }
        guard quotes.count > 1 else { return quotes[0] }
        if remaining.isEmpty {
            remaining = quotes.shuffled()
            if remaining.last == last {
                remaining.swapAt(remaining.count - 1, 0)
            }
        }
        let quote = remaining.removeLast()
        last = quote
        return quote
    }

    public static let focus = QuoteDeck(quotes: [
        "If you're so smart, why aren't you rich?",
        "You didn't come this far to scroll.",
        "Nobody is coming to do the work for you.",
        "Discipline is choosing what you want most over what you want now.",
        "The feed will still be there. Your deadline won't wait.",
        "Future you is watching. Make them proud.",
        "Do the hard thing first.",
        "You don't need more time. You need fewer tabs.",
        "Small daily wins compound.",
        "Every minute here is a minute stolen from what you said mattered.",
        "Busy isn't the same as productive.",
        "Close the tab. Open the work.",
    ])
}
