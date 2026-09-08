import Foundation
import Security

/// Reads the session the Claude Code CLI already holds, so the first account can be
/// added without the browser round-trip.
///
/// The CLI stores its tokens in a generic-password item named `Claude Code-credentials`.
/// macOS asks the user to allow access the first time — that prompt *is* the consent,
/// which is why the app never reads it unless the user clicks Import.
public enum ClaudeCodeSession {
    static let keychainService = "Claude Code-credentials"

    public static func read() -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String, !accessToken.isEmpty else {
            return nil
        }

        // `expiresAt` is in milliseconds, unlike everything else the app handles.
        let expiresAt = (oauth["expiresAt"] as? Double).map {
            Date(timeIntervalSince1970: $0 / 1000)
        }

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: expiresAt,
            scopes: (oauth["scopes"] as? [String]) ?? OAuthClient.scopes
        )
    }

    /// Whether the item exists at all — checked without reading it, so the permission
    /// prompt only appears when the user actually asks to import.
    public static var isAvailable: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}
