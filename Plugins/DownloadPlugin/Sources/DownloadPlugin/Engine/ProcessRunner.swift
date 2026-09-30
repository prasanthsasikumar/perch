import Foundation

/// Runs a command to completion, handing over stdout a line at a time as it
/// arrives. Cancelling the calling task terminates the process.
enum ProcessRunner {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let collector = Collector(onLine: onLine)
        // Both pipes are drained as they fill; a pipe left unread blocks the
        // child once its buffer is full, and `-j` output easily fills one.
        out.fileHandleForReading.readabilityHandler = { handle in
            collector.appendOut(handle.availableData)
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            collector.appendErr(handle.availableData)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                process.terminationHandler = { process in
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    collector.appendOut(out.fileHandleForReading.readDataToEndOfFile())
                    collector.appendErr(err.fileHandleForReading.readDataToEndOfFile())
                    collector.finish()
                    continuation.resume(returning: Result(
                        status: process.terminationStatus,
                        stdout: collector.stdout,
                        stderr: collector.stderr
                    ))
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()
        private var pending = Data()
        private let onLine: @Sendable (String) -> Void

        init(onLine: @escaping @Sendable (String) -> Void) { self.onLine = onLine }

        func appendOut(_ data: Data) {
            guard !data.isEmpty else { return }
            let lines: [String] = lock.withLock {
                out.append(data)
                pending.append(data)
                var lines: [String] = []
                while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                    pending.removeSubrange(pending.startIndex...newline)
                }
                return lines
            }
            lines.forEach(onLine)
        }

        func appendErr(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.withLock { err.append(data) }
        }

        func finish() {
            let rest: String? = lock.withLock {
                defer { pending.removeAll() }
                return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
            }
            if let rest { onLine(rest) }
        }

        var stdout: String { lock.withLock { String(decoding: out, as: UTF8.self) } }
        var stderr: String { lock.withLock { String(decoding: err, as: UTF8.self) } }
    }
}
