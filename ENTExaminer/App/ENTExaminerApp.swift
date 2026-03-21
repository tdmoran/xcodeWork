import SwiftUI
#if os(macOS)
import AppKit
#endif

private func appDebugLog(_ message: String) {
    let url = URL(fileURLWithPath: "/tmp/entexaminer_debug.log")
    let line = "\(Date()): \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: url)
        }
    }
}

@main
struct ENTExaminerApp: App {
    @State private var appState = AppState()

    init() {
        appDebugLog("ENTExaminerApp initialized")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 650)
                .onAppear {
                    appDebugLog("ContentView appeared")
                    let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns")
                        ?? Self.findIconPath()
                    if let path = iconPath, let icon = NSImage(contentsOfFile: path) {
                        NSApplication.shared.applicationIconImage = icon
                    }
                }
                #endif
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 750)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
        }
        #endif
    }

    #if os(macOS)
    /// Walks up from the executable to find the icon in the source tree.
    private static func findIconPath() -> String? {
        // When run via `swift run`, the executable is deep in .build/
        // Walk up to find the project root and look for the icon there
        var url = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        for _ in 0..<10 {
            url = url.deletingLastPathComponent()
            let candidate = url.appendingPathComponent("ENTExaminer/Resources/AppIcon.icns")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return nil
    }
    #endif
}
