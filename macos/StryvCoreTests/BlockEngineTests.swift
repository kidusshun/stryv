import Foundation
import Testing
@testable import StryvCore

final class FakeEnvironment: BlockEnvironment {
    let directory: URL
    let hostsURL: URL
    let stateURL: URL
    var wall = Date(timeIntervalSince1970: 1_800_000_000)
    var monotonic: TimeInterval = 1_000
    var boot = "boot-1"
    var flushCount = 0

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("stryv-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        hostsURL = directory.appendingPathComponent("hosts")
        stateURL = directory.appendingPathComponent("state/block-state.json")
        try "127.0.0.1 localhost\n".write(to: hostsURL, atomically: true, encoding: .utf8)
    }

    func now() -> Date { wall }
    func monotonicSeconds() -> TimeInterval { monotonic }
    func bootSessionID() -> String { boot }
    func flushDNSCache() { flushCount += 1 }
    func log(_ message: String) {}

    /// Real time passing (awake or asleep): both clocks advance together.
    func advance(_ seconds: TimeInterval) {
        wall += seconds
        monotonic += seconds
    }

    var hosts: String { (try? String(contentsOf: hostsURL, encoding: .utf8)) ?? "" }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

struct BlockEngineTests {
    @Test func startingWritesHostsAndState() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        let block = try engine.start(StartBlockRequest(domains: ["https://www.youtube.com", "x.com"], durationSeconds: 3600))

        #expect(block.domains == ["youtube.com", "x.com"])
        #expect(block.endsAt == env.wall.addingTimeInterval(3600))
        #expect(env.hosts.contains("0.0.0.0 youtube.com"))
        #expect(env.hosts.hasPrefix("127.0.0.1 localhost\n"))
        #expect(FileManager.default.fileExists(atPath: env.stateURL.path))
        #expect(env.flushCount == 1)
    }

    @Test func aShorterRequestCannotShortenTheBlock() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        let first = try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 7200))
        let merged = try engine.start(StartBlockRequest(domains: ["reddit.com"], durationSeconds: 60))

        #expect(merged.endsAt == first.endsAt)
        #expect(merged.startedAt == first.startedAt)
        #expect(merged.domains == ["x.com", "reddit.com"])
        #expect(env.hosts.contains("0.0.0.0 reddit.com"))
    }

    @Test func aLongerRequestExtendsTheBlock() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 600))
        let extended = try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 3600))
        #expect(extended.endsAt == env.wall.addingTimeInterval(3600))
    }

    @Test func rejectsInvalidRequests() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        #expect(throws: BlockError.noValidDomains) { try engine.start(StartBlockRequest(domains: ["nope"], durationSeconds: 600)) }
        #expect(throws: BlockError.durationOutOfRange) { try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 10)) }
        #expect(throws: BlockError.durationOutOfRange) { try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 90_000)) }
        #expect(throws: BlockError.durationOutOfRange) { try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: .infinity)) }
        #expect(engine.block == nil)
    }

    @Test func expiryCleansUpHostsAndState() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 600))

        env.advance(599)
        #expect(engine.reconcile() == false)
        #expect(env.hosts.contains("x.com"))

        env.advance(2)
        #expect(engine.reconcile() == true)
        #expect(engine.block == nil)
        #expect(env.hosts == "127.0.0.1 localhost\n")
        #expect(!FileManager.default.fileExists(atPath: env.stateURL.path))
        #expect(engine.status().block == nil)
    }

    @Test func editedHostsFileIsRestored() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 600))
        let blocked = env.hosts

        try "127.0.0.1 localhost\n# I removed it\n".write(to: env.hostsURL, atomically: true, encoding: .utf8)
        engine.reconcile()
        #expect(env.hosts.contains("0.0.0.0 x.com"))
        #expect(env.hosts.contains("# I removed it"))

        try FileManager.default.removeItem(at: env.hostsURL)
        engine.reconcile()
        #expect(env.hosts.contains("0.0.0.0 x.com"))
        _ = blocked
    }

    @Test func movingTheClockForwardExtendsTheBlock() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        let original = try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 3600))

        env.advance(60)
        env.wall += 2 * 3600 // someone sets the clock 2 hours ahead
        #expect(engine.reconcile() == true)
        #expect(engine.block?.endsAt == original.endsAt.addingTimeInterval(2 * 3600))
        let remaining = try #require(engine.block?.remaining(at: env.wall))
        #expect(abs(remaining - (3600 - 60)) < 0.001)
    }

    @Test func sleepingDoesNotExtendTheBlock() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        let original = try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 3600))

        env.advance(1800) // asleep for 30 minutes: both clocks move
        engine.reconcile()
        #expect(engine.block?.endsAt == original.endsAt)
    }

    @Test func smallClockCorrectionsAreIgnored() throws {
        let env = try FakeEnvironment()
        let engine = BlockEngine(environment: env)
        let original = try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 3600))
        env.wall += 5 // NTP nudge
        engine.reconcile()
        #expect(engine.block?.endsAt == original.endsAt)
    }

    @Test func blockSurvivesDaemonRestartAndDetectsTamperingAcrossIt() throws {
        let env = try FakeEnvironment()
        let original = try BlockEngine(environment: env).start(StartBlockRequest(domains: ["x.com"], durationSeconds: 3600))

        // Daemon killed, clock moved forward, daemon relaunched in the same boot.
        env.advance(10)
        env.wall += 3600
        let restarted = BlockEngine(environment: env)
        #expect(restarted.block?.domains == ["x.com"])
        restarted.reconcile()
        #expect(restarted.block?.endsAt == original.endsAt.addingTimeInterval(3600))
        #expect(env.hosts.contains("0.0.0.0 x.com"))
    }

    @Test func blockSurvivesRebootUntilItsEndTime() throws {
        let env = try FakeEnvironment()
        let original = try BlockEngine(environment: env).start(StartBlockRequest(domains: ["x.com"], durationSeconds: 3600))

        env.boot = "boot-2"
        env.monotonic = 30 // the monotonic clock restarts after a reboot
        env.wall += 600
        let afterReboot = BlockEngine(environment: env)
        #expect(afterReboot.reconcile() == false)
        #expect(afterReboot.block?.endsAt == original.endsAt)

        env.advance(3001)
        #expect(afterReboot.reconcile() == true)
        #expect(afterReboot.block == nil)
    }

    @Test func neverOverwritesAnUnreadableHostsFile() throws {
        let env = try FakeEnvironment()
        let garbage = Data([0xFF, 0xFE, 0x00, 0xC3, 0x28])
        try garbage.write(to: env.hostsURL)
        let engine = BlockEngine(environment: env)
        try engine.start(StartBlockRequest(domains: ["x.com"], durationSeconds: 600))
        #expect(try Data(contentsOf: env.hostsURL) == garbage)
    }
}
