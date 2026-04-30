import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class OutlookAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    @Published var isSignedIn: Bool = false
    @Published var currentUser: (name: String, email: String)? = nil
    @Published var error: String? = nil
    @Published var isSigningIn: Bool = false

    private let settings: SettingsStore
    private var codeVerifier = ""

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
        isSignedIn = settings.isLoggedIn
    }

    // MARK: - Sign In

    func signIn() async {
        guard !settings.clientId.isEmpty else {
            error = "Client ID is not set. Add your Azure App Registration Client ID in Settings."
            return
        }
        codeVerifier  = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: codeVerifier)
        let state     = UUID().uuidString

        var comps = URLComponents(string:
            "https://login.microsoftonline.com/\(settings.tenantId)/oauth2/v2.0/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id",             value: settings.clientId),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: SettingsStore.redirectURI),
            URLQueryItem(name: "scope",                 value: SettingsStore.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "response_mode",         value: "query")
        ]
        guard let authURL = comps.url else { error = "Could not build auth URL."; return }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let callback = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "rokidoutlook") { url, err in
                    if let url = url { cont.resume(returning: url) }
                    else { cont.resume(throwing: err ?? URLError(.cancelled)) }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }

            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value
            else { throw OAuthError.noCode }

            try await exchangeCode(code)
            isSignedIn = true

        } catch {
            if (error as? URLError)?.code != .cancelled {
                self.error = error.localizedDescription
            }
            isSignedIn = false
        }
    }

    // MARK: - Token exchange

    private func exchangeCode(_ code: String) async throws {
        var req = URLRequest(url: URL(string:
            "https://login.microsoftonline.com/\(settings.tenantId)/oauth2/v2.0/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [String: String] = [
            "client_id":     settings.clientId,
            "code":          code,
            "redirect_uri":  SettingsStore.redirectURI,
            "grant_type":    "authorization_code",
            "code_verifier": codeVerifier,
            "scope":         SettingsStore.scopes.joined(separator: " ")
        ]
        req.httpBody = encodeForm(params)
        let (data, _) = try await URLSession.shared.data(for: req)
        try storeTokens(from: data)
    }

    // MARK: - Token refresh

    func refreshIfNeeded() async throws -> String {
        if settings.isTokenValid { return settings.accessToken }
        guard !settings.refreshToken.isEmpty else { throw OAuthError.notSignedIn }

        var req = URLRequest(url: URL(string:
            "https://login.microsoftonline.com/\(settings.tenantId)/oauth2/v2.0/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [String: String] = [
            "client_id":     settings.clientId,
            "refresh_token": settings.refreshToken,
            "grant_type":    "refresh_token",
            "scope":         SettingsStore.scopes.joined(separator: " ")
        ]
        req.httpBody = encodeForm(params)
        let (data, _) = try await URLSession.shared.data(for: req)
        try storeTokens(from: data)
        return settings.accessToken
    }

    // MARK: - Sign out

    func signOut() {
        settings.clearTokens()
        isSignedIn   = false
        currentUser  = nil
    }

    // MARK: - Helpers

    private func storeTokens(from data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.tokenParseError
        }
        if let errDesc = json["error_description"] as? String { throw OAuthError.serverError(errDesc) }
        guard let access  = json["access_token"] as? String,
              let expires = json["expires_in"]   as? Int
        else { throw OAuthError.tokenParseError }

        settings.accessToken  = access
        settings.refreshToken = json["refresh_token"] as? String ?? settings.refreshToken
        settings.tokenExpiry  = Date().addingTimeInterval(TimeInterval(expires))
    }

    private func encodeForm(_ params: [String: String]) -> Data? {
        params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
              .joined(separator: "&")
              .data(using: .utf8)
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

enum OAuthError: LocalizedError {
    case noCode, tokenParseError, notSignedIn, serverError(String)
    var errorDescription: String? {
        switch self {
        case .noCode:               return "No authorization code received."
        case .tokenParseError:      return "Could not parse token response."
        case .notSignedIn:          return "Not signed in. Please sign in first."
        case .serverError(let msg): return msg
        }
    }
}
