import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let taskManager = DownloadTaskManager()
    private(set) lazy var clipboardMonitor = ClipboardMonitor(taskManager: taskManager)
    private var panelController: FloatingPanelController?
    private var mainWindowController: MainWindowController?
    private var visibilityObserver: Any?

    // Menu bar
    private var statusItem: NSStatusItem?
    private var menuPanel: NSPanel?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = FloatingPanelController(taskManager: taskManager)

        if SettingsManager.shared.isIslandVisible {
            panelController?.showIsland()
        }

        clipboardMonitor.start()

        // Main window
        mainWindowController = MainWindowController(historyManager: taskManager.historyManager)
        mainWindowController?.showWindow()

        NotificationCenter.default.addObserver(
            forName: .showMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.mainWindowController?.showWindow()
            }
        }

        // Menu bar status item
        setupStatusItem()

        // Observe visibility toggle via UserDefaults KVO
        visibilityObserver = UserDefaults.standard.observe(
            \.isIslandVisible, options: [.new]
        ) { [weak self] _, change in
            DispatchQueue.main.async {
                if change.newValue == true {
                    self?.panelController?.showIsland()
                } else {
                    self?.panelController?.hideIsland()
                }
            }
        }

        // Handle screen configuration changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panelController?.clampToScreen()
            }
        }
    }

    // MARK: - Dock Icon Click

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController?.showWindow()
        return false
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked)
        }

    }

    @objc private func statusItemClicked() {
        if let panel = menuPanel, panel.isVisible {
            hideMenuPanel()
        } else {
            showMenuPanel()
        }
    }

    private func showMenuPanel() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        // Get button position in screen coordinates
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let panelWidth: CGFloat = 220
        // Left-align panel with icon's left edge
        let x = screenRect.minX
        let y = screenRect.minY - 4 // 4pt gap below menu bar

        let contentView = SettingsView(taskManager: taskManager)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 300)

        // Measure actual content height
        let fittingSize = hostingView.fittingSize
        let panelHeight = fittingSize.height

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y - panelHeight, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Wrap in a rounded visual container
        let wrapper = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        wrapper.material = .popover
        wrapper.state = .active
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 10
        wrapper.layer?.masksToBounds = true

        hostingView.frame = wrapper.bounds
        hostingView.autoresizingMask = [.width, .height]
        wrapper.addSubview(hostingView)

        panel.contentView = wrapper
        panel.orderFrontRegardless()
        self.menuPanel = panel

        // Dismiss when clicking outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.hideMenuPanel()
            }
        }
    }

    private func hideMenuPanel() {
        menuPanel?.orderOut(nil)
        menuPanel = nil
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

}

// KVO-compatible key path for @AppStorage
private extension UserDefaults {
    @objc dynamic var isIslandVisible: Bool {
        bool(forKey: AppConstants.Keys.isIslandVisible)
    }
}
