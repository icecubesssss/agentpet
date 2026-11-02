import AppKit
import SwiftUI
import Combine

/// A custom NSPanel that allows borderless windows to become key windows and
/// receive keyboard focus (essential for TextEditor, TextField, and shortcuts).
final class KeyableDrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class EdgeDrawerWindowController: ObservableObject {
    static let shared = EdgeDrawerWindowController()

    @Published private(set) var isOpen: Bool = false

    private var handlePanel: NSPanel?
    private var drawerPanel: KeyableDrawerPanel?

    private var dwellTimer: Task<Void, Never>?
    private var closeTimer: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    private var isDraggingHandle = false
    private var dragStartY: CGFloat = 0
    private var dragStartRatio: CGFloat = 0

    func start() {
        setupPanels()
        observeSettings()
        setupHotkeys()
    }

    private func setupPanels() {
        guard EdgeDrawerSettings.shared.enabled else {
            closeDrawer(animated: false)
            handlePanel?.orderOut(nil)
            return
        }

        if handlePanel == nil {
            let panel = makeHandlePanel()
            self.handlePanel = panel
        }
        repositionHandle()
        handlePanel?.orderFront(nil)

        if drawerPanel == nil {
            let panel = makeDrawerPanel()
            self.drawerPanel = panel
            repositionDrawer()
        }
    }

    private func observeSettings() {
        EdgeDrawerSettings.shared.$enabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if enabled {
                    self?.setupPanels()
                } else {
                    self?.closeDrawer(animated: false)
                    self?.handlePanel?.orderOut(nil)
                }
            }
            .store(in: &cancellables)

        EdgeDrawerSettings.shared.$edgeSide
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionHandle()
                self?.repositionDrawer()
            }
            .store(in: &cancellables)

        EdgeDrawerSettings.shared.$verticalRatio
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionHandle()
            }
            .store(in: &cancellables)
    }

    // MARK: - Handle Panel (The Notch Tab)

    private func makeHandlePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 18, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let handleView = HandleContentView(
            onHoverStart: { [weak self] in self?.handleHoverEntered() },
            onHoverEnd: { [weak self] in self?.handleHoverExited() },
            onClick: { [weak self] in self?.toggleDrawer() },
            onDragStart: { [weak self] y in self?.startHandleDrag(y) },
            onDragUpdate: { [weak self] deltaY in self?.updateHandleDrag(deltaY) }
        )
        panel.contentView = NSHostingView(rootView: handleView)
        return panel
    }

    private func repositionHandle() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let settings = EdgeDrawerSettings.shared

        let width: CGFloat = 18
        let height: CGFloat = 76

        let x: CGFloat = settings.edgeSide == .right ? visible.maxX - width : visible.minX
        let y: CGFloat = visible.minY + (visible.height * settings.verticalRatio) - (height / 2)

        handlePanel?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: - Drawer Panel

    private func makeDrawerPanel() -> KeyableDrawerPanel {
        let panel = KeyableDrawerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let drawerView = CozyEdgeDrawerView(onClose: { [weak self] in
            self?.closeDrawer(animated: true)
        })

        let hosting = DrawerHostingView(
            rootView: drawerView,
            onMouseEntered: { [weak self] in self?.drawerMouseEntered() },
            onMouseExited: { [weak self] in self?.drawerMouseExited() }
        )
        panel.contentView = hosting
        return panel
    }

    private func repositionDrawer() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let settings = EdgeDrawerSettings.shared

        let width: CGFloat = 380
        let height = min(visible.height * 0.85, 680)
        let y = visible.minY + (visible.height - height) / 2

        let targetX: CGFloat
        if isOpen {
            targetX = settings.edgeSide == .right ? visible.maxX - width : visible.minX
        } else {
            targetX = settings.edgeSide == .right ? visible.maxX : visible.minX - width
        }

        drawerPanel?.setFrame(NSRect(x: targetX, y: y, width: width, height: height), display: true)
    }

    // MARK: - Interactions

    func toggleDrawer() {
        if isOpen {
            closeDrawer(animated: true)
        } else {
            openDrawer(animated: true)
        }
    }

    func openDrawer(animated: Bool = true, tab: DrawerTab? = nil) {
        if let tab {
            EdgeDrawerSettings.shared.selectedTab = tab
        }
        closeTimer?.cancel()
        dwellTimer?.cancel()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let settings = EdgeDrawerSettings.shared

        let width: CGFloat = 380
        let height = min(visible.height * 0.85, 680)
        let y = visible.minY + (visible.height - height) / 2
        let openX = settings.edgeSide == .right ? visible.maxX - width : visible.minX
        let offscreenX = settings.edgeSide == .right ? visible.maxX : visible.minX - width

        guard let panel = drawerPanel else { return }
        isOpen = true

        // Ensure app activation for keyboard focus (TextEditor, TextField, shortcuts)
        NSApp.activate(ignoringOtherApps: true)

        if animated {
            if !panel.isVisible || panel.frame.origin.x == offscreenX {
                panel.setFrame(NSRect(x: offscreenX, y: y, width: width, height: height), display: false)
            }
            panel.alphaValue = 1.0
            panel.makeKeyAndOrderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(NSRect(x: openX, y: y, width: width, height: height), display: true)
            } completionHandler: {
                MainActor.assumeIsolated {
                    panel.makeKey()
                }
            }
        } else {
            panel.setFrame(NSRect(x: openX, y: y, width: width, height: height), display: true)
            panel.alphaValue = 1.0
            panel.makeKeyAndOrderFront(nil)
            panel.makeKey()
        }
    }

    func closeDrawer(animated: Bool = true) {
        guard isOpen else { return }
        closeTimer?.cancel()
        dwellTimer?.cancel()
        isOpen = false

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let settings = EdgeDrawerSettings.shared

        let width: CGFloat = 380
        let height = drawerPanel?.frame.height ?? min(visible.height * 0.85, 680)
        let y = drawerPanel?.frame.minY ?? (visible.minY + (visible.height - height) / 2)
        let offscreenX = settings.edgeSide == .right ? visible.maxX : visible.minX - width

        guard let panel = drawerPanel else { return }

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().setFrame(NSRect(x: offscreenX, y: y, width: width, height: height), display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    if self?.isOpen == false {
                        panel.orderOut(nil)
                    }
                }
            })
        } else {
            panel.setFrame(NSRect(x: offscreenX, y: y, width: width, height: height), display: true)
            panel.orderOut(nil)
        }
    }

    private func handleHoverEntered() {
        guard EdgeDrawerSettings.shared.triggerMode == .hover else { return }
        closeTimer?.cancel()
        dwellTimer?.cancel()

        dwellTimer = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            self.openDrawer(animated: true)
        }
    }

    private func handleHoverExited() {
        dwellTimer?.cancel()
    }

    private func drawerMouseEntered() {
        closeTimer?.cancel()
    }

    private func drawerMouseExited() {
        guard !EdgeDrawerSettings.shared.isPinned else { return }
        guard isOpen else { return }
        closeTimer?.cancel()
        closeTimer = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            // Verify cursor is indeed outside before closing
            let mouseLoc = NSEvent.mouseLocation
            if let frame = self.drawerPanel?.frame, frame.contains(mouseLoc) {
                return
            }
            if let hFrame = self.handlePanel?.frame, hFrame.contains(mouseLoc) {
                return
            }
            self.closeDrawer(animated: true)
        }
    }

    // MARK: - Vertical Dragging of the Notch

    private func startHandleDrag(_ screenY: CGFloat) {
        isDraggingHandle = true
        dragStartY = screenY
        dragStartRatio = EdgeDrawerSettings.shared.verticalRatio
    }

    private func updateHandleDrag(_ deltaY: CGFloat) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let totalHeight = screen.visibleFrame.height
        guard totalHeight > 0 else { return }

        let ratioDelta = deltaY / totalHeight
        let newRatio = min(max(dragStartRatio + ratioDelta, 0.15), 0.85)
        EdgeDrawerSettings.shared.verticalRatio = newRatio
    }

    // MARK: - Global Hotkeys

    private func setupHotkeys() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc closes drawer if open
            if event.keyCode == 53 && self?.isOpen == true {
                self?.closeDrawer(animated: true)
                return nil
            }
            // Option + T (keyCode 17) -> toggle drawer
            if event.modifierFlags.contains(.option) && event.keyCode == 17 {
                self?.toggleDrawer()
                return nil
            }
            // Option + N (keyCode 45) -> open drawer directly to Notes
            if event.modifierFlags.contains(.option) && event.keyCode == 45 {
                self?.openDrawer(animated: true, tab: .notes)
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Option + T (keyCode 17)
            if event.modifierFlags.contains(.option) && event.keyCode == 17 {
                MainActor.assumeIsolated {
                    self?.toggleDrawer()
                }
            }
            // Option + N (keyCode 45)
            if event.modifierFlags.contains(.option) && event.keyCode == 45 {
                MainActor.assumeIsolated {
                    self?.openDrawer(animated: true, tab: .notes)
                }
            }
        }
    }
}

// MARK: - Handle Notch View (MFinder-style edge tab)

private struct HandleContentView: View {
    var onHoverStart: () -> Void
    var onHoverEnd: () -> Void
    var onClick: () -> Void
    var onDragStart: (CGFloat) -> Void
    var onDragUpdate: (CGFloat) -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @ObservedObject private var settings = EdgeDrawerSettings.shared

    var body: some View {
        let isRight = settings.edgeSide == .right

        ZStack {
            // Background Tab
            RoundedRectangle(cornerRadius: 10)
                .fill(settings.theme.tintColor.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(settings.theme.accentColor.opacity(isHovered ? 0.35 : 0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(settings.theme.accentColor.opacity(isHovered ? 0.85 : 0.4), lineWidth: 1.2)
                )
                .shadow(color: settings.theme.accentColor.opacity(isHovered ? 0.45 : 0.2), radius: 6, x: isRight ? -2 : 2, y: 0)

            // Visual Grabber indicator
            VStack(spacing: 3) {
                Image(systemName: isRight ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(settings.theme.accentColor)

                Capsule()
                    .fill(settings.theme.accentColor.opacity(isHovered ? 0.9 : 0.5))
                    .frame(width: 3, height: 16)
            }
        }
        .frame(width: isHovered ? 18 : 14, height: 72)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { inside in
            isHovered = inside
            if inside {
                onHoverStart()
            } else {
                onHoverEnd()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    if abs(val.translation.height) > 4 {
                        if !isDragging {
                            isDragging = true
                            onDragStart(val.startLocation.y)
                        }
                        onDragUpdate(val.translation.height)
                    }
                }
                .onEnded { val in
                    if !isDragging && abs(val.translation.height) < 5 && abs(val.translation.width) < 5 {
                        onClick()
                    }
                    isDragging = false
                }
        )
    }
}

// MARK: - Drawer Mouse Tracking Wrapper

private final class DrawerHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: () -> Void
    var onMouseExited: () -> Void
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    init(rootView: Content, onMouseEntered: @escaping () -> Void, onMouseExited: @escaping () -> Void) {
        self.onMouseEntered = onMouseEntered
        self.onMouseExited = onMouseExited
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required public init(rootView: Content) {
        self.onMouseEntered = {}
        self.onMouseExited = {}
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited()
    }
}
