import Foundation
import ServiceManagement
import StryvCore

enum HelperState: Equatable {
    case checking
    case notInstalled
    case notResponding
    case outdated
    case ready
}

/// App-side state for blocking. The daemon is the source of truth for the active block;
/// this model mirrors it and refreshes when the daemon announces a change.
@MainActor
final class BlockModel: ObservableObject {
    static let presetMinutes = [15, 25, 45, 60, 120, 240, 480]
    static let restOfDayLabel = "Rest of day"
    static let defaultBlocklist = ["x.com", "twitter.com", "youtube.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com"]

    @Published var blocklist: [String] {
        didSet { defaults.set(blocklist, forKey: Keys.blocklist) }
    }
    /// What the user typed, e.g. "2m", "45 min", "1h 30m". Presets fill it in too.
    @Published var durationText: String {
        didSet { defaults.set(durationText, forKey: Keys.duration) }
    }
    @Published private(set) var status: DaemonStatus?
    @Published private(set) var helperState: HelperState = .checking
    @Published private(set) var now = Date()
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let client = DaemonClient()
    private let defaults = UserDefaults.standard
    private var changeObserver: DarwinNotificationObserver?
    private var ticker: Timer?

    private enum Keys {
        static let blocklist = "blocklist"
        static let duration = "durationText"
    }

    init() {
        blocklist = defaults.stringArray(forKey: Keys.blocklist) ?? Self.defaultBlocklist
        durationText = defaults.string(forKey: Keys.duration) ?? "1h"
        changeObserver = DarwinNotificationObserver(name: StryvConstants.blockChangedNotification) { [weak self] in
            Task { await self?.refresh() }
        }
        Task { await refresh() }
    }

    var activeBlock: BlockState? {
        guard let block = status?.block, block.isActive(at: now) else { return nil }
        return block
    }

    /// The typed duration in minutes, or nil when it isn't valid (1 minute to 24 hours).
    var durationMinutes: Int? {
        DurationParser.minutes(from: durationText)
    }

    func selectPreset(_ minutes: Int) {
        durationText = Format.duration(minutes: minutes)
    }

    /// Fills in the time left until midnight, like any other preset.
    func selectRestOfDay() {
        durationText = Format.duration(minutes: DurationParser.minutesUntilMidnight(from: Date()))
    }

    /// True when the duration means "until midnight tonight".
    var isRestOfDay: Bool {
        DurationParser.isRestOfDay(durationText)
    }

    var canStartBlock: Bool {
        helperState == .ready && !blocklist.isEmpty && !isWorking && durationMinutes != nil
    }

    // MARK: - Daemon

    func refresh() async {
        do {
            let status = try await client.status()
            self.status = status
            helperState = status.daemonVersion == StryvConstants.daemonVersion ? .ready : .outdated
        } catch {
            status = nil
            let installed = client.isDevelopmentDaemon || FileManager.default.fileExists(atPath: StryvConstants.launchDaemonPlistPath)
            helperState = installed ? .notResponding : .notInstalled
        }
        now = Date()
        updateTicker()
    }

    func startBlock() async {
        guard let minutes = durationMinutes else {
            errorMessage = "Enter a duration between 1 minute and 24 hours, like 2m, 45m or 1h 30m."
            return
        }
        await send(domains: blocklist, duration: TimeInterval(minutes * 60))
    }

    /// Adds a site to the running block without changing its end time.
    func addToActiveBlock(_ input: String) async -> Bool {
        guard let domain = DomainRules.normalize(input) else {
            errorMessage = "“\(input)” isn't a website address."
            return false
        }
        if !blocklist.contains(domain) { blocklist.append(domain) }
        await send(domains: [domain], duration: StryvConstants.minimumBlockDuration)
        return errorMessage == nil
    }

    private func send(domains: [String], duration: TimeInterval) async {
        isWorking = true
        defer { isWorking = false }
        do {
            status = try await client.startBlock(domains: domains, duration: duration)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        now = Date()
        updateTicker()
    }

    func installHelper() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await HelperInstaller.install()
            errorMessage = nil
            // launchd starts the daemon right away; give it a moment to register.
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(300))
                await refresh()
                if helperState == .ready { break }
            }
        } catch HelperInstallerError.cancelled {
            // The user closed the password prompt.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Blocklist

    @discardableResult
    func addToBlocklist(_ input: String) -> Bool {
        guard let domain = DomainRules.normalize(input) else {
            errorMessage = "“\(input)” isn't a website address."
            return false
        }
        if !blocklist.contains(domain) { blocklist.append(domain) }
        errorMessage = nil
        return true
    }

    func removeFromBlocklist(_ domain: String) {
        blocklist.removeAll { $0 == domain }
    }

    // MARK: - Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Countdown

    /// A one-second UI tick, only while a block is active, to drive the countdowns.
    private func updateTicker() {
        if activeBlock != nil {
            guard ticker == nil else { return }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        now = Date()
        if activeBlock == nil {
            // The end time just passed; the daemon will confirm with a notification too.
            updateTicker()
            Task { await refresh() }
        }
    }
}
