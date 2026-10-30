import Foundation

public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Runs an external command and collects its output.
public protocol CommandRunner: Sendable {
    /// Throws `FetchError.timedOut` when the command does not exit within `timeout`.
    func run(
        executable: URL, arguments: [String], environment: [String: String], timeout: Duration
    ) async throws -> CommandResult
}

/// Runs commands as child processes.
public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(
        executable: URL, arguments: [String], environment: [String: String], timeout: Duration
    ) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let (exited, exitSignal) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in
            exitSignal.yield()
            exitSignal.finish()
        }
        do {
            try process.run()
        } catch {
            throw FetchError.commandFailed("cannot start \(executable.lastPathComponent): \(error)")
        }

        // Drain both pipes while the process runs so a full pipe never blocks it.
        let outTask = Task.detached { outPipe.fileHandleForReading.readDataToEndOfFile() }
        let errTask = Task.detached { errPipe.fileHandleForReading.readDataToEndOfFile() }

        let timedOut = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in exited {}
                return false
            }
            group.addTask {
                (try? await Task.sleep(for: timeout)) != nil
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        if timedOut {
            process.terminate()
            for await _ in exited {}
            throw FetchError.timedOut
        }

        let out = await outTask.value
        let err = await errTask.value
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: out, as: UTF8.self),
            stderr: String(decoding: err, as: UTF8.self))
    }
}
