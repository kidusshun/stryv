import Foundation
import IOKit
import IOKit.pwr_mgt

/// Watches one file with kqueue. Editors and our own atomic writes replace the file
/// (new inode), so after every event the watcher re-opens the path and keeps watching.
final class FileWatcher {
    private let path: String
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?

    init(path: String, queue: DispatchQueue, onChange: @escaping () -> Void) {
        self.path = path
        self.queue = queue
        self.onChange = onChange
    }

    func start() {
        queue.async { self.arm() }
    }

    private func arm() {
        source?.cancel()
        source = nil
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The file is missing (deleted?). Let the owner recreate it, then try again shortly.
            onChange()
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.arm() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .attrib, .link, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if !events.intersection([.delete, .rename, .revoke]).isEmpty {
                self.arm()
            }
            self.onChange()
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }
}

/// Calls `onWake` when the Mac wakes from sleep.
final class PowerObserver {
    // iokit_common_msg() values; the C macros aren't imported into Swift.
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300

    private let onWake: () -> Void
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var notificationPort: IONotificationPortRef?

    init(onWake: @escaping () -> Void) {
        self.onWake = onWake
    }

    func start(queue: DispatchQueue) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &notificationPort, { context, _, messageType, argument in
            guard let context else { return }
            Unmanaged<PowerObserver>.fromOpaque(context).takeUnretainedValue().handle(messageType, argument)
        }, &notifier)
        guard rootPort != 0, let notificationPort else { return }
        IONotificationPortSetDispatchQueue(notificationPort, queue)
    }

    private func handle(_ messageType: UInt32, _ argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case Self.canSystemSleep, Self.systemWillSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case Self.systemHasPoweredOn:
            onWake()
        default:
            break
        }
    }
}
