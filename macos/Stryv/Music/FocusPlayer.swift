import AppKit
import StryvCore
import WebKit

/// Focus music. The YouTube embed player lives for the whole app session in an invisible
/// window, so music keeps playing when the popover closes. Stryv's own buttons drive it
/// through its JavaScript API. In video mode the same web view moves into the popover;
/// moving it doesn't interrupt playback.
///
/// The player page comes from youtube-nocookie.com, which keeps working while youtube.com is
/// blocked.
@MainActor
final class FocusPlayer: NSObject, ObservableObject {
    static let defaultPlaylists = [
        FocusPlaylist(id: "PLm1EodmV4HIjT0EjDGKFsWU5vOidU2rtW", name: "Deep Focus"),
        FocusPlaylist(id: "PLAU5-CEOGjbuJmA2gmtvO0hsE3DK78NUX", name: "brain.fm"),
        FocusPlaylist(id: "PLLLbpwy-JBzA", name: "alex shouting at me"),
    ]

    enum PlaybackState: Equatable {
        case loading
        case ready
        case playing
        case paused
        case buffering
        case failed(String)
    }

    @Published private(set) var playlists: [FocusPlaylist] {
        didSet { savePlaylists() }
    }
    @Published private(set) var selectedID: String?
    @Published private(set) var state: PlaybackState = .loading
    @Published private(set) var trackTitle: String?
    @Published private(set) var videoID: String?
    @Published private(set) var trackIndex = 0
    @Published private(set) var trackCount = 0
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// 0...100. Remembered, and re-applied on every track so YouTube never resets it.
    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: Keys.volume)
            applyVolume()
        }
    }

    /// Show the video in the popover instead of playing audio only. Remembered.
    @Published var showsVideo: Bool {
        didSet { UserDefaults.standard.set(showsVideo, forKey: Keys.showsVideo) }
    }

    private let webView: WKWebView
    private let hostWindow: NSWindow
    private let hostContainer = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 270))
    private var refreshedTrackLists = Set<String>()
    private var loadGeneration = 0
    private var currentNavigation: WKNavigation?
    private var retryCount = 0

    private enum Keys {
        static let playlists = "focusPlaylists"
        static let selected = "focusPlaylistSelected"
        static let volume = "focusVolume"
        static let showsVideo = "focusShowsVideo"
        static let seeded = "focusSeededPlaylists"
    }

    override init() {
        let defaults = UserDefaults.standard
        var loaded = Self.defaultPlaylists
        if let data = defaults.data(forKey: Keys.playlists),
           let saved = try? JSONDecoder().decode([FocusPlaylist].self, from: data) {
            loaded = saved
        }
        // Add built-in playlists once; if you remove one, it stays removed.
        var seeded = Set(defaults.stringArray(forKey: Keys.seeded) ?? loaded.map(\.id))
        for playlist in Self.defaultPlaylists where !seeded.contains(playlist.id) {
            if !loaded.contains(where: { $0.id == playlist.id }) { loaded.append(playlist) }
            seeded.insert(playlist.id)
        }
        defaults.set(Array(seeded), forKey: Keys.seeded)
        playlists = loaded
        showsVideo = defaults.bool(forKey: Keys.showsVideo)
        let savedSelection = defaults.string(forKey: Keys.selected)
        selectedID = loaded.contains(where: { $0.id == savedSelection }) ? savedSelection : loaded.first?.id
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 40

        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 270), configuration: configuration)

        // An invisible, click-through window far off screen keeps the player alive.
        hostWindow = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 480, height: 270),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.alphaValue = 0
        hostWindow.ignoresMouseEvents = true
        hostWindow.isReleasedWhenClosed = false
        hostWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hostWindow.contentView = hostContainer
        webView.autoresizingMask = [.width, .height]
        webView.frame = hostContainer.bounds
        hostContainer.addSubview(webView)

        super.init()
        configuration.userContentController.add(WeakScriptHandler(self), name: "stryvPlayer")
        webView.navigationDelegate = self
        hostWindow.orderFrontRegardless()
        loadSelected()

        // Cache every playlist's tracks while youtube.com is reachable, so switching
        // playlists still works later during a block.
        Task { [weak self] in
            guard let self else { return }
            for playlist in self.playlists where playlist.id != self.selectedID && (playlist.videoIDs ?? []).isEmpty {
                await self.refreshTrackList(for: playlist.id)
            }
        }
    }

    var selectedPlaylist: FocusPlaylist? {
        playlists.first { $0.id == selectedID }
    }

    var isPlaying: Bool { state == .playing || state == .buffering }

    var artworkURL: URL? {
        videoID.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/mqdefault.jpg") }
    }

    // MARK: - Controls

    func togglePlayback() {
        run(isPlaying ? "p.pauseVideo()" : "p.playVideo()")
    }

    func nextTrack() {
        run("p.nextVideo()")
    }

    func previousTrack() {
        // Like a music app: restart the track unless it just began.
        run(position > 3 ? "p.seekTo(0, true)" : "p.previousVideo()")
    }

    func seek(to fraction: Double) {
        guard duration > 0 else { return }
        let seconds = max(0, min(duration, fraction * duration))
        position = seconds
        run("p.seekTo(\(seconds), true)")
    }

    // MARK: - Playlists

    func select(_ playlistID: String) {
        guard playlistID != selectedID else { return }
        selectedID = playlistID
        UserDefaults.standard.set(playlistID, forKey: Keys.selected)
        loadSelected()
    }

    /// Returns an error message, or nil when the playlist was added. Without a name, the
    /// playlist's YouTube title is used once it's fetched.
    func addPlaylist(link: String, name: String) -> String? {
        guard let id = FocusPlaylist.playlistID(from: link) else {
            return "Paste a YouTube playlist link (it contains “list=”)."
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !playlists.contains(where: { $0.id == id }) {
            playlists.append(FocusPlaylist(id: id, name: trimmedName.isEmpty ? "New playlist" : trimmedName))
        }
        refreshedTrackLists.remove(id)
        select(id)
        if trimmedName.isEmpty {
            Task { await refreshTrackList(for: id, renameFromTitle: true) }
        }
        return nil
    }

    func removeSelectedPlaylist() {
        guard let selectedID else { return }
        playlists.removeAll { $0.id == selectedID }
        self.selectedID = nil
        if let first = playlists.first?.id {
            select(first)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.selected)
            loadSelected()
        }
    }

    func reload() {
        if let selectedID { refreshedTrackLists.remove(selectedID) }
        loadSelected()
    }

    // MARK: - Video mode

    /// Moves the player into a view in the popover. Playback continues uninterrupted.
    func showVideo(in container: NSView) {
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        container.addSubview(webView)
    }

    /// Moves the player back to its invisible window (audio-only).
    func hideVideo(from container: NSView) {
        guard webView.superview === container else { return }
        webView.removeFromSuperview()
        webView.frame = hostContainer.bounds
        hostContainer.addSubview(webView)
    }

    // MARK: - Track lists

    /// Reads the playlist's videos from its YouTube page and caches them. Fails quietly
    /// (for example while youtube.com is blocked); the cached list or YouTube's own playlist
    /// embed is used instead.
    @discardableResult
    private func refreshTrackList(for playlistID: String, renameFromTitle: Bool = false) async -> Bool {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return false }
        var request = URLRequest(url: playlist.pageURL, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else { return false }
        refreshedTrackLists.insert(playlistID)
        let videoIDs = YouTubePlaylistPage.videoIDs(in: html, playlistID: playlistID)
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return false }
        if !videoIDs.isEmpty, playlists[index].videoIDs != videoIDs {
            playlists[index].videoIDs = videoIDs
        }
        if renameFromTitle, let title = YouTubePlaylistPage.title(in: html) {
            playlists[index].name = title
        }
        return !videoIDs.isEmpty
    }

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: Keys.playlists)
        }
    }

    // MARK: - Player plumbing

    private func loadSelected() {
        state = .loading
        trackTitle = nil
        videoID = nil
        position = 0
        duration = 0
        trackIndex = 0
        trackCount = 0
        loadGeneration += 1
        retryCount = 0
        let generation = loadGeneration
        guard let playlist = selectedPlaylist else {
            webView.loadHTMLString("<html></html>", baseURL: nil)
            return
        }
        if refreshedTrackLists.contains(playlist.id) {
            loadPlayer(for: playlist)
            return
        }
        // Get a fresh track list first when there isn't one yet; otherwise play the cached
        // one right away and refresh it in the background for next time.
        let hasCache = !(playlist.videoIDs ?? []).isEmpty
        if hasCache { loadPlayer(for: playlist) }
        Task {
            await refreshTrackList(for: playlist.id)
            guard !hasCache, generation == loadGeneration, let current = selectedPlaylist else { return }
            loadPlayer(for: current)
        }
    }

    private func loadPlayer(for playlist: FocusPlaylist) {
        var components = URLComponents(url: playlist.embedURL, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "enablejsapi", value: "1")]
        var request = URLRequest(url: components.url!)
        // YouTube refuses embeds that don't come from a web page.
        request.setValue("https://stryv.app/", forHTTPHeaderField: "Referer")
        currentNavigation = webView.load(request)
    }

    /// Retry delays after a failed load (network hiccups), before showing an error.
    private static let retryDelays: [TimeInterval] = [2, 5, 10]

    fileprivate func navigationFinished(_ navigation: WKNavigation?) {
        if navigation === currentNavigation { retryCount = 0 }
    }

    fileprivate func navigationFailed(_ navigation: WKNavigation?, error: Error) {
        // Only the latest load counts. Switching playlists cancels the previous load, and
        // that cancellation (or any other stale failure) must not mark the new one failed.
        guard navigation === currentNavigation else { return }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return } // interrupted by policy change

        guard retryCount < Self.retryDelays.count else {
            state = .failed("Couldn't load the player. Check your connection and try again.")
            return
        }
        let delay = Self.retryDelays[retryCount]
        retryCount += 1
        state = .loading
        let generation = loadGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, generation == self.loadGeneration, let playlist = self.selectedPlaylist else { return }
            self.loadPlayer(for: playlist)
        }
    }

    private func run(_ command: String) {
        let script = "(() => { const p = document.getElementById('movie_player'); if (p && p.playVideo) { \(command); } })()"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func applyVolume() {
        run("p.unMute(); p.setVolume(\(Int(volume.rounded())))")
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        if let error = message["error"] as? Int {
            state = .failed(error == 150 || error == 101
                ? "This playlist can't be played outside YouTube. Make sure it's Public or Unlisted."
                : "YouTube couldn't play this track (error \(error)).")
            return
        }
        let previousVideo = videoID
        let wasPlaying = state == .playing
        if let title = message["title"] as? String, !title.isEmpty { trackTitle = title }
        if let id = message["videoId"] as? String, id.count == 11 { videoID = id }
        if let time = message["time"] as? Double { position = time }
        if let total = message["duration"] as? Double { duration = total }
        if let index = message["index"] as? Int { trackIndex = index }
        if let count = message["count"] as? Int { trackCount = count }
        if let playerState = message["state"] as? Int {
            switch playerState {
            case 1: state = .playing
            case 2: state = .paused
            case 3: state = .buffering
            case -1, 0, 5: state = .ready
            default: break
            }
        }
        // YouTube resets volume per track, so re-apply ours when the player is ready, the
        // track changes, or playback starts.
        if message["ready"] as? Bool == true || videoID != previousVideo || (!wasPlaying && state == .playing) {
            applyVolume()
        }
    }

    /// Reports player events to Stryv: readiness, state changes, track changes, and the
    /// position once a second while playing.
    private static let bridgeScript = """
    (() => {
      const post = (extra) => {
        const p = document.getElementById('movie_player');
        if (!p || !p.getPlayerState) return;
        const d = p.getVideoData ? p.getVideoData() : {};
        const list = (p.getPlaylist && p.getPlaylist()) || [];
        window.webkit.messageHandlers.stryvPlayer.postMessage(Object.assign({
          state: p.getPlayerState(),
          time: p.getCurrentTime ? p.getCurrentTime() : 0,
          duration: p.getDuration ? p.getDuration() : 0,
          title: d.title || '',
          videoId: d.video_id || '',
          index: p.getPlaylistIndex ? p.getPlaylistIndex() : 0,
          count: list.length
        }, extra || {}));
      };
      const attach = () => {
        const p = document.getElementById('movie_player');
        if (!p || !p.addEventListener || !p.getPlayerState) { setTimeout(attach, 250); return; }
        p.addEventListener('onStateChange', () => post());
        p.addEventListener('onError', (code) => window.webkit.messageHandlers.stryvPlayer.postMessage({ error: Number(code) }));
        setInterval(() => { if (p.getPlayerState() === 1) post(); }, 1000);
        post({ ready: true });
      };
      attach();
    })();
    """
}

extension FocusPlayer: WKNavigationDelegate {
    /// The player page may only load YouTube's embed; anything else (such as "Watch on
    /// YouTube") is refused.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.targetFrame?.isMainFrame ?? true else {
            decisionHandler(.allow)
            return
        }
        let host = navigationAction.request.url?.host ?? ""
        let allowed = host.isEmpty || host == "www.youtube-nocookie.com" || navigationAction.request.url?.scheme == "about"
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationFinished(navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error: error)
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var player: FocusPlayer?

    init(_ player: FocusPlayer) {
        self.player = player
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { player?.receive(body) }
    }
}
