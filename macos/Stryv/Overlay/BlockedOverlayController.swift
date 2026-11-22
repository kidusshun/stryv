import AppKit
import Combine
import SwiftUI
import StryvCore

@MainActor
final class BlockedOverlayState: ObservableObject {
    @Published var domain = ""
    @Published var endsAt = Date()
    @Published var quote = ""
}

/// Shows the native "this site is blocked" panel over the browser's page area while a block
/// is active, and wires the browser watcher to the block and the Accessibility permission.
@MainActor
final class BlockedOverlayController: ObservableObject {
    private let model: BlockModel
    private let watcher = BrowserWatcher()
    private let state = BlockedOverlayState()
    /// Created the first time a blocked page is shown.
    private var existingPanel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var trustObserver: NSObjectProtocol?
    private var currentMatch: BlockedPageMatch?
    private var quotes = QuoteDeck.focus
    private var quoteTimer: Timer?
    /// How long each quote stays up while the blocked screen is showing.
    private static let quoteInterval: TimeInterval = 20

    @Published private(set) var isAccessibilityTrusted = AX.isTrusted

    init(model: BlockModel) {
        self.model = model
        watcher.onChange = { [weak self] match in self?.show(match) }

        model.$status
            .map { $0?.block }
            .removeDuplicates()
            .sink { [weak self] _ in
                // Let the @Published value land before reading the model.
                DispatchQueue.main.async { self?.syncWithBlock() }
            }
            .store(in: &cancellables)

        // macOS broadcasts this whenever any app's Accessibility permission changes.
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.syncWithBlock() }
            }
        }
    }

    func requestAccessibility() {
        AX.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func syncWithBlock() {
        isAccessibilityTrusted = AX.isTrusted
        if let block = model.status?.block, block.isActive(at: Date()), isAccessibilityTrusted {
            state.endsAt = block.endsAt
            watcher.start(domains: block.domains)
        } else {
            watcher.stop()
            show(nil)
        }
    }

    private func show(_ match: BlockedPageMatch?) {
        let wasShowing = currentMatch != nil
        let previousDomain = currentMatch?.domain
        currentMatch = match
        guard let match else {
            existingPanel?.orderOut(nil)
            stopQuoteRotation()
            return
        }
        // A fresh quote every time the screen appears or moves to another blocked site.
        if !wasShowing || previousDomain != match.domain {
            state.quote = quotes.next()
            startQuoteRotation()
        }
        state.domain = match.domain
        let panel = existingPanel ?? makePanel()
        existingPanel = panel
        panel.setFrame(match.frame, display: true)
        panel.orderFrontRegardless()
    }

    /// Shuffles to the next quote every `quoteInterval` seconds, only while the screen is up.
    private func startQuoteRotation() {
        quoteTimer?.invalidate()
        let timer = Timer(timeInterval: Self.quoteInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.6)) { self.state.quote = self.quotes.next() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        quoteTimer = timer
    }

    private func stopQuoteRotation() {
        quoteTimer?.invalidate()
        quoteTimer = nil
    }

    private func closeTab() {
        guard let match = currentMatch else { return }
        // ⌘W in the browser, which closes the current tab.
        let source = CGEventSource(stateID: .hidSystemState)
        let keyW: CGKeyCode = 13
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyW, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.postToPid(match.processIdentifier)
        }
    }

    #if DEBUG
    /// Renders the blocked screen to a PNG (STRYV_OVERLAY_SNAPSHOT=/path.png).
    func saveDebugSnapshot(to path: String) {
        let sample = BlockedOverlayState()
        sample.domain = "youtube.com"
        sample.endsAt = Date().addingTimeInterval(47 * 60 + 12)
        sample.quote = QuoteDeck.focus.quotes[0]
        let hostingView = NSHostingView(rootView: BlockedOverlayView(state: sample) {})
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 1100, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
        window.contentView = hostingView
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            window.orderOut(nil)
        }
    }
    #endif

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = BlockedOverlayView(state: state) { [weak self] in self?.closeTab() }
        let hostingView = NSHostingView(rootView: view)
        // The panel's size comes from the browser window, never from the SwiftUI content.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        return panel
    }
}
