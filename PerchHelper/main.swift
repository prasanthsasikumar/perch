import Foundation

/// Perch's root helper. Started by launchd when Perch connects, does one
/// thing, and exits once nobody has asked for anything in a while.

/// Exits the process after a quiet spell, so nothing root stays resident.
final class IdleExit {
    private let delay: TimeInterval = 10
    private var pending: DispatchWorkItem?

    func touch() {
        pending?.cancel()
        let item = DispatchWorkItem { exit(EXIT_SUCCESS) }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

final class HelperService: NSObject, SleepHelperProtocol {
    private let onRequest: () -> Void

    init(onRequest: @escaping () -> Void) {
        self.onRequest = onRequest
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (String?) -> Void) {
        DispatchQueue.main.async(execute: onRequest)

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
    let idle = IdleExit()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.exportedObject = HelperService(onRequest: { [idle] in idle.touch() })
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
