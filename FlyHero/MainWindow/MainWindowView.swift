import SwiftUI
import AppKit

// MARK: - Main Window View

struct MainWindowView: View {
    @ObservedObject var historyManager: DownloadHistoryManager
    @ObservedObject var settings: SettingsManager
    @State private var selectedTab = 0
    @Namespace private var tabAnimation

    var body: some View {
        VStack(spacing: 0) {
            // Title bar spacer
            Color(nsColor: .windowBackgroundColor)
                .frame(height: 28)

            // Centered Capsule Tab Bar
            HStack(spacing: 2) {
                CapsuleTab(title: "设置", icon: "gearshape", isSelected: selectedTab == 0, namespace: tabAnimation) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = 0
                    }
                }
                CapsuleTab(title: "历史", icon: "clock.arrow.circlepath", isSelected: selectedTab == 1, namespace: tabAnimation) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = 1
                    }
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.vertical, 8)

            // Tab content with slide transition
            ZStack {
                if selectedTab == 0 {
                    SettingsTabContent(settings: settings)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
                if selectedTab == 1 {
                    HistoryTabContent(historyManager: historyManager)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Capsule Tab

private struct CapsuleTab: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .primary.opacity(0.08), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "tab_bg", in: namespace)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Tab

private struct SettingsTabContent: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 12)

            // Directory card
            VStack(alignment: .leading, spacing: 14) {
                Text("同步目录")
                    .font(.system(size: 15, weight: .semibold))

                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前目录")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if let url = settings.targetDirectoryURL {
                            Text(url.abbreviatedPath)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("未设置")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: pickDirectory) {
                        Text("选择")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)

            // Status card
            VStack(alignment: .leading, spacing: 14) {
                Text("状态")
                    .font(.system(size: 15, weight: .semibold))

                Divider()

                HStack(spacing: 24) {
                    StatusDot(label: "剪贴板", value: "监听中", active: true)
                    StatusDot(label: "悬浮窗", value: settings.isIslandVisible ? "显示" : "隐藏", active: settings.isIslandVisible)
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    private func pickDirectory() {
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

private struct StatusDot: View {
    let label: String
    let value: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active ? .primary : .secondary)
        }
    }
}

// MARK: - History Tab

private struct HistoryTabContent: View {
    @ObservedObject var historyManager: DownloadHistoryManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("下载历史")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(historyManager.records.count) 条记录")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 28)

            if historyManager.records.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("暂无下载记录")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Column header
                        HStack(spacing: 0) {
                            Text("文件名")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("类型")
                                .frame(width: 60)
                            Text("时间")
                                .frame(width: 90)
                            Text("操作")
                                .frame(width: 50)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.03))

                        Divider()

                        // Records
                        ForEach(Array(historyManager.records.enumerated()), id: \.element.id) { index, record in
                            HistoryRow(record: record, isEven: index % 2 == 0) {
                                historyManager.revealInFinder(record)
                            }
                            if index < historyManager.records.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
            }
        }
    }
}

private struct HistoryRow: View {
    let record: DownloadRecord
    let isEven: Bool
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(record.fileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.linkType)
                .frame(width: 60)
                .foregroundStyle(.secondary)

            Text(record.formattedDate)
                .frame(width: 90)
                .foregroundStyle(.secondary)

            Button(action: onReveal) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 50)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isEven ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.02))
    }
}
