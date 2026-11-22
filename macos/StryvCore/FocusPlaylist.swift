import Foundation

public struct FocusPlaylist: Codable, Hashable, Identifiable, Sendable {
    /// The YouTube playlist ID (the `list=` value).
    public var id: String
    public var name: String
    /// The playlist's videos in order, read from its YouTube page and cached. Playing these
    /// as an explicit queue works even when YouTube's playlist embed refuses the list, and
    /// while youtube.com itself is blocked.
    public var videoIDs: [String]?

    public init(id: String, name: String, videoIDs: [String]? = nil) {
        self.id = id
        self.name = name
        self.videoIDs = videoIDs
    }

    /// Played through YouTube's privacy-enhanced embed host, which keeps working while
    /// youtube.com itself is blocked.
    public var embedURL: URL {
        let videos = videoIDs ?? []
        var components: URLComponents
        if let first = videos.first {
            components = URLComponents(string: "https://www.youtube-nocookie.com/embed/\(first)")!
            components.queryItems = [URLQueryItem(name: "playlist", value: videos.joined(separator: ","))]
        } else {
            components = URLComponents(string: "https://www.youtube-nocookie.com/embed/videoseries")!
            components.queryItems = [URLQueryItem(name: "list", value: id)]
        }
        components.queryItems! += [
            URLQueryItem(name: "rel", value: "0"),
            URLQueryItem(name: "playsinline", value: "1"),
        ]
        return components.url!
    }

    public var pageURL: URL {
        URL(string: "https://www.youtube.com/playlist?list=\(id)")!
    }

    /// Accepts a playlist URL (youtube.com, youtu.be, music.youtube.com) or a bare playlist ID.
    public static func playlistID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed),
           let list = components.queryItems?.first(where: { $0.name == "list" })?.value {
            return isValidID(list) ? list : nil
        }
        return isValidID(trimmed) ? trimmed : nil
    }

    static func isValidID(_ id: String) -> Bool {
        id.count >= 10 && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}

/// Reads a YouTube playlist page (youtube.com/playlist?list=…).
public enum YouTubePlaylistPage {
    /// The playlist's video IDs in playlist order (the first 100 the page includes).
    public static func videoIDs(in html: String, playlistID: String) -> [String] {
        let escapedID = NSRegularExpression.escapedPattern(for: playlistID)
        let pattern = #""watchEndpoint":\{"videoId":"([A-Za-z0-9_-]{11})","playlistId":""# + escapedID + #"","index":(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = html as NSString
        var byIndex: [Int: String] = [:]
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            guard let index = Int(text.substring(with: match.range(at: 2))) else { continue }
            if byIndex[index] == nil {
                byIndex[index] = text.substring(with: match.range(at: 1))
            }
        }
        var seen = Set<String>()
        return byIndex.keys.sorted().compactMap { byIndex[$0] }.filter { seen.insert($0).inserted }
    }

    /// The playlist's title from the page's Open Graph tag.
    public static func title(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta property="og:title" content="([^"]*)""#),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length))
        else { return nil }
        let title = (html as NSString).substring(with: match.range(at: 1))
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return title.isEmpty ? nil : title
    }
}
