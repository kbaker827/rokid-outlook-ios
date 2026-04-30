import Foundation
import Network

/// Bidirectional TCP server on port 8099.
/// Glasses → Phone: "QUERY: email" / "QUERY: calendar" / "QUERY: contact Sarah" etc.
/// Phone → Glasses: newline-delimited JSON packets
@MainActor
final class GlassesServer: ObservableObject {

    @Published var isRunning   = false
    @Published var clientCount = 0

    var onRemoteQuery: ((String) -> Void)?

    private var listener:    NWListener?
    private var connections: [ConnectionWrapper] = []
    private let port: NWEndpoint.Port = 8099
    private let queue = DispatchQueue(label: "OutlookGlassesQ", qos: .userInitiated)

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        guard let l = try? NWListener(using: .tcp, on: port) else { return }
        listener = l
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor [weak self] in self?.accept(conn) }
        }
        l.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in self?.isRunning = (state == .ready) }
        }
        l.start(queue: queue)
    }

    func stop() {
        listener?.cancel(); listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        clientCount = 0; isRunning = false
    }

    // MARK: - Broadcast helpers

    /// Push Outlook summary HUD.
    func broadcastSummary(
        unreadCount: Int,
        emails: [OutlookEmail],
        events: [OutlookEvent],
        format: GlassesFormat
    ) {
        let nextEvent = events.filter { $0.start > Date() }.sorted { $0.start < $1.start }.first
        let latestUnread = emails.filter { !$0.isRead }.first ?? emails.first

        let text: String
        switch format {
        case .minimal:
            var parts = ["📧 \(unreadCount) unread"]
            if let e = nextEvent { parts.append("\(e.statusIcon) \(e.subject) \(e.timeFormatted)") }
            text = parts.joined(separator: "  ")

        case .compact:
            var lines: [String] = ["📧 \(unreadCount) unread"]
            if let e = nextEvent {
                let mins = e.minutesUntilStart
                let when = mins == 0 ? "now" : "in \(mins)m"
                lines.append("\(e.statusIcon) \(e.subject) \(when)")
            }
            if let m = latestUnread {
                lines.append("✉️ \(m.from.displayName): \(m.subject)")
            }
            text = lines.joined(separator: "\n")

        case .detailed:
            var lines: [String] = []
            if let m = latestUnread {
                lines.append("✉️ From: \(m.from.displayName)")
                lines.append("  \(m.subject)")
                if !m.bodyPreview.isEmpty {
                    lines.append("  \(String(m.bodyPreview.prefix(80)))")
                }
            }
            if let e = nextEvent {
                lines.append("\(e.statusIcon) \(e.subject) @ \(e.timeFormatted)")
            }
            text = lines.isEmpty ? "📧 \(unreadCount) unread  No upcoming events" : lines.joined(separator: "\n")
        }
        broadcast(type: "outlook", text: text)
    }

    /// Alert glasses about a new email.
    func broadcastEmailAlert(_ email: OutlookEmail, reason: String) {
        let imp = email.isImportant ? "❗ " : ""
        broadcast(type: "email_alert", text: "\(imp)[\(reason)] ✉️ \(email.from.displayName): \(email.subject)")
    }

    /// Alert glasses about an upcoming event.
    func broadcastEventAlert(_ event: OutlookEvent) {
        let mins = event.minutesUntilStart
        let when = mins == 0 ? "NOW" : "in \(mins) min"
        broadcast(type: "event_alert", text: "📅 Starting \(when): \(event.subject)\n\(event.timeFormatted)")
    }

    /// Push email list.
    func broadcastEmails(_ emails: [OutlookEmail]) {
        if emails.isEmpty { broadcast(type: "emails", text: "No emails found"); return }
        let lines = emails.prefix(5).map { e -> String in
            let read = e.isRead ? "" : "● "
            let imp  = e.isImportant ? "❗" : ""
            return "\(read)\(imp)✉️ \(e.from.displayName): \(e.subject) (\(e.ageFormatted))"
        }
        broadcast(type: "emails", text: lines.joined(separator: "\n"))
    }

    /// Push calendar events.
    func broadcastEvents(_ events: [OutlookEvent]) {
        if events.isEmpty { broadcast(type: "calendar", text: "No events today"); return }
        let lines = events.prefix(5).map { "\($0.statusIcon) \($0.subject)\n  \($0.timeFormatted)" }
        broadcast(type: "calendar", text: lines.joined(separator: "\n"))
    }

    /// Push contact info.
    func broadcastContact(_ contact: OutlookContact) {
        var lines = ["\(contact.displayName)"]
        if let email = contact.email   { lines.append("✉️ \(email)") }
        if let phone = contact.phone   { lines.append("📞 \(phone)") }
        if let title = contact.jobTitle { lines.append("💼 \(title)") }
        if let co    = contact.company  { lines.append("🏢 \(co)") }
        broadcast(type: "contact", text: lines.joined(separator: "\n"))
    }

    func broadcastStatus(_ text: String) { broadcast(type: "status", text: text) }
    func broadcastError (_ text: String) { broadcast(type: "error",  text: "❌ \(text)") }

    // MARK: - Private

    private func accept(_ nwConn: NWConnection) {
        let w = ConnectionWrapper(connection: nwConn, queue: queue)
        w.onReceiveLine = { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                if let q = GlassesPacket.parseQuery(from: line) { self.onRemoteQuery?(q) }
            }
        }
        w.onDisconnect = { [weak self] in
            Task { @MainActor [weak self] in
                self?.connections.removeAll { $0 === w }
                self?.clientCount = self?.connections.count ?? 0
            }
        }
        connections.append(w)
        clientCount = connections.count
        w.start()
    }

    private func broadcast(type: String, text: String) {
        let packet = GlassesPacket.make(type: type, text: text)
        connections.forEach { $0.send(packet) }
    }
}

// MARK: - Connection wrapper

private final class ConnectionWrapper {
    let connection: NWConnection
    var onReceiveLine: ((String) -> Void)?
    var onDisconnect:  (() -> Void)?
    private let queue: DispatchQueue
    private var buffer = Data()

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection; self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed   = state { self?.onDisconnect?() }
            if case .cancelled = state { self?.onDisconnect?() }
        }
        connection.start(queue: queue)
        receiveNext()
    }

    func send(_ data: Data) { connection.send(content: data, completion: .contentProcessed { _ in }) }
    func cancel() { connection.cancel() }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, err in
            guard let self else { return }
            if let d = data, !d.isEmpty { self.buffer.append(d); self.flush() }
            if done || err != nil { self.onDisconnect?() } else { self.receiveNext() }
        }
    }

    private func flush() {
        while let idx = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<idx]
            buffer.removeSubrange(buffer.startIndex...idx)
            if let s = String(data: line, encoding: .utf8) { onReceiveLine?(s) }
        }
    }
}
