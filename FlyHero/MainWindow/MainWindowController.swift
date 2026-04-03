import AppKit
import SwiftUI

extension Notification.Name {
    static let showMainWindow = Notification.Name("ShowMainWindow")
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let historyManager: DownloadHistoryManager
    private let settings = SettingsManager.shared
    private let minWindowSize = NSSize(width: 480, height: 600)

    init(historyManager: DownloadHistoryManager) {
        self.historyManager = historyManager
    }

    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = MainWindowView(
            historyManager: historyManager,
            settings: settings
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "飞行侠"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = minWindowSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self

        // Title bar blends with content
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)

        window.contentView = NSHostingView(rootView: contentView)
        window.backgroundColor = .windowBackgroundColor

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        var size = frameSize
        if size.width < 480 { size.width = 480 }
        if size.height < 600 { size.height = 600 }
        return size
    }
}
