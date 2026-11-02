import SwiftUI

struct CozyEdgeDrawerView: View {
    @ObservedObject private var settings = EdgeDrawerSettings.shared
    @State private var stats: DrawerProfileStats?
    @State private var showThemePicker = false

    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 8) {
                // Mascot / Title
                HStack(spacing: 6) {
                    Text(settings.theme.emoji)
                        .font(.system(size: 16))
                    Text("Titroutine")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                // Stats badges
                if let stats {
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Text("🔥")
                            Text("\(stats.streak)")
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(settings.theme.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(settings.theme.accentColor.opacity(0.15)))

                        HStack(spacing: 3) {
                            Text("🪙")
                            Text("\(stats.coins)")
                                .fontWeight(.bold)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.yellow.opacity(0.15)))
                    }
                }

                // Theme selector button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showThemePicker.toggle()
                    }
                }) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(showThemePicker ? settings.theme.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Đổi giao diện Theme")

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
                        .foregroundStyle(settings.isPinned ? settings.theme.accentColor : Color.secondary)
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

            // Theme Picker dropdown strip
            if showThemePicker {
                HStack(spacing: 8) {
                    ForEach(DrawerThemePreset.allCases) { t in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.theme = t
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(t.emoji)
                                    .font(.system(size: 11))
                                Text(t.displayName)
                                    .font(.system(size: 10, weight: settings.theme == t ? .bold : .medium))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(settings.theme == t ? t.accentColor.opacity(0.3) : Color.primary.opacity(0.06))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(settings.theme == t ? t.accentColor : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(settings.theme.cardBackground)
                )
                .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }

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
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(settings.selectedTab == tab ? settings.theme.accentColor.opacity(0.25) : Color.clear)
                        )
                        .foregroundStyle(settings.selectedTab == tab ? settings.theme.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(settings.theme.cardBackground)
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
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(settings.theme.tintColor.opacity(0.85))
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(settings.theme.accentColor.opacity(0.25), lineWidth: 1.2)
        )
        .shadow(color: settings.theme.accentColor.opacity(0.12), radius: 20, x: settings.edgeSide == .right ? -4 : 4, y: 4)
        .shadow(color: .black.opacity(0.35), radius: 14, x: settings.edgeSide == .right ? -4 : 4, y: 4)
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
