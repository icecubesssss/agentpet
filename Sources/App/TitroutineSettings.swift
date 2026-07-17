import Foundation

/// User config for the Titroutine habit/task reminder. UserDefaults-backed and
/// `@Published`, matching `BreakReminderSettings`. `onChange` lets
/// `TitroutineReminderController` (re)start its timer when a value flips.
///
/// Only non-secret prefs live here; the Supabase refresh token is in `Keychain`.
@MainActor
final class TitroutineSettings: ObservableObject {
    static let shared = TitroutineSettings()

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); onChange?() }
    }
    @Published var reminderIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(reminderIntervalMinutes, forKey: Self.intervalKey); onChange?() }
    }
    /// Email of the linked Titroutine account (nil = not connected). Display only.
    @Published var connectedEmail: String? {
        didSet {
            if let connectedEmail { UserDefaults.standard.set(connectedEmail, forKey: Self.emailKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.emailKey) }
            onChange?()
        }
    }

    /// Supabase project the habit backend lives in. Kept out of source (entered
    /// by the user) so this repo carries no reference to any specific project.
    /// Both are public-by-design values (`NEXT_PUBLIC_*`): the anon key can only
    /// read what Postgres RLS allows, so they are not secrets.
    @Published var supabaseURL: String {
        didSet { UserDefaults.standard.set(supabaseURL, forKey: Self.urlKey) }
    }
    @Published var anonKey: String {
        didSet { UserDefaults.standard.set(anonKey, forKey: Self.anonKey_) }
    }
    @Published var webAppURL: String {
        didSet { UserDefaults.standard.set(webAppURL, forKey: Self.webAppURLKey) }
    }

    /// Invoked on any change so `TitroutineReminderController` can react.
    var onChange: (() -> Void)?

    var isConnected: Bool { connectedEmail != nil }

    var baseURL: URL? {
        let s = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : URL(string: s)
    }
    /// True once a Supabase URL + anon key have been provided.
    var isConfigured: Bool {
        baseURL != nil && !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let enabledKey = "agentpet.titroutine.enabled"
    private static let intervalKey = "agentpet.titroutine.reminderIntervalMinutes"
    private static let emailKey = "agentpet.titroutine.connectedEmail"
    private static let urlKey = "agentpet.titroutine.supabaseURL"
    private static let anonKey_ = "agentpet.titroutine.anonKey"
    private static let webAppURLKey = "agentpet.titroutine.webAppURL"

    init() {
        let d = UserDefaults.standard
        enabled = (d.object(forKey: Self.enabledKey) as? Bool) ?? false
        reminderIntervalMinutes = (d.object(forKey: Self.intervalKey) as? Int) ?? 60
        connectedEmail = d.string(forKey: Self.emailKey)
        supabaseURL = d.string(forKey: Self.urlKey) ?? ""
        anonKey = d.string(forKey: Self.anonKey_) ?? ""
        
        let storedURL = d.string(forKey: Self.webAppURLKey)
        if storedURL == nil || storedURL == "http://localhost:3000" {
            webAppURL = "https://titroutines.vercel.app/"
            d.set("https://titroutines.vercel.app/", forKey: Self.webAppURLKey)
        } else {
            webAppURL = storedURL!
        }
    }
}
