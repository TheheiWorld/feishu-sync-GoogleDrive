import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var taskManager: DownloadTaskManager


    var body: some View {
        VStack(spacing: 0) {
            // MARK: - App Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 66/255, green: 133/255, blue: 244/255),
                                             Color(red: 52/255, green: 100/255, blue: 220/255)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("飞行侠")
                        .font(.system(size: 16, weight: .semibold))
                    Text("V1.0.0")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .padding(.horizontal, 12)

            // MARK: - Menu Items
            VStack(spacing: 2) {
                // Select Directory
                MenuItemRow(
                    icon: "folder.fill",
                    iconColor: .secondary,
                    title: settings.hasTargetDirectory
                        ? (settings.targetDirectoryURL?.abbreviatedPath ?? "选择目录")
                        : "选择目录"
                ) {
                    pickTargetDirectory()
                }

                // Show Floating Window
                MenuToggleRow(
                    icon: "macwindow",
                    iconColor: .secondary,
                    title: "显示悬浮窗",
                    isOn: $settings.isIslandVisible
                )

            }
            .padding(.vertical, 6)

            Divider()
                .padding(.horizontal, 12)

            // MARK: - Quit
            MenuItemRow(
                icon: "power",
                iconColor: .red,
                title: "退出 飞行侠",
                titleColor: .red,
                shortcut: "⌘Q"
            ) {
                NSApplication.shared.terminate(nil)
            }
            .padding(.vertical, 6)
        }
        .frame(width: 220)
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

// MARK: - Menu Item Row

private struct MenuItemRow: View {
    let icon: String
    var iconColor: Color = .primary
    let title: String
    var titleColor: Color = .primary
    var shortcut: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menu Toggle Row

private struct MenuToggleRow: View {
    let icon: String
    var iconColor: Color = .primary
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 13))

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - URL Path Abbreviation

extension URL {
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = self.path
        if p.hasPrefix(home) {
            return "~" + p.dropFirst(home.count)
        }
        return p
    }
}
