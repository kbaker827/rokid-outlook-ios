import Foundation
import Combine

@MainActor
final class OutlookViewModel: ObservableObject {

    // MARK: - Published state
    @Published var emails:       [OutlookEmail]   = []
    @Published var events:       [OutlookEvent]   = []
    @Published var contacts:     [OutlookContact] = []
    @Published var folders:      [MailFolder]     = []
    @Published var unreadCount:  Int              = 0
    @Published var isLoading:    Bool             = false
    @Published var errorMessage: String?          = nil
    @Published var lastRefresh:  Date?            = nil
    @Published var searchQuery:  String           = ""
    @Published var selectedFolder: String         = "inbox"

    // MARK: - Sub-objects
    let glassesServer = GlassesServer()
    let authManager:   OutlookAuthManager

    // MARK: - Private
    private let api      = OutlookAPIClient()
    private var pollTask: Task<Void, Never>?
    private var prevEmailIds:    Set<String> = []
    private var alertedEventIds: Set<String> = []

    var settings: SettingsStore

    // MARK: - Init

    init(settings: SettingsStore, authManager: OutlookAuthManager) {
        self.settings    = settings
        self.authManager = authManager

        glassesServer.onRemoteQuery = { [weak self] query in
            Task { @MainActor [weak self] in
                guard let self, self.settings.glassesQueryEnabled else { return }
                await self.handleGlassesQuery(query)
            }
        }
        glassesServer.start()
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(settings.pollInterval))
            }
        }
    }

    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    func refresh() async {
        guard authManager.isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let token = try await authManager.refreshIfNeeded()

            // Fetch in parallel
            async let emailsTask  = api.fetchInbox(token: token, limit: settings.maxEmails, unreadOnly: settings.showUnreadOnly)
            async let eventsTask  = api.fetchTodaysEvents(token: token)
            async let countTask   = api.fetchUnreadCount(token: token)

            let (fetchedEmails, fetchedEvents, count) = try await (emailsTask, eventsTask, countTask)

            // Fetch user if not set
            if authManager.currentUser == nil {
                authManager.currentUser = try? await api.fetchMe(token: token)
            }

            checkNewEmails(fetchedEmails)
            checkEventAlerts(fetchedEvents)

            emails       = fetchedEmails
            events       = fetchedEvents.sorted { $0.start < $1.start }
            unreadCount  = count
            lastRefresh  = Date()
            errorMessage = nil

            glassesServer.broadcastSummary(
                unreadCount: unreadCount,
                emails:      emails,
                events:      events,
                format:      settings.glassesFormat
            )

        } catch GraphError.unauthorized {
            errorMessage = "Session expired. Please sign in again."
            authManager.signOut()
        } catch {
            errorMessage = error.localizedDescription
            glassesServer.broadcastError(error.localizedDescription)
        }
    }

    // MARK: - Alerts

    private func checkNewEmails(_ incoming: [OutlookEmail]) {
        guard !prevEmailIds.isEmpty else {
            prevEmailIds = Set(incoming.map { $0.id }); return
        }
        let cutoff = Date().addingTimeInterval(-Double(settings.pollInterval) * 2)
        for email in incoming where !prevEmailIds.contains(email.id) && email.receivedDateTime > cutoff {
            if settings.alertNewEmail {
                let reason = email.isImportant ? "IMPORTANT" : "NEW"
                glassesServer.broadcastEmailAlert(email, reason: reason)
            }
        }
        prevEmailIds = Set(incoming.map { $0.id })
    }

    private func checkEventAlerts(_ events: [OutlookEvent]) {
        guard settings.alertEventStart else { return }
        let threshold = TimeInterval(settings.eventAlertMinutes * 60)
        for event in events where !alertedEventIds.contains(event.id)
                               && event.start > Date()
                               && event.start.timeIntervalSinceNow <= threshold + 30 {
            glassesServer.broadcastEventAlert(event)
            alertedEventIds.insert(event.id)
        }
        alertedEventIds = alertedEventIds.intersection(Set(events.map { $0.id }))
    }

    // MARK: - Glasses query handler

    private func handleGlassesQuery(_ query: String) async {
        let lower = query.lowercased()

        guard authManager.isSignedIn else {
            glassesServer.broadcastError("Not signed in to Outlook")
            return
        }

        // Email / inbox
        if lower.contains("email") || lower.contains("inbox") || lower.contains("mail") {
            glassesServer.broadcastEmails(emails)
            return
        }

        // Unread
        if lower.contains("unread") {
            let unread = emails.filter { !$0.isRead }
            if unread.isEmpty {
                glassesServer.broadcastStatus("📧 Inbox is clear — no unread emails")
            } else {
                glassesServer.broadcastEmails(unread)
            }
            return
        }

        // Flagged
        if lower.contains("flag") {
            let flagged = emails.filter { $0.flag == .flagged }
            if flagged.isEmpty {
                glassesServer.broadcastStatus("No flagged emails")
            } else {
                glassesServer.broadcastEmails(flagged)
            }
            return
        }

        // Important
        if lower.contains("important") {
            let important = emails.filter { $0.isImportant }
            glassesServer.broadcastEmails(important)
            return
        }

        // Calendar / events / meetings / schedule
        if lower.contains("calendar") || lower.contains("event") || lower.contains("meeting") || lower.contains("schedule") {
            glassesServer.broadcastEvents(events)
            return
        }

        // Next event
        if lower.contains("next") {
            if let next = events.filter({ $0.start > Date() }).sorted(by: { $0.start < $1.start }).first {
                glassesServer.broadcastEventAlert(next)
            } else {
                glassesServer.broadcastStatus("No upcoming events today")
            }
            return
        }

        // Contact lookup: "contact Sarah" or "find Sarah"
        if lower.hasPrefix("contact ") || lower.hasPrefix("find ") {
            let name = lower.hasPrefix("contact ") ? String(query.dropFirst(8)) : String(query.dropFirst(5))
            await lookupContact(name.trimmingCharacters(in: .whitespaces))
            return
        }

        // Summary / status
        if lower.contains("summary") || lower.contains("status") || lower.contains("count") {
            glassesServer.broadcastSummary(
                unreadCount: unreadCount,
                emails:      emails,
                events:      events,
                format:      .compact
            )
            return
        }

        // Refresh
        if lower.contains("refresh") || lower.contains("reload") {
            await refresh()
            return
        }

        // Default: summary
        glassesServer.broadcastSummary(
            unreadCount: unreadCount,
            emails:      emails,
            events:      events,
            format:      settings.glassesFormat
        )
    }

    private func lookupContact(_ name: String) async {
        glassesServer.broadcastStatus("🔍 Searching '\(name)'…")
        do {
            let token    = try await authManager.refreshIfNeeded()
            let results  = try await api.searchContacts(query: name, token: token)
            if results.isEmpty {
                glassesServer.broadcastStatus("No contact found for '\(name)'")
            } else {
                results.prefix(3).forEach { glassesServer.broadcastContact($0) }
            }
        } catch {
            glassesServer.broadcastError(error.localizedDescription)
        }
    }

    // MARK: - Mark as read

    func markAsRead(_ email: OutlookEmail) {
        Task {
            guard let token = try? await authManager.refreshIfNeeded() else { return }
            try? await api.markAsRead(emailId: email.id, token: token)
            if let idx = emails.firstIndex(where: { $0.id == email.id }) {
                emails[idx] = OutlookEmail(
                    id: email.id, subject: email.subject, bodyPreview: email.bodyPreview,
                    from: email.from, toRecipients: email.toRecipients,
                    receivedDateTime: email.receivedDateTime, isRead: true,
                    isImportant: email.isImportant, hasAttachments: email.hasAttachments,
                    flag: email.flag, conversationId: email.conversationId, folder: email.folder
                )
                if unreadCount > 0 { unreadCount -= 1 }
            }
        }
    }

    // MARK: - Computed

    var filteredEmails: [OutlookEmail] {
        var result = emails
        if !searchQuery.isEmpty {
            result = result.filter {
                $0.subject.localizedCaseInsensitiveContains(searchQuery) ||
                $0.from.displayName.localizedCaseInsensitiveContains(searchQuery) ||
                $0.bodyPreview.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        return result
    }

    var todaysEvents: [OutlookEvent] {
        let cal = Calendar.current
        return events.filter { cal.isDateInToday($0.start) }.sorted { $0.start < $1.start }
    }

    var nextEvent: OutlookEvent? {
        events.filter { $0.start > Date() }.sorted { $0.start < $1.start }.first
    }
}
