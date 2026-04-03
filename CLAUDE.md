# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build (debug)
swift build

# Run the built binary
.build/debug/IslandDrop

# Build (release)
swift build -c release
```

The project uses Swift Package Manager (no .xcodeproj). Minimum macOS 13 (Ventura).

## Architecture

**IslandDrop** is a macOS menu-bar utility with a floating "Dynamic Island" widget. Users drag files onto the island to sync them to a configured directory.

### Core Layers

- **App/** — Entry point (`@main` SwiftUI app) + `AppDelegate` that owns the floating panel lifecycle. The app is `LSUIElement=YES` (no Dock icon, menu-bar only).

- **FloatingIsland/** — The main UI surface. `FloatingPanel` is an `NSPanel` subclass (not a SwiftUI Window) configured as `nonactivatingPanel` + `floating` level so it never steals focus. `IslandContentView` (SwiftUI) is embedded via `NSHostingView` inside an `NSVisualEffectView` for the blur effect. `IslandDropDelegate` implements SwiftUI's `DropDelegate` to handle file drag-and-drop.

- **Services/** — `FileSyncService` copies dropped files to the target directory with Finder-style conflict renaming `(1), (2)...`. `SettingsManager` wraps `UserDefaults` / `@AppStorage` and persists the target directory as a **security-scoped bookmark** (required for Sandbox). `LaunchAtLoginService` wraps `SMAppService`.

- **MenuBar/** — `SettingsView` renders inside `MenuBarExtra(.window)` for configuration (directory picker, visibility toggle, quit).

- **Plugins/** — Extensibility layer for future integrations. `IslandPlugin` protocol defines the contract. `ClipboardMonitor` polls `NSPasteboard.general.changeCount` for URL detection. `FeishuPlugin` is a stub for Feishu/Lark file link auto-download.

### Key Design Decisions

- **NSPanel over SwiftUI Window**: `NSPanel` with `nonactivatingPanel` is the only way to have a floating overlay that doesn't steal focus from the user's active app. SwiftUI's `.windowLevel(.floating)` still activates the app.
- **Security-Scoped Bookmarks**: The sandboxed app stores the user-selected sync directory as a bookmark (`URL.bookmarkData(options: .withSecurityScope)`), not a path. Must call `startAccessingSecurityScopedResource()` before file operations.
- **`@AppStorage` is not a Combine publisher**: Observation in AppDelegate uses `UserDefaults.observe(_:options:)` (KVO), not `$property.sink`.
- **`DragAcceptingHostingView`**: Custom `NSHostingView` subclass that overrides `acceptsFirstMouse(for:)` → `true`, required for the panel to accept drag-and-drop from other apps.
- **`@MainActor` on services**: `FileSyncService` and `PluginManager` are `@MainActor`-isolated. When referencing their properties from closures, use `MainActor.assumeIsolated {}` or `Task { @MainActor in }`.

### Data Flow

```
File drag → NSPanel → SwiftUI DropDelegate → FileSyncService.syncFiles() → FileManager.copyItem
                                                ↑
Clipboard URL → ClipboardMonitor → PluginManager → IslandPlugin.handleInput() → [URL]
```
