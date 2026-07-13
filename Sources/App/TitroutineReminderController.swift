// Sources/App/TitroutineReminderController.swift
import AppKit
import AgentPetCore

/// Keeps the pet continuously nudging about unfinished Titroutine work.
///
/// Two cadences: a slow **data** timer (every `reminderIntervalMinutes`) re-fetches
/// the outstanding habits/tasks — that's the "did I finish yet?" refresh — and a
/// fast **bubble** timer keeps the spoken reminder on screen so it doesn't vanish
/// after a few seconds. While a coding agent is actively working the pet shows the
/// agent status instead (so both features coexist); the reminder returns the
/// moment you're idle. Modeled on `BreakReminderController`.
@MainActor
final class TitroutineReminderController {
    static let shared = TitroutineReminderController()

    private let settings = TitroutineSettings.shared
    private var dataTimer: Timer?
    private var bubbleTimer: Timer?
    private var fetching = false
    /// Last known outstanding work; drives the bubble between data refreshes.
    private var cached: TitroutineClient.Outstanding?

    private static let bubbleInterval: TimeInterval = 5

    func start() {
        settings.onChange = { [weak self] in self?.applyEnabled() }
        applyEnabled()
    }

    /// Start/stop both timers to match enabled + connected. Called on every change
    /// (e.g. the user edits the interval or connects/disconnects).
    private func applyEnabled() {
        dataTimer?.invalidate(); dataTimer = nil
        bubbleTimer?.invalidate(); bubbleTimer = nil
        cached = nil
        guard settings.enabled, TitroutineClient.shared.isConnected else { return }

        refreshData()   // fetch immediately, no wait for the first tick

        let dataInterval = TimeInterval(max(1, settings.reminderIntervalMinutes)) * 60
        let dt = Timer(timeInterval: dataInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refreshData() }
        }
        RunLoop.main.add(dt, forMode: .common)
        dataTimer = dt

        let bt = Timer(timeInterval: Self.bubbleInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.assertBubble() }
        }
        RunLoop.main.add(bt, forMode: .common)
        bubbleTimer = bt
    }

    /// Re-fetch outstanding work. Celebrates once when the last item is cleared.
    private func refreshData() {
        guard settings.enabled, TitroutineClient.shared.isConnected, !fetching else { return }
        fetching = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.fetching = false }
            let prev = self.cached?.total ?? 0
            self.cached = try? await TitroutineClient.shared.fetchOutstanding()
            if let out = self.cached, out.total == 0, prev > 0 {
                PetController.shared.flashReactiveLine("Xong hết việc rồi, giỏi ghê! 🐰✨")
            }
            self.assertBubble()
        }
    }

    /// Keep the reminder line on the pet, unless a coding agent is mid-run.
    private func assertBubble() {
        guard settings.enabled, let out = cached, out.total > 0 else { return }
        let agentBusy = AppDaemon.shared.sessions.contains { $0.state == .working || $0.state == .waiting }
        guard !agentBusy else { return }
        PetController.shared.flashReactiveLine(line(for: out))
    }

    private func line(for out: TitroutineClient.Outstanding) -> String {
        let n = out.total
        let names = (out.habitTitles + out.taskTitles).prefix(2).joined(separator: ", ")
        if n == 1 { return "Còn “\(names)” chưa xong nè, làm nốt đi nha! 🐰" }
        let more = n > 2 ? " và \(n - 2) việc nữa" : ""
        return "Còn \(n) việc chưa xong nè: \(names)\(more) — cố lên nha! 🐰"
    }
}
