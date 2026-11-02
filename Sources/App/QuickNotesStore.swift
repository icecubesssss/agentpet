import Foundation
import SwiftUI
import Combine

@MainActor
final class QuickNotesStore: ObservableObject {
    static let shared = QuickNotesStore()

    private static let localKey = "agentpet.quicknotes.content"

    @Published var notesText: String {
        didSet {
            UserDefaults.standard.set(notesText, forKey: Self.localKey)
            scheduleSync()
        }
    }

    @Published var isSyncing: Bool = false
    @Published var lastSyncedAt: Date?

    private var syncTask: Task<Void, Never>?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.localKey)
        if let stored, !stored.isEmpty {
            self.notesText = stored
        } else {
            self.notesText = "- [ ] Chào ngày mới! Ghi chú nhanh tại đây...\n"
        }
    }

    /// Add a new checklist item at the bottom of notes
    func addChecklistItem(text: String = "") {
        let prefix = notesText.hasSuffix("\n") || notesText.isEmpty ? "" : "\n"
        notesText += "\(prefix)- [ ] \(text)"
    }

    /// Convert a line or text into a real Titroutine task
    func convertToTask(title: String) async -> Bool {
        let cleanTitle = title
            .replacingOccurrences(of: "- [ ]", with: "")
            .replacingOccurrences(of: "- [x]", with: "")
            .replacingOccurrences(of: "- [X]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else { return false }

        do {
            _ = try await TitroutineClient.shared.createTask(
                title: cleanTitle,
                notes: "Tạo nhanh từ Quick Notes trong AgentPet",
                priority: "medium",
                assigneeType: "self",
                focusDuration: 25,
                deadline: nil
            )
            return true
        } catch {
            return false
        }
    }

    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s debounce
            guard let self, !Task.isCancelled else { return }
            await self.pushToCloud()
        }
    }

    func pushToCloud() async {
        guard TitroutineClient.shared.isConnected else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await TitroutineClient.shared.saveQuickNotes(notes: notesText)
            lastSyncedAt = Date()
        } catch {
            // Silently fail on network error, local is already preserved
        }
    }
}

