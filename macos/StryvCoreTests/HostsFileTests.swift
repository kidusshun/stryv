import Testing
@testable import StryvCore

struct HostsFileTests {
    let original = """
    ##
    # Host Database
    ##
    127.0.0.1\tlocalhost
    10.0.0.5 nas.home

    """

    @Test func appendsManagedSectionAndKeepsUserEntries() {
        let rendered = HostsFile.render(original, blocking: ["x.com"])
        #expect(rendered.hasPrefix(original))
        #expect(rendered.contains("0.0.0.0 x.com\n"))
        #expect(rendered.contains(":: www.x.com\n"))
        #expect(rendered.hasSuffix(HostsFile.endMarker + "\n"))
    }

    @Test func renderingIsIdempotent() {
        let once = HostsFile.render(original, blocking: ["x.com", "reddit.com"])
        let twice = HostsFile.render(once, blocking: ["x.com", "reddit.com"])
        #expect(once == twice)
    }

    @Test func removingTheBlockRestoresTheOriginal() {
        let blocked = HostsFile.render(original, blocking: ["x.com"])
        #expect(HostsFile.render(blocked, blocking: []) == original)
    }

    @Test func handlesFileWithoutTrailingNewline() {
        let noNewline = "127.0.0.1 localhost"
        let blocked = HostsFile.render(noNewline, blocking: ["x.com"])
        #expect(blocked.hasPrefix("127.0.0.1 localhost\n" + HostsFile.beginMarker))
        #expect(HostsFile.render(blocked, blocking: []) == "127.0.0.1 localhost\n")
    }

    @Test func replacesAnOutdatedSection() {
        let old = HostsFile.render(original, blocking: ["x.com"])
        let updated = HostsFile.render(old, blocking: ["reddit.com"])
        #expect(!updated.contains("x.com"))
        #expect(updated.contains("0.0.0.0 reddit.com"))
    }
}
