import SwiftUI

enum TaskFilterStatus: String, CaseIterable, Identifiable {
    case all = "all"
    case inProgress = "in_progress"
    case todo = "todo"
    case done = "done"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Tất cả"
        case .inProgress: return "Đang làm"
        case .todo: return "Cần làm"
        case .done: return "Đã xong"
        }
    }
}

struct DrawerTasksView: View {
    @ObservedObject private var settings = EdgeDrawerSettings.shared
    @ObservedObject private var timer = FocusTimerManager.shared

    @State private var tasks: [DrawerTaskItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filterStatus: TaskFilterStatus = .all

    // Quick Add Form
    @State private var newTitle = ""
    @State private var selectedPriority = "medium"
    @State private var focusDuration = 25
    @State private var assigneeType = "self"
    @State private var isAdding = false

    var body: some View {
        VStack(spacing: 10) {
            // Quick Add Box
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    TextField(NSLocalizedString("Thêm task mới (Enter để tạo)...", comment: ""), text: $newTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settings.theme.cardBackground)
                        )
                        .onSubmit {
                            submitTask()
                        }

                    if isAdding {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 24, height: 24)
                    } else {
                        Button(action: submitTask) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(newTitle.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : settings.theme.accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                // Options strip
                HStack(spacing: 6) {
                    Picker("", selection: $selectedPriority) {
                        Text("Vừa").tag("medium")
                        Text("Cao").tag("high")
                        Text("Thấp").tag("low")
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 130)

                    Menu {
                        Button("15 phút") { focusDuration = 15 }
                        Button("25 phút (chuẩn)") { focusDuration = 25 }
                        Button("45 phút") { focusDuration = 45 }
                        Button("60 phút") { focusDuration = 60 }
                    } label: {
                        Text("⏱ \(focusDuration)m")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(settings.theme.accentColor)
                    }
                    .menuStyle(.borderlessButton)

                    Picker("", selection: $assigneeType) {
                        Text("👤 Tôi").tag("self")
                        Text("🐰 Pet").tag("pet")
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 90)

                    Spacer()
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(settings.theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(settings.theme.accentColor.opacity(0.15), lineWidth: 1)
            )

            // Status Filter Tabs
            HStack(spacing: 4) {
                ForEach(TaskFilterStatus.allCases) { filter in
                    let count = countFor(filter)
                    Button(action: {
                        filterStatus = filter
                    }) {
                        Text("\(filter.title) (\(count))")
                            .font(.system(size: 10, weight: filterStatus == filter ? .bold : .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(filterStatus == filter ? settings.theme.accentColor.opacity(0.25) : Color.primary.opacity(0.05))
                            )
                            .foregroundStyle(filterStatus == filter ? settings.theme.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: loadTasks) {
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

            // Task list
            let filtered = filteredTasks()
            if isLoading && tasks.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if filtered.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Không có task nào trong mục này.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { task in
                            taskRow(task: task)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            loadTasks()
        }
    }

    private func countFor(_ filter: TaskFilterStatus) -> Int {
        switch filter {
        case .all: return tasks.count
        case .inProgress: return tasks.filter { $0.status == "in_progress" }.count
        case .todo: return tasks.filter { $0.status == "todo" }.count
        case .done: return tasks.filter { $0.status == "done" }.count
        }
    }

    private func filteredTasks() -> [DrawerTaskItem] {
        switch filterStatus {
        case .all: return tasks
        case .inProgress: return tasks.filter { $0.status == "in_progress" }
        case .todo: return tasks.filter { $0.status == "todo" }
        case .done: return tasks.filter { $0.status == "done" }
        }
    }

    private func taskRow(task: DrawerTaskItem) -> some View {
        let isCurrentFocus = timer.isRunning && timer.activeTask?.id == task.id

        return HStack(spacing: 8) {
            // Checkmark button
            Button(action: {
                toggleTaskDone(task)
            }) {
                Image(systemName: task.status == "done" ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(task.status == "done" ? settings.theme.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 12, weight: task.status == "in_progress" ? .semibold : .regular))
                        .strikethrough(task.status == "done")
                        .foregroundStyle(task.status == "done" ? .secondary : .primary)
                        .lineLimit(2)

                    if task.assigneeType == "pet" {
                        Text("🐰")
                            .font(.system(size: 10))
                    }
                }

                HStack(spacing: 6) {
                    // Priority Pill
                    if task.priority == "high" {
                        Text("Cao")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.12)))
                    } else if task.priority == "low" {
                        Text("Thấp")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.12)))
                    }

                    // Duration
                    Text("⏱ \(task.focusDuration)m")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if isCurrentFocus {
                        HStack(spacing: 3) {
                            Text(timer.carrotStageEmoji)
                            Text(timer.formattedTime)
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(settings.theme.accentColor)
                    } else if task.status == "in_progress" {
                        Text("• đang chạy")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(settings.theme.accentColor)
                    }
                }
            }

            Spacer()

            // Quick Focus button
            if task.status != "done" {
                Button(action: {
                    startFocusOnTask(task)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text(isCurrentFocus ? "Đang tập trung" : "Tập trung")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(settings.theme.accentColor.opacity(isCurrentFocus ? 0.35 : 0.2))
                    )
                    .foregroundStyle(settings.theme.accentColor)
                }
                .buttonStyle(.plain)
                .help("Bắt đầu bộ đếm Pomodoro và trồng Cà rốt cho Task này")
            }

            // Delete
            Button(action: {
                deleteTask(task)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(task.status == "in_progress" ? settings.theme.accentColor.opacity(0.12) : settings.theme.cardBackground)
        )
    }

    private func startFocusOnTask(_ task: DrawerTaskItem) {
        timer.start(task: task, minutes: task.focusDuration, type: .pomodoro)
        settings.selectedTab = .timer
    }

    private func loadTasks() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await TitroutineClient.shared.fetchDrawerTasks()
                self.tasks = fetched
                self.isLoading = false
            } catch {
                self.errorMessage = "Không thể tải tasks: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func submitTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isAdding = true
        Task {
            do {
                let created = try await TitroutineClient.shared.createTask(
                    title: trimmed,
                    priority: selectedPriority,
                    assigneeType: assigneeType,
                    focusDuration: focusDuration
                )
                self.tasks.insert(created, at: 0)
                self.newTitle = ""
                self.isAdding = false
            } catch {
                self.errorMessage = "Lỗi tạo task: \(error.localizedDescription)"
                self.isAdding = false
            }
        }
    }

    private func toggleTaskDone(_ task: DrawerTaskItem) {
        let nextStatus = task.status == "done" ? "todo" : "done"
        setStatus(task, to: nextStatus)
    }

    private func setStatus(_ task: DrawerTaskItem, to nextStatus: String) {
        Task {
            do {
                try await TitroutineClient.shared.updateTaskStatus(taskId: task.id, status: nextStatus)
                if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[idx].status = nextStatus
                    if nextStatus == "in_progress" {
                        tasks[idx].startedAt = Date()
                        for i in tasks.indices where tasks[i].id != task.id && tasks[i].status == "in_progress" {
                            tasks[i].status = "todo"
                            tasks[i].startedAt = nil
                        }
                    }
                }
            } catch {
                self.errorMessage = "Lỗi cập nhật: \(error.localizedDescription)"
            }
        }
    }

    private func deleteTask(_ task: DrawerTaskItem) {
        Task {
            do {
                try await TitroutineClient.shared.deleteTask(taskId: task.id)
                tasks.removeAll(where: { $0.id == task.id })
            } catch {
                self.errorMessage = "Lỗi xóa: \(error.localizedDescription)"
            }
        }
    }
}
