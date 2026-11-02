import SwiftUI

struct DrawerHabitsView: View {
    @ObservedObject private var settings = EdgeDrawerSettings.shared

    @State private var habits: [DrawerHabitItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 10) {
            if isLoading && habits.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if habits.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "repeat")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Không có thói quen nào cho hôm nay!")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                let completedCount = habits.filter { $0.isCompleted }.count
                HStack {
                    Text("HÔM NAY: \(completedCount)/\(habits.count) HOÀN THÀNH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(settings.theme.accentColor.opacity(0.85))
                    Spacer()
                }
                .padding(.top, 4)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(habits) { habit in
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

    private func habitRow(habit: DrawerHabitItem) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                toggleHabit(habit)
            }) {
                Image(systemName: habit.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(habit.isCompleted ? settings.theme.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.title)
                    .font(.system(size: 13, weight: habit.isCompleted ? .regular : .medium))
                    .strikethrough(habit.isCompleted)
                    .foregroundStyle(habit.isCompleted ? .secondary : .primary)

                if let timeOfDay = habit.timeOfDay, timeOfDay != "anytime" {
                    Text(timeOfDayLabel(timeOfDay))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(habit.isCompleted ? settings.theme.accentColor.opacity(0.12) : settings.theme.cardBackground)
        )
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
        // Optimistic UI update
        if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
            habits[idx].isCompleted = willComplete
        }
        Task {
            do {
                try await TitroutineClient.shared.toggleHabit(habitId: habit.id, willComplete: willComplete)
            } catch {
                // Revert on error
                if let idx = habits.firstIndex(where: { $0.id == habit.id }) {
                    habits[idx].isCompleted = !willComplete
                }
                self.errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
            }
        }
    }
}
