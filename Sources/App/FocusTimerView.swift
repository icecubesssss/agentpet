import SwiftUI

struct FocusTimerView: View {
    @ObservedObject private var timer = FocusTimerManager.shared
    @ObservedObject private var settings = EdgeDrawerSettings.shared

    @State private var availableTasks: [DrawerTaskItem] = []
    @State private var showTaskPicker = false

    var body: some View {
        VStack(spacing: 12) {
            // Mode selector (Pomodoro / Short Break / Long Break)
            HStack(spacing: 6) {
                ForEach(FocusSessionType.allCases) { type in
                    Button(action: {
                        if !timer.isRunning {
                            timer.start(task: timer.activeTask, minutes: type.defaultMinutes, type: type)
                            timer.pause() // select without auto-starting
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.system(size: 11))
                            Text(type.title)
                                .font(.system(size: 11, weight: timer.sessionType == type ? .bold : .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(timer.sessionType == type ? settings.theme.accentColor.opacity(0.25) : settings.theme.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(timer.sessionType == type ? settings.theme.accentColor : Color.clear, lineWidth: 1)
                        )
                        .foregroundStyle(timer.sessionType == type ? settings.theme.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Carrot Planting Card 🥕
            HStack(spacing: 12) {
                // Growth emoji avatar box
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(settings.theme.accentColor.opacity(0.18))
                        .frame(width: 54, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(settings.theme.accentColor.opacity(0.3), lineWidth: 1)
                        )

                    Text(timer.carrotStageEmoji)
                        .font(.system(size: 28))
                        .scaleEffect(timer.isRunning ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: timer.isRunning)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("TRỒNG CÀ RỐT 🥕")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(settings.theme.accentColor)

                        Spacer()

                        Text("\(timer.carrotGrowth)%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(settings.theme.accentColor)
                    }

                    Text(timer.carrotStageText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    // Mini Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 5)

                            Capsule()
                                .fill(settings.theme.accentColor)
                                .frame(width: max(4, geo.size.width * CGFloat(timer.progress)), height: 5)
                        }
                    }
                    .frame(height: 5)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(settings.theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(settings.theme.accentColor.opacity(0.15), lineWidth: 1)
            )

            // Active Task Association Box
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12))
                    .foregroundStyle(settings.theme.accentColor)

                if let task = timer.activeTask {
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button(action: {
                        timer.start(task: nil, minutes: timer.totalSeconds / 60, type: timer.sessionType)
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Hủy liên kết task")
                } else {
                    Menu {
                        if availableTasks.isEmpty {
                            Text("Không có task khả dụng")
                        } else {
                            ForEach(availableTasks) { task in
                                Button(task.title) {
                                    timer.start(task: task, minutes: task.focusDuration, type: .pomodoro)
                                }
                            }
                        }
                    } label: {
                        Text("Chọn Task để tập trung...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)

                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.theme.cardBackground)
            )

            Spacer(minLength: 4)

            // Giant Countdown Display
            VStack(spacing: 8) {
                Text(timer.formattedTime)
                    .font(.system(size: 54, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(settings.theme.accentColor)
                    .shadow(color: settings.theme.accentColor.opacity(timer.isRunning ? 0.35 : 0.0), radius: 10, x: 0, y: 0)

                // Quick duration presets (when paused or idle)
                if !timer.isRunning {
                    HStack(spacing: 6) {
                        ForEach([15, 25, 45, 60], id: \.self) { mins in
                            Button(action: {
                                timer.start(task: timer.activeTask, minutes: mins, type: .pomodoro)
                                timer.pause()
                            }) {
                                Text("\(mins)m")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(timer.totalSeconds == mins * 60 ? settings.theme.accentColor.opacity(0.25) : Color.primary.opacity(0.06))
                                    )
                                    .foregroundStyle(timer.totalSeconds == mins * 60 ? settings.theme.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            // Main Controls
            HStack(spacing: 12) {
                if !timer.isRunning && !timer.isPaused {
                    Button(action: {
                        timer.start(task: timer.activeTask, minutes: timer.totalSeconds / 60, type: timer.sessionType)
                    }) {
                        Label("Bắt đầu tập trung", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(settings.theme.accentColor)
                            )
                            .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.plain)
                } else if timer.isRunning {
                    Button(action: {
                        timer.pause()
                    }) {
                        Label("Tạm dừng", systemImage: "pause.fill")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.18))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        timer.completeEarly()
                    }) {
                        Label("Thu hoạch (+1 🥕)", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(settings.theme.accentColor)
                            )
                            .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.plain)
                } else if timer.isPaused {
                    Button(action: {
                        timer.resume()
                    }) {
                        Label("Tiếp tục", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(settings.theme.accentColor)
                            )
                            .foregroundStyle(Color.black)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        timer.reset()
                    }) {
                        Label("Đặt lại", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.18))
                            )
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 2)
        .onAppear {
            loadAvailableTasks()
        }
    }

    private func loadAvailableTasks() {
        Task {
            if let tasks = try? await TitroutineClient.shared.fetchDrawerTasks() {
                self.availableTasks = tasks.filter { $0.status != "done" }
            }
        }
    }
}

