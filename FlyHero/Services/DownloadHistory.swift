import Foundation
import AppKit

struct DownloadRecord: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let filePath: String
    let linkType: String
    let downloadedAt: Date

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: downloadedAt)
    }
}

@MainActor
final class DownloadHistoryManager: ObservableObject {
    @Published var records: [DownloadRecord] = []
    private let maxRecords = 100

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FlyHero")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("download_history.json")
    }

    init() {
        load()
    }

    func addRecord(fileName: String, filePath: String, linkType: String) {
        let record = DownloadRecord(
            id: UUID(),
            fileName: fileName,
            filePath: filePath,
            linkType: linkType,
            downloadedAt: Date()
        )
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    func revealInFinder(_ record: DownloadRecord) {
        let path = record.filePath
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } else {
            // Fallback: open the parent directory or sync directory
            let parentDir = (path as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: parentDir) {
                NSWorkspace.shared.open(URL(fileURLWithPath: parentDir))
            } else if let syncDir = SettingsManager.shared.targetDirectoryURL {
                NSWorkspace.shared.open(syncDir)
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([DownloadRecord].self, from: data)) ?? []
    }
}
