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
