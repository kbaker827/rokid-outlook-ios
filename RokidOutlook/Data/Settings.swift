import Foundation

final class SettingsStore: ObservableObject {

    // MARK: - Azure App Registration
    @Published var clientId: String {
        didSet { UserDefaults.standard.set(clientId, forKey: "outlook_client_id") }
    }
    @Published var tenantId: String {
        didSet { UserDefaults.standard.set(tenantId, forKey: "outlook_tenant_id") }
    }

    // MARK: - OAuth tokens
    var accessToken: String {
        get { UserDefaults.standard.string(forKey: "outlook_access_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "outlook_access_token") }
    }
    var refreshToken: String {
        get { UserDefaults.standard.string(forKey: "outlook_refresh_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "outlook_refresh_token") }
    }
    var tokenExpiry: Date {
        get { UserDefaults.standard.object(forKey: "outlook_token_expiry") as? Date ?? Date() }
        set { UserDefaults.standard.set(newValue, forKey: "outlook_token_expiry") }
    }

    var isTokenValid: Bool { !accessToken.isEmpty && tokenExpiry > Date().addingTimeInterval(60) }
    var isLoggedIn:   Bool { !accessToken.isEmpty }

    // MARK: - Polling
    @Published var pollInterval: Int {
        didSet { UserDefaults.standard.set(pollInterval, forKey: "outlook_poll_interval") }
    }

    // MARK: - Inbox settings
    @Published var maxEmails: Int {
        didSet { UserDefaults.standard.set(maxEmails, forKey: "outlook_max_emails") }
    }
    @Published var showUnreadOnly: Bool {
        didSet { UserDefaults.standard.set(showUnreadOnly, forKey: "outlook_unread_only") }
    }
    @Published var watchedFolders: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(watchedFolders) {
                UserDefaults.standard.set(data, forKey: "outlook_watched_folders")
            }
        }
    }

    // MARK: - Alerts
    @Published var alertNewEmail: Bool {
        didSet { UserDefaults.standard.set(alertNewEmail, forKey: "outlook_alert_new") }
    }
    @Published var alertImportant: Bool {
        didSet { UserDefaults.standard.set(alertImportant, forKey: "outlook_alert_important") }
    }
    @Published var alertFlagged: Bool {
        didSet { UserDefaults.standard.set(alertFlagged, forKey: "outlook_alert_flagged") }
    }
    @Published var alertEventStart: Bool {
        didSet { UserDefaults.standard.set(alertEventStart, forKey: "outlook_alert_event") }
    }
    @Published var eventAlertMinutes: Int {
        didSet { UserDefaults.standard.set(eventAlertMinutes, forKey: "outlook_event_minutes") }
    }

    // MARK: - Glasses
    @Published var glassesFormat: GlassesFormat {
        didSet { UserDefaults.standard.set(glassesFormat.rawValue, forKey: "outlook_glasses_format") }
    }
    @Published var glassesQueryEnabled: Bool {
        didSet { UserDefaults.standard.set(glassesQueryEnabled, forKey: "outlook_glasses_query") }
    }

    // MARK: - Init
    init() {
        let ud = UserDefaults.standard
        clientId            = ud.string(forKey: "outlook_client_id")      ?? ""
        tenantId            = ud.string(forKey: "outlook_tenant_id")      ?? "common"
        pollInterval        = ud.integer(forKey: "outlook_poll_interval").nonZero ?? 60
        maxEmails           = ud.integer(forKey: "outlook_max_emails").nonZero    ?? 20
        showUnreadOnly      = ud.object(forKey: "outlook_unread_only")    as? Bool ?? false
        alertNewEmail       = ud.object(forKey: "outlook_alert_new")      as? Bool ?? true
        alertImportant      = ud.object(forKey: "outlook_alert_important") as? Bool ?? true
        alertFlagged        = ud.object(forKey: "outlook_alert_flagged")  as? Bool ?? true
        alertEventStart     = ud.object(forKey: "outlook_alert_event")    as? Bool ?? true
        eventAlertMinutes   = ud.integer(forKey: "outlook_event_minutes").nonZero ?? 5
        glassesFormat       = GlassesFormat(rawValue: ud.string(forKey: "outlook_glasses_format") ?? "") ?? .compact
        glassesQueryEnabled = ud.object(forKey: "outlook_glasses_query")  as? Bool ?? true

        if let data = ud.data(forKey: "outlook_watched_folders"),
           let folders = try? JSONDecoder().decode([String].self, from: data) {
            watchedFolders = folders
        } else {
            watchedFolders = ["inbox"]
        }
    }

    func clearTokens() {
        accessToken  = ""
        refreshToken = ""
        tokenExpiry  = Date()
        ["outlook_access_token", "outlook_refresh_token", "outlook_token_expiry"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
    }

    static let redirectURI = "rokidoutlook://auth"
    static let scopes = [
        "User.Read",
        "Mail.Read",
        "Mail.ReadWrite",
        "Calendars.Read",
        "Contacts.Read",
        "offline_access"
    ]
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
