import Foundation
import StryvCore

// The root blocking daemon. launchd keeps it alive (KeepAlive) and starts it at boot.
// It never removes blocked hosts entries on exit: only the block's end time does that.

let environment = SystemEnvironment()
let daemon = BlockDaemon(environment: environment)
daemon.start()

let serviceName = ProcessInfo.processInfo.environment[StryvConstants.Environment.machService] ?? StryvConstants.daemonLabel
let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = daemon
listener.resume()

environment.log("Stryv blocker daemon v\(StryvConstants.daemonVersion) listening on \(serviceName)")
dispatchMain()
