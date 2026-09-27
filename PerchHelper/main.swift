import Foundation

/// Perch's root helper. Started by launchd when Perch connects, does one
/// thing, and exits once nobody has asked for anything in a while.

final class HelperService: NSObject, SleepHelperProtocol {
    private let idle: IdleExit

    init(idle: IdleExit) {
        self.idle = idle
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (String?) -> Void) {
        // Held for the whole call, so the helper cannot exit under it.
        DispatchQueue.main.sync { idle.begin() }
        defer { DispatchQueue.main.async { [idle] in idle.end() } }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: PmsetCommand.executable)
        process.arguments = PmsetCommand.arguments(disabled: disabled)
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            reply("Could not run pmset: \(error.localizedDescription)")
            return
        }
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            reply(PmsetCommand.failureMessage(
                status: process.terminationStatus,
                stderr: String(decoding: errorData, as: UTF8.self)
            ))
            return
        }
        reply(nil)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let idle = IdleExit(delay: 10) { exit(EXIT_SUCCESS) }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.exportedObject = HelperService(idle: idle)
        connection.resume()
        DispatchQueue.main.async { [idle] in idle.touch() }
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: SleepHelper.machServiceName)
// The system refuses any caller that is not Perch, signed by our team,
// before `shouldAcceptNewConnection` is ever asked.
listener.setConnectionCodeSigningRequirement(SleepHelper.clientRequirement)
listener.delegate = delegate
listener.resume()
delegate.idle.touch()
dispatchMain()
