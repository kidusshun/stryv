import Foundation

enum HelperInstallerError: LocalizedError {
    case missingBundleFiles
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleFiles: "This copy of Stryv is missing its blocker helper. Rebuild the app."
        case .cancelled: nil
        case .failed(let message): "Installing the blocker failed: \(message)"
        }
    }
}

/// Installs the root daemon once, through the standard macOS administrator password prompt.
/// The daemon is copied out of the app to /Library/PrivilegedHelperTools, so deleting or
/// moving the app doesn't stop a running block.
enum HelperInstaller {
    static func install() async throws {
        guard let daemon = Bundle.main.url(forAuxiliaryExecutable: "StryvBlockd"),
              let script = Bundle.main.url(forResource: "install-daemon", withExtension: "sh")
        else { throw HelperInstallerError.missingBundleFiles }

        let command = "/bin/sh \(shellQuote(script.path)) \(shellQuote(daemon.path))"
        let source = """
        do shell script "\(appleScriptEscape(command))" with prompt "Stryv needs your password once to install its website blocker." with administrator privileges
        """
        try await runAppleScript(source)
    }

    private static func runAppleScript(_ source: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = Pipe()
            process.terminationHandler = { process in
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else if stderr.contains("-128") {
                    continuation.resume(throwing: HelperInstallerError.cancelled)
                } else {
                    continuation.resume(throwing: HelperInstallerError.failed(stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: HelperInstallerError.failed(error.localizedDescription))
            }
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
