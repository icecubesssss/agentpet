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
    @State private var expandedMonthHabitId: String? = nil

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
                    .padding(.leading, 2)
                }

                // Continuous Habit Streak Badge (from last broken day)
                if habit.streak > 0 {
                    HStack(spacing: 1) {
                        Text("🔥")
                            .font(.system(size: 8))
                        Text("\(habit.streak)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.orange)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                    .help("Chuỗi hiện tại: \(habit.streak) ngày liên tục")
                }

                // Month Calendar Expansion Toggle
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        if expandedMonthHabitId == habit.id {
                            expandedMonthHabitId = nil
                        } else {
                            expandedMonthHabitId = habit.id
                        }
                    }
                }) {
                    Image(systemName: expandedMonthHabitId == habit.id ? "calendar.badge.minus" : "calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(expandedMonthHabitId == habit.id ? settings.theme.accentColor : Color.secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(expandedMonthHabitId == habit.id ? settings.theme.accentColor.opacity(0.2) : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(expandedMonthHabitId == habit.id ? "Thu gọn lịch tháng" : "Xem chuỗi theo tháng & check-in bù")
            }

            if expandedMonthHabitId == habit.id {
                Divider()
                    .padding(.vertical, 2)

                HabitMonthGridView(
                    habit: habit,
                    onToggleToday: { willComplete in
                        if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
                            habits[idx].isCompleted = willComplete
                        }
                    },
                    onRefresh: {
                        loadHabits()
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
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

// MARK: - Habit Monthly Calendar & Backfill Grid View

struct HabitMonthGridView: View {
    let habit: DrawerHabitItem
    let onToggleToday: (Bool) -> Void
    var onRefresh: (() -> Void)? = nil
    @ObservedObject private var settings = EdgeDrawerSettings.shared

    @State private var viewDate: Date = Date()
    @State private var completedDates: Set<String> = []
    @State private var isLoading = false

    private let calendar = Calendar.current
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var todayString: String {
        dayFormatter.string(from: Date())
    }

    private var currentMonthKey: String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM"
        return f.string(from: viewDate)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        f.dateFormat = "MM/yyyy"
        return f.string(from: viewDate)
    }

    private var isCurrentOrFutureMonth: Bool {
        let nowComps = calendar.dateComponents([.year, .month], from: Date())
        let viewComps = calendar.dateComponents([.year, .month], from: viewDate)
        if let vy = viewComps.year, let ny = nowComps.year,
           let vm = viewComps.month, let nm = nowComps.month {
            return (vy > ny) || (vy == ny && vm >= nm)
        }
        return false
    }

    private struct DayItem: Identifiable {
        var id: String { dateString }
        let dayNumber: Int
        let dateString: String
        let isToday: Bool
        let isPast: Bool
        let isFuture: Bool
    }

    private func leadingOffset() -> Int {
        var comps = calendar.dateComponents([.year, .month], from: viewDate)
        comps.day = 1
        guard let start = calendar.date(from: comps) else { return 0 }
        let weekday = calendar.component(.weekday, from: start)
        return (weekday + 5) % 7
    }

    private func computeMonthDays() -> [DayItem] {
        var comps = calendar.dateComponents([.year, .month], from: viewDate)
        comps.day = 1
        guard let startOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth)
        else { return [] }

        let today = todayString
        return range.compactMap { d -> DayItem? in
            guard let date = calendar.date(byAdding: .day, value: d - 1, to: startOfMonth) else { return nil }
            let dateStr = dayFormatter.string(from: date)
            return DayItem(
                dayNumber: d,
                dateString: dateStr,
                isToday: dateStr == today,
                isPast: dateStr < today,
                isFuture: dateStr > today
            )
        }
    }

    private struct MonthSummary {
        let completed: Int
        let elapsed: Int
        let rate: Int
        let streak: Int
    }

    private func computeSummary(days: [DayItem]) -> MonthSummary {
        let today = todayString
        let completedCount = days.filter { completedDates.contains($0.dateString) }.count
        let elapsedCount = days.filter { $0.dateString <= today }.count
        let rate = elapsedCount > 0 ? (completedCount * 100 / elapsedCount) : 0

        var maxStreak = 0
        var current = 0
        for d in days {
            if completedDates.contains(d.dateString) {
                current += 1
                maxStreak = max(maxStreak, current)
            } else if d.dateString <= today {
                current = 0
            }
        }

        return MonthSummary(completed: completedCount, elapsed: elapsedCount, rate: rate, streak: maxStreak)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Month navigation header
            HStack {
                Button(action: { changeMonth(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Tháng \(monthTitle)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(settings.theme.accentColor)

                Spacer()

                Button(action: { changeMonth(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isCurrentOrFutureMonth ? Color.secondary.opacity(0.2) : Color.secondary)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .disabled(isCurrentOrFutureMonth)
            }
            .padding(.horizontal, 4)

            // Day of week headers: T2 .. CN
            HStack(spacing: 0) {
                ForEach(["T2", "T3", "T4", "T5", "T6", "T7", "CN"], id: \.self) { w in
                    Text(w)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }

            // Month Grid
            let days = computeMonthDays()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

            LazyVGrid(columns: columns, spacing: 4) {
                // Leading blank placeholders
                ForEach(0..<leadingOffset(), id: \.self) { _ in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }

                // Days
                ForEach(days) { item in
                    dayCell(item: item)
                }
            }

            // Summary stats & retroactive hint
            let summary = computeSummary(days: days)
            VStack(spacing: 3) {
                HStack {
                    Text("Đạt \(summary.completed)/\(summary.elapsed) ngày (\(summary.rate)%)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    if habit.streak > 0 {
                        Text("🔥 Chuỗi hiện tại: \(habit.streak) ngày")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.orange)
                            .help("Tính liên tục từ ngày mất chuỗi gần nhất hoặc ngày bắt đầu đến nay")
                    } else if summary.streak > 0 {
                        Text("Chuỗi trong tháng: \(summary.streak) ngày")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
                Text("💡 Chạm vào ngày quá khứ để check-in bù nếu hôm đó quên tích nhé!")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 2)
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
        .onAppear {
            loadMonthData()
        }
    }

    @ViewBuilder
    private func dayCell(item: DayItem) -> some View {
        let isCompleted = completedDates.contains(item.dateString)
        let isInteractive = !item.isFuture

        Button(action: {
            guard isInteractive else { return }
            toggleDay(dateString: item.dateString)
        }) {
            ZStack {
                if isCompleted {
                    Circle()
                        .fill(settings.theme.accentColor)
                } else if item.isToday {
                    Circle()
                        .stroke(settings.theme.accentColor, lineWidth: 1.5)
                        .background(Circle().fill(settings.theme.accentColor.opacity(0.1)))
                } else if item.isPast {
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                } else {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2]))
                }

                Text("\(item.dayNumber)")
                    .font(.system(size: 9, weight: isCompleted || item.isToday ? .heavy : .medium))
                    .foregroundStyle(isCompleted ? Color.black : (item.isFuture ? Color.secondary.opacity(0.3) : Color.primary.opacity(0.85)))
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .help(isInteractive ? "\(item.dateString): \(isCompleted ? "Đã xong (Bấm để hủy)" : "Chưa tích (Bấm để check-in bù)")" : item.dateString)
    }

    private func toggleDay(dateString: String) {
        let wasCompleted = completedDates.contains(dateString)
        let willComplete = !wasCompleted

        // Optimistic update
        if willComplete {
            completedDates.insert(dateString)
        } else {
            completedDates.remove(dateString)
        }

        if dateString == todayString {
            onToggleToday(willComplete)
        }

        Task {
            do {
                try await TitroutineClient.shared.toggleHabit(habitId: habit.id, date: dateString, willComplete: willComplete)
                await MainActor.run {
                    onRefresh?()
                }
            } catch {
                // Revert on error
                await MainActor.run {
                    if wasCompleted {
                        completedDates.insert(dateString)
                    } else {
                        completedDates.remove(dateString)
                    }
                    if dateString == todayString {
                        onToggleToday(wasCompleted)
                    }
                }
            }
        }
    }

    private func loadMonthData() {
        isLoading = true
        let key = currentMonthKey
        Task {
            do {
                var dates = try await TitroutineClient.shared.fetchHabitMonthLogs(habitId: habit.id, monthKey: key)
                if key == String(todayString.prefix(7)) && habit.isCompleted {
                    dates.insert(todayString)
                }
                await MainActor.run {
                    self.completedDates = dates
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func changeMonth(by delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: viewDate) {
            viewDate = next
            loadMonthData()
        }
    }
}
