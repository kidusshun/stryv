import Foundation
import notify

/// Subscribes to a Darwin (notify(3)) notification, such as the daemon's "block changed".
final class DarwinNotificationObserver {
    private var token: Int32 = 0

    init(name: String, queue: DispatchQueue = .main, handler: @escaping () -> Void) {
        notify_register_dispatch(name, &token, queue) { _ in handler() }
    }

    deinit {
        notify_cancel(token)
    }
}
