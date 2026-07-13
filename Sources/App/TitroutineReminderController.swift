// Sources/App/TitroutineReminderController.swift
import AppKit
import AgentPetCore

/// Keeps the home pet showing a live list of unfinished Titroutine work. One
/// timer (every `reminderIntervalMinutes`) re-fetches; the result is pushed to the
/// pet as a structured task bubble (`PetController.setTitroutineTasks`) that stays
/// on screen on its own and yields to live coding-agent rows — so it never fights
/// the idle chatter. Modeled on `BreakReminderController`.
@MainActor
final class TitroutineReminderController {
    static let shared = TitroutineReminderController()

    private let settings = TitroutineSettings.shared
    private var timer: Timer?
    private var fetching = false
    private var lastTotal = 0

    func start() {
        settings.onChange = { [weak self] in self?.applyEnabled() }
        applyEnabled()
    }

    /// Start/stop the refresh timer to match enabled + connected. Clears the
    /// bubble when turned off. Called on every settings change.
    private func applyEnabled() {
        timer?.invalidate()
        timer = nil
        guard settings.enabled, TitroutineClient.shared.isConnected else {
            PetController.shared.setTitroutineRows([])
            lastTotal = 0
            return
        }
        refresh()   // fetch immediately, no wait for the first tick
        let interval = TimeInterval(max(1, settings.reminderIntervalMinutes)) * 60
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Re-fetch outstanding work and push it to the pet. Celebrates once when the
    /// last item is cleared.
    private func refresh() {
        guard settings.enabled, TitroutineClient.shared.isConnected, !fetching else { return }
        fetching = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.fetching = false }
            do {
                let out = try await TitroutineClient.shared.fetchOutstanding()
                PetController.shared.setTitroutineRows(out.rows)
                if out.total == 0, self.lastTotal > 0 {
                    PetController.shared.flashReactiveLine("Xong hết việc rồi, giỏi ghê! 🐰✨")
                }
                self.lastTotal = out.total
            } catch {
                // Offline / transient failure — keep the last list until the next
                // refresh (silent, matching the app's other pollers).
            }
        }
    }
}
