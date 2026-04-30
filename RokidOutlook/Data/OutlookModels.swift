import Foundation

// MARK: - Email

struct OutlookEmail: Identifiable, Equatable {
    let id: String
    let subject: String
    let bodyPreview: String
    let from: EmailAddress
    let toRecipients: [EmailAddress]
    let receivedDateTime: Date
    let isRead: Bool
    let isImportant: Bool
    let hasAttachments: Bool
    let flag: EmailFlag
    let conversationId: String
    let folder: String   // inbox, sent, drafts, etc.

    var ageFormatted: String {
        let diff = Date().timeIntervalSince(receivedDateTime)
        if diff < 60        { return "just now" }
        if diff < 3600      { return "\(Int(diff/60))m ago" }
        if diff < 86400     { return "\(Int(diff/3600))h ago" }
        if diff < 86400 * 7 { return receivedDateTime.formatted(.dateTime.weekday(.wide)) }
        return receivedDateTime.formatted(date: .abbreviated, time: .omitted)
    }

    var compactLine: String {
        let readDot = isRead ? "" : "● "
        let attach  = hasAttachments ? "📎 " : ""
        let imp     = isImportant ? "❗ " : ""
        return "\(readDot)\(imp)\(attach)\(from.name): \(subject)"
    }
}

struct EmailAddress: Equatable {
    let name: String
    let address: String

    var displayName: String { name.isEmpty ? address : name }
}

enum EmailFlag: String {
    case notFlagged, flagged, complete
}

// MARK: - Calendar Event

struct OutlookEvent: Identifiable, Equatable {
    let id: String
    let subject: String
    let bodyPreview: String
    let start: Date
    let end: Date
    let location: String?
    let organizer: EmailAddress?
    let isOnlineMeeting: Bool
    let joinURL: String?
    let isAllDay: Bool
    let showAs: ShowAsStatus
    let importance: EventImportance
    let attendeeCount: Int
    let responseStatus: ResponseStatus

    var isNow:     Bool { Date() >= start && Date() <= end }
    var isUpcoming: Bool { start > Date() && start.timeIntervalSinceNow < 3600 }
    var minutesUntilStart: Int { max(0, Int(start.timeIntervalSinceNow / 60)) }

    var statusIcon: String {
        if isNow      { return "🟢" }
        if isUpcoming { return "🟡" }
        return "📅"
    }

    var timeFormatted: String {
        if isAllDay { return "All day" }
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }

    var compactLine: String { "\(statusIcon) \(subject) · \(timeFormatted)" }
}

enum ShowAsStatus: String {
    case free, tentative, busy, oof, workingElsewhere, unknown
}

enum EventImportance: String {
    case low, normal, high
}

enum ResponseStatus: String {
    case none, organizer, tentativelyAccepted, accepted, declined, notResponded
    var displayName: String {
        switch self {
        case .accepted:            return "Accepted"
        case .tentativelyAccepted: return "Tentative"
        case .declined:            return "Declined"
        case .notResponded:        return "Not responded"
        case .organizer:           return "Organizer"
        default:                   return "—"
        }
    }
}

// MARK: - Contact

struct OutlookContact: Identifiable, Equatable {
    let id: String
    let displayName: String
    let email: String?
    let phone: String?
    let jobTitle: String?
    let company: String?

    var initials: String {
        let parts = displayName.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map { String($0) }.joined()
    }
}

// MARK: - Mail folder

struct MailFolder: Identifiable, Equatable {
    let id: String
    let displayName: String
    let unreadCount: Int
    let totalCount: Int
}

// MARK: - Glasses display format

enum GlassesFormat: String, CaseIterable, Identifiable {
    case compact  = "compact"
    case detailed = "detailed"
    case minimal  = "minimal"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .compact:  return "Compact"
        case .detailed: return "Detailed"
        case .minimal:  return "Minimal"
        }
    }
    var description: String {
        switch self {
        case .compact:  return "Unread count + latest email + next event"
        case .detailed: return "Full email preview + event details"
        case .minimal:  return "Unread count and next event only"
        }
    }
}

// MARK: - Glasses wire packets

struct GlassesPacket {
    static func make(type: String, text: String) -> Data {
        let dict: [String: String] = ["type": type, "text": text]
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return data + Data([0x0A])
    }

    static func parseQuery(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.uppercased().hasPrefix("QUERY:") {
            let q = trimmed.dropFirst("QUERY:".count).trimmingCharacters(in: .whitespaces)
            return q.isEmpty ? nil : q
        }
        return trimmed
    }
}
