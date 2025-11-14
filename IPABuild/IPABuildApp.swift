import SwiftUI
import AppKit

@main
struct IPABuildApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        if #available(macOS 13.0, *) {
            MenuBarExtra("证书管理", systemImage: "lock.shield") {
                Button("打开证书管理") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
                }
                Divider()
                Button("退出证书管理") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        #endif
    }
}
