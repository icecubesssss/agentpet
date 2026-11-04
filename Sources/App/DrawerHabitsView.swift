import SwiftUI

enum HabitTimeOfDayFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case morning = "morning"
    case afternoon = "afternoon"
    case evening = "evening"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Tất cả"
        case .morning: return "🌅 Sáng"
        case .afternoon: return "☀️ Chiều"
        case .evening: return "🌙 Tối"
        }
    }
}

struct DrawerHabitsView: View {
    @ObservedObject private var settings = EdgeDrawerSettings.shared
    @ObservedObject private var timer = FocusTimerManager.shared

    @State private var habits: [DrawerHabitItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: HabitTimeOfDayFilter = .all

    // Quick Add Habit form
    @State private var showAddForm = false
    @State private var newTitle = ""
    @State private var newType = "boolean" // boolean, counter, timer
    @State private var newTargetCount = 8
    @State private var newDurationMinutes = 20
    @State private var newTimeOfDay = "anytime"
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 10) {
            // Header stats & Add button
            HStack {
                let completedCount = habits.filter { $0.isCompleted }.count
                Text("HÔM NAY: \(completedCount)/\(habits.count) HOÀN THÀNH")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(settings.theme.accentColor.opacity(0.85))

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showAddForm.toggle()
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: showAddForm ? "xmark.circle" : "plus.circle.fill")
                        Text(showAddForm ? "Đóng" : "Thêm thói quen")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(settings.theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
            .padding(.horizontal, 2)

            // Add Habit Form (Expandable)
            if showAddForm {
                VStack(spacing: 8) {
                    TextField("Tên thói quen mới (VD: Uống nước, Đọc sách)...", text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(settings.theme.cardBackground)
                        )

                    HStack(spacing: 6) {
                        Picker("", selection: $newType) {
                            Text("Thường").tag("boolean")
                            Text("Bộ đếm").tag("counter")
                            Text("Hẹn giờ").tag("timer")
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.mini)
                        .frame(width: 140)

                        if newType == "counter" {
                            HStack(spacing: 2) {
                                Text("Mục tiêu:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $newTargetCount) {
                                    ForEach([3, 5, 8, 10, 15, 20], id: \.self) { c in
                                        Text("\(c)").tag(c)
                                    }
                                }
                                .controlSize(.mini)
                            }
                        } else if newType == "timer" {
                            HStack(spacing: 2) {
                                Text("Thời lượng:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $newDurationMinutes) {
                                    ForEach([10, 15, 20, 25, 30, 45, 60], id: \.self) { m in
                                        Text("\(m)m").tag(m)
                                    }
                                }
                                .controlSize(.mini)
                            }
                        }

                        Spacer()

                        Button(action: submitNewHabit) {
                            if isSubmitting {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 20, height: 20)
                            } else {
                                Text("Tạo")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(settings.theme.accentColor))
                                    .foregroundStyle(Color.black)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(settings.theme.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(settings.theme.accentColor.opacity(0.3), lineWidth: 1)
                )
                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }

            // Time of Day Filter Bar
            HStack(spacing: 4) {
                ForEach(HabitTimeOfDayFilter.allCases) { f in
                    Button(action: {
                        selectedFilter = f
                    }) {
                        Text(f.title)
                            .font(.system(size: 10, weight: selectedFilter == f ? .bold : .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == f ? settings.theme.accentColor.opacity(0.25) : Color.primary.opacity(0.05))
                            )
                            .foregroundStyle(selectedFilter == f ? settings.theme.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: loadHabits) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Tải lại danh sách")
            }
            .padding(.horizontal, 2)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            // Habits list
            let filtered = filteredHabits()
            if isLoading && habits.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if filtered.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "repeat")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Không có thói quen nào trong mục này!")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { habit in
                            habitRow(habit: habit)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            loadHabits()
        }
    }

    private func filteredHabits() -> [DrawerHabitItem] {
        switch selectedFilter {
        case .all: return habits
        case .morning: return habits.filter { $0.timeOfDay == "morning" }
        case .afternoon: return habits.filter { $0.timeOfDay == "afternoon" }
        case .evening: return habits.filter { $0.timeOfDay == "evening" }
        }
    }

    private func habitRow(habit: DrawerHabitItem) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                // Checkmark / Action Button
                if habit.type == "counter" {
                    // Counter control
                    HStack(spacing: 4) {
                        Button(action: {
                            incrementCounter(habit: habit, delta: -1)
                        }) {
                            Image(systemName: "minus.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(habit.currentValue <= 0)

                        Text("\(habit.currentValue)/\(habit.targetCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(habit.isCompleted ? settings.theme.accentColor : .primary)
                            .frame(minWidth: 32)

                        Button(action: {
                            incrementCounter(habit: habit, delta: 1)
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(settings.theme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                } else if habit.type == "timer" {
                    Button(action: {
                        startHabitTimer(habit: habit)
                    }) {
                        Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "play.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(habit.isCompleted ? settings.theme.accentColor : Color.orange)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        toggleHabit(habit)
                    }) {
                        Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(habit.isCompleted ? settings.theme.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Title & Details
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.title)
                        .font(.system(size: 12, weight: habit.isCompleted ? .regular : .medium))
                        .strikethrough(habit.isCompleted && habit.type == "boolean")
                        .foregroundStyle(habit.isCompleted ? .secondary : .primary)

                    HStack(spacing: 6) {
                        if habit.type == "timer" {
                            Text("⏱ \(habit.targetSeconds / 60) phút")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.orange)
                        } else if habit.type == "counter" {
                            Text("🔢 Đếm số lần")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        if let timeOfDay = habit.timeOfDay, timeOfDay != "anytime" {
                            Text(timeOfDayLabel(timeOfDay))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // If timer habit, show Focus Launch button
                if habit.type == "timer" && !habit.isCompleted {
                    Button(action: {
                        startHabitTimer(habit: habit)
                    }) {
                        Text("Bấm giờ")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.2)))
                            .foregroundStyle(Color.orange)
                    }
                    .buttonStyle(.plain)
                }

                // 7-Day Weekly Streak Dots (Mon..Sun)
                if !habit.weeklyLogs.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(0..<min(7, habit.weeklyLogs.count), id: \.self) { i in
                            Circle()
                                .fill(habit.weeklyLogs[i] ? settings.theme.accentColor : Color.primary.opacity(0.12))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(habit.isCompleted ? settings.theme.accentColor.opacity(0.12) : settings.theme.cardBackground)
        )
    }

    private func startHabitTimer(habit: DrawerHabitItem) {
        let mins = max(1, habit.targetSeconds / 60)
        timer.start(task: nil, minutes: mins, type: .pomodoro)
        settings.selectedTab = .timer
    }

    private func timeOfDayLabel(_ tod: String) -> String {
        switch tod {
        case "morning": return "🌅 Sáng"
        case "afternoon": return "☀️ Chiều"
        case "evening": return "🌙 Tối"
        default: return tod
        }
    }

    private func loadHabits() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await TitroutineClient.shared.fetchDrawerHabits()
                self.habits = fetched
                self.isLoading = false
            } catch {
                self.errorMessage = "Lỗi tải thói quen: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func toggleHabit(_ habit: DrawerHabitItem) {
        let willComplete = !habit.isCompleted
        if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[idx].isCompleted = willComplete
        }
        Task {
            do {
                try await TitroutineClient.shared.toggleHabit(habitId: habit.id, willComplete: willComplete)
            } catch {
                if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
                    habits[idx].isCompleted = !willComplete
                }
                self.errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
            }
        }
    }

    private func incrementCounter(habit: DrawerHabitItem, delta: Int) {
        let current = habit.currentValue
        let next = max(0, current + delta)
        let willComplete = next >= habit.targetCount

        if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[idx].currentValue = next
            habits[idx].isCompleted = willComplete
        }

        Task {
            do {
                try await TitroutineClient.shared.incrementCounterHabit(
                    habitId: habit.id,
                    delta: delta,
                    targetCount: habit.targetCount
                )
            } catch {
                self.errorMessage = "Lỗi cập nhật số lần: \(error.localizedDescription)"
            }
        }
    }

    private func submitNewHabit() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        Task {
            do {
                try await TitroutineClient.shared.createHabit(
                    title: trimmed,
                    type: newType,
                    targetCount: newTargetCount,
                    durationMinutes: newDurationMinutes,
                    timeOfDay: newTimeOfDay
                )
                self.newTitle = ""
                self.showAddForm = false
                self.isSubmitting = false
                loadHabits()
            } catch {
                self.errorMessage = "Lỗi tạo thói quen: \(error.localizedDescription)"
                self.isSubmitting = false
            }
        }
    }
}
