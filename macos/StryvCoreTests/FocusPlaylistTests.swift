import Testing
@testable import StryvCore

struct FocusPlaylistTests {
    @Test func parsesPlaylistLinks() {
        #expect(FocusPlaylist.playlistID(from: "https://youtube.com/playlist?list=PLm1EodmV4HIjT0EjDGKFsWU5vOidU2rtW&si=7uKcJ2ahbcJsYXnO")
            == "PLm1EodmV4HIjT0EjDGKFsWU5vOidU2rtW")
        #expect(FocusPlaylist.playlistID(from: "https://www.youtube.com/watch?v=abc&list=PLAU5-CEOGjbuJmA2gmtvO0hsE3DK78NUX")
            == "PLAU5-CEOGjbuJmA2gmtvO0hsE3DK78NUX")
        #expect(FocusPlaylist.playlistID(from: "PLm1EodmV4HIjT0EjDGKFsWU5vOidU2rtW") == "PLm1EodmV4HIjT0EjDGKFsWU5vOidU2rtW")
        #expect(FocusPlaylist.playlistID(from: "https://youtube.com/watch?v=abc") == nil)
    }

    @Test func embedsThroughNoCookieHost() {
        let url = FocusPlaylist(id: "PLm1EodmV4HIjT0EjDGKFsWU5vOidU2rtW", name: "x").embedURL
        #expect(url.host == "www.youtube-nocookie.com")
        #expect(url.absoluteString.contains("list=PLm1EodmV4HIjT0EjDGKFsWU5vOidU2rtW"))
    }
}

struct PlaylistQueueTests {
    @Test func playsCachedVideosAsAnExplicitQueue() throws {
        let playlist = FocusPlaylist(id: "PLAU5-CEOGjbuJmA2gmtvO0hsE3DK78NUX", name: "x", videoIDs: ["NHOFkcun06s", "IMerWLNDYxU"])
        let url = playlist.embedURL
        #expect(url.host == "www.youtube-nocookie.com")
        #expect(url.path == "/embed/NHOFkcun06s")
        #expect(url.absoluteString.contains("playlist=NHOFkcun06s,IMerWLNDYxU"))
    }

    @Test func readsVideoIDsInPlaylistOrder() {
        let id = "PLAU5-CEOGjbuJmA2gmtvO0hsE3DK78NUX"
        let html = """
        <meta property="og:title" content="brain &amp; focus">
        "watchEndpoint":{"videoId":"BBBBBBBBBBB","playlistId":"\(id)","index":1}
        "watchEndpoint":{"videoId":"AAAAAAAAAAA","playlistId":"\(id)","index":0}
        "watchEndpoint":{"videoId":"BBBBBBBBBBB","playlistId":"\(id)","index":1}
        "watchEndpoint":{"videoId":"ZZZZZZZZZZZ","playlistId":"PLsomethingElse12345","index":0}
        "watchEndpoint":{"videoId":"CCCCCCCCCCC","playlistId":"\(id)","index":2}
        """
        #expect(YouTubePlaylistPage.videoIDs(in: html, playlistID: id) == ["AAAAAAAAAAA", "BBBBBBBBBBB", "CCCCCCCCCCC"])
        #expect(YouTubePlaylistPage.title(in: html) == "brain & focus")
    }
}
