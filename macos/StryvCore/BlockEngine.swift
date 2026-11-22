import Foundation

/// Everything the engine needs from the outside world, so tests can run it against
/// temporary files and fake clocks without root.
public protocol BlockEnvironment: AnyObject {
    var hostsURL: URL { get }
    var stateURL: URL { get }
    func now() -> Date
    /// Seconds from a clock that can't be set and keeps counting during sleep (CLOCK_MONOTONIC).
    func monotonicSeconds() -> TimeInterval
    /// Changes on every reboot, which resets the monotonic clock.
    func bootSessionID() -> String
    func flushDNSCache()
    func log(_ message: String)
}

public enum BlockError: LocalizedError, Equatable {
    case noValidDomains
    case durationOutOfRange
    case tooManyDomains

    public var errorDescription: String? {
        switch self {
        case .noValidDomains: "Add at least one valid website to block."
        case .durationOutOfRange: "A block must last between 1 minute and 24 hours."
        case .tooManyDomains: "That's more sites than a single block supports."
        }
    }
}

/// The blocking rules. Not thread-safe: the daemon calls it from one serial queue.
///
/// The daemon calls `reconcile()` whenever something happens (boot, hosts edited, clock set,
/// wake, the end time arriving). `reconcile()` is idempotent and does all the work:
/// detect clock tampering, expire the block, save state, and make /etc/hosts match.
public final class BlockEngine {
    /// Wall-clock jumps smaller than this are treated as normal NTP corrections.
    public static let clockJumpTolerance: TimeInterval = 30

    private let environment: BlockEnvironment
    public private(set) var block: BlockState?
    private var anchor: ClockAnchor?

    public init(environment: BlockEnvironment) {
        self.environment = environment
        if let data = try? Data(contentsOf: environment.stateURL),
           let saved = try? StryvJSON.decoder().decode(PersistedBlockState.self, from: data) {
            block = saved.block
            anchor = saved.anchor
        }
    }

    /// Starts a block, or merges into the running one. Merging only ever adds sites and
    /// keeps the later end time, so no request can shorten or end a block.
    @discardableResult
    public func start(_ request: StartBlockRequest) throws -> BlockState {
        let domains = DomainRules.normalizedList(request.domains)
        guard !domains.isEmpty else { throw BlockError.noValidDomains }
        guard request.durationSeconds.isFinite,
              request.durationSeconds >= StryvConstants.minimumBlockDuration,
              request.durationSeconds <= StryvConstants.maximumBlockDuration
        else { throw BlockError.durationOutOfRange }

        // Apply any pending clock correction before comparing end times.
        reconcile()

        let now = environment.now()
        let requestedEnd = now.addingTimeInterval(request.durationSeconds)
        let next: BlockState
        if let current = block, current.isActive(at: now) {
            let merged = DomainRules.normalizedList(current.domains + domains)
            guard merged.count <= StryvConstants.maximumDomainCount else { throw BlockError.tooManyDomains }
            next = BlockState(domains: merged, startedAt: current.startedAt, endsAt: max(current.endsAt, requestedEnd))
        } else {
            guard domains.count <= StryvConstants.maximumDomainCount else { throw BlockError.tooManyDomains }
            next = BlockState(domains: domains, startedAt: now, endsAt: requestedEnd)
        }
        block = next
        environment.log("Block set: \(next.domains.count) sites until \(next.endsAt)")
        reconcile()
        return next
    }

    /// Brings the world in line with the block. Returns true when the block changed
    /// (extended because the clock jumped, or ended).
    @discardableResult
    public func reconcile() -> Bool {
        let now = environment.now()
        let monotonic = environment.monotonicSeconds()
        let bootSession = environment.bootSessionID()
        var changed = false

        if var current = block, let anchor, anchor.bootSession == bootSession {
            let wallElapsed = now.timeIntervalSince(anchor.wall)
            let realElapsed = monotonic - anchor.monotonic
            let skew = wallElapsed - realElapsed
            if skew > Self.clockJumpTolerance {
                current.endsAt = current.endsAt.addingTimeInterval(skew)
                block = current
                changed = true
                environment.log("Clock moved forward by \(Int(skew))s; block extended to \(current.endsAt)")
            }
        }
        anchor = ClockAnchor(wall: now, monotonic: monotonic, bootSession: bootSession)

        if let current = block, !current.isActive(at: now) {
            block = nil
            changed = true
            environment.log("Block ended")
        }

        persist()
        enforceHosts()
        return changed
    }

    public func status() -> DaemonStatus {
        let now = environment.now()
        let active = block.flatMap { $0.isActive(at: now) ? $0 : nil }
        return DaemonStatus(daemonVersion: StryvConstants.daemonVersion, block: active, checkedAt: now)
    }

    // MARK: - Side effects

    private func persist() {
        let url = environment.stateURL
        let fileManager = FileManager.default
        guard block != nil else {
            if fileManager.fileExists(atPath: url.path) {
                do { try fileManager.removeItem(at: url) } catch { environment.log("Couldn't remove state: \(error)") }
            }
            return
        }
        do {
            let data = try StryvJSON.encoder().encode(PersistedBlockState(block: block, anchor: anchor))
            if (try? Data(contentsOf: url)) == data { return }
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            environment.log("Couldn't save state: \(error)")
        }
    }

    private func enforceHosts() {
        let url = environment.hostsURL
        let current: String
        do {
            current = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Never overwrite a hosts file we couldn't read: that would wipe the user's entries.
            guard !FileManager.default.fileExists(atPath: url.path) else {
                environment.log("Couldn't read hosts file: \(error)")
                return
            }
            current = ""
        }

        let desired = HostsFile.render(current, blocking: block?.domains ?? [])
        guard desired != current else { return }
        do {
            try desired.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            environment.flushDNSCache()
            environment.log(block == nil ? "Removed blocked sites from hosts" : "Wrote \(block?.domains.count ?? 0) blocked sites to hosts")
        } catch {
            environment.log("Couldn't write hosts file: \(error)")
        }
    }
}
