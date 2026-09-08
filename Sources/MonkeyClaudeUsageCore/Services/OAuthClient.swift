import CryptoKit
import Foundation

/// OAuth 2.1 + PKCE against claude.ai, using the public Claude Code client id.
///
/// Stateless on purpose: every account runs the same flow with its own verifier, which
/// is what makes several accounts possible in one app.
public struct OAuthClient: Sendable {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    public static let scopes = ["user:profile", "user:inference"]

    static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    static let tokenEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Authorization

    public struct PendingAuthorization: Sendable {
        public let url: URL
        public let verifier: String
        public let state: String
    }

    public func beginAuthorization() -> PendingAuthorization {
        let verifier = Self.randomURLSafeString()
        let state = Self.randomURLSafeString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()

        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        return PendingAuthorization(url: components.url!, verifier: verifier, state: state)
    }

    /// The callback page hands back `code#state`; both halves are validated here.
    public func exchange(pastedCode: String, pending: PendingAuthorization) async throws -> OAuthCredentials {
        let trimmed = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "#", maxSplits: 1)
        guard let code = parts.first, !code.isEmpty else { throw OAuthError.emptyCode }
        if parts.count > 1, String(parts[1]) != pending.state { throw OAuthError.stateMismatch }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": String(code),
            "state": pending.state,
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "code_verifier": pending.verifier,
        ]
        return try await requestToken(body: body, fallback: nil)
    }

    public func refresh(_ credentials: OAuthCredentials) async throws -> OAuthCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw OAuthError.noRefreshToken
        }
        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        if !credentials.scopes.isEmpty { body["scope"] = credentials.scopes.joined(separator: " ") }
        return try await requestToken(body: body, fallback: credentials)
    }

    private func requestToken(body: [String: String], fallback: OAuthCredentials?) async throws -> OAuthCredentials {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OAuthError.badResponse }
        guard http.statusCode == 200 else {
            throw OAuthError.tokenRequestFailed(status: http.statusCode, permanent: (400..<500).contains(http.statusCode))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let credentials = Self.credentials(from: json, fallback: fallback) else {
            throw OAuthError.badResponse
        }
        return credentials
    }

    static func credentials(from json: [String: Any], fallback: OAuthCredentials?) -> OAuthCredentials? {
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else { return nil }
        let scopes = (json["scope"] as? String)?.split(whereSeparator: \.isWhitespace).map(String.init)
            ?? fallback?.scopes ?? scopes
        let expiresAt: Date? = {
            if let seconds = json["expires_in"] as? Double { return Date().addingTimeInterval(seconds) }
            if let seconds = json["expires_in"] as? Int { return Date().addingTimeInterval(TimeInterval(seconds)) }
            return fallback?.expiresAt
        }()
        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? fallback?.refreshToken,
            expiresAt: expiresAt,
            scopes: scopes
        )
    }

    // MARK: - Resources

    public struct HTTPResult: Sendable {
        public let data: Data
        public let statusCode: Int
        public let retryAfter: TimeInterval?
    }

    public func fetchUsage(token: String) async throws -> HTTPResult {
        try await get(Self.usageEndpoint, token: token)
    }

    public func fetchProfile(token: String) async throws -> AccountProfile? {
        let result = try await get(Self.profileEndpoint, token: token)
        guard result.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(AccountProfile.self, from: result.data)
    }

    private func get(_ url: URL, token: String) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OAuthError.badResponse }
        return HTTPResult(
            data: data,
            statusCode: http.statusCode,
            retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
        )
    }

    // MARK: - PKCE helpers

    static func randomURLSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

public enum OAuthError: LocalizedError, Equatable {
    case emptyCode
    case stateMismatch
    case noRefreshToken
    case badResponse
    case tokenRequestFailed(status: Int, permanent: Bool)

    public var errorDescription: String? {
        switch self {
        case .emptyCode: "The authorization code is empty."
        case .stateMismatch: "The authorization state does not match. Start over."
        case .noRefreshToken: "No refresh token stored for this account."
        case .badResponse: "Unexpected response from the authorization server."
        case let .tokenRequestFailed(status, _): "Token request failed (HTTP \(status))."
        }
    }

    public var isPermanent: Bool {
        switch self {
        case .emptyCode, .stateMismatch, .noRefreshToken: true
        case .badResponse: false
        case let .tokenRequestFailed(_, permanent): permanent
        }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
