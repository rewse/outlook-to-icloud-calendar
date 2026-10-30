import Foundation
import Testing

@testable import Outlook2iCloudCalCore

private final class FakeRunner: CommandRunner, @unchecked Sendable {
    struct Call {
        let executable: URL
        let arguments: [String]
        let environment: [String: String]
        let timeout: Duration
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let handler: @Sendable () throws -> CommandResult

    init(_ handler: @escaping @Sendable () throws -> CommandResult) { self.handler = handler }

    var calls: [Call] { lock.withLock { recorded } }

    func run(
        executable: URL, arguments: [String], environment: [String: String], timeout: Duration
    ) async throws -> CommandResult {
        lock.withLock {
            recorded.append(
                Call(executable: executable, arguments: arguments, environment: environment, timeout: timeout))
        }
        return try handler()
    }
}

private let validOutput = """
    [{"meetingId":"id-1","subject":"Sample","start":"2026-11-02T10:00:00+09:00",\
    "end":"2026-11-02T11:00:00+09:00","location":"","isAllDay":false,"isCanceled":false,\
    "response":"Accept"}]
    """

struct MCPorterSourceTests {
    private let expiry = Date(timeIntervalSince1970: 1_793_390_167)
    private let interval = DateInterval(start: tokyo("2026-10-30T00:00:00"), end: tokyo("2026-11-30T00:00:00"))

    private func cookieFile(_ expiry: Date?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "cookie")
        if let expiry {
            let line = "#HttpOnly_midway-auth.amazon.com\tFALSE\t/\tTRUE\t\(Int(expiry.timeIntervalSince1970))\tsession\tdummy"
            try line.write(to: file, atomically: true, encoding: .utf8)
        }
        return file
    }

    private func source(_ runner: FakeRunner, cookie: URL, now: @escaping @Sendable () -> Date) -> MCPorterSource {
        MCPorterSource(
            runner: runner, mcporter: URL(fileURLWithPath: "/fake/mcporter"), cookieFile: cookie,
            now: now, calendar: cal)
    }

    @Test func buildsCalendarViewArguments() async throws {
        let runner = FakeRunner { CommandResult(exitCode: 0, stdout: validOutput, stderr: "") }
        let cookie = try cookieFile(expiry)
        let events = try await source(runner, cookie: cookie) { expiry.addingTimeInterval(-60) }.fetch(interval)
        #expect(events.count == 1)
        let call = try #require(runner.calls.first)
        #expect(call.executable.path == "/fake/mcporter")
        #expect(
            call.arguments == [
                "call", "aws-outlook-mcp.calendar_view", "view=day", "start_date=10-30-2026",
                "end_date=11-30-2026",
            ])
        #expect(call.environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        #expect(call.environment["HOME"] != nil)
        #expect(call.timeout == .seconds(180))
    }

    @Test func expiredCookieSkipsCommand() async throws {
        let runner = FakeRunner { CommandResult(exitCode: 0, stdout: validOutput, stderr: "") }
        let cookie = try cookieFile(expiry)
        await #expect(throws: FetchError.certificateExpired) {
            try await source(runner, cookie: cookie) { expiry.addingTimeInterval(1) }.fetch(interval)
        }
        #expect(runner.calls.isEmpty)
    }

    @Test func nonZeroExitWithExpiredCookieAfterRunIsCertificateExpired() async throws {
        let cookie = try cookieFile(expiry)
        let clock = Clock(times: [expiry.addingTimeInterval(-1), expiry.addingTimeInterval(1)])
        let runner = FakeRunner { CommandResult(exitCode: 1, stdout: "", stderr: "boom") }
        await #expect(throws: FetchError.certificateExpired) {
            try await source(runner, cookie: cookie) { clock.next() }.fetch(interval)
        }
        #expect(runner.calls.count == 1)
    }

    @Test func nonZeroExitIsCommandFailed() async throws {
        let cookie = try cookieFile(expiry)
        let runner = FakeRunner { CommandResult(exitCode: 1, stdout: "", stderr: "boom") }
        await #expect(throws: FetchError.commandFailed("boom")) {
            try await source(runner, cookie: cookie) { expiry.addingTimeInterval(-60) }.fetch(interval)
        }
    }

    @Test func timeoutPropagates() async throws {
        let cookie = try cookieFile(expiry)
        let runner = FakeRunner { throw FetchError.timedOut }
        await #expect(throws: FetchError.timedOut) {
            try await source(runner, cookie: cookie) { expiry.addingTimeInterval(-60) }.fetch(interval)
        }
    }

    @Test func garbageOutputIsInvalidOutput() async throws {
        let cookie = try cookieFile(expiry)
        let runner = FakeRunner { CommandResult(exitCode: 0, stdout: "not json", stderr: "") }
        do {
            _ = try await source(runner, cookie: cookie) { expiry.addingTimeInterval(-60) }.fetch(interval)
            Issue.record("expected invalidOutput")
        } catch let error as FetchError {
            guard case .invalidOutput = error else {
                Issue.record("unexpected \(error)")
                return
            }
        }
    }
}

/// Returns the given times in order, repeating the last one.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var times: [Date]

    init(times: [Date]) { self.times = times }

    func next() -> Date {
        lock.withLock { times.count > 1 ? times.removeFirst() : times[0] }
    }
}

struct ProcessCommandRunnerTests {
    private let sh = URL(fileURLWithPath: "/bin/sh")

    @Test func capturesOutputAndExitCode() async throws {
        let result = try await ProcessCommandRunner().run(
            executable: sh, arguments: ["-c", "echo out; echo err >&2; exit 3"],
            environment: [:], timeout: .seconds(10))
        #expect(result.exitCode == 3)
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
    }

    @Test func readsLargeOutputWithoutBlocking() async throws {
        let result = try await ProcessCommandRunner().run(
            executable: sh, arguments: ["-c", "yes 0123456789 | head -c 600000"],
            environment: [:], timeout: .seconds(10))
        #expect(result.stdout.utf8.count == 600_000)
    }

    @Test func timeoutThrowsTimedOut() async throws {
        await #expect(throws: FetchError.timedOut) {
            try await ProcessCommandRunner().run(
                executable: sh, arguments: ["-c", "exec sleep 5"],
                environment: [:], timeout: .milliseconds(500))
        }
    }
}
