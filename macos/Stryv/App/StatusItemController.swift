import AppKit
import Combine
import SwiftUI

/// The menu bar icon and its popover. The popover's content is created once and kept.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let model: BlockModel
    private let overlay: BlockedOverlayController
    private let makeContent: () -> AnyView
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(model: BlockModel, player: FocusPlayer, overlay: BlockedOverlayController) {
        self.model = model
        self.overlay = overlay
        self.makeContent = {
            AnyView(
                MenuContentView()
                    .environmentObject(model)
                    .environmentObject(player)
                    .environmentObject(overlay)
            )
        }
        super.init()

        let hosting = NSHostingController(rootView: makeContent())
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
        }

        model.$status.combineLatest(model.$now)
            .sink { [weak self] _, _ in
                DispatchQueue.main.async { self?.updateButton() }
            }
            .store(in: &cancellables)
        updateButton()

        #if DEBUG
        installDebugAids()
        #endif
    }

    @objc private func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        overlay.syncWithBlock()
        Task { await model.refresh() }

        // A menu bar app is often not the active app, so .transient alone doesn't see clicks
        // in other apps. Close on any click outside Stryv, and whenever Stryv loses focus.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }
    }

    private func closePopover() {
        if popover.isShown { popover.performClose(nil) }
        removeCloseTriggers()
    }

    func popoverDidClose(_ notification: Notification) {
        removeCloseTriggers()
    }

    private func removeCloseTriggers() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        if let block = model.activeBlock {
            let image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Stryv: blocking")
            image?.isTemplate = true
            button.image = image
            button.title = " " + Format.menuBarRemaining(block.remaining(at: model.now))
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        } else {
            let image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Stryv")
            image?.isTemplate = true
            button.image = image
            button.title = ""
        }
    }

    #if DEBUG
    /// STRYV_SHOW_POPOVER=1 opens the popover on launch. STRYV_SNAPSHOT_PATH=/x.png also
    /// renders the popover content to PNGs (x-light.png and x-dark.png).
    private func installDebugAids() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["STRYV_SHOW_POPOVER"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.showPopover()
            guard let path = environment["STRYV_SNAPSHOT_PATH"] else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                self?.saveSnapshot(to: path, appearance: .aqua, suffix: "light")
                self?.saveSnapshot(to: path, appearance: .darkAqua, suffix: "dark")
            }
        }
    }

    private func saveSnapshot(to path: String, appearance: NSAppearance.Name, suffix: String) {
        let hostingView = NSHostingView(rootView: makeContent())
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 380, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        // Draw on the popover's material so the snapshot matches the real translucent popover.
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .withinWindow
        material.state = .active
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: material.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        window.contentView = material
        hostingView.layoutSubtreeIfNeeded()
        window.setContentSize(hostingView.fittingSize)
        window.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard let contentView = window.contentView?.superview,
                  let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else { return }
            contentView.cacheDisplay(in: contentView.bounds, to: rep)
            let url = URL(fileURLWithPath: path)
            let output = url.deletingPathExtension().path + "-\(suffix).png"
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            window.orderOut(nil)
        }
    }
    #endif
}
