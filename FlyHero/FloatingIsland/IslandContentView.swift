import SwiftUI
import AppKit

// MARK: - Transfer Icon

private struct TransferIconView: View {
    private var templateImage: NSImage? {
        guard let img = NSImage(named: "TransferIcon") else { return nil }
        let copy = img.copy() as! NSImage
        copy.isTemplate = true
        return copy
    }

    var body: some View {
        if let img = templateImage {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "bicycle")
                .font(.system(size: 20))
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let showTaskList = Notification.Name("ShowTaskList")
    static let islandContentSizeChanged = Notification.Name("IslandContentSizeChanged")
}

// MARK: - Island Content View

struct IslandContentView: View {
    @ObservedObject var taskManager: DownloadTaskManager
    @ObservedObject var stateObject: IslandStateObject
    @ObservedObject var settings: SettingsManager
    @State private var showingResult = false
    @State private var showTaskList = false
    @State private var rideOffset: CGFloat = 0
    @State private var rideTimer: Timer?

    private var needsSetup: Bool {
        !settings.hasTargetDirectory
    }

    private var isOpen: Bool {
        stateObject.isMouseHovering || hasActivity || showingResult
    }

    private var hasActivity: Bool {
        taskManager.hasActiveTasks || taskManager.hasPendingConfirmation
    }

    // MARK: - State

    private enum IslandState {
        case idle, hasPending(Int), hasWaiting(Int), downloading, allDone(Int), hasFailed(Int)
    }

    private var currentState: IslandState {
        let pendingCount = taskManager.tasks.filter { $0.status == .pendingConfirmation }.count
        if pendingCount > 0 { return .hasPending(pendingCount) }
        if taskManager.currentTask != nil { return .downloading }
        let waitingCount = taskManager.tasks.filter { $0.status == .waiting }.count
        if waitingCount > 0 { return .hasWaiting(waitingCount) }
        if taskManager.failedCount > 0 { return .hasFailed(taskManager.failedCount) }
        if taskManager.completedCount > 0 && showingResult { return .allDone(taskManager.completedCount) }
        return .idle
    }

    private var isRiding: Bool {
        switch currentState {
        case .downloading, .hasWaiting: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Capsule header
            HStack(spacing: 8) {
                TransferIconView()
                    .frame(width: 28, height: 28)
                    .offset(x: isRiding ? rideOffset : 0)

                if isOpen || showTaskList {
                    Text(statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, (isOpen || showTaskList) ? 16 : 0)
            .frame(
                width: showTaskList ? AppConstants.Island.taskListWidth : (isOpen ? AppConstants.Island.openWidth : AppConstants.Island.closedWidth),
                height: isOpen || showTaskList ? AppConstants.Island.openHeight : AppConstants.Island.closedHeight
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if needsSetup {
                    pickTargetDirectory()
                } else {
                    let willExpand = !showTaskList
                    // Expand panel BEFORE animation starts
                    if willExpand {
                        notifySizeChanged(expanding: true)
                    }
                    withAnimation(.easeInOut(duration: 0.45)) {
                        showTaskList.toggle()
                    }
                    // Shrink panel AFTER animation ends
                    if !willExpand {
                        notifySizeChanged(expanding: false)
                    }
                }
            }

            // MARK: Task list (embedded, same panel)
            if showTaskList {
                VStack(spacing: 0) {
                    Divider()

                    // Header
                    HStack {
                        Text("下载任务")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if taskManager.completedCount > 0 || taskManager.failedCount > 0 {
                            Button("清除") {
                                taskManager.clearCompleted()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()

                    if taskManager.tasks.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                            Text("暂无任务")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(taskManager.tasks) { task in
                                    TaskRowView(
                                        task: task,
                                        onRetry: { taskManager.retryTask(task) },
                                        onConfirm: { taskManager.confirmTask(task) },
                                        onCancel: { taskManager.cancelTask(task) }
                                    )
                                    if task.id != taskManager.tasks.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }
                .frame(width: AppConstants.Island.taskListWidth)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(white: 0.22, alpha: 1)   // dark mode: soft dark
                        : NSColor(white: 0.94, alpha: 1)   // light mode: slight gray
                })))
                .shadow(color: .primary.opacity(showTaskList ? 0.15 : 0.08), radius: showTaskList ? 12 : 4, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.easeInOut(duration: 0.45), value: isOpen)
        .animation(.easeInOut(duration: 0.45), value: showTaskList)
        .onChange(of: taskManager.hasActiveTasks) { hasActive in
            if !hasActive && !taskManager.tasks.isEmpty {
                showingResult = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { showingResult = false }
                }
            }
        }
        .onChange(of: isRiding) { riding in
            if riding { startRideAnimation() } else { stopRideAnimation() }
        }
        .onChange(of: stateObject.isMouseHovering) { hovering in
            // Collapse task list when mouse leaves entirely
            if !hovering && showTaskList {
                withAnimation(.easeInOut(duration: 0.45)) {
                    showTaskList = false
                }
                notifySizeChanged(expanding: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTaskList)) { _ in
            if !showTaskList {
                notifySizeChanged(expanding: true)
                withAnimation(.easeInOut(duration: 0.45)) {
                    showTaskList = true
                }
            }
        }
        .onAppear {
            if isRiding { startRideAnimation() }
        }
    }

    private func notifySizeChanged(expanding: Bool) {
        if expanding {
            // Expand panel immediately so content has room during animation
            NotificationCenter.default.post(name: .islandContentSizeChanged, object: NSNumber(value: true))
        } else {
            // Shrink panel after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: .islandContentSizeChanged, object: NSNumber(value: false))
            }
        }
    }

    // MARK: - Ride Animation

    private func startRideAnimation() {
        rideTimer?.invalidate()
        rideTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.12)) {
                rideOffset = rideOffset == 0 ? 2 : (rideOffset == 2 ? -1 : 0)
            }
        }
    }

    private func stopRideAnimation() {
        rideTimer?.invalidate()
        rideTimer = nil
        withAnimation { rideOffset = 0 }
    }

    // MARK: - Visual State

    private var textColor: Color {
        switch currentState {
        case .hasPending: return .orange
        case .allDone: return .green
        case .hasFailed: return .red
        default: return .primary
        }
    }

    private var statusText: String {
        if needsSetup { return "点击设置同步目录" }
        switch currentState {
        case .idle: return "监听剪贴板中"
        case .hasPending(let n): return "确认 \(n)"
        case .hasWaiting(let n): return "等待 \(n)"
        case .downloading: return "配送中..."
        case .allDone(let n): return "完成 \(n)"
        case .hasFailed(let n): return "失败 \(n)"
        }
    }

    private func pickTargetDirectory() {
        DispatchQueue.main.async {
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
        }
    }
}
