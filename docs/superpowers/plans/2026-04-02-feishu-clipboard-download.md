# Feishu Clipboard Download Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform IslandDrop from file drag-drop sync into Feishu link clipboard monitor + Claude Code downloader

**Architecture:** ClipboardMonitor detects Feishu URLs -> FeishuLinkParser identifies content type -> DownloadTaskManager queues tasks -> ClaudeCodeRunner spawns `claude --print` processes to execute `lark-cli` downloads -> TaskListPanel shows status

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (NSPanel), Foundation (Process), macOS 13+

---

## Task 1: FeishuLinkParser -- parse Feishu URLs into typed tokens

**Files:**
- **Create:** `IslandDrop/Services/FeishuLinkParser.swift`

**Steps:**

- [ ] Create the file `IslandDrop/Services/FeishuLinkParser.swift` with the complete content below:

```swift
import Foundation

// MARK: - Feishu Link Types

enum FeishuLinkType: Equatable {
    case doc(token: String)        // /docs/ or /docx/
    case sheet(token: String)      // /sheets/
    case base(token: String)       // /base/
    case driveFile(token: String)  // /file/ or /drive/
    case wiki(token: String)       // /wiki/
    case minutes(token: String)    // /minutes/
    case unknown                   // other feishu.cn URLs

    var displayTypeName: String {
        switch self {
        case .doc: return "文档"
        case .sheet: return "表格"
        case .base: return "多维表格"
        case .driveFile: return "文件"
        case .wiki: return "知识库"
        case .minutes: return "妙记"
        case .unknown: return "飞书链接"
        }
    }

    var iconName: String {
        switch self {
        case .doc: return "doc.text.fill"
        case .sheet: return "tablecells.fill"
        case .base: return "square.grid.3x3.fill"
        case .driveFile: return "doc.fill"
        case .wiki: return "book.fill"
        case .minutes: return "mic.fill"
        case .unknown: return "link"
        }
    }
}

// MARK: - Feishu Link Parser

struct FeishuLinkParser {
    private static let feishuHosts = [
        "feishu.cn",
        "larksuite.com",
        "feishu.net"
    ]

    /// Check if a URL belongs to Feishu/Lark domains (including subdomains)
    static func isFeishuURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return feishuHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// Parse a Feishu URL into a typed link with extracted token
    static func parse(_ url: URL) -> FeishuLinkType? {
        guard isFeishuURL(url) else { return nil }

        let pathComponents = url.pathComponents // e.g. ["/", "docs", "doccnABCDEF"]
        guard pathComponents.count >= 3 else { return .unknown }

        // Find the type segment and extract token from the next segment
        for (index, component) in pathComponents.enumerated() {
            let lower = component.lowercased()
            let nextIndex = index + 1

            switch lower {
            case "docs", "docx":
                if nextIndex < pathComponents.count {
                    return .doc(token: pathComponents[nextIndex])
                }
            case "sheets":
                if nextIndex < pathComponents.count {
                    return .sheet(token: pathComponents[nextIndex])
                }
            case "base":
                if nextIndex < pathComponents.count {
                    return .base(token: pathComponents[nextIndex])
                }
            case "file":
                if nextIndex < pathComponents.count {
                    return .driveFile(token: pathComponents[nextIndex])
                }
            case "drive":
                // /drive/folder/xxx or /drive/xxx
                if nextIndex < pathComponents.count {
                    let next = pathComponents[nextIndex]
                    if next.lowercased() == "folder" && nextIndex + 1 < pathComponents.count {
                        return .driveFile(token: pathComponents[nextIndex + 1])
                    }
                    return .driveFile(token: next)
                }
            case "wiki":
                if nextIndex < pathComponents.count {
                    return .wiki(token: pathComponents[nextIndex])
                }
            case "minutes":
                if nextIndex < pathComponents.count {
                    return .minutes(token: pathComponents[nextIndex])
                }
            default:
                continue
            }
        }

        return .unknown
    }
}
```

- [ ] Build and verify compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 2: DownloadTaskManager -- task model + queue

**Files:**
- **Create:** `IslandDrop/Services/DownloadTaskManager.swift`

**Steps:**

- [ ] Create the file `IslandDrop/Services/DownloadTaskManager.swift` with the complete content below:

```swift
import Foundation
import Combine

// MARK: - Download Task Status

enum DownloadTaskStatus: Equatable {
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

    private let maxTasks = 50
    private var isProcessing = false

    // MARK: - Computed Properties

    var activeTasks: [DownloadTask] {
        tasks.filter { $0.status == .waiting || $0.status == .downloading }
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

    // MARK: - Queue Operations

    func enqueue(url: URL, linkType: FeishuLinkType) {
        // Dedup: skip if same URL already waiting or downloading
        let isDuplicate = tasks.contains { task in
            task.url == url && (task.status == .waiting || task.status == .downloading)
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
            status: .waiting,
            createdAt: Date(),
            completedAt: nil
        )
        tasks.insert(task, at: 0)
        pruneOldTasks()
        processQueue()
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
                    // Try to extract a better display name from output
                    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let lastLine = trimmed.components(separatedBy: "\n").last {
                        let filename = (lastLine as NSString).lastPathComponent
                        if !filename.isEmpty {
                            self.tasks[idx].displayName = filename
                        }
                    }
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

    private func pruneOldTasks() {
        // Keep at most maxTasks, pruning oldest completed first
        while tasks.count > maxTasks {
            if let idx = tasks.lastIndex(where: { $0.status == .success || {
                if case .failed = $0.status { return true }
                return false
            }() }) {
                tasks.remove(at: idx)
            } else {
                break
            }
        }
    }
}
```

> **Note:** This file references `ClaudeCodeRunner.shared` which does not exist yet. The build will fail until Task 3 is complete. That is expected -- both files are created before the first full build verification.

- [ ] Build will be verified after Task 3 (ClaudeCodeRunner) is created.

---

## Task 3: ClaudeCodeRunner -- spawn claude --print processes

**Files:**
- **Create:** `IslandDrop/Services/ClaudeCodeRunner.swift`

**Steps:**

- [ ] Create the file `IslandDrop/Services/ClaudeCodeRunner.swift` with the complete content below:

```swift
import Foundation

// MARK: - Claude Code Runner Errors

enum ClaudeCodeRunnerError: LocalizedError {
    case claudeNotFound
    case timeout
    case processError(String)
    case noOutput

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "找不到 claude 命令行工具"
        case .timeout:
            return "执行超时 (180秒)"
        case .processError(let msg):
            return "执行错误: \(msg)"
        case .noOutput:
            return "无输出结果"
        }
    }
}

// MARK: - Claude Code Runner

@MainActor
final class ClaudeCodeRunner {
    static let shared = ClaudeCodeRunner()

    private var resolvedClaudePath: String?
    private let timeoutSeconds: TimeInterval = 180

    private init() {}

    // MARK: - Public API

    func executeDownload(
        link: URL,
        linkType: FeishuLinkType,
        targetDirectory: URL
    ) async throws -> String {
        let claudePath = try await resolveClaudePath()
        let prompt = buildPrompt(for: linkType, url: link, targetDir: targetDirectory)

        return try await runClaudeProcess(
            claudePath: claudePath,
            prompt: prompt,
            workingDirectory: targetDirectory
        )
    }

    // MARK: - Claude Path Resolution

    private func resolveClaudePath() async throws -> String {
        if let cached = resolvedClaudePath {
            return cached
        }

        // Try `which claude` first
        if let path = try? await runShellCommand("/usr/bin/env", arguments: ["which", "claude"]) {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && FileManager.default.fileExists(atPath: trimmed) {
                resolvedClaudePath = trimmed
                return trimmed
            }
        }

        // Fallback to known path
        let knownPath = "/Users/juststand/.nvm/versions/node/v22.22.0/bin/claude"
        if FileManager.default.fileExists(atPath: knownPath) {
            resolvedClaudePath = knownPath
            return knownPath
        }

        // Try common locations
        let commonPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        for p in commonPaths {
            if FileManager.default.fileExists(atPath: p) {
                resolvedClaudePath = p
                return p
            }
        }

        throw ClaudeCodeRunnerError.claudeNotFound
    }

    // MARK: - Prompt Construction

    private func buildPrompt(for linkType: FeishuLinkType, url: URL, targetDir: URL) -> String {
        let targetPath = targetDir.path
        let urlString = url.absoluteString

        switch linkType {
        case .doc:
            return "请使用 lark-cli 将这个飞书文档导出为 PDF 并保存到 \(targetPath) 目录。文档链接: \(urlString)。请用文档标题作为文件名。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .sheet:
            return "请使用 lark-cli sheets +export 将这个飞书电子表格导出为 xlsx 文件并保存到 \(targetPath) 目录。表格链接: \(urlString)。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .base:
            return "请使用 lark-cli 将这个飞书多维表格导出为 xlsx 文件并保存到 \(targetPath) 目录。多维表格链接: \(urlString)。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .driveFile:
            return "请使用 lark-cli drive +download 下载这个飞书云空间文件到 \(targetPath) 目录。文件链接: \(urlString)。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .wiki:
            return "请使用 lark-cli 下载这个飞书知识库文档到 \(targetPath) 目录。如果是文档类型请导出为 PDF，如果是表格类型请导出为 xlsx。知识库链接: \(urlString)。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .minutes:
            return "请使用 lark-cli 获取这个飞书妙记的完整内容摘要，并保存为 txt 文件到 \(targetPath) 目录。妙记链接: \(urlString)。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .unknown:
            return "请使用 lark-cli 下载这个飞书链接对应的内容到 \(targetPath) 目录。请自行判断内容类型和最佳下载方式（文档导出为PDF，表格导出为xlsx，文件直接下载）。链接: \(urlString)。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        }
    }

    // MARK: - Process Execution

    private func runClaudeProcess(
        claudePath: String,
        prompt: String,
        workingDirectory: URL
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: claudePath)
                process.arguments = ["--print", "--permission-mode", "bypassPermissions", "-p", prompt]
                process.currentDirectoryURL = workingDirectory

                // Set up environment with common PATH entries
                var env = ProcessInfo.processInfo.environment
                let additionalPaths = [
                    "/usr/local/bin",
                    "/opt/homebrew/bin",
                    "/Users/juststand/.nvm/versions/node/v22.22.0/bin",
                    "/usr/bin",
                    "/bin"
                ]
                let existingPath = env["PATH"] ?? "/usr/bin:/bin"
                env["PATH"] = (additionalPaths + [existingPath]).joined(separator: ":")
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Timeout handling
                var didTimeout = false
                let timeoutWorkItem = DispatchWorkItem {
                    didTimeout = true
                    if process.isRunning {
                        process.terminate()
                    }
                }
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + 180,
                    execute: timeoutWorkItem
                )

                do {
                    try process.run()
                    process.waitUntilExit()
                    timeoutWorkItem.cancel()

                    if didTimeout {
                        continuation.resume(throwing: ClaudeCodeRunnerError.timeout)
                        return
                    }

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        let errorMsg = stderr.isEmpty ? "Exit code \(process.terminationStatus)" : stderr
                        continuation.resume(throwing: ClaudeCodeRunnerError.processError(errorMsg))
                        return
                    }

                    if stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !stderr.isEmpty {
                            continuation.resume(throwing: ClaudeCodeRunnerError.processError(stderr))
                        } else {
                            continuation.resume(throwing: ClaudeCodeRunnerError.noOutput)
                        }
                        return
                    }

                    continuation.resume(returning: stdout)
                } catch {
                    timeoutWorkItem.cancel()
                    continuation.resume(throwing: ClaudeCodeRunnerError.processError(error.localizedDescription))
                }
            }
        }
    }

    private func runShellCommand(_ command: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

- [ ] Build and verify both Task 2 and Task 3 compile together:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 4: Update ClipboardMonitor -- connect to DownloadTaskManager

**Files:**
- **Modify:** `IslandDrop/Plugins/ClipboardMonitor.swift` (lines 1-54)

**Current code reference:**
- Line 10: `private let pluginManager: PluginManager`
- Line 12: `init(pluginManager: PluginManager)`
- Line 13: `self.pluginManager = pluginManager`
- Lines 42-52: URL detection and pluginManager.processInput calls

**Steps:**

- [ ] Replace the entire content of `IslandDrop/Plugins/ClipboardMonitor.swift` with:

```swift
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
```

**Changes summary (old -> new):**
- Line 10: `private let pluginManager: PluginManager` -> `private let taskManager: DownloadTaskManager`
- Line 12: `init(pluginManager: PluginManager)` -> `init(taskManager: DownloadTaskManager)`
- Line 13: `self.pluginManager = pluginManager` -> `self.taskManager = taskManager`
- Lines 42-52: Replaced generic URL/text handling with Feishu-only detection using `FeishuLinkParser.isFeishuURL()` and `FeishuLinkParser.parse()`, then calling `taskManager.enqueue()`
- Removed all non-Feishu clipboard text processing

- [ ] Build and verify compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 5: Update Constants -- new dimensions and keys

**Files:**
- **Modify:** `IslandDrop/Services/Constants.swift` (lines 1-41)

**Current code reference:**
- Lines 16-26: `enum Island` with closedSize, openWidth, openHeight, dropWidth, dropHeight, cornerRadius

**Steps:**

- [ ] In `IslandDrop/Services/Constants.swift`, replace the `Island` enum (lines 16-26) with:

**Old code (lines 16-26):**
```swift
    enum Island {
        // Closed mailbox: icon only
        static let closedSize: CGFloat = 48
        // Open mailbox: hover state with text
        static let openWidth: CGFloat = 200
        static let openHeight: CGFloat = 48
        // File drag state: larger prompt
        static let dropWidth: CGFloat = 260
        static let dropHeight: CGFloat = 52
        static let cornerRadius: CGFloat = 24
    }
```

**New code:**
```swift
    enum Island {
        // Closed state: icon only
        static let closedSize: CGFloat = 48
        // Open state: with status text
        static let openWidth: CGFloat = 200
        static let openHeight: CGFloat = 48
        static let cornerRadius: CGFloat = 24

        // Task list panel dimensions
        static let taskListWidth: CGFloat = 320
        static let taskListMaxHeight: CGFloat = 400
    }
```

**Changes summary:**
- Removed `dropWidth` (line 23) and `dropHeight` (line 24) -- no longer needed since drag-and-drop is removed
- Added `taskListWidth = 320` and `taskListMaxHeight = 400` for the new TaskListPanel

- [ ] Build and verify compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 6: Rewrite IslandContentView -- task status display

**Files:**
- **Modify:** `IslandDrop/FloatingIsland/IslandContentView.swift` (lines 1-285, complete rewrite)

**Current code reference:**
- Line 2: `import UniformTypeIdentifiers` (to be removed)
- Line 14: `@ObservedObject var fileSyncService: FileSyncService` (to be replaced)
- Line 17: `@State private var isDragHovering = false` (to be removed)
- Lines 22-23: `isOpen` computed property references `isDragHovering`, `fileSyncService.isSyncing` (to be replaced)
- Lines 91-96: `.onDrop()` modifier with `IslandFileDropDelegate` (to be removed)
- Lines 228-285: `IslandFileDropDelegate` struct (to be removed)

**Steps:**

- [ ] Replace the entire content of `IslandDrop/FloatingIsland/IslandContentView.swift` with:

```swift
import SwiftUI

// MARK: - Notification for toggling task list panel

extension Notification.Name {
    static let toggleTaskList = Notification.Name("ToggleTaskList")
}

// MARK: - Google Drive Colors

private extension Color {
    static let driveBlue = Color(red: 66/255, green: 133/255, blue: 244/255)     // #4285F4
    static let driveGreen = Color(red: 52/255, green: 168/255, blue: 83/255)     // #34A853
    static let driveYellow = Color(red: 251/255, green: 188/255, blue: 4/255)    // #FBBC04
    static let driveRed = Color(red: 234/255, green: 67/255, blue: 53/255)       // #EA4335
}

struct IslandContentView: View {
    @ObservedObject var taskManager: DownloadTaskManager
    @ObservedObject var stateObject: IslandStateObject
    @ObservedObject var settings: SettingsManager
    @State private var showingResult = false

    private var needsSetup: Bool {
        !settings.hasTargetDirectory
    }

    private var isOpen: Bool {
        stateObject.isMouseHovering || taskManager.hasActiveTasks || showingResult
    }

    // MARK: - State derivation

    private enum IslandState {
        case idle
        case hasWaiting(Int)
        case downloading
        case allDone(Int)
        case hasFailed(Int)
    }

    private var currentState: IslandState {
        if let _ = taskManager.currentTask {
            return .downloading
        }
        let waitingCount = taskManager.tasks.filter { $0.status == .waiting }.count
        if waitingCount > 0 {
            return .hasWaiting(waitingCount)
        }
        let failedCount = taskManager.failedCount
        if failedCount > 0 {
            return .hasFailed(failedCount)
        }
        let completedCount = taskManager.completedCount
        if completedCount > 0 && showingResult {
            return .allDone(completedCount)
        }
        return .idle
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Image(systemName: islandIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            if isOpen {
                Text(statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.horizontal, isOpen ? 18 : 0)
        .frame(
            width: isOpen ? AppConstants.Island.openWidth : AppConstants.Island.closedSize,
            height: AppConstants.Island.openHeight
        )
        .background(
            ZStack {
                Capsule()
                    .fill(.white)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .driveBlue.opacity(0.05),
                                .driveGreen.opacity(0.03),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: borderColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isOpen ? 1.5 : 1
                    )
            }
            .shadow(color: shadowColor, radius: isOpen ? 10 : 5, y: isOpen ? 3 : 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
        .onTapGesture {
            if needsSetup {
                pickTargetDirectory()
            } else {
                NotificationCenter.default.post(name: .toggleTaskList, object: nil)
            }
        }
        .onChange(of: taskManager.hasActiveTasks) { hasActive in
            if !hasActive && !taskManager.tasks.isEmpty {
                showingResult = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showingResult = false
                    }
                }
            }
        }
    }

    // MARK: - Visual state

    private var islandIcon: String {
        if needsSetup {
            return stateObject.isMouseHovering ? "folder.badge.plus" : "icloud.and.arrow.down"
        }
        switch currentState {
        case .idle:
            return stateObject.isMouseHovering ? "tray.and.arrow.down.fill" : "icloud.and.arrow.down"
        case .hasWaiting:
            return "clock.fill"
        case .downloading:
            return "arrow.triangle.2.circlepath"
        case .allDone:
            return "checkmark.circle.fill"
        case .hasFailed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        if needsSetup {
            return stateObject.isMouseHovering ? .driveBlue : .driveBlue.opacity(0.6)
        }
        switch currentState {
        case .idle:
            return stateObject.isMouseHovering ? .driveBlue : .driveBlue.opacity(0.7)
        case .hasWaiting:
            return .gray
        case .downloading:
            return .driveBlue
        case .allDone:
            return .driveGreen
        case .hasFailed:
            return .driveRed
        }
    }

    private var textColor: Color {
        switch currentState {
        case .allDone: return .driveGreen
        case .hasFailed: return .driveRed
        default: return Color(white: 0.25)
        }
    }

    private var borderColors: [Color] {
        switch currentState {
        case .downloading:
            return [.driveBlue.opacity(0.4), .driveGreen.opacity(0.3)]
        case .allDone:
            return [.driveGreen.opacity(0.5), .driveGreen.opacity(0.3)]
        case .hasFailed:
            return [.driveRed.opacity(0.5), .driveYellow.opacity(0.4)]
        default:
            if isOpen {
                return [.driveBlue.opacity(0.3), .driveGreen.opacity(0.2)]
            }
            return [Color(white: 0.82), Color(white: 0.85)]
        }
    }

    private var shadowColor: Color {
        switch currentState {
        case .downloading: return .driveBlue.opacity(0.2)
        case .allDone: return .driveGreen.opacity(0.2)
        case .hasFailed: return .driveRed.opacity(0.2)
        default: return Color.black.opacity(0.1)
        }
    }

    private var statusText: String {
        if needsSetup { return "点击设置同步目录" }
        switch currentState {
        case .idle:
            return "监听剪贴板中"
        case .hasWaiting(let count):
            return "等待 \(count)"
        case .downloading:
            return "下载中..."
        case .allDone(let count):
            return "完成 \(count)"
        case .hasFailed(let count):
            return "失败 \(count)"
        }
    }

    // MARK: - Actions

    private func pickTargetDirectory() {
        DispatchQueue.main.async {
            let previousPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "选择同步目录"
            panel.message = "请选择文件同步的目标目录"

            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                settings.setTargetDirectory(url)
            }

            NSApp.setActivationPolicy(previousPolicy)
        }
    }
}
```

**Changes summary (complete rewrite):**
- Removed `import UniformTypeIdentifiers` (line 2)
- Replaced `@ObservedObject var fileSyncService: FileSyncService` (line 14) with `@ObservedObject var taskManager: DownloadTaskManager`
- Removed `@State private var isDragHovering = false` (line 17)
- Removed `@State private var showSuccess = false` and `@State private var showError = false` (lines 18-19)
- Added `@State private var showingResult = false`
- Added `Notification.Name.toggleTaskList` extension
- Added `IslandState` enum for state derivation
- Rewrote `isOpen` (line 21-23) to use `taskManager.hasActiveTasks` instead of `isDragHovering`/`fileSyncService.isSyncing`
- Removed `.onDrop()` modifier entirely (lines 91-96)
- Tap gesture now toggles TaskListPanel via `NotificationCenter` instead of only handling needsSetup
- Replaced `handleSyncComplete()` with `onChange(of: taskManager.hasActiveTasks)` for auto-collapse
- Removed entire `IslandFileDropDelegate` struct (lines 228-285)
- All visual properties rewritten for new states: idle, hasWaiting, downloading, allDone, hasFailed

- [ ] Build and verify compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 7: TaskListPanel -- popup task list

**Files:**
- **Create:** `IslandDrop/FloatingIsland/TaskListPanel.swift`

**Steps:**

- [ ] Create the file `IslandDrop/FloatingIsland/TaskListPanel.swift` with the complete content below:

```swift
import AppKit
import SwiftUI

// MARK: - Task List Panel (NSPanel subclass)

final class TaskListPanelWindow: NSPanel {
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
        hasShadow = true
        isMovableByWindowBackground = false
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

// MARK: - Task List Panel Controller

@MainActor
final class TaskListPanelController {
    private var panel: TaskListPanelWindow?
    private let taskManager: DownloadTaskManager
    private var clickMonitor: Any?

    init(taskManager: DownloadTaskManager) {
        self.taskManager = taskManager
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(below anchorFrame: NSRect) {
        if isVisible {
            hide()
        } else {
            show(below: anchorFrame)
        }
    }

    func show(below anchorFrame: NSRect) {
        if panel != nil { hide() }

        let width = AppConstants.Island.taskListWidth
        let maxHeight = AppConstants.Island.taskListMaxHeight

        // Position below the island, centered horizontally
        let x = anchorFrame.midX - width / 2
        let y = anchorFrame.minY - maxHeight - 8

        let rect = NSRect(x: x, y: y, width: width, height: maxHeight)
        let panelWindow = TaskListPanelWindow(contentRect: rect)

        let contentView = TaskListContentView(taskManager: taskManager)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = panelWindow.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panelWindow.contentView = hostingView
        panelWindow.orderFrontRegardless()
        self.panel = panelWindow

        // Auto-dismiss when clicking outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return }
            let location = event.locationInWindow
            // Convert to screen coordinates if needed
            if let eventWindow = event.window {
                let screenPoint = eventWindow.convertPoint(toScreen: location)
                if !panel.frame.contains(screenPoint) {
                    Task { @MainActor in
                        self.hide()
                    }
                }
            } else {
                // Global event - location is already in screen coordinates
                if !panel.frame.contains(location) {
                    Task { @MainActor in
                        self.hide()
                    }
                }
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}

// MARK: - Task List SwiftUI Content

struct TaskListContentView: View {
    @ObservedObject var taskManager: DownloadTaskManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("下载任务")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if taskManager.completedCount > 0 || taskManager.failedCount > 0 {
                    Button("清除") {
                        taskManager.clearCompleted()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Task list
            if taskManager.tasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("暂无任务")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(taskManager.tasks) { task in
                            TaskRowView(task: task) {
                                taskManager.retryTask(task)
                            }
                            if task.id != taskManager.tasks.last?.id {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
                .frame(maxHeight: AppConstants.Island.taskListMaxHeight - 60)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: DownloadTask
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Type icon
            Image(systemName: task.linkType.iconName)
                .font(.system(size: 16))
                .foregroundStyle(typeIconColor)
                .frame(width: 24)

            // Task name
            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if case .failed(let message) = task.status {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            // Status indicator
            statusView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusView: some View {
        switch task.status {
        case .waiting:
            Image(systemName: "clock.fill")
                .font(.system(size: 14))
                .foregroundStyle(.gray)
        case .downloading:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.green)
        case .failed:
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("重试")
        }
    }

    private var typeIconColor: Color {
        switch task.linkType {
        case .doc: return .blue
        case .sheet: return .green
        case .base: return .purple
        case .driveFile: return .orange
        case .wiki: return .teal
        case .minutes: return .pink
        case .unknown: return .gray
        }
    }
}
```

- [ ] Build and verify compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 8: Update FloatingPanelController -- manage TaskListPanel + remove FileSyncService

**Files:**
- **Modify:** `IslandDrop/FloatingIsland/FloatingPanelController.swift` (lines 94-176)

**Current code reference:**
- Line 96: `private let fileSyncService: FileSyncService`
- Line 100: `init(fileSyncService: FileSyncService)`
- Line 101: `self.fileSyncService = fileSyncService`
- Lines 107-108: `let size = AppConstants.Island.dropWidth` and `let height = AppConstants.Island.dropHeight`
- Lines 125-129: `IslandContentView(fileSyncService: fileSyncService, stateObject: stateObject, settings: settings)`
- Line 144: `hostingView.registerForDraggedTypes([.fileURL])`

**Steps:**

- [ ] In `IslandDrop/FloatingIsland/FloatingPanelController.swift`, replace the `FloatingPanelController` class (lines 94-176) with:

**Old code (lines 94-176):**
```swift
final class FloatingPanelController {
    private var panel: FloatingPanel?
    private let fileSyncService: FileSyncService
    private let settings = SettingsManager.shared
    private let stateObject = IslandStateObject()

    init(fileSyncService: FileSyncService) {
        self.fileSyncService = fileSyncService
    }

    func showIsland() {
        if panel != nil { return }

        let size = AppConstants.Island.dropWidth
        let height = AppConstants.Island.dropHeight

        let origin: CGPoint
        if let saved = settings.islandPosition {
            origin = saved
        } else if let screen = NSScreen.main {
            origin = CGPoint(
                x: screen.visibleFrame.midX - size / 2,
                y: screen.visibleFrame.maxY - height - 12
            )
        } else {
            origin = CGPoint(x: 100, y: 100)
        }

        let rect = NSRect(origin: origin, size: NSSize(width: size, height: height))
        let floatingPanel = FloatingPanel(contentRect: rect)

        let contentView = IslandContentView(
            fileSyncService: fileSyncService,
            stateObject: stateObject,
            settings: settings
        )
        let hostingView = TrackingHostingView(rootView: contentView)
        hostingView.frame = floatingPanel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        hostingView.onMouseEntered = { [weak self] in
            self?.stateObject.isMouseHovering = true
        }
        hostingView.onMouseExited = { [weak self] in
            self?.stateObject.isMouseHovering = false
        }

        floatingPanel.contentView = hostingView
        hostingView.registerForDraggedTypes([.fileURL])

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

    @objc private func windowDidMove(_ notification: Notification) {
        guard let panel = panel else { return }
        settings.saveIslandPosition(panel.frame.origin)
    }
}
```

**New code:**
```swift
final class FloatingPanelController {
    private var panel: FloatingPanel?
    private let taskManager: DownloadTaskManager
    private let settings = SettingsManager.shared
    private let stateObject = IslandStateObject()
    private var taskListController: TaskListPanelController?
    private var toggleObserver: Any?

    init(taskManager: DownloadTaskManager) {
        self.taskManager = taskManager
        self.taskListController = TaskListPanelController(taskManager: taskManager)

        // Listen for task list toggle from IslandContentView tap
        toggleObserver = NotificationCenter.default.addObserver(
            forName: .toggleTaskList,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.toggleTaskList()
            }
        }
    }

    deinit {
        if let observer = toggleObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showIsland() {
        if panel != nil { return }

        let size = AppConstants.Island.openWidth
        let height = AppConstants.Island.openHeight

        let origin: CGPoint
        if let saved = settings.islandPosition {
            origin = saved
        } else if let screen = NSScreen.main {
            origin = CGPoint(
                x: screen.visibleFrame.midX - size / 2,
                y: screen.visibleFrame.maxY - height - 12
            )
        } else {
            origin = CGPoint(x: 100, y: 100)
        }

        let rect = NSRect(origin: origin, size: NSSize(width: size, height: height))
        let floatingPanel = FloatingPanel(contentRect: rect)

        let contentView = IslandContentView(
            taskManager: taskManager,
            stateObject: stateObject,
            settings: settings
        )
        let hostingView = TrackingHostingView(rootView: contentView)
        hostingView.frame = floatingPanel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        hostingView.onMouseEntered = { [weak self] in
            self?.stateObject.isMouseHovering = true
        }
        hostingView.onMouseExited = { [weak self] in
            self?.stateObject.isMouseHovering = false
        }

        floatingPanel.contentView = hostingView

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
        taskListController?.hide()
        panel?.orderOut(nil)
        panel = nil
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

    // MARK: - Task List Panel

    private func toggleTaskList() {
        guard let panel = panel else { return }
        taskListController?.toggle(below: panel.frame)
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard let panel = panel else { return }
        settings.saveIslandPosition(panel.frame.origin)
    }
}
```

**Changes summary:**
- Line 96: `private let fileSyncService: FileSyncService` -> `private let taskManager: DownloadTaskManager`
- Added: `private var taskListController: TaskListPanelController?` and `private var toggleObserver: Any?`
- Line 100: `init(fileSyncService: FileSyncService)` -> `init(taskManager: DownloadTaskManager)` with TaskListPanelController creation and NotificationCenter observer for `.toggleTaskList`
- Added `deinit` to remove observer
- Lines 107-108: `AppConstants.Island.dropWidth`/`dropHeight` -> `AppConstants.Island.openWidth`/`openHeight`
- Lines 125-129: `IslandContentView(fileSyncService:...)` -> `IslandContentView(taskManager:...)`
- Line 144: Removed `hostingView.registerForDraggedTypes([.fileURL])` entirely
- Added `toggleTaskList()` method
- `hideIsland()` now also hides TaskListPanel

- [ ] Build and verify compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 9: Update AppDelegate -- wire everything together

**Files:**
- **Modify:** `IslandDrop/App/AppDelegate.swift` (lines 1-49)

**Current code reference:**
- Line 7: `let fileSyncService = FileSyncService()`
- Line 12: `panelController = FloatingPanelController(fileSyncService: fileSyncService)`

**Steps:**

- [ ] Replace the entire content of `IslandDrop/App/AppDelegate.swift` with:

**Old code (lines 1-49):**
```swift
import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let fileSyncService = FileSyncService()
    private var panelController: FloatingPanelController?
    private var visibilityObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = FloatingPanelController(fileSyncService: fileSyncService)

        if SettingsManager.shared.isIslandVisible {
            panelController?.showIsland()
        }

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
}

// KVO-compatible key path for @AppStorage
private extension UserDefaults {
    @objc dynamic var isIslandVisible: Bool {
        bool(forKey: AppConstants.Keys.isIslandVisible)
    }
}
```

**New code:**
```swift
import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let taskManager = DownloadTaskManager()
    private var panelController: FloatingPanelController?
    private var clipboardMonitor: ClipboardMonitor?
    private var visibilityObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = FloatingPanelController(taskManager: taskManager)

        // Start clipboard monitoring
        let monitor = ClipboardMonitor(taskManager: taskManager)
        monitor.start()
        clipboardMonitor = monitor

        if SettingsManager.shared.isIslandVisible {
            panelController?.showIsland()
        }

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
}

// KVO-compatible key path for @AppStorage
private extension UserDefaults {
    @objc dynamic var isIslandVisible: Bool {
        bool(forKey: AppConstants.Keys.isIslandVisible)
    }
}
```

**Changes summary:**
- Line 7: `let fileSyncService = FileSyncService()` -> `let taskManager = DownloadTaskManager()`
- Added line 9: `private var clipboardMonitor: ClipboardMonitor?`
- Line 12: `FloatingPanelController(fileSyncService: fileSyncService)` -> `FloatingPanelController(taskManager: taskManager)`
- Added lines 15-17: Create `ClipboardMonitor(taskManager:)`, call `.start()`, store reference

- [ ] Build and verify compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 10: Update IslandDropApp -- update SettingsView wiring

**Files:**
- **Modify:** `IslandDrop/App/IslandDropApp.swift` (lines 1-15)

**Current code reference:**
- Line 9: `SettingsView(fileSyncService: appDelegate.fileSyncService)`

**Steps:**

- [ ] In `IslandDrop/App/IslandDropApp.swift`, replace line 9:

**Old code (line 9):**
```swift
            SettingsView(fileSyncService: appDelegate.fileSyncService)
```

**New code:**
```swift
            SettingsView(taskManager: appDelegate.taskManager)
```

**Changes summary:**
- Line 9: Changed from `fileSyncService: appDelegate.fileSyncService` to `taskManager: appDelegate.taskManager`

- [ ] Build and verify compiles (will fail until Task 11 updates SettingsView -- that is expected):

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 11: Update SettingsView -- show task status instead of sync status

**Files:**
- **Modify:** `IslandDrop/MenuBar/SettingsView.swift` (lines 1-111)

**Current code reference:**
- Line 5: `@ObservedObject var fileSyncService: FileSyncService`
- Lines 45-58: `if let result = fileSyncService.lastResult { ... }` section showing last sync status

**Steps:**

- [ ] Replace the entire content of `IslandDrop/MenuBar/SettingsView.swift` with:

**Old code (lines 1-111):**
```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var fileSyncService: FileSyncService
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled

    var body: some View {
        Form {
            // MARK: - 同步目录
            Section {
                LabeledContent("同步目录") {
                    HStack(spacing: 6) {
                        if let url = settings.targetDirectoryURL {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                            Text(url.abbreviatedPath)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .foregroundStyle(.primary)
                                .help(url.path)
                        } else {
                            Text("未设置")
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("选择…") {
                            pickTargetDirectory()
                        }
                        .controlSize(.small)
                    }
                }
            }

            // MARK: - 偏好设置
            Section {
                Toggle("显示悬浮岛", isOn: $settings.isIslandVisible)
                Toggle("开机启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _ in
                        LaunchAtLoginService.toggle()
                    }
            }

            // MARK: - 同步状态
            if let result = fileSyncService.lastResult {
                Section {
                    LabeledContent("上次同步") {
                        HStack(spacing: 4) {
                            Image(systemName: result.errors.isEmpty
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.triangle.fill")
                                .foregroundStyle(result.errors.isEmpty ? .green : .orange)
                            Text("\(result.successCount)/\(result.totalFiles) 个文件")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: - 退出
            Section {
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("退出")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
    }

    private func pickTargetDirectory() {
        DispatchQueue.main.async {
            let previousPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "选择同步目录"
            panel.message = "选择文件将要同步到的目录"

            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                settings.setTargetDirectory(url)
            }

            NSApp.setActivationPolicy(previousPolicy)
        }
    }
}

// MARK: - URL Path Abbreviation

private extension URL {
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = self.path
        if p.hasPrefix(home) {
            return "~" + p.dropFirst(home.count)
        }
        return p
    }
}
```

**New code:**
```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var taskManager: DownloadTaskManager
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled

    var body: some View {
        Form {
            // MARK: - 同步目录
            Section {
                LabeledContent("同步目录") {
                    HStack(spacing: 6) {
                        if let url = settings.targetDirectoryURL {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                            Text(url.abbreviatedPath)
                                .lineLimit(1)
                                .truncationMode(.head)
                                .foregroundStyle(.primary)
                                .help(url.path)
                        } else {
                            Text("未设置")
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("选择…") {
                            pickTargetDirectory()
                        }
                        .controlSize(.small)
                    }
                }
            }

            // MARK: - 偏好设置
            Section {
                Toggle("显示悬浮岛", isOn: $settings.isIslandVisible)
                Toggle("开机启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _ in
                        LaunchAtLoginService.toggle()
                    }
            }

            // MARK: - 任务状态
            if !taskManager.tasks.isEmpty {
                Section {
                    LabeledContent("已完成") {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("\(taskManager.completedCount) 个任务")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if taskManager.failedCount > 0 {
                        LabeledContent("失败") {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("\(taskManager.failedCount) 个任务")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    let waitingCount = taskManager.tasks.filter { $0.status == .waiting }.count
                    if waitingCount > 0 {
                        LabeledContent("等待中") {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(.gray)
                                Text("\(waitingCount) 个任务")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // MARK: - 退出
            Section {
                Button(role: .destructive) {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("退出")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
    }

    private func pickTargetDirectory() {
        DispatchQueue.main.async {
            let previousPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "选择同步目录"
            panel.message = "选择文件将要同步到的目录"

            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                settings.setTargetDirectory(url)
            }

            NSApp.setActivationPolicy(previousPolicy)
        }
    }
}

// MARK: - URL Path Abbreviation

private extension URL {
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = self.path
        if p.hasPrefix(home) {
            return "~" + p.dropFirst(home.count)
        }
        return p
    }
}
```

**Changes summary:**
- Line 5: `@ObservedObject var fileSyncService: FileSyncService` -> `@ObservedObject var taskManager: DownloadTaskManager`
- Lines 45-58: Replaced `if let result = fileSyncService.lastResult` section with new task status section showing `taskManager.completedCount`, `taskManager.failedCount`, and waiting count

- [ ] Build and verify compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

---

## Task 12: Delete unused files

**Files:**
- **Delete:** `IslandDrop/FloatingIsland/IslandDropDelegate.swift`
- **Delete:** `IslandDrop/Plugins/FeishuPlugin.swift`
- **Delete:** `IslandDrop/Plugins/PluginProtocol.swift`
- **Delete:** `IslandDrop/Services/FileSyncService.swift`

**Steps:**

- [ ] Delete `IslandDrop/FloatingIsland/IslandDropDelegate.swift`:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && rm IslandDrop/FloatingIsland/IslandDropDelegate.swift
```

- [ ] Delete `IslandDrop/Plugins/FeishuPlugin.swift`:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && rm IslandDrop/Plugins/FeishuPlugin.swift
```

- [ ] Delete `IslandDrop/Plugins/PluginProtocol.swift`:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && rm IslandDrop/Plugins/PluginProtocol.swift
```

- [ ] Delete `IslandDrop/Services/FileSyncService.swift`:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && rm IslandDrop/Services/FileSyncService.swift
```

- [ ] Build and verify everything still compiles:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

- [ ] Commit all changes:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && git add \
  IslandDrop/Services/FeishuLinkParser.swift \
  IslandDrop/Services/DownloadTaskManager.swift \
  IslandDrop/Services/ClaudeCodeRunner.swift \
  IslandDrop/Services/Constants.swift \
  IslandDrop/FloatingIsland/TaskListPanel.swift \
  IslandDrop/FloatingIsland/IslandContentView.swift \
  IslandDrop/FloatingIsland/FloatingPanelController.swift \
  IslandDrop/Plugins/ClipboardMonitor.swift \
  IslandDrop/App/AppDelegate.swift \
  IslandDrop/App/IslandDropApp.swift \
  IslandDrop/MenuBar/SettingsView.swift \
  && git rm \
  IslandDrop/FloatingIsland/IslandDropDelegate.swift \
  IslandDrop/Plugins/FeishuPlugin.swift \
  IslandDrop/Plugins/PluginProtocol.swift \
  IslandDrop/Services/FileSyncService.swift \
  && git commit -m "feat: transform IslandDrop into Feishu clipboard monitor + Claude Code downloader

Replace file drag-drop sync with clipboard monitoring for Feishu URLs.
ClipboardMonitor detects Feishu links, FeishuLinkParser identifies content
type, DownloadTaskManager queues serial downloads, and ClaudeCodeRunner
spawns claude --print processes to execute lark-cli commands.

New files:
- FeishuLinkParser: parse Feishu URLs into typed tokens
- DownloadTaskManager: task model + serial queue
- ClaudeCodeRunner: spawn claude --print with lark-cli prompts
- TaskListPanel: popup panel showing download task status

Removed:
- IslandDropDelegate, FeishuPlugin, PluginProtocol, FileSyncService"
```

---

## Task 13: Final build + smoke test

**Files:** None (verification only)

**Steps:**

- [ ] Clean build to ensure no stale artifacts:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && swift build
```

- [ ] Run the app briefly to verify it launches without crashing:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && timeout 5 .build/debug/IslandDrop || true
```

- [ ] Verify expected behavior:
  - Island appears on screen as a floating capsule
  - Clipboard monitor is running (check console output)
  - Copying a Feishu URL (e.g., `https://abc.feishu.cn/docs/doccnABCDEF`) should trigger task creation
  - Clicking the island should toggle the TaskListPanel
  - Settings menu bar extra should show task counts instead of sync status

- [ ] If everything passes, make a final commit if there were any fixes:

```bash
cd /Users/juststand/study/ai/mac-file-transfer && git status && git diff --stat
# Only commit if there are changes from smoke test fixes
```

---

## File Summary

### New Files (4)
| File | Purpose |
|------|---------|
| `IslandDrop/Services/FeishuLinkParser.swift` | Parse Feishu URLs into typed tokens (doc, sheet, base, drive, wiki, minutes) |
| `IslandDrop/Services/DownloadTaskManager.swift` | Task model + serial queue with dedup, retry, and pruning |
| `IslandDrop/Services/ClaudeCodeRunner.swift` | Spawn `claude --print` processes with lark-cli prompts per content type |
| `IslandDrop/FloatingIsland/TaskListPanel.swift` | NSPanel popup showing task list with status indicators |

### Modified Files (7)
| File | Key Changes |
|------|-------------|
| `IslandDrop/Plugins/ClipboardMonitor.swift` | Replace PluginManager with DownloadTaskManager, Feishu-only detection |
| `IslandDrop/Services/Constants.swift` | Remove dropWidth/dropHeight, add taskListWidth/taskListMaxHeight |
| `IslandDrop/FloatingIsland/IslandContentView.swift` | Complete rewrite: remove drop delegate, add task status states |
| `IslandDrop/FloatingIsland/FloatingPanelController.swift` | Replace FileSyncService with DownloadTaskManager, add TaskListPanel management |
| `IslandDrop/App/AppDelegate.swift` | Wire DownloadTaskManager and ClipboardMonitor |
| `IslandDrop/App/IslandDropApp.swift` | Pass taskManager to SettingsView |
| `IslandDrop/MenuBar/SettingsView.swift` | Show task counts instead of sync result |

### Deleted Files (4)
| File | Reason |
|------|--------|
| `IslandDrop/FloatingIsland/IslandDropDelegate.swift` | Legacy drop delegate, fully replaced by clipboard monitoring |
| `IslandDrop/Plugins/FeishuPlugin.swift` | Stub replaced by FeishuLinkParser + ClaudeCodeRunner architecture |
| `IslandDrop/Plugins/PluginProtocol.swift` | Plugin system no longer needed |
| `IslandDrop/Services/FileSyncService.swift` | File copy service replaced by ClaudeCodeRunner |