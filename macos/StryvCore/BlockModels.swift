import Foundation

public struct BlockState: Codable, Equatable, Sendable {
    public var domains: [String]
    public var startedAt: Date
    public var endsAt: Date

    public init(domains: [String], startedAt: Date, endsAt: Date) {
        self.domains = domains
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    public func isActive(at date: Date) -> Bool { date < endsAt }

    public func remaining(at date: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(date)) }

    public var totalDuration: TimeInterval { max(1, endsAt.timeIntervalSince(startedAt)) }

    /// The blocked domain that covers `host` (exact match or subdomain), if any.
    public func blockedDomain(covering host: String) -> String? {
        DomainRules.matchingDomain(for: host, in: domains)
    }
}

public struct StartBlockRequest: Codable, Equatable, Sendable {
    public var domains: [String]
    public var durationSeconds: TimeInterval

    public init(domains: [String], durationSeconds: TimeInterval) {
        self.domains = domains
        self.durationSeconds = durationSeconds
    }
}

public struct DaemonStatus: Codable, Equatable, Sendable {
    public var daemonVersion: Int
    /// The active block, or nil when nothing is blocked.
    public var block: BlockState?
    public var checkedAt: Date

    public init(daemonVersion: Int, block: BlockState?, checkedAt: Date) {
        self.daemonVersion = daemonVersion
        self.block = block
        self.checkedAt = checkedAt
    }
}

/// A (wall clock, monotonic clock) reading taken at the same instant. Comparing two anchors
/// reveals a wall clock that was moved forward, because the monotonic clock can't be set.
public struct ClockAnchor: Codable, Equatable, Sendable {
    public var wall: Date
    public var monotonic: TimeInterval
    public var bootSession: String
}

/// What the daemon keeps on disk so a block survives restarts and reboots.
public struct PersistedBlockState: Codable, Equatable, Sendable {
    public var block: BlockState?
    public var anchor: ClockAnchor?
}

public enum StryvJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
