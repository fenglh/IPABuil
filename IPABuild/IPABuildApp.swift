import SwiftUI
import AppKit

@main
struct IPABuildApp: App {
    init() {
        DingTalkReminderManager.shared.start()
    }
    
    var body: some Scene {
        WindowGroup("证书管理", id: "mainWindow") {
            ContentView()
        }
        #if os(macOS)
        if #available(macOS 13.0, *) {
            MenuBarExtra("证书管理", systemImage: "lock.shield") {
                MenuBarControls()
            }
        }
        #endif
    }
}

@available(macOS 13.0, *)
private struct MenuBarControls: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        Button("打开证书管理") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "mainWindow")
        }
        Divider()
        Button("退出证书管理") {
            NSApplication.shared.terminate(nil)
        }
    }
}
