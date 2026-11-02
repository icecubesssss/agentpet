import SwiftUI

struct QuickNotesView: View {
    @ObservedObject private var store = QuickNotesStore.shared
    @ObservedObject private var settings = EdgeDrawerSettings.shared
    @FocusState private var isEditorFocused: Bool

    @State private var statusMessage: String?
    @State private var statusTimer: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            // Action bar
            HStack(spacing: 6) {
                Button(action: {
                    store.addChecklistItem()
                    isEditorFocused = true
                }) {
                    Label(NSLocalizedString("+ Checklist", comment: ""), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(settings.theme.accentColor)

                Button(action: {
                    convertFirstUnfinishedLine()
                }) {
                    Label(NSLocalizedString("Dòng → Task", comment: ""), systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(settings.theme.accentColor)
                .help("Chuyển dòng checklist chưa hoàn thành đầu tiên thành Task Titroutine")

                Spacer()

                if store.isSyncing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else if store.lastSyncedAt != nil {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(settings.theme.accentColor.opacity(0.8))
                        .help("Đã đồng bộ lên cloud")
                }

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.notesText, forType: .string)
                    showStatus("Đã copy toàn bộ!")
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Sao chép ghi chú")

                Button(action: {
                    store.notesText = ""
                    showStatus("Đã xóa sạch!")
                    isEditorFocused = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Xóa nội dung")
            }
            .padding(.horizontal, 2)

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.theme.accentColor)
                    .transition(.opacity)
            }

            // Note editor
            ZStack(alignment: .topLeading) {
                if store.notesText.isEmpty {
                    Text("Gõ ghi chú hoặc checklist tại đây...\n- [ ] Việc cần làm 1\n- [ ] Việc cần làm 2")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $store.notesText)
                    .focused($isEditorFocused)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(5)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(settings.theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(settings.theme.accentColor.opacity(0.18), lineWidth: 1)
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isEditorFocused = true
            }
        }
    }

    private func showStatus(_ msg: String) {
        statusMessage = msg
        statusTimer?.cancel()
        statusTimer = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            statusMessage = nil
        }
    }

    private func convertFirstUnfinishedLine() {
        let lines = store.notesText.components(separatedBy: .newlines)
        guard let lineToConvert = lines.first(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespaces)
            return trimmed.starts(with: "- [ ]") || (!trimmed.isEmpty && !trimmed.starts(with: "- [x]") && !trimmed.starts(with: "- [X]"))
        }) else {
            showStatus("Không tìm thấy dòng checklist phù hợp")
            return
        }

        Task {
            let success = await store.convertToTask(title: lineToConvert)
            if success {
                let updatedLines = lines.map { l in
                    if l == lineToConvert {
                        return "- [x] \(lineToConvert.replacingOccurrences(of: "- [ ]", with: "").trimmingCharacters(in: .whitespaces)) (→ đã tạo Task)"
                    }
                    return l
                }
                store.notesText = updatedLines.joined(separator: "\n")
                showStatus("⚡ Đã chuyển thành Task Titroutine!")
            } else {
                showStatus("Lỗi khi tạo Task (kiểm tra kết nối)")
            }
        }
    }
}
