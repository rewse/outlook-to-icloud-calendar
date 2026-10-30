import Foundation
import Testing

@testable import Outlook2iCloudCalCore

let cal: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

func tokyo(_ local: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = cal
    formatter.timeZone = cal.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.date(from: local)!
}

func event(
    id: String = "id-1",
    response: String = "Accept",
    subject: String = "Sample",
    start: String = "2026-11-02T10:00:00",
    end: String = "2026-11-02T11:00:00",
    isAllDay: Bool = false,
    isCanceled: Bool = false
) -> OutlookEvent {
    OutlookEvent(
        meetingId: id,
        subject: subject,
        start: tokyo(start),
        end: tokyo(end),
        location: "",
        isAllDay: isAllDay,
        isCanceled: isCanceled,
        response: response)
}
