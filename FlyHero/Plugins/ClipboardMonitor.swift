import AppKit
import Combine

@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published var isMonitoring = false

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let taskManager: DownloadTaskManager

    init(taskManager: DownloadTaskManager) {
        self.taskManager = taskManager
    }

    func start() {
        guard !isMonitoring else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        isMonitoring = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }

    private func checkPasteboard() {
        let current = NSPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to parse as URL
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            return
        }

        // Only handle Feishu URLs
        guard FeishuLinkParser.isFeishuURL(url) else { return }

        if let linkType = FeishuLinkParser.parse(url) {
            taskManager.enqueue(url: url, linkType: linkType)
        }
    }
}
