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
    case notes = "notes"
    case tasks = "tasks"
    case habits = "habits"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return NSLocalizedString("Notes", comment: "")
        case .tasks: return NSLocalizedString("Tasks", comment: "")
        case .habits: return NSLocalizedString("Habits", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .notes: return "note.text"
        case .tasks: return "checklist"
        case .habits: return "repeat"
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

    var onChange: (() -> Void)?

    private static let enabledKey = "agentpet.edgedrawer.enabled"
    private static let edgeSideKey = "agentpet.edgedrawer.edgeSide"
    private static let verticalRatioKey = "agentpet.edgedrawer.verticalRatio"
    private static let triggerModeKey = "agentpet.edgedrawer.triggerMode"
    private static let isPinnedKey = "agentpet.edgedrawer.isPinned"
    private static let selectedTabKey = "agentpet.edgedrawer.selectedTab"

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
    }
}

