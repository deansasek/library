import AppKit

/// Finds an address, a phone number, and a date in a text clip. Detection runs on this Mac with NSDataDetector and
/// never touches the network. Quick Open offers an action for each kind it finds.
enum SmartText {
    /// A date or time in the text, with the length the text gives it. A zero length means the text names none.
    struct DetectedDate: Equatable {
        let start: Date
        let duration: TimeInterval
    }

    /// The first match of each kind, or nil when the text has none of it.
    struct Matches: Equatable {
        var address: String?
        var phone: String?
        var date: DetectedDate?
    }

    /// Only this many characters are searched, so a very large copy does not stall the action list.
    static let detectionLimit = 10_000

    static func detect(_ text: String) -> Matches {
        let sample = String(text.prefix(detectionLimit))
        let types = NSTextCheckingResult.CheckingType.address.union(.phoneNumber).union(.date)
        guard !sample.isEmpty, let detector = try? NSDataDetector(types: types.rawValue) else { return Matches() }
        let ns = sample as NSString
        var found = Matches()
        for match in detector.matches(in: sample, range: NSRange(location: 0, length: ns.length)) {
            switch match.resultType {
            case .address where found.address == nil:
                found.address = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            case .phoneNumber where found.phone == nil:
                found.phone = match.phoneNumber ?? ns.substring(with: match.range)
            case .date where found.date == nil:
                if let start = match.date {
                    found.date = DetectedDate(start: start, duration: match.duration)
                }
            default:
                break
            }
        }
        return found
    }

    /// The Apple Maps search for an address. Nil only if the address cannot be put in a URL.
    static func mapsURL(for address: String) -> URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [URLQueryItem(name: "q", value: address)]
        return parts?.url
    }

    /// A phone number with only its digits and plus sign, such as "+14155550132" for "+1 (415) 555-0132".
    static func phoneDigits(_ phone: String) -> String {
        String(phone.filter { $0 == "+" || ("0"..."9").contains($0) })
    }

    /// An iCalendar event for the date. The summary is the first non-empty line of the text. An event with no length
    /// lasts one hour. Dates are written in UTC, so Calendar shows them in the Mac's time zone.
    static func calendarEvent(text: String, date: DetectedDate, created: Date, uid: String) -> String {
        let summary = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let length = date.duration > 0 ? date.duration : 3_600
        let lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Library//Quick Open//EN",
            "BEGIN:VEVENT",
            "UID:\(uid)@library",
            "DTSTAMP:\(utc(created))",
            "DTSTART:\(utc(date.start))",
            "DTEND:\(utc(date.start.addingTimeInterval(length)))",
            "SUMMARY:\(escaped(String(summary.prefix(120))))",
            "END:VEVENT",
            "END:VCALENDAR",
        ]
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the event to a temporary .ics file and opens it, so Calendar shows its add-event sheet. The file is
    /// removed a few seconds later, after Calendar has had time to read it.
    @MainActor
    static func openInCalendar(text: String, date: DetectedDate) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Library-Event-\(UUID().uuidString).ics")
        let event = calendarEvent(text: text, date: date, created: Date(), uid: UUID().uuidString)
        do {
            try event.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        NSWorkspace.shared.open(url)
        Task {
            try? await Task.sleep(for: .seconds(5))
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A date as UTC in iCalendar form, such as 20261225T143000Z.
    private static func utc(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04ld%02ld%02ldT%02ld%02ld%02ldZ",
                      parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1,
                      parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// Escapes the characters iCalendar gives a meaning to in a text value.
    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
    }
}
