import SwiftUI

// MARK: - Task Row View

struct TaskRowView: View {
    let task: DownloadTask
    let onRetry: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.linkType.iconName)
                .font(.system(size: 16))
                .foregroundStyle(typeIconColor)
                .frame(width: 24)

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

            statusView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusView: some View {
        switch task.status {
        case .pendingConfirmation:
            HStack(spacing: 6) {
                Button(action: onConfirm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("确认下载")
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("取消")
            }
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
