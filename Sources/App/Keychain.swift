import Foundation
import Security

/// Minimal Keychain wrapper for small secrets. Used for the Titroutine Supabase
/// refresh token, which is sensitive (it mints access tokens) and so does not
/// belong in UserDefaults. Values are generic-password items scoped to this
/// app's service and keyed by an account string.
enum Keychain {
    private static let service = "com.agentpet.app.titroutine"

    /// Upsert (or, with `nil`, delete) the secret for `account`.
    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)   // always overwrite; no duplicates
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        // AfterFirstUnlock so a background refresh works while the screen is
        // locked; ThisDeviceOnly so the token never syncs to iCloud Keychain.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
