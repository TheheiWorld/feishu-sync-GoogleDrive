import Foundation

enum AppConstants {
    static let appName = "飞行侠"

    // MARK: - UserDefaults Keys
    enum Keys {
        static let targetDirectoryBookmark = "targetDirectoryBookmark"
        static let isIslandVisible = "isIslandVisible"
        static let islandPositionX = "islandPositionX"
        static let islandPositionY = "islandPositionY"
        static let launchAtLogin = "launchAtLogin"
    }

    // MARK: - Island Dimensions
    enum Island {
        // Default capsule: icon only
        static let closedWidth: CGFloat = 68
        static let closedHeight: CGFloat = 40
        // Expanded: icon + text
        static let openWidth: CGFloat = 220
        static let openHeight: CGFloat = 44
        static let cornerRadius: CGFloat = 22

        // Task list panel dimensions
        static let taskListWidth: CGFloat = 320
        static let taskListMaxHeight: CGFloat = 400
    }

    // MARK: - Menu Bar
    enum MenuBar {
        static let iconName = "arrow.down.doc.fill"
    }

    // MARK: - Google Drive Colors
    enum Colors {
        static let driveBlue = "#4285F4"
        static let driveGreen = "#34A853"
        static let driveYellow = "#FBBC04"
        static let driveRed = "#EA4335"
    }
}
