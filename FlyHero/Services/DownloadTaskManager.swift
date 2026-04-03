import Foundation
import Combine

// MARK: - Download Task Status

enum DownloadTaskStatus: Equatable {
    case pendingConfirmation
    case waiting
    case downloading
    case success
    case failed(String)
}

// MARK: - Download Task Model

struct DownloadTask: Identifiable {
    let id: UUID
    let url: URL
    let linkType: FeishuLinkType
    var displayName: String
    var status: DownloadTaskStatus
    let createdAt: Date
    var completedAt: Date?
}

// MARK: - Download Task Manager

@MainActor
final class DownloadTaskManager: ObservableObject {
    @Published var tasks: [DownloadTask] = []
    let historyManager = DownloadHistoryManager()

    private let maxTasks = 50
    private var isProcessing = false

    // MARK: - Computed Properties

    var activeTasks: [DownloadTask] {
        tasks.filter { $0.status == .pendingConfirmation || $0.status == .waiting || $0.status == .downloading }
    }

    var completedCount: Int {
        tasks.filter { $0.status == .success }.count
    }

    var failedCount: Int {
        tasks.filter {
            if case .failed = $0.status { return true }
            return false
        }.count
    }

    var currentTask: DownloadTask? {
        tasks.first { $0.status == .downloading }
    }

    var hasActiveTasks: Bool {
        tasks.contains { $0.status == .waiting || $0.status == .downloading }
    }

    var hasPendingConfirmation: Bool {
        tasks.contains { $0.status == .pendingConfirmation }
    }

    // MARK: - Queue Operations

    func enqueue(url: URL, linkType: FeishuLinkType) {
        // Dedup: skip if same URL already pending, waiting or downloading
        let isDuplicate = tasks.contains { task in
            task.url == url && (task.status == .pendingConfirmation || task.status == .waiting || task.status == .downloading)
        }
        guard !isDuplicate else {
            print("[DownloadTaskManager] Skipping duplicate URL: \(url.absoluteString)")
            return
        }

        // Generate display name from URL
        let displayName = linkType.displayTypeName + ": " + (url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent)

        let task = DownloadTask(
            id: UUID(),
            url: url,
            linkType: linkType,
            displayName: displayName,
            status: .pendingConfirmation,
            createdAt: Date(),
            completedAt: nil
        )
        tasks.insert(task, at: 0)
        pruneOldTasks()
        NotificationCenter.default.post(name: .showTaskList, object: nil)
    }

    func confirmTask(_ task: DownloadTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].status = .waiting
        processQueue()
    }

    func cancelTask(_ task: DownloadTask) {
        tasks.removeAll { $0.id == task.id }
    }

    func retryTask(_ task: DownloadTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].status = .waiting
        tasks[index].completedAt = nil
        processQueue()
    }

    func clearCompleted() {
        tasks.removeAll { task in
            task.status == .success || {
                if case .failed = task.status { return true }
                return false
            }()
        }
    }

    // MARK: - Private

    private func processQueue() {
        // Only one download at a time
        guard !isProcessing else { return }
        guard let index = tasks.firstIndex(where: { $0.status == .waiting }) else { return }

        isProcessing = true
        tasks[index].status = .downloading

        let task = tasks[index]

        Task { @MainActor in
            do {
                let output = try await ClaudeCodeRunner.shared.executeDownload(
                    link: task.url,
                    linkType: task.linkType,
                    targetDirectory: SettingsManager.shared.targetDirectoryURL ?? FileManager.default.homeDirectoryForCurrentUser
                )
                if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[idx].status = .success
                    self.tasks[idx].completedAt = Date()
                    // Extract file path from Claude output, clean markdown artifacts
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    var filePath = ""
                    if !trimmed.isEmpty, let lastLine = trimmed.components(separatedBy: "\n").last {
                        // Remove markdown backticks, quotes, and whitespace
                        let cleaned = lastLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "`", with: "")
                            .replacingOccurrences(of: "\"", with: "")
                            .replacingOccurrences(of: "'", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        filePath = cleaned
                        let filename = (cleaned as NSString).lastPathComponent
                        if !filename.isEmpty {
                            self.tasks[idx].displayName = filename
                        }
                    }
                    // Record in history
                    self.historyManager.addRecord(
                        fileName: self.tasks[idx].displayName,
                        filePath: filePath,
                        linkType: task.linkType.displayTypeName
                    )
                }
            } catch {
                if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[idx].status = .failed(error.localizedDescription)
                    self.tasks[idx].completedAt = Date()
                }
            }
            self.isProcessing = false
            self.processQueue()
        }
    }

    private func isTerminalStatus(_ status: DownloadTaskStatus) -> Bool {
        if status == .success { return true }
        if case .failed = status { return true }
        return false
    }

    private func pruneOldTasks() {
        // Keep at most maxTasks, pruning oldest completed first
        while tasks.count > maxTasks {
            if let idx = tasks.lastIndex(where: { isTerminalStatus($0.status) }) {
                tasks.remove(at: idx)
            } else {
                break
            }
        }
    }
}
