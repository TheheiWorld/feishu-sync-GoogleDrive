import SwiftUI
import Combine

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @AppStorage(AppConstants.Keys.isIslandVisible)
    var isIslandVisible: Bool = true

    @AppStorage(AppConstants.Keys.islandPositionX)
    var islandPositionX: Double = -1

    @AppStorage(AppConstants.Keys.islandPositionY)
    var islandPositionY: Double = -1

    @Published var targetDirectoryURL: URL?

    private init() {
        resolveBookmark()
    }

    // MARK: - Target Directory (Security-Scoped Bookmark)

    func setTargetDirectory(_ url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: AppConstants.Keys.targetDirectoryBookmark)
            targetDirectoryURL = url
        } catch {
            print("Failed to create bookmark: \(error)")
        }
    }

    func resolveBookmark() {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.Keys.targetDirectoryBookmark) else {
            return
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                setTargetDirectory(url)
            }
            _ = url.startAccessingSecurityScopedResource()
            targetDirectoryURL = url
        } catch {
            print("Failed to resolve bookmark: \(error)")
        }
    }

    var hasTargetDirectory: Bool {
        targetDirectoryURL != nil
    }

    // MARK: - Island Position

    var islandPosition: CGPoint? {
        guard islandPositionX >= 0, islandPositionY >= 0 else { return nil }
        return CGPoint(x: islandPositionX, y: islandPositionY)
    }

    func saveIslandPosition(_ point: CGPoint) {
        islandPositionX = point.x
        islandPositionY = point.y
    }
}
