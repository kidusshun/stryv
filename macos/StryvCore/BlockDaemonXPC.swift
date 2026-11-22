import Foundation

/// The whole API between the app and the root daemon. There is deliberately no "stop":
/// a block can only be started, have sites added, or be lengthened.
///
/// Payloads are JSON (`StartBlockRequest`, `DaemonStatus`) so the XPC interface stays tiny.
@objc public protocol BlockDaemonXPC {
    func fetchStatus(reply: @escaping (Data) -> Void)
    func startBlock(_ request: Data, reply: @escaping (Data?, String?) -> Void)
}
