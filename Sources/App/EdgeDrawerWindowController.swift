import AppKit
import SwiftUI
import Combine

@MainActor
final class EdgeDrawerWindowController: ObservableObject {
    static let shared = EdgeDrawerWindowController()

    @Published private(set) var isOpen: Bool = false

    private var handlePanel: NSPanel?
    private var drawerPanel: NSPanel?

    private var dwellTimer: Task<Void, Never>?
    private var closeTimer: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var keyMonitor: Any?

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

    // MARK: - Handle Panel (The Notch)

    private func makeHandlePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 8, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
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

        let width: CGFloat = 8
        let height: CGFloat = 50

        let x: CGFloat = settings.edgeSide == .right ? visible.maxX - width : visible.minX
        let y: CGFloat = visible.minY + (visible.height * settings.verticalRatio) - (height / 2)

        handlePanel?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    // MARK: - Drawer Panel

    private func makeDrawerPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
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
        let height = min(visible.height * 0.8, 650)
        let y = visible.minY + (visible.height - height) / 2

        let targetX: CGFloat
        if isOpen {
            targetX = settings.edgeSide == .right ? visible.maxX - width - 8 : visible.minX + 8
        } else {
            targetX = settings.edgeSide == .right ? visible.maxX + 20 : visible.minX - width - 20
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
        guard !isOpen else { return }
        isOpen = true

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let settings = EdgeDrawerSettings.shared

        let width: CGFloat = 380
        let height = min(visible.height * 0.8, 650)
        let y = visible.minY + (visible.height - height) / 2
        let endX = settings.edgeSide == .right ? visible.maxX - width - 8 : visible.minX + 8

        drawerPanel?.setFrame(NSRect(x: endX, y: y, width: width, height: height), display: true)
        drawerPanel?.alphaValue = 0.0
        drawerPanel?.orderFront(nil)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                drawerPanel?.animator().alphaValue = 1.0
            }
        } else {
            drawerPanel?.alphaValue = 1.0
        }
    }

    func closeDrawer(animated: Bool = true) {
        guard isOpen else { return }
        isOpen = false

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                drawerPanel?.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    if self?.isOpen == false {
                        self?.drawerPanel?.orderOut(nil)
                    }
                }
            })
        } else {
            drawerPanel?.alphaValue = 0.0
            drawerPanel?.orderOut(nil)
        }
    }

    private func handleHoverEntered() {
        guard EdgeDrawerSettings.shared.triggerMode == .hover else { return }
        closeTimer?.cancel()
        dwellTimer?.cancel()

        // 160ms dwell filter to prevent accidental triggers on rapid mouse moves
        dwellTimer = Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
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
        closeTimer?.cancel()
        closeTimer = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
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
    }
}

// MARK: - Handle Notch View

private struct HandleContentView: View {
    var onHoverStart: () -> Void
    var onHoverEnd: () -> Void
    var onClick: () -> Void
    var onDragStart: (CGFloat) -> Void
    var onDragUpdate: (CGFloat) -> Void

    @State private var isHovered = false

    var body: some View {
        Capsule()
            .fill(isHovered ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.25))
            .frame(width: isHovered ? 8 : 5, height: 48)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { inside in
                isHovered = inside
                if inside {
                    onHoverStart()
                } else {
                    onHoverEnd()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { val in
                        onDragUpdate(val.translation.height)
                    }
            )
            .onTapGesture {
                onClick()
            }
    }
}

// MARK: - Drawer Mouse Tracking Wrapper

private final class DrawerHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: () -> Void
    var onMouseExited: () -> Void
    private var trackingArea: NSTrackingArea?

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
