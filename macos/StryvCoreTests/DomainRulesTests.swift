import Testing
@testable import StryvCore

struct DomainRulesTests {
    @Test(arguments: [
        ("youtube.com", "youtube.com"),
        ("https://www.YouTube.com/watch?v=1", "youtube.com"),
        ("*.x.com", "x.com"),
        ("news.ycombinator.com:443", "news.ycombinator.com"),
        ("  reddit.com/r/swift  ", "reddit.com"),
        ("user@instagram.com", "instagram.com"),
        ("www.com", "www.com"),
        ("bbc.co.uk.", "bbc.co.uk"),
    ])
    func normalizesWebsites(input: String, expected: String) {
        #expect(DomainRules.normalize(input) == expected)
    }

    @Test(arguments: ["", "localhost", "192.168.0.1", "foo bar.com", "-bad.com", "exa_mple.com", "http://"])
    func rejectsNonWebsites(input: String) {
        #expect(DomainRules.normalize(input) == nil)
    }

    @Test func deduplicatesInOrder() {
        #expect(DomainRules.normalizedList(["x.com", "www.x.com", "nope", "reddit.com"]) == ["x.com", "reddit.com"])
    }

    @Test func expandsCommonSubdomains() {
        #expect(DomainRules.hostsToBlock(for: ["x.com"]) == ["x.com", "www.x.com", "m.x.com", "mobile.x.com"])
    }

    @Test func matchesSubdomainsButNotLookalikes() {
        let domains = ["youtube.com"]
        #expect(DomainRules.matchingDomain(for: "music.youtube.com", in: domains) == "youtube.com")
        #expect(DomainRules.matchingDomain(for: "youtube.com", in: domains) == "youtube.com")
        #expect(DomainRules.matchingDomain(for: "notyoutube.com", in: domains) == nil)
        #expect(DomainRules.matchingDomain(for: "www.youtube-nocookie.com", in: domains) == nil)
    }

    @Test func readsHostsOnlyFromWholeAddresses() {
        #expect(DomainRules.host(inAddress: "youtube.com") == "youtube.com")
        #expect(DomainRules.host(inAddress: "https://www.youtube.com/watch?v=1") == "www.youtube.com")
        #expect(DomainRules.host(inAddress: "youtube.com - Google Search") == nil)
        #expect(DomainRules.host(inAddress: "Failed to open page") == nil)
        #expect(DomainRules.host(inAddress: "chrome-error://chromewebdata/") == nil)
    }
}
