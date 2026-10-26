import SwiftUI
import AppKit

@main
struct SystemMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = SystemMonitor.shared

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        Window("System Monitor", id: "dashboard") {
            DashboardView()
                .environmentObject(monitor)
        }
        .defaultSize(width: 1080, height: 820)
        .commands {
            CommandGroup(replacing: .appSettings) { SettingsMenuButton() }
        }

        Window("Customize System Monitor", id: "settings") {
            SettingsView()
                .environmentObject(monitor)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuPopoverView()
                .environmentObject(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

struct SettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let showDock = UserDefaults.standard.bool(forKey: Prefs.showDockIcon)
        NSApp.setActivationPolicy(showDock ? .regular : .accessory)
        if showDock { NSApp.activate(ignoringOtherApps: true) }
        SystemMonitor.shared.start()
    }

    // Keep running in the menu bar after the dashboard window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
