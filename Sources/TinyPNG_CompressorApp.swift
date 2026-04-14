import SwiftUI

@main
struct 轻图pngApp: App {
    @StateObject private var viewModel = CompressorViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.checkAPIKeyOnLaunch()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 820, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 确保窗口在前台并激活
        if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // 应用被激活时（如从 Dock 点击），确保窗口显示
        if let window = NSApplication.shared.windows.first, !window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
