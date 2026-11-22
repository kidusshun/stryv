import Foundation
import notify
import StryvCore

/// Runs `BlockEngine` on one serial queue and wakes it only when something happens:
///
/// | Event                         | Source                                      |
/// |-------------------------------|---------------------------------------------|
/// | Daemon launch (boot, restart) | `start()`                                   |
/// | App starts/extends a block    | XPC `startBlock`                            |
/// | Block end time                | one wall-clock timer set for `endsAt`       |
/// | /etc/hosts edited             | kqueue file watcher                         |
/// | System clock set              | `com.apple.system.clock_set` notification   |
/// | Wake from sleep               | IOKit power notification                    |
/// | Anything missed               | 5-minute safety-net timer                   |
final class BlockDaemon: NSObject, NSXPCListenerDelegate, BlockDaemonXPC {
    private static let safetyNetInterval: DispatchTimeInterval = .seconds(300)

    private let queue = DispatchQueue(label: "com.stryv.blockd.engine")
    private let engine: BlockEngine
    private let environment: SystemEnvironment
    private var expiryTimer: DispatchSourceTimer?
    private var safetyNetTimer: DispatchSourceTimer?
    private var hostsWatcher: FileWatcher?
    private var powerObserver: PowerObserver?
    private var clockToken: Int32 = 0
    private var lastAnnouncedBlock: BlockState?

    init(environment: SystemEnvironment) {
        self.environment = environment
        self.engine = BlockEngine(environment: environment)
    }

    func start() {
        queue.sync { handleEvent("launch") }

        hostsWatcher = FileWatcher(path: environment.hostsURL.path, queue: queue) { [weak self] in
            self?.handleEvent("hosts changed")
        }
        hostsWatcher?.start()

        notify_register_dispatch("com.apple.system.clock_set", &clockToken, queue) { [weak self] _ in
            self?.handleEvent("clock set")
        }

        powerObserver = PowerObserver { [weak self] in self?.handleEvent("wake") }
        powerObserver?.start(queue: queue)

        let safetyNet = DispatchSource.makeTimerSource(queue: queue)
        safetyNet.schedule(deadline: .now() + Self.safetyNetInterval, repeating: Self.safetyNetInterval, leeway: .seconds(30))
        safetyNet.setEventHandler { [weak self] in self?.handleEvent("safety net") }
        safetyNet.resume()
        safetyNetTimer = safetyNet
    }

    /// Must run on `queue`.
    private func handleEvent(_ reason: String) {
        engine.reconcile()
        afterStateChange()
    }

    private func afterStateChange() {
        scheduleExpiryTimer()
        let block = engine.status().block
        if block != lastAnnouncedBlock {
            lastAnnouncedBlock = block
            notify_post(StryvConstants.blockChangedNotification)
        }
    }

    /// One timer for the exact end time. It uses a wall-clock deadline so it fires
    /// immediately on wake if the Mac slept through the end time.
    private func scheduleExpiryTimer() {
        expiryTimer?.cancel()
        expiryTimer = nil
        guard let endsAt = engine.block?.endsAt else { return }
        let seconds = endsAt.timeIntervalSince1970
        var deadline = timespec()
        deadline.tv_sec = Int(seconds.rounded(.down))
        deadline.tv_nsec = Int((seconds - seconds.rounded(.down)) * 1_000_000_000)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(wallDeadline: DispatchWallTime(timespec: deadline) + .milliseconds(200), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.handleEvent("block end time") }
        timer.resume()
        expiryTimer = timer
    }

    // MARK: - XPC

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if ProcessInfo.processInfo.environment[StryvConstants.Environment.hostsPath] == nil {
            connection.setCodeSigningRequirement(StryvConstants.clientCodeSigningRequirement)
        }
        connection.exportedInterface = NSXPCInterface(with: BlockDaemonXPC.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func fetchStatus(reply: @escaping (Data) -> Void) {
        queue.async { [engine] in
            reply((try? StryvJSON.encoder().encode(engine.status())) ?? Data())
        }
    }

    func startBlock(_ request: Data, reply: @escaping (Data?, String?) -> Void) {
        queue.async { [self] in
            do {
                let decoded = try StryvJSON.decoder().decode(StartBlockRequest.self, from: request)
                try engine.start(decoded)
                afterStateChange()
                reply(try StryvJSON.encoder().encode(engine.status()), nil)
            } catch let error as BlockError {
                reply(nil, error.errorDescription)
            } catch {
                reply(nil, "The blocker couldn't read that request.")
            }
        }
    }
}
