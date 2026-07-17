// Sources/App/FocusBlockController.swift
import AppKit
import AgentPetCore

/// Shared on-disk locations + identifiers for the Focus Block bridge. Used by both
/// the running app (`FocusBlockController`, writer) and the short-lived native host
/// subprocess (`FocusHostCLI`, reader).
enum FocusBlockPaths {
    /// JSON the app writes and the host streams to the extension.
    static var stateFile: String { AgentPetPaths.baseDir + "/focus-state.json" }
    /// Tiny shell shim browsers exec as the native host (execs the app binary with
    /// the `focus-host` subcommand — Chrome's manifest can't carry arguments).
    static var hostWrapper: String { AgentPetPaths.baseDir + "/focus-host.sh" }
    static let hostName = "com.agentpet.focus"
    /// Pinned by the `key` in the extension's manifest.json — must match, or the
    /// browser refuses to launch the host for that extension.
    static let extensionID = "ifgnoilgboddebgmbnjnkbmmopppkneb"
}

/// Drives the focus website block. Owns the canonical block state, writes it to a
/// shared file that every browser profile's native host streams, and (when
/// `autoDuringFocus`) polls Titroutine so blocking follows an in-progress task.
/// Modeled on `BreakReminderController`. No root, no /etc/hosts — enforcement is
/// entirely in the browser extension.
@MainActor
final class FocusBlockController {
    static let shared = FocusBlockController()

    private let settings = FocusBlockSettings.shared
    private var focusTimer: Timer?
    private var polling = false

    /// Last known "is a Titroutine task in progress" + its title (for the reason).
    private var hasInProgressTask = false
    private var focusReason = ""

    private static let pollInterval: TimeInterval = 60

    func start() {
        installBridge() // idempotent; refreshes the wrapper path on every launch
        settings.onChange = { [weak self] in self?.applyEnabled() }
        applyEnabled()
    }

    /// Clear the block on quit so a closed app never leaves a profile blocked.
    func shutdown() {
        focusTimer?.invalidate()
        focusTimer = nil
        writeState(blockingOverride: false)
    }

    // MARK: - State

    private func computeBlocking() -> Bool {
        guard settings.enabled else { return false }
        return settings.autoDuringFocus ? hasInProgressTask : settings.manualBlocking
    }

    /// Atomically write the state file. The atomic rename bumps mtime, which each
    /// host's poll notices and forwards to its extension.
    private func writeState(blockingOverride: Bool? = nil) {
        let blocking = blockingOverride ?? computeBlocking()
        let payload: [String: Any] = [
            "blocking": blocking,
            "sites": settings.blockedSites,
            "reason": (blocking && settings.autoDuringFocus) ? focusReason : "",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? FileManager.default.createDirectory(
            atPath: AgentPetPaths.baseDir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: FocusBlockPaths.stateFile), options: .atomic)
    }

    // MARK: - Focus polling

    /// (Re)start the in-progress poll to match settings, and reflect the current
    /// state immediately. Called on every settings change.
    private func applyEnabled() {
        focusTimer?.invalidate()
        focusTimer = nil

        guard settings.enabled, settings.autoDuringFocus, TitroutineClient.shared.isConnected else {
            // Manual mode / disabled / not connected: no polling, just publish now.
            hasInProgressTask = false
            focusReason = ""
            writeState()
            return
        }

        pollFocus() // fetch immediately, no wait for the first tick
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.pollFocus() }
        }
        RunLoop.main.add(t, forMode: .common)
        focusTimer = t
        writeState()
    }

    /// Ask Titroutine whether a task is in progress; a `startedAt != nil` row is
    /// the ⏱ running task. Keeps the last value on transient failure.
    private func pollFocus() {
        guard settings.enabled, settings.autoDuringFocus,
              TitroutineClient.shared.isConnected, !polling else { return }
        polling = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.polling = false }
            do {
                let out = try await TitroutineClient.shared.fetchOutstanding()
                let running = out.rows.first { $0.startedAt != nil }
                self.hasInProgressTask = (running != nil)
                self.focusReason = running?.title ?? ""
            } catch {
                // Offline / transient: keep the last known state (matches the app's
                // other pollers), just re-publish it below.
            }
            self.writeState()
        }
    }

    // MARK: - Bridge setup

    /// Reinstall the native-host bridge and reveal the bundled extension folder so
    /// the user can "Load unpacked". Wired to the Settings button.
    func setupBridgeAndRevealExtension() {
        installBridge()
        if let url = Self.bundledExtensionURL() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func bundledExtensionURL() -> URL? {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("browser-extension"),
              FileManager.default.fileExists(atPath: dir.path) else { return nil }
        return dir
    }

    /// Write the host wrapper script + native-messaging manifest into every
    /// installed Chromium-family browser (all at the user level — no root). Safe to
    /// call repeatedly; it just refreshes the files.
    private func installBridge() {
        guard let exe = Bundle.main.executablePath else { return }
        try? FileManager.default.createDirectory(
            atPath: AgentPetPaths.baseDir, withIntermediateDirectories: true)

        // 1. Wrapper: the browser can't pass args to the host, so shim through it.
        let wrapper = "#!/bin/sh\nexec \"\(exe)\" focus-host \"$@\"\n"
        try? wrapper.write(toFile: FocusBlockPaths.hostWrapper, atomically: true, encoding: .utf8)
        chmod(FocusBlockPaths.hostWrapper, 0o755)

        // 2. Manifest, one per browser that exists on disk.
        let manifest: [String: Any] = [
            "name": FocusBlockPaths.hostName,
            "description": "AgentPet focus block bridge",
            "path": FocusBlockPaths.hostWrapper,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(FocusBlockPaths.extensionID)/"],
        ]
        guard let mdata = try? JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted]) else { return }

        let home = NSHomeDirectory() + "/Library/Application Support/"
        let browsers = [
            "Google/Chrome",
            "Google/Chrome Beta",
            "Google/Chrome Canary",
            "Microsoft Edge",
            "BraveSoftware/Brave-Browser",
            "Chromium",
            "Arc/User Data",
        ]
        for rel in browsers {
            let browserDir = home + rel
            guard FileManager.default.fileExists(atPath: browserDir) else { continue }
            let nmDir = browserDir + "/NativeMessagingHosts"
            try? FileManager.default.createDirectory(atPath: nmDir, withIntermediateDirectories: true)
            try? mdata.write(to: URL(fileURLWithPath: nmDir + "/\(FocusBlockPaths.hostName).json"))
        }
    }
}
