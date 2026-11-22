import AppKit
import ApplicationServices
import StryvCore

struct BlockedPageMatch: Equatable {
    var domain: String
    var processIdentifier: pid_t
    /// Where to cover, in Cocoa screen coordinates (bottom-left origin).
    var frame: CGRect
}

/// Notices when the front browser tab is on a blocked site, without polling and without
/// any browser extension. It reads the browser's own window through macOS Accessibility:
///
/// - re-checks only when macOS reports a change: a different app comes to the front, or the
///   browser's focused window, title, position or size changes;
/// - reads the page URL, the address bar and the window title, and matches them against the
///   blocked domains.
@MainActor
final class BrowserWatcher {
    static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.operasoftware.Opera", "com.operasoftware.OperaGX",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser", "company.thebrowser.dia",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "app.zen-browser.zen",
        "com.kagi.kagimacOS",
    ]

    private static let appNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXTitleChangedNotification,
    ]
    private static let windowNotifications = [
        kAXTitleChangedNotification,
        kAXMovedNotification,
        kAXResizedNotification,
        kAXUIElementDestroyedNotification,
    ]

    var onChange: ((BlockedPageMatch?) -> Void)?

    private var domains: [String] = []
    private var isRunning = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var observer: AXObserver?
    private var observedApp: AXUIElement?
    private var observedWindow: AXUIElement?
    private var pendingCheck: DispatchWorkItem?
    private var lastMatch: BlockedPageMatch?

    func start(domains: [String]) {
        self.domains = domains
        guard !isRunning else {
            scheduleCheck()
            return
        }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frontmostAppChanged() }
            },
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleCheck() }
            },
        ]
        frontmostAppChanged()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        detach()
        pendingCheck?.cancel()
        publish(nil)
    }

    // MARK: - Observation

    private func frontmostAppChanged() {
        detach()
        if let app = NSWorkspace.shared.frontmostApplication,
           let bundleID = app.bundleIdentifier,
           Self.browserBundleIdentifiers.contains(bundleID) {
            attach(to: app.processIdentifier)
        }
        scheduleCheck()
    }

    private func attach(to pid: pid_t) {
        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, notification, context in
            guard let context else { return }
            let watcher = Unmanaged<BrowserWatcher>.fromOpaque(context).takeUnretainedValue()
            let name = notification as String
            MainActor.assumeIsolated { watcher.axNotification(name) }
        }
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let newObserver else { return }
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.appNotifications {
            AXObserverAddNotification(newObserver, appElement, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        observer = newObserver
        observedApp = appElement
        observeFocusedWindow()
    }

    private func observeFocusedWindow() {
        guard let observer, let observedApp else { return }
        if let observedWindow {
            for name in Self.windowNotifications {
                AXObserverRemoveNotification(observer, observedWindow, name as CFString)
            }
        }
        observedWindow = AX.element(observedApp, kAXFocusedWindowAttribute)
        if let observedWindow {
            let context = Unmanaged.passUnretained(self).toOpaque()
            for name in Self.windowNotifications {
                AXObserverAddNotification(observer, observedWindow, name as CFString, context)
            }
        }
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedApp = nil
        observedWindow = nil
    }

    private func axNotification(_ name: String) {
        if name == kAXFocusedWindowChangedNotification || name == kAXMainWindowChangedNotification
            || name == kAXUIElementDestroyedNotification {
            observeFocusedWindow()
        }
        scheduleCheck()
    }

    /// Coalesces bursts of notifications (a page load fires several) into one check.
    private func scheduleCheck() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: work)
    }

    private func check() {
        guard isRunning else { return }
        publish(currentMatch())
    }

    private func publish(_ match: BlockedPageMatch?) {
        guard match != lastMatch else { return }
        lastMatch = match
        onChange?(match)
    }

    // MARK: - Reading the browser window

    private func currentMatch() -> BlockedPageMatch? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              Self.browserBundleIdentifiers.contains(bundleID),
              let observedApp,
              let window = AX.element(observedApp, kAXFocusedWindowAttribute)
        else { return nil }

        let scan = WindowScan(window: window)
        guard let host = scan.currentHost(),
              let domain = DomainRules.matchingDomain(for: host, in: domains),
              let windowFrame = AX.frame(of: window)
        else { return nil }

        // Cover the page area; if the browser doesn't expose it, everything below the toolbar.
        var cover = scan.webAreaFrame ?? CGRect(
            x: windowFrame.minX,
            y: windowFrame.minY + 88,
            width: windowFrame.width,
            height: max(0, windowFrame.height - 88)
        )
        cover = cover.intersection(windowFrame)
        guard cover.width > 120, cover.height > 120 else { return nil }
        return BlockedPageMatch(domain: domain, processIdentifier: app.processIdentifier, frame: AX.cocoaRect(fromAX: cover))
    }
}

/// One pass over a browser window's accessibility tree (toolbar and tab strip only; it
/// never walks into page content).
private struct WindowScan {
    var title: String?
    var document: String?
    var webAreaURL: String?
    var webAreaFrame: CGRect?
    var addressValues: [String] = []

    init(window: AXUIElement) {
        title = AX.string(window, kAXTitleAttribute)
        document = AX.string(window, kAXDocumentAttribute)

        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        var largestWebArea: CGFloat = 0
        while !queue.isEmpty, visited < 600 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = AX.string(element, kAXRoleAttribute)
            if role == "AXWebArea" {
                if let frame = AX.frame(of: element), frame.width * frame.height > largestWebArea {
                    largestWebArea = frame.width * frame.height
                    webAreaFrame = frame
                    webAreaURL = AX.urlString(element, kAXURLAttribute)
                }
                continue
            }
            if role == kAXTextFieldRole || role == kAXComboBoxRole {
                // Skip the address bar while you're typing in it.
                if AX.bool(element, kAXFocusedAttribute) != true, let value = AX.string(element, kAXValueAttribute) {
                    addressValues.append(value)
                }
                continue
            }
            if depth < 14 {
                for child in AX.elements(element, kAXChildrenAttribute) {
                    queue.append((child, depth + 1))
                }
            }
        }
    }

    /// The page's own URL is the most reliable signal. Error pages ("can't reach this site")
    /// often have no usable URL, so fall back to the window document, address bar and title.
    func currentHost() -> String? {
        if let webAreaURL, let host = DomainRules.host(inAddress: webAreaURL) { return host }
        for candidate in [document].compactMap({ $0 }) + addressValues + [title].compactMap({ $0 }) {
            if let host = DomainRules.host(inAddress: candidate) { return host }
        }
        return nil
    }
}

/// Small typed wrappers over the C Accessibility API.
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func urlString(_ element: AXUIElement, _ attribute: String) -> String? {
        let raw = value(element, attribute)
        if let url = raw as? URL { return url.absoluteString }
        return raw as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        value(element, attribute) as? Bool
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (value(element, attribute) as? [AXUIElement]) ?? []
    }

    /// Frame in Accessibility coordinates (top-left origin of the main display).
    static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = value(element, kAXPositionAttribute),
              let sizeValue = value(element, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    /// Converts a top-left-origin Accessibility rect into Cocoa's bottom-left-origin space.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
