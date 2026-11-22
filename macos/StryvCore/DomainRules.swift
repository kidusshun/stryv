import Foundation

public enum DomainRules {
    /// Subdomains added for every blocked domain, because /etc/hosts has no wildcards.
    public static let subdomainPrefixes = ["www", "m", "mobile"]

    /// Turns user input ("https://www.YouTube.com/watch?v=1", "*.x.com", "reddit.com:443")
    /// into a bare lowercase domain ("youtube.com"), or nil when it isn't a website.
    public static func normalize(_ input: String) -> String? {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = host.range(of: "://") {
            host = String(host[scheme.upperBound...])
        }
        if let end = host.firstIndex(where: { "/?#".contains($0) }) {
            host = String(host[..<end])
        }
        if let at = host.lastIndex(of: "@") {
            host = String(host[host.index(after: at)...])
        }
        if let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        while host.hasPrefix("*.") {
            host.removeFirst(2)
        }
        host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host.hasPrefix("www."), host.dropFirst(4).contains(".") {
            host.removeFirst(4)
        }
        return isValidHostname(host) ? host : nil
    }

    /// Lowercased, de-duplicated, valid domains in their original order.
    public static func normalizedList(_ inputs: [String]) -> [String] {
        var seen = Set<String>()
        return inputs.compactMap(normalize).filter { seen.insert($0).inserted }
    }

    /// Every hostname written to /etc/hosts for the given domains.
    public static func hostsToBlock(for domains: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for domain in domains {
            for host in [domain] + subdomainPrefixes.map({ "\($0).\(domain)" }) where seen.insert(host).inserted {
                result.append(host)
            }
        }
        return result
    }

    /// The domain in `domains` that covers `host` (same domain or a subdomain of it).
    public static func matchingDomain(for host: String, in domains: [String]) -> String? {
        let host = host.lowercased()
        return domains.first { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Extracts a hostname from text that is *entirely* a URL or a bare host
    /// ("youtube.com", "https://www.youtube.com/watch?v=1"). Text with spaces returns nil,
    /// so a page titled "youtube.com - Google Search" never counts as youtube.com.
    public static func host(inAddress text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        var candidate = trimmed.lowercased()
        if let scheme = candidate.range(of: "://") {
            candidate = String(candidate[scheme.upperBound...])
        }
        if let end = candidate.firstIndex(where: { "/?#".contains($0) }) {
            candidate = String(candidate[..<end])
        }
        if let colon = candidate.firstIndex(of: ":") {
            candidate = String(candidate[..<colon])
        }
        return isValidHostname(candidate) ? candidate : nil
    }

    static func isValidHostname(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        for label in labels {
            guard (1...63).contains(label.count),
                  !label.hasPrefix("-"),
                  !label.hasSuffix("-"),
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return false }
        }
        // Reject IP addresses: a real top-level domain is never all digits.
        guard let tld = labels.last, !tld.allSatisfy(\.isNumber) else { return false }
        return true
    }
}
