import SwiftUI

struct CozyEdgeDrawerView: View {
    @ObservedObject private var settings = EdgeDrawerSettings.shared
    @State private var stats: DrawerProfileStats?
    @State private var isRefreshing = false

    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 8) {
                // Mascot / Title
                HStack(spacing: 5) {
                    Text("🐰")
                        .font(.system(size: 16))
                    Text("Titroutine")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                // Stats badges
                if let stats {
                    HStack(spacing: 6) {
                        Text("🔥 \(stats.streak)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))

                        Text("🪙 \(stats.coins)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.yellow.opacity(0.12)))
                    }
                }

                // Web App link
                Button(action: openWebApp) {
                    Image(systemName: "safari")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Mở Titroutine Web")

                // Pin toggle
                Button(action: {
                    settings.isPinned.toggle()
                }) {
                    Image(systemName: settings.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12))
                        .foregroundStyle(settings.isPinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(settings.isPinned ? "Bỏ ghim (tự ẩn khi rê chuột ra ngoài)" : "Ghim cửa sổ trên màn hình")

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Đóng (Esc)")
            }
            .padding(.top, 2)

            // Segmented Tab Picker
            HStack(spacing: 4) {
                ForEach(DrawerTab.allCases) { tab in
                    Button(action: {
                        settings.selectedTab = tab
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11))
                            Text(tab.title)
                                .font(.system(size: 11, weight: settings.selectedTab == tab ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(settings.selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                        .foregroundStyle(settings.selectedTab == tab ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.04))
            )

            // Content Area
            Group {
                switch settings.selectedTab {
                case .notes:
                    QuickNotesView()
                case .tasks:
                    DrawerTasksView()
                case .habits:
                    DrawerHabitsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(14)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, x: settings.edgeSide == .right ? -4 : 4, y: 4)
        .onAppear {
            refreshStats()
        }
    }

    private func refreshStats() {
        Task {
            if let stats = try? await TitroutineClient.shared.fetchProfileStats() {
                self.stats = stats
            }
        }
    }

    private func openWebApp() {
        if let base = TitroutineSettings.shared.baseURL {
            NSWorkspace.shared.open(base)
        }
    }
}
