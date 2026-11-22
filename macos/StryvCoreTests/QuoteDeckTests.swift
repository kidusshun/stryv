import Testing
@testable import StryvCore

struct QuoteDeckTests {
    @Test func showsEveryQuoteBeforeRepeating() {
        var deck = QuoteDeck(quotes: ["a", "b", "c", "d"])
        let firstRound = (0..<4).map { _ in deck.next() }
        #expect(Set(firstRound) == ["a", "b", "c", "d"])
    }

    @Test func neverRepeatsBackToBack() {
        var deck = QuoteDeck(quotes: ["a", "b", "c"])
        var previous = deck.next()
        for _ in 0..<300 {
            let quote = deck.next()
            #expect(quote != previous)
            previous = quote
        }
    }

    @Test func includesTheRequestedQuote() {
        #expect(QuoteDeck.focus.quotes.contains("If you're so smart, why aren't you rich?"))
    }
}
