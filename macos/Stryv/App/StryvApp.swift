import SwiftUI

@main
struct StryvApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Stryv lives in the menu bar (see StatusItemController). Future windows, such as
        // reports, go here as additional scenes.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var blockModel: BlockModel?
    private var player: FocusPlayer?
    private var overlay: BlockedOverlayController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let blockModel = BlockModel()
        let player = FocusPlayer()
        let overlay = BlockedOverlayController(model: blockModel)
        statusItem = StatusItemController(model: blockModel, player: player, overlay: overlay)
        self.blockModel = blockModel
        self.player = player
        self.overlay = overlay

        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["STRYV_OVERLAY_SNAPSHOT"] {
            overlay.saveDebugSnapshot(to: path)
        }
        #endif
    }
}
