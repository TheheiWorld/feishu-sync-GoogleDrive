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
            return "执行超时 (300秒)"
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
            return "请使用 lark-cli 将这个飞书文档导出为 PDF 并保存到 \(targetPath) 目录。文档链接: \(urlString)。请先使用 lark-cli 获取文档的原始标题，然后用原始标题作为保存的文件名（例如：原始标题.pdf）。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .sheet:
            return "请使用 lark-cli 将这个飞书电子表格导出为 xlsx 文件并保存到 \(targetPath) 目录。表格链接: \(urlString)。请先使用 lark-cli sheets +info 获取表格的原始标题，然后使用该原始标题作为导出的文件名（例如：原始标题.xlsx）。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .base:
            return "请使用 lark-cli 将这个飞书多维表格导出为 xlsx 文件并保存到 \(targetPath) 目录。多维表格链接: \(urlString)。请先使用 lark-cli 获取多维表格的原始标题，然后用原始标题作为保存的文件名（例如：原始标题.xlsx）。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .driveFile:
            return "请使用 lark-cli drive +download 下载这个飞书云空间文件到 \(targetPath) 目录。文件链接: \(urlString)。请保留文件的原始名称。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .wiki:
            return "请使用 lark-cli 下载这个飞书知识库文档到 \(targetPath) 目录。如果是文档类型请导出为 PDF，如果是表格类型请导出为 xlsx。知识库链接: \(urlString)。请先获取文档的原始标题，然后用原始标题作为保存的文件名。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .minutes:
            return "请使用 lark-cli 获取这个飞书妙记的完整内容摘要，并保存为 txt 文件到 \(targetPath) 目录。妙记链接: \(urlString)。请先获取妙记的原始标题，然后用原始标题作为保存的文件名（例如：原始标题.txt）。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
        case .unknown:
            return "请使用 lark-cli 下载这个飞书链接对应的内容到 \(targetPath) 目录。请自行判断内容类型和最佳下载方式（文档导出为PDF，表格导出为xlsx，文件直接下载）。链接: \(urlString)。请先获取内容的原始标题，然后用原始标题作为保存的文件名。操作完成后只输出最终保存的完整文件路径，不要输出其他内容。"
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
                    deadline: .now() + 300,
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
