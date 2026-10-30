import Foundation

/// An Outlook calendar event as reported by `calendar_view`.
public struct OutlookEvent: Equatable, Sendable {
    public let meetingId: String
    public let subject: String
    public let start: Date
    public let end: Date
    public let location: String
    public let isAllDay: Bool
    public let isCanceled: Bool
    public let response: String

    public init(
        meetingId: String,
        subject: String,
        start: Date,
        end: Date,
        location: String,
        isAllDay: Bool,
        isCanceled: Bool,
        response: String
    ) {
        self.meetingId = meetingId
        self.subject = subject
        self.start = start
        self.end = end
        self.location = location
        self.isAllDay = isAllDay
        self.isCanceled = isCanceled
        self.response = response
    }
}
