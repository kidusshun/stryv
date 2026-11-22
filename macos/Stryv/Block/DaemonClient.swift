import Foundation
import StryvCore

enum DaemonClientError: LocalizedError {
    case unavailable
    case timedOut
    case rejected(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: "The Stryv blocker isn't running."
        case .timedOut: "The Stryv blocker didn't answer."
        case .rejected(let reason): reason
        case .badResponse: "The Stryv blocker sent an unexpected answer."
        }
    }
}

/// Talks to the root daemon over XPC. The daemon only offers "status" and "start/extend".
final class DaemonClient: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private let serviceName: String
    private let isPrivileged: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if let devService = environment[StryvConstants.Environment.machService] {
            serviceName = devService
            isPrivileged = false
        } else {
            serviceName = StryvConstants.daemonLabel
            isPrivileged = true
        }
    }

    var isDevelopmentDaemon: Bool { !isPrivileged }

    func status() async throws -> DaemonStatus {
        let data = try await call { daemon, finish in
            daemon.fetchStatus { finish(.success($0)) }
        }
        return try decode(data)
    }

    func startBlock(domains: [String], duration: TimeInterval) async throws -> DaemonStatus {
        let request = try StryvJSON.encoder().encode(StartBlockRequest(domains: domains, durationSeconds: duration))
        let data = try await call { daemon, finish in
            daemon.startBlock(request) { data, error in
                if let data {
                    finish(.success(data))
                } else {
                    finish(.failure(DaemonClientError.rejected(error ?? "The blocker refused the request.")))
                }
            }
        }
        return try decode(data)
    }

    private func decode(_ data: Data) throws -> DaemonStatus {
        do {
            return try StryvJSON.decoder().decode(DaemonStatus.self, from: data)
        } catch {
            throw DaemonClientError.badResponse
        }
    }

    private func call(_ body: @escaping (BlockDaemonXPC, @escaping (Result<Data, Error>) -> Void) -> Void) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            let finish: (Result<Data, Error>) -> Void = { result in
                if once.claim() { continuation.resume(with: result) }
            }
            let proxy = currentConnection().remoteObjectProxyWithErrorHandler { _ in
                finish(.failure(DaemonClientError.unavailable))
            }
            guard let daemon = proxy as? BlockDaemonXPC else {
                finish(.failure(DaemonClientError.unavailable))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                finish(.failure(DaemonClientError.timedOut))
            }
            body(daemon, finish)
        }
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: serviceName, options: isPrivileged ? .privileged : [])
        connection.remoteObjectInterface = NSXPCInterface(with: BlockDaemonXPC.self)
        connection.invalidationHandler = { [weak self] in self?.dropConnection() }
        connection.interruptionHandler = { [weak self] in self?.dropConnection() }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func dropConnection() {
        lock.lock()
        let old = connection
        connection = nil
        lock.unlock()
        old?.invalidationHandler = nil
        old?.interruptionHandler = nil
        old?.invalidate()
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
