// Sources/App/TitroutineReminderController.swift
import AppKit
import AgentPetCore

/// Periodically asks Titroutine for habits/tasks the user hasn't finished and,
/// when any remain, nudges with a notification + a pet chat line. Modeled on
/// `BreakReminderController`: the timer only runs while the feature is enabled
/// and an account is linked, so a disabled/disconnected reminder costs nothing.
@MainActor
final class TitroutineReminderController {
    static let shared = TitroutineReminderController()

    private let settings = TitroutineSettings.shared
    private var timer: Timer?
    /// Guards against overlapping fetches if one poll outlives the tick interval.
    private var checking = false

    func start() {
        settings.onChange = { [weak self] in self?.applyEnabled() }
        applyEnabled()
    }

    /// Start/stop the timer to match enabled + connected. Called on every change.
    private func applyEnabled() {
        timer?.invalidate()
        timer = nil
        guard settings.enabled, TitroutineClient.shared.isConnected else { return }
        let interval = TimeInterval(max(1, settings.reminderIntervalMinutes)) * 60
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard settings.enabled, TitroutineClient.shared.isConnected, !checking else { return }
        checking = true
        Task { @MainActor [weak self] in
            defer { self?.checking = false }
            guard let out = try? await TitroutineClient.shared.fetchOutstanding(), out.total > 0 else { return }
            self?.nudge(out)
        }
    }

    /// Nudge purely through the pet: a spoken chat bubble naming a couple of the
    /// open items. No macOS notification — the reminder is meant to feel like the
    /// pet chatting, not a system alert. A soft purr signals it spoke.
    private func nudge(_ out: TitroutineClient.Outstanding) {
        let n = out.total
        let names = (out.habitTitles + out.taskTitles).prefix(2).joined(separator: ", ")
        let line: String
        if n == 1 {
            line = "Còn “\(names)” chưa xong nè, làm nốt đi nha! 🐰"
        } else {
            let more = n > 2 ? " và \(n - 2) việc nữa" : ""
            line = "Còn \(n) việc chưa xong nè: \(names)\(more) — cố lên nha! 🐰"
        }
        NSSound(named: "Purr")?.play()
        PetController.shared.flashReactiveLine(line)
    }
}
