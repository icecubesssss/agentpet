import Foundation
import SwiftUI
import Combine
import AppKit

public enum FocusSessionType: String, CaseIterable, Identifiable {
    case pomodoro = "pomodoro"
    case shortBreak = "shortBreak"
    case longBreak = "longBreak"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pomodoro: return "Tập trung"
        case .shortBreak: return "Nghỉ ngắn"
        case .longBreak: return "Nghỉ dài"
        }
    }

    public var defaultMinutes: Int {
        switch self {
        case .pomodoro: return 25
        case .shortBreak: return 5
        case .longBreak: return 15
        }
    }

    public var icon: String {
        switch self {
        case .pomodoro: return "flame.fill"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "bed.double.fill"
        }
    }
}

@MainActor
public final class FocusTimerManager: ObservableObject {
    public static let shared = FocusTimerManager()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var remainingSeconds: Int = 25 * 60
    @Published public private(set) var totalSeconds: Int = 25 * 60
    @Published public private(set) var sessionType: FocusSessionType = .pomodoro
    @Published public private(set) var activeTask: DrawerTaskItem? = nil

    private var timer: Timer?

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }

    public var carrotGrowth: Int {
        return min(100, max(0, Int(progress * 100)))
    }

    public var carrotStageEmoji: String {
        let g = carrotGrowth
        if g <= 25 { return "🌱" }
        if g <= 50 { return "🌿" }
        if g <= 75 { return "🍃" }
        return "🥕"
    }

    public var carrotStageText: String {
        let g = carrotGrowth
        if g <= 25 { return "Vừa gieo hạt..." }
        if g <= 50 { return "Đang mọc mầm..." }
        if g <= 75 { return "Cà rốt lớn dần..." }
        return "Sắp thu hoạch!"
    }

    public var formattedTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private init() {}

    public func start(task: DrawerTaskItem? = nil, minutes: Int? = nil, type: FocusSessionType = .pomodoro) {
        sessionType = type
        let duration = (minutes ?? (task?.focusDuration ?? type.defaultMinutes)) * 60
        totalSeconds = max(60, duration)
        remainingSeconds = totalSeconds
        activeTask = task
        isPaused = false
        isRunning = true

        if let task {
            Task {
                try? await TitroutineClient.shared.updateTaskStatus(taskId: task.id, status: "in_progress")
            }
        }

        startTimer()
    }

    public func resume() {
        guard !isRunning, isPaused else { return }
        isRunning = true
        isPaused = false
        startTimer()
    }

    public func pause() {
        guard isRunning else { return }
        isRunning = false
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    public func reset() {
        isRunning = false
        isPaused = false
        timer?.invalidate()
        timer = nil
        remainingSeconds = totalSeconds
    }

    public func completeEarly() {
        completeSession()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRunning else { return }
        if remainingSeconds > 1 {
            remainingSeconds -= 1
        } else {
            remainingSeconds = 0
            completeSession()
        }
    }

    private func completeSession() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isPaused = false

        NSSound.beep()

        if let task = activeTask {
            Task {
                try? await TitroutineClient.shared.updateTaskStatus(taskId: task.id, status: "done")
            }
            activeTask = nil
        }

        // Celebrate on pet!
        PetController.shared.flashCelebrate(line: "🎉 Hoàn thành tập trung! +1 🥕")
    }
}

