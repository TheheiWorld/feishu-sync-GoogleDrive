# IslandDrop: Feishu Clipboard Download Design

## Overview

Transform IslandDrop from a file drag-and-drop sync tool into a **Feishu link clipboard monitor + Claude Code downloader**. When users copy a Feishu link, the app detects it via clipboard monitoring, queues a download task, and uses `claude --print` to invoke `lark-cli` commands for downloading the content to the user's configured directory.

## Requirements

1. **Remove drag-and-drop**: All file drop functionality is removed. The Island becomes a task status display.
2. **Clipboard monitoring**: Detect Feishu/Lark URLs copied to clipboard (already partially implemented).
3. **Link type parsing**: Identify document type from URL pattern (docs, sheets, base, drive, wiki, minutes, etc.).
4. **Claude Code execution**: For each detected link, spawn `claude --print` process with a prompt instructing it to use `lark-cli` to download the content.
5. **Download format mapping**:
   - Documents (docs/docx) → PDF
   - Spreadsheets (sheets) → XLSX
   - Bitable/Base (base) → XLSX
   - Drive files (file/drive) → original format
   - Wiki pages → resolve to underlying doc type, then download accordingly
   - Minutes (minutes) → TXT (summary content)
   - Unknown Feishu URLs → let Claude determine the best approach
6. **Task queue**: Serial execution (one at a time), with waiting/downloading/success/failed states.
7. **Task list UI**: Island shows summary; click to open a separate panel with full task list.

## Architecture

### Data Flow

```
User copies Feishu link
    ↓
ClipboardMonitor detects feishu.cn/larksuite.com URL (1.5s polling)
    ↓
FeishuLinkParser.parse(url) → FeishuLinkType + token
    ↓
DownloadTaskManager.enqueue(task)
    ↓
Serial execution loop picks next .waiting task
    ↓
ClaudeCodeRunner.executeDownload(link, type, targetDir)
    → Process("claude", ["--print", "--permission-mode", "bypassPermissions", "-p", prompt])
    ↓
Task status updated → UI refreshes
```

### Components

#### 1. FeishuLinkParser (new)

**File:** `IslandDrop/Services/FeishuLinkParser.swift`

Parses Feishu URLs to determine content type and extract tokens.

```swift
enum FeishuLinkType {
    case doc(token: String)        // /docs/ or /docx/
    case sheet(token: String)      // /sheets/
    case base(token: String)       // /base/
    case driveFile(token: String)  // /file/ or /drive/
    case wiki(token: String)       // /wiki/
    case minutes(token: String)    // /minutes/
    case unknown                   // other feishu.cn URLs
}

struct FeishuLinkParser {
    static func parse(_ url: URL) -> FeishuLinkType?
    static func isFeishuURL(_ url: URL) -> Bool
}
```

**URL pattern matching:**

| Pattern | Type | Token extraction |
|---------|------|-----------------|
| `*/docs/{token}` or `*/docx/{token}` | `.doc` | Path segment after docs/docx |
| `*/sheets/{token}` | `.sheet` | Path segment after sheets |
| `*/base/{token}` | `.base` | Path segment after base |
| `*/file/{token}` or `*/drive/*` | `.driveFile` | Path segment after file |
| `*/wiki/{token}` | `.wiki` | Path segment after wiki |
| `*/minutes/{token}` | `.minutes` | Path segment after minutes |

Host matching: `feishu.cn`, `larksuite.com`, `feishu.net` and any subdomain thereof.

#### 2. DownloadTask Model (new)

**File:** `IslandDrop/Services/DownloadTaskManager.swift`

```swift
enum DownloadTaskStatus: Equatable {
    case waiting
    case downloading
    case success
    case failed(String)  // error message
}

struct DownloadTask: Identifiable {
    let id: UUID
    let url: URL
    let linkType: FeishuLinkType
    var displayName: String      // Initially derived from URL, updated after download
    var status: DownloadTaskStatus
    let createdAt: Date
    var completedAt: Date?
}
```

#### 3. DownloadTaskManager (new)

**File:** `IslandDrop/Services/DownloadTaskManager.swift`

```swift
@MainActor
final class DownloadTaskManager: ObservableObject {
    static let shared = DownloadTaskManager()
    
    @Published var tasks: [DownloadTask] = []
    
    // Computed properties for UI
    var activeTasks: [DownloadTask]      // waiting + downloading
    var completedCount: Int              // success count
    var failedCount: Int                 // failed count
    var currentTask: DownloadTask?       // the one currently downloading
    var hasActiveTasks: Bool
    
    func enqueue(url: URL, linkType: FeishuLinkType)
    // Creates task with .waiting, triggers processQueue()
    
    private func processQueue()
    // Picks first .waiting task, sets to .downloading, calls ClaudeCodeRunner
    // On completion: sets success/failed, calls processQueue() for next
    
    func retryTask(_ task: DownloadTask)
    // Re-enqueue a failed task
    
    func clearCompleted()
    // Remove all success/failed tasks from list
}
```

**Queue behavior:**
- Maximum 50 tasks retained (oldest completed tasks pruned)
- Serial execution: only one `.downloading` task at a time
- New clipboard detections during download are queued as `.waiting`
- Duplicate URL detection: skip if same URL already in `.waiting` or `.downloading`

#### 4. ClaudeCodeRunner (new)

**File:** `IslandDrop/Services/ClaudeCodeRunner.swift`

```swift
@MainActor
final class ClaudeCodeRunner {
    static let shared = ClaudeCodeRunner()
    
    func executeDownload(
        link: URL,
        linkType: FeishuLinkType,
        targetDirectory: URL
    ) async throws -> String  // returns output from claude
}
```

**Implementation:**
- Uses `Process` to spawn `claude` CLI
- Arguments: `["--print", "--permission-mode", "bypassPermissions", "-p", prompt]`
- Working directory: set to targetDirectory
- Timeout: 180 seconds (some exports take time)
- Captures stdout + stderr via `Pipe`
- Process execution runs on a background thread (via `Task.detached` or `DispatchQueue.global`), results dispatched back to `@MainActor`
- Returns combined output for status reporting
- Environment: inherits PATH from user shell to find `claude` and `lark-cli`

**Prompt construction per type:**

| Type | Prompt template |
|------|----------------|
| `.doc` | "用 lark-cli 将这个飞书文档导出为 PDF 保存到 {targetDir}。链接: {url}。请用文档标题作为文件名。只输出最终保存的文件路径。" |
| `.sheet` | "用 lark-cli sheets +export 将这个电子表格导出为 xlsx 保存到 {targetDir}。链接: {url}。只输出最终保存的文件路径。" |
| `.base` | "用 lark-cli 将这个多维表格导出为 xlsx 保存到 {targetDir}。链接: {url}。只输出最终保存的文件路径。" |
| `.driveFile` | "用 lark-cli drive +download 下载这个文件到 {targetDir}。链接: {url}。只输出最终保存的文件路径。" |
| `.wiki` | "用 lark-cli 下载这个知识库文档到 {targetDir}。如果是文档导出为 PDF，如果是表格导出为 xlsx。链接: {url}。只输出最终保存的文件路径。" |
| `.minutes` | "用 lark-cli 获取这个妙记的内容摘要并保存为 txt 文件到 {targetDir}。链接: {url}。只输出最终保存的文件路径。" |
| `.unknown` | "用 lark-cli 下载这个飞书链接的内容到 {targetDir}。链接: {url}。自行判断最佳下载方式和格式。只输出最终保存的文件路径。" |

**Claude binary path resolution:**
- First try: `which claude` output
- Fallback: common paths (`/usr/local/bin/claude`, `~/.nvm/versions/node/*/bin/claude`)
- Store resolved path for reuse

#### 5. ClipboardMonitor (modify existing)

**File:** `IslandDrop/Plugins/ClipboardMonitor.swift`

Changes:
- Remove dependency on `PluginManager`
- Directly reference `DownloadTaskManager` instead
- When a Feishu URL is detected:
  1. Parse with `FeishuLinkParser`
  2. If valid, call `DownloadTaskManager.shared.enqueue()`
- Ignore non-Feishu URLs entirely (no more generic clipboard text handling)

#### 6. IslandContentView (modify existing)

**File:** `IslandDrop/FloatingIsland/IslandContentView.swift`

**Remove:**
- All `DropDelegate` code (`IslandFileDropDelegate`)
- `isDragHovering` state
- `.onDrop()` modifier
- Drop-related visual states

**New states:**

| State | Appearance | Size |
|-------|-----------|------|
| Idle (no tasks) | Feishu icon + "IslandDrop" | 48x48 capsule |
| Has waiting tasks | Feishu icon + "等待 3" | ~140x48 |
| Downloading | Spinning icon + "下载中..." | ~160x48 |
| All done | Checkmark + "完成 5" | ~130x48, auto-collapse after 3s |
| Has failures | Warning icon + "失败 2" | ~130x48 |

**Tap action:** Toggle TaskListPanel visibility

#### 7. TaskListPanel (new)

**File:** `IslandDrop/FloatingIsland/TaskListPanel.swift`

A new `NSPanel` (same pattern as FloatingPanel) that shows the complete task list.

**Panel properties:**
- `NSPanel` with `.nonactivatingPanel` + `.floating`
- Width: 320pt, max height: 400pt
- Positioned below the Island (anchored to Island's frame)
- Auto-dismiss when clicking outside (via `NSEvent.addGlobalMonitorForEvents`)
- Transparent background with vibrancy effect

**Content (SwiftUI via NSHostingView):**

```
┌─────────────────────────────────┐
│  下载任务                  清除  │  ← Header with clear button
├─────────────────────────────────┤
│  📄 项目需求文档.pdf        ✅  │  ← success
│  📊 Q4销售数据.xlsx        ✅  │  ← success  
│  📋 OKR表格.xlsx           ⏳  │  ← waiting
│  📄 会议纪要.pdf           🔄  │  ← downloading (animated)
│  📄 技术方案.pdf           ❌  │  ← failed (tap to retry)
└─────────────────────────────────┘
```

Each row:
- Type icon (based on FeishuLinkType)
- Display name (file name or URL abbreviation)
- Status icon (color-coded)
- Failed tasks: tap to retry

### Files to Remove

- `IslandDrop/FloatingIsland/IslandDropDelegate.swift` — legacy drop delegate, fully replaced
- `IslandDrop/Plugins/FeishuPlugin.swift` — stub replaced by new architecture
- `IslandDrop/Plugins/PluginProtocol.swift` — plugin system no longer needed

### Files to Modify

- `IslandDrop/App/AppDelegate.swift` — start ClipboardMonitor, remove FileSyncService references
- `IslandDrop/App/IslandDropApp.swift` — wire up new services
- `IslandDrop/FloatingIsland/FloatingPanelController.swift` — add TaskListPanel management
- `IslandDrop/FloatingIsland/IslandContentView.swift` — complete rewrite of visual states
- `IslandDrop/Plugins/ClipboardMonitor.swift` — simplify, connect to DownloadTaskManager
- `IslandDrop/MenuBar/SettingsView.swift` — update status display for new task model
- `IslandDrop/Services/FileSyncService.swift` — remove (replaced by ClaudeCodeRunner)
- `IslandDrop/Services/Constants.swift` — update constants for new UI

### Files to Create

- `IslandDrop/Services/FeishuLinkParser.swift`
- `IslandDrop/Services/DownloadTaskManager.swift`
- `IslandDrop/Services/ClaudeCodeRunner.swift`
- `IslandDrop/FloatingIsland/TaskListPanel.swift`

## Error Handling

- **Claude not found:** Show error in SettingsView, disable monitoring
- **Claude process timeout (180s):** Mark task as failed with timeout message
- **Claude process error:** Capture stderr, show in task failure reason
- **No target directory configured:** Show setup prompt in Island (existing behavior)
- **Duplicate URL:** Skip silently (don't enqueue)
- **lark-cli auth issues:** Claude's output will mention auth errors; surface in task failure

## Testing Strategy

- Unit test `FeishuLinkParser` with various URL patterns
- Unit test `DownloadTaskManager` queue logic (enqueue, dedup, serial execution, retry)
- Integration test: mock `Process` for `ClaudeCodeRunner`
