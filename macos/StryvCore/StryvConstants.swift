import Foundation

public enum StryvConstants {
    public static let appBundleIdentifier = "com.stryv.mac"
    public static let teamIdentifier = "PUWH8RNHCN"

    /// launchd label and XPC Mach service name of the root blocking daemon.
    public static let daemonLabel = "com.stryv.blockd"
    /// Bump whenever the daemon's behavior changes, so the app offers to reinstall it.
    public static let daemonVersion = 1

    public static let installedDaemonPath = "/Library/PrivilegedHelperTools/com.stryv.blockd"
    public static let launchDaemonPlistPath = "/Library/LaunchDaemons/com.stryv.blockd.plist"
    public static let stateFilePath = "/Library/Application Support/Stryv/block-state.json"
    public static let hostsFilePath = "/private/etc/hosts"

    /// Darwin notification the daemon posts whenever the block starts, changes, or ends.
    public static let blockChangedNotification = "com.stryv.block.changed"

    public static let minimumBlockDuration: TimeInterval = 60
    public static let maximumBlockDuration: TimeInterval = 24 * 60 * 60
    public static let maximumDomainCount = 500

    /// Only the Stryv app signed by this team may talk to the daemon.
    public static let clientCodeSigningRequirement =
        "anchor apple generic and identifier \"\(appBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""

    /// Development overrides (see Scripts/dev-daemon.sh). Production never sets these.
    public enum Environment {
        public static let machService = "STRYV_MACH_SERVICE"
        public static let hostsPath = "STRYV_HOSTS_PATH"
        public static let statePath = "STRYV_STATE_PATH"
    }
}
