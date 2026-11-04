import Foundation
import SwiftUI
import Combine

enum DrawerEdgeSide: String, CaseIterable, Identifiable {
    case right = "right"
    case left = "left"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .right: return NSLocalizedString("Right", comment: "")
        case .left: return NSLocalizedString("Left", comment: "")
        }
    }
}

enum DrawerTriggerMode: String, CaseIterable, Identifiable {
    case hover = "hover"
    case click = "click"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hover: return NSLocalizedString("Hover (with 160ms dwell)", comment: "")
        case .click: return NSLocalizedString("Click only", comment: "")
        }
    }
}

enum DrawerTab: String, CaseIterable, Identifiable {
    case timer = "timer"
    case tasks = "tasks"
    case habits = "habits"
    case notes = "notes"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer: return NSLocalizedString("Timer", comment: "")
        case .tasks: return NSLocalizedString("Tasks", comment: "")
        case .habits: return NSLocalizedString("Habits", comment: "")
        case .notes: return NSLocalizedString("Notes", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .timer: return "timer"
        case .tasks: return "checklist"
        case .habits: return "repeat"
        case .notes: return "note.text"
        }
    }
}

enum DrawerThemePreset: String, CaseIterable, Identifiable {
    case midnight = "midnight"   // Cozy Midnight Dark (Deep obsidian + Amber glow)
    case sakura = "sakura"       // Sakura Blossom (Rosy dusk + Peach Pink glow)
    case matcha = "matcha"       // Matcha Morning (Forest green + Mint glow)
    case lavender = "lavender"   // Lavender Dusk (Deep violet + Lilac glow)
    case latte = "latte"         // Warm Latte (Coffee brown + Caramel gold)
    case cyberpunk = "cyberpunk" // Neon Cyber (Deep slate navy + Cyan neon)
    case nord = "nord"           // Nord Frost (Polar night + Glacier blue)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .sakura: return "Sakura"
        case .matcha: return "Matcha"
        case .lavender: return "Lavender"
        case .latte: return "Latte"
        case .cyberpunk: return "Cyber"
        case .nord: return "Nord"
        }
    }

    var emoji: String {
        switch self {
        case .midnight: return "🌙"
        case .sakura: return "🌸"
        case .matcha: return "🍵"
        case .lavender: return "💜"
        case .latte: return "☕"
        case .cyberpunk: return "⚡"
        case .nord: return "❄️"
        }
    }

    var accentColor: Color {
        switch self {
        case .midnight: return Color(red: 1.0, green: 0.62, blue: 0.26)
        case .sakura: return Color(red: 1.0, green: 0.46, blue: 0.60)
        case .matcha: return Color(red: 0.18, green: 0.83, blue: 0.45)
        case .lavender: return Color(red: 0.65, green: 0.37, blue: 0.92)
        case .latte: return Color(red: 1.0, green: 0.65, blue: 0.01)
        case .cyberpunk: return Color(red: 0.0, green: 0.95, blue: 0.85)
        case .nord: return Color(red: 0.53, green: 0.75, blue: 0.85)
        }
    }

    var tintColor: Color {
        switch self {
        case .midnight: return Color(red: 0.08, green: 0.10, blue: 0.15)
        case .sakura: return Color(red: 0.15, green: 0.08, blue: 0.12)
        case .matcha: return Color(red: 0.07, green: 0.14, blue: 0.10)
        case .lavender: return Color(red: 0.12, green: 0.08, blue: 0.18)
        case .latte: return Color(red: 0.14, green: 0.10, blue: 0.06)
        case .cyberpunk: return Color(red: 0.05, green: 0.08, blue: 0.16)
        case .nord: return Color(red: 0.12, green: 0.15, blue: 0.19)
        }
    }

    var cardBackground: Color {
        switch self {
        case .midnight: return Color.black.opacity(0.3)
        case .sakura: return Color(red: 0.25, green: 0.12, blue: 0.18).opacity(0.35)
        case .matcha: return Color(red: 0.10, green: 0.22, blue: 0.15).opacity(0.35)
        case .lavender: return Color(red: 0.20, green: 0.12, blue: 0.28).opacity(0.35)
        case .latte: return Color(red: 0.22, green: 0.15, blue: 0.10).opacity(0.35)
        case .cyberpunk: return Color(red: 0.06, green: 0.12, blue: 0.22).opacity(0.4)
        case .nord: return Color(red: 0.18, green: 0.22, blue: 0.28).opacity(0.35)
        }
    }
}

@MainActor
final class EdgeDrawerSettings: ObservableObject {
    static let shared = EdgeDrawerSettings()

    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); onChange?() }
    }
    @Published var edgeSide: DrawerEdgeSide {
        didSet { UserDefaults.standard.set(edgeSide.rawValue, forKey: Self.edgeSideKey); onChange?() }
    }
    @Published var verticalRatio: CGFloat {
        didSet { UserDefaults.standard.set(Double(verticalRatio), forKey: Self.verticalRatioKey); onChange?() }
    }
    @Published var triggerMode: DrawerTriggerMode {
        didSet { UserDefaults.standard.set(triggerMode.rawValue, forKey: Self.triggerModeKey); onChange?() }
    }
    @Published var isPinned: Bool {
        didSet { UserDefaults.standard.set(isPinned, forKey: Self.isPinnedKey) }
    }
    @Published var selectedTab: DrawerTab {
        didSet { UserDefaults.standard.set(selectedTab.rawValue, forKey: Self.selectedTabKey) }
    }
    @Published var theme: DrawerThemePreset {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    var onChange: (() -> Void)?

    private static let enabledKey = "agentpet.edgedrawer.enabled"
    private static let edgeSideKey = "agentpet.edgedrawer.edgeSide"
    private static let verticalRatioKey = "agentpet.edgedrawer.verticalRatio"
    private static let triggerModeKey = "agentpet.edgedrawer.triggerMode"
    private static let isPinnedKey = "agentpet.edgedrawer.isPinned"
    private static let selectedTabKey = "agentpet.edgedrawer.selectedTab"
    private static let themeKey = "agentpet.edgedrawer.theme"

    private init() {
        let d = UserDefaults.standard
        enabled = (d.object(forKey: Self.enabledKey) as? Bool) ?? true
        if let rawSide = d.string(forKey: Self.edgeSideKey), let side = DrawerEdgeSide(rawValue: rawSide) {
            edgeSide = side
        } else {
            edgeSide = .right
        }
        let ratio = d.double(forKey: Self.verticalRatioKey)
        verticalRatio = ratio > 0.05 ? CGFloat(min(max(ratio, 0.15), 0.85)) : 0.45
        if let rawMode = d.string(forKey: Self.triggerModeKey), let mode = DrawerTriggerMode(rawValue: rawMode) {
            triggerMode = mode
        } else {
            triggerMode = .hover
        }
        isPinned = d.bool(forKey: Self.isPinnedKey)
        if let rawTab = d.string(forKey: Self.selectedTabKey), let tab = DrawerTab(rawValue: rawTab) {
            selectedTab = tab
        } else {
            selectedTab = .notes
        }
        if let rawTheme = d.string(forKey: Self.themeKey), let t = DrawerThemePreset(rawValue: rawTheme) {
            theme = t
        } else {
            theme = .midnight
        }
    }
}
