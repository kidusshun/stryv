import Foundation
import os
import StryvCore

/// The real machine: /etc/hosts, the root-owned state file, real clocks.
final class SystemEnvironment: BlockEnvironment {
    let hostsURL: URL
    let stateURL: URL
    private let isDevelopment: Bool
    private let logger = Logger(subsystem: StryvConstants.daemonLabel, category: "daemon")

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        hostsURL = URL(fileURLWithPath: environment[StryvConstants.Environment.hostsPath] ?? StryvConstants.hostsFilePath)
        stateURL = URL(fileURLWithPath: environment[StryvConstants.Environment.statePath] ?? StryvConstants.stateFilePath)
        isDevelopment = environment[StryvConstants.Environment.hostsPath] != nil
    }

    func now() -> Date { Date() }

    func monotonicSeconds() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    func bootSessionID() -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }

    func flushDNSCache() {
        guard !isDevelopment else { return }
        run("/usr/bin/dscacheutil", ["-flushcache"])
        run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
    }

    func log(_ message: String) {
        logger.log("\(message, privacy: .public)")
    }

    private func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log("Couldn't run \(path): \(error)")
        }
    }
}
