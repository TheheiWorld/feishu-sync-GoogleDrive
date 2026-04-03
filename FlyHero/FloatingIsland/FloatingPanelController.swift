import AppKit
import SwiftUI

// MARK: - FloatingPanel (NSPanel subclass)

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Custom Hosting View (hover tracking)

final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = .clear

        var current = superview
        while let sv = current {
            sv.wantsLayer = true
            sv.layer?.isOpaque = false
            sv.layer?.backgroundColor = .clear
            current = sv.superview
        }
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = .clear
        layer?.isOpaque = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

// MARK: - Observable state shared between controller and SwiftUI

final class IslandStateObject: ObservableObject {
    @Published var isMouseHovering: Bool = false
}

// MARK: - FloatingPanelController

@MainActor
final class FloatingPanelController {
    private var panel: FloatingPanel?
    private var hostingView: TrackingHostingView<IslandContentView>?
    private let taskManager: DownloadTaskManager
    private let settings = SettingsManager.shared
    private let stateObject = IslandStateObject()
    private var sizeObserver: Any?

    init(taskManager: DownloadTaskManager) {
        self.taskManager = taskManager

        // Listen for content size changes to resize the panel
        sizeObserver = NotificationCenter.default.addObserver(
            forName: .islandContentSizeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                let expanding = (notification.object as? NSNumber)?.boolValue ?? true
                self?.resizePanelToFit(expanding: expanding)
            }
        }
    }

    deinit {
        if let observer = sizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showIsland() {
        if panel != nil { return }

        // Panel is always openWidth x openHeight — large enough for the capsule in all hover states
        // SwiftUI content aligns itself within this frame
        let width = AppConstants.Island.openWidth
        let height = AppConstants.Island.openHeight

        let origin: CGPoint
        if let saved = settings.islandPosition {
            origin = saved
        } else if let screen = NSScreen.main {
            origin = CGPoint(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.maxY - height - 12
            )
        } else {
            origin = CGPoint(x: 100, y: 100)
        }

        let rect = NSRect(origin: origin, size: NSSize(width: width, height: height))
        let floatingPanel = FloatingPanel(contentRect: rect)

        let contentView = IslandContentView(
            taskManager: taskManager,
            stateObject: stateObject,
            settings: settings
        )
        let hosting = TrackingHostingView(rootView: contentView)
        hosting.frame = floatingPanel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear

        hosting.onMouseEntered = { [weak self] in
            self?.stateObject.isMouseHovering = true
        }
        hosting.onMouseExited = { [weak self] in
            self?.stateObject.isMouseHovering = false
        }

        floatingPanel.contentView = hosting
        self.hostingView = hosting

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove),
            name: NSWindow.didMoveNotification,
            object: floatingPanel
        )

        floatingPanel.orderFrontRegardless()
        self.panel = floatingPanel
    }

    func hideIsland() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    func clampToScreen() {
        guard let panel = panel, let screen = NSScreen.main else { return }
        var frame = panel.frame
        let visible = screen.visibleFrame
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        panel.setFrame(frame, display: true, animate: true)
        settings.saveIslandPosition(frame.origin)
    }

    // MARK: - Resize panel to fit SwiftUI content

    private func resizePanelToFit(expanding: Bool) {
        guard let panel = panel else { return }

        let oldFrame = panel.frame
        let baseWidth = AppConstants.Island.openWidth
        let baseHeight = AppConstants.Island.openHeight

        if expanding {
            // Make panel big enough for task list, anchor at top-right
            let expandedWidth = AppConstants.Island.taskListWidth
            let expandedHeight: CGFloat = 500
            let newFrame = NSRect(
                x: oldFrame.maxX - expandedWidth,
                y: oldFrame.maxY - expandedHeight,
                width: expandedWidth,
                height: expandedHeight
            )
            panel.setFrame(newFrame, display: true, animate: false)
        } else {
            // Shrink back to base size, anchor at top-right
            let newFrame = NSRect(
                x: oldFrame.maxX - baseWidth,
                y: oldFrame.maxY - baseHeight,
                width: baseWidth,
                height: baseHeight
            )
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let panel = panel else { return }
        settings.saveIslandPosition(panel.frame.origin)
    }
}
