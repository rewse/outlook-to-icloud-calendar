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

/// Collects the state of one child process from the callbacks of several queues.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private var outEOF = false
    private var errEOF = false
    private var exited = false
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []
    private let complete: AsyncStream<Void>.Continuation

    init(complete: AsyncStream<Void>.Continuation) { self.complete = complete }

    var hasExited: Bool { lock.withLock { exited } }
    var output: (out: Data, err: Data) { lock.withLock { (out, err) } }

    func append(_ data: Data, toStdout: Bool) {
        lock.withLock {
            if toStdout { out.append(data) } else { err.append(data) }
        }
    }

    func markEOF(stdout: Bool) {
        let done = lock.withLock {
            if stdout { outEOF = true } else { errEOF = true }
            return outEOF && errEOF && exited
        }
        if done { finish() }
    }

    func markExited() {
        let (done, waiters) = lock.withLock {
            exited = true
            let waiters = exitWaiters
            exitWaiters = []
            return (outEOF && errEOF, waiters)
        }
        waiters.forEach { $0.resume() }
        if done { finish() }
    }

    /// Returns once the process has exited, regardless of task cancellation.
    func waitForExit() async {
        await withCheckedContinuation { continuation in
            let alreadyExited = lock.withLock {
                if !exited { exitWaiters.append(continuation) }
                return exited
            }
            if alreadyExited { continuation.resume() }
        }
    }

    private func finish() {
        complete.yield()
        complete.finish()
    }
}

/// Runs commands as child processes.
public struct ProcessCommandRunner: CommandRunner {
    /// How long a terminated child may take to exit before it is killed.
    private static let killGrace = DispatchTimeInterval.seconds(2)

    private enum Outcome { case completed, timedOut, cancelled }

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

        let (complete, completeSignal) = AsyncStream<Void>.makeStream()
        let state = RunState(complete: completeSignal)
        process.terminationHandler = { _ in state.markExited() }
        // Drain both pipes while the process runs so a full pipe never blocks it.
        for (pipe, isStdout) in [(outPipe, true), (errPipe, false)] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    state.markEOF(stdout: isStdout)
                } else {
                    state.append(data, toStdout: isStdout)
                }
            }
        }
        do {
            try process.run()
        } catch {
            for pipe in [outPipe, errPipe] { pipe.fileHandleForReading.readabilityHandler = nil }
            throw FetchError.commandFailed("cannot start \(executable.lastPathComponent): \(error)")
        }

        // One deadline covers the exit of the child and the end of its output.
        let outcome = await withTaskGroup(of: Outcome.self) { group in
            group.addTask {
                for await _ in complete {}
                return .completed
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return .cancelled
                }
            }
            let first = await group.next() ?? .cancelled
            group.cancelAll()
            return Task.isCancelled ? .cancelled : first
        }

        switch outcome {
        case .completed:
            let (out, err) = state.output
            return CommandResult(
                exitCode: process.terminationStatus,
                stdout: String(decoding: out, as: UTF8.self),
                stderr: String(decoding: err, as: UTF8.self))
        case .timedOut, .cancelled:
            for pipe in [outPipe, errPipe] {
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForReading.close()
            }
            if !state.hasExited {
                process.terminate()
                let pid = process.processIdentifier
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.killGrace) {
                    if !state.hasExited { kill(pid, SIGKILL) }
                }
                await state.waitForExit()
            }
            if outcome == .cancelled { throw CancellationError() }
            throw FetchError.timedOut
        }
    }
}
