import Foundation

/// Renders the Stryv-managed section of /etc/hosts. Everything outside the markers is
/// left exactly as the user wrote it.
public enum HostsFile {
    public static let beginMarker = "# >>> Stryv block (managed by Stryv, removed automatically when the block ends) >>>"
    public static let endMarker = "# <<< Stryv block <<<"

    public static func stripManagedSection(from contents: String) -> String {
        var output: [Substring] = []
        var insideSection = false
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == beginMarker {
                insideSection = true
                continue
            }
            if insideSection {
                if trimmed == endMarker { insideSection = false }
                continue
            }
            output.append(line)
        }
        return output.joined(separator: "\n")
    }

    /// The hosts file with the managed section replaced by entries for `domains`
    /// (or removed entirely when `domains` is empty). Idempotent.
    public static func render(_ contents: String, blocking domains: [String]) -> String {
        var base = stripManagedSection(from: contents)
        let hosts = DomainRules.hostsToBlock(for: domains)
        guard !hosts.isEmpty else { return base }
        if !base.isEmpty, !base.hasSuffix("\n") { base += "\n" }
        var section = beginMarker + "\n"
        for host in hosts {
            section += "0.0.0.0 \(host)\n:: \(host)\n"
        }
        section += endMarker + "\n"
        return base + section
    }
}
