// Sources/App/FocusBlockSettings.swift
import Foundation

/// User config for the focus website block (tab General). UserDefaults-backed and
/// `@Published`, matching `BreakReminderSettings`. `onChange` lets
/// `FocusBlockController` re-evaluate + rewrite the shared state file whenever a
/// value flips. The block list here is canonical: the app pushes it to every
/// browser profile, so switching Chrome profiles keeps the same protection.
@MainActor
final class FocusBlockSettings: ObservableObject {
    static let shared = FocusBlockSettings()

    /// Master switch for the whole feature (installs the bridge, drives blocking).
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); onChange?() }
    }
    /// Block automatically whenever a Titroutine task is `in_progress` (the ⏱ row).
    @Published var autoDuringFocus: Bool {
        didSet { UserDefaults.standard.set(autoDuringFocus, forKey: Self.autoKey); onChange?() }
    }
    /// Manual on/off, used only when `autoDuringFocus` is off.
    @Published var manualBlocking: Bool {
        didSet { UserDefaults.standard.set(manualBlocking, forKey: Self.manualKey); onChange?() }
    }
    /// Canonical block list (bare domains, e.g. "youtube.com"). Pushed to every
    /// browser profile via the native-messaging bridge.
    @Published var blockedSites: [String] {
        didSet { UserDefaults.standard.set(blockedSites, forKey: Self.sitesKey); onChange?() }
    }

    /// Invoked on any change so `FocusBlockController` can react.
    var onChange: (() -> Void)?

    private static let enabledKey = "agentpet.focusBlock.enabled"
    private static let autoKey = "agentpet.focusBlock.autoDuringFocus"
    private static let manualKey = "agentpet.focusBlock.manualBlocking"
    private static let sitesKey = "agentpet.focusBlock.sites"

    private static let defaultSites = [
        "facebook.com", "instagram.com", "youtube.com",
        "tiktok.com", "x.com", "twitter.com", "reddit.com",
    ]

    init() {
        let d = UserDefaults.standard
        enabled = (d.object(forKey: Self.enabledKey) as? Bool) ?? false
        autoDuringFocus = (d.object(forKey: Self.autoKey) as? Bool) ?? true
        manualBlocking = (d.object(forKey: Self.manualKey) as? Bool) ?? false
        blockedSites = (d.object(forKey: Self.sitesKey) as? [String]) ?? Self.defaultSites
    }

    /// Add a normalized domain to the block list (no-op if blank/duplicate).
    func addSite(_ raw: String) {
        let d = Self.normalize(raw)
        guard !d.isEmpty, !blockedSites.contains(d) else { return }
        blockedSites.append(d)
    }

    func removeSite(_ domain: String) {
        blockedSites.removeAll { $0 == domain }
    }

    /// Reduce user input to a bare host: no scheme, path, port, or leading www.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        return s
    }
}
