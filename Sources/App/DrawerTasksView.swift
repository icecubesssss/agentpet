import SwiftUI

struct DrawerTasksView: View {
    @ObservedObject private var settings = EdgeDrawerSettings.shared

    @State private var tasks: [DrawerTaskItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Quick Add
    @State private var newTitle = ""
    @State private var selectedPriority = "medium"
    @State private var focusDuration = 25
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
                HStack(spacing: 8) {
                    Picker("", selection: $selectedPriority) {
                        Text("Vừa").tag("medium")
                        Text("Cao").tag("high")
                        Text("Thấp").tag("low")
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)
                    .frame(width: 140)

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
                    .frame(width: 60)

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

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            // Task list
            if isLoading && tasks.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if tasks.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("Không có task nào. Thêm task phía trên nhé!")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // In Progress
                        let inProgress = tasks.filter { $0.status == "in_progress" }
                        if !inProgress.isEmpty {
                            sectionHeader(title: "ĐANG THỰC HIỆN", count: inProgress.count, color: settings.theme.accentColor)
                            ForEach(inProgress) { task in
                                taskRow(task: task)
                            }
                        }

                        // Todo
                        let todos = tasks.filter { $0.status == "todo" }
                        if !todos.isEmpty {
                            sectionHeader(title: "CẦN LÀM", count: todos.count, color: .primary)
                            ForEach(todos) { task in
                                taskRow(task: task)
                            }
                        }

                        // Done
                        let done = tasks.filter { $0.status == "done" }
                        if !done.isEmpty {
                            sectionHeader(title: "ĐÃ XONG", count: done.count, color: .secondary)
                            ForEach(done) { task in
                                taskRow(task: task)
                            }
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

    private func sectionHeader(title: String, count: Int, color: Color) -> some View {
        HStack {
            Text("\(title) (\(count))")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color.opacity(0.85))
            Spacer()
        }
        .padding(.top, 4)
    }

    private func taskRow(task: DrawerTaskItem) -> some View {
        HStack(spacing: 8) {
            // Checkmark button
            Button(action: {
                toggleTaskDone(task)
            }) {
                Image(systemName: task.status == "done" ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(task.status == "done" ? settings.theme.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12, weight: task.status == "in_progress" ? .semibold : .regular))
                    .strikethrough(task.status == "done")
                    .foregroundStyle(task.status == "done" ? .secondary : .primary)

                HStack(spacing: 6) {
                    if task.priority == "high" {
                        Text("Cao")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    Text("⏱ \(task.focusDuration)m")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if task.status == "in_progress", task.startedAt != nil {
                        Text("• đang chạy")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(settings.theme.accentColor)
                    }
                }
            }

            Spacer()

            // Action buttons
            if task.status == "todo" {
                Button(action: {
                    setStatus(task, to: "in_progress")
                }) {
                    Text("Bắt đầu")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(settings.theme.accentColor.opacity(0.2)))
                        .foregroundStyle(settings.theme.accentColor)
                }
                .buttonStyle(.plain)
            } else if task.status == "in_progress" {
                Button(action: {
                    setStatus(task, to: "todo")
                }) {
                    Text("Tạm dừng")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

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
