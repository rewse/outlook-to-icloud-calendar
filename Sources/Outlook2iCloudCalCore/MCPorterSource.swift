import Foundation

/// Reads Outlook events by calling the `calendar_view` tool through mcporter.
public struct MCPorterSource: OutlookSource {
    static let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
    static let timeout = Duration.seconds(180)

    private let runner: CommandRunner
    private let mcporter: URL
    private let cookieFile: URL
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        runner: CommandRunner,
        mcporter: URL = URL(fileURLWithPath: "/opt/homebrew/bin/mcporter"),
        cookieFile: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".midway/cookie"),
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.runner = runner
        self.mcporter = mcporter
        self.cookieFile = cookieFile
        self.now = now
        self.calendar = calendar
    }

    public func fetch(_ interval: DateInterval) async throws -> [OutlookEvent] {
        guard MidwayCookie.isValid(fileURL: cookieFile, now: now()) else {
            throw FetchError.certificateExpired
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.path
        let result = try await runner.run(
            executable: mcporter,
            arguments: [
                "call", "aws-outlook-mcp.calendar_view", "view=day",
                "start_date=\(format(interval.start))", "end_date=\(format(interval.end))",
            ],
            environment: environment,
            timeout: Self.timeout)
        guard result.exitCode == 0 else {
            if !MidwayCookie.isValid(fileURL: cookieFile, now: now()) {
                throw FetchError.certificateExpired
            }
            throw FetchError.commandFailed(String(result.stderr.prefix(500)))
        }
        do {
            return try CalendarViewParser.parse(result.stdout)
        } catch {
            throw FetchError.invalidOutput(String(describing: error))
        }
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd-yyyy"
        return formatter.string(from: date)
    }
}
