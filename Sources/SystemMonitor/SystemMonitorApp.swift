import SwiftUI
import AppKit

@main
struct CorMonApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // A plain reference, not @StateObject: the App itself must not observe the monitor,
    // or every sample would re-evaluate all scenes. Views observe it via environmentObject.
    private let monitor = SystemMonitor.shared

    init() {
        Prefs.registerDefaults()
    }

    var body: some Scene {
        Window("CorMon", id: "dashboard") {
            DashboardView()
                .environmentObject(monitor)
        }
        .defaultSize(width: 1120, height: 860)
        .commands {
            CommandGroup(replacing: .appSettings) { SettingsMenuButton() }
            CommandGroup(after: .windowArrangement) { GlanceMenuButton() }
        }

        Window("Customize CorMon", id: "settings") {
            SettingsView()
                .environmentObject(monitor)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuPopoverView()
                .environmentObject(monitor)
        } label: {
            MenuBarLabel(model: monitor.menuBar)
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

struct GlanceMenuButton: View {
    var body: some View {
        Button("Show Glance Panel") { GlancePanelController.shared.toggle() }
            .keyboardShortcut("g", modifiers: [.command, .shift])
    }
}

enum AppMode {
    /// Background mode: no Dock icon or app-switcher entry; CorMon lives in the menu bar
    /// and the hot corner, and keeps sampling while its windows are closed.
    static func apply(runInBackground: Bool, activate: Bool = true) {
        NSApp.setActivationPolicy(runInBackground ? .accessory : .regular)
        if activate && !runInBackground {
            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let background = UserDefaults.standard.bool(forKey: Prefs.runInBackground)
        AppMode.apply(runInBackground: background)
        SystemMonitor.shared.start()
        GlancePanelController.shared.startWatching()

        // In background mode, start quietly: close the dashboard SwiftUI opens at launch.
        if background {
            DispatchQueue.main.async {
                for window in NSApp.windows where window.identifier?.rawValue.contains("dashboard") == true {
                    window.close()
                }
            }
        }
    }

    // Keep running in the menu bar after the last window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // Clicking the Dock icon with no windows open brings the dashboard back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowRouter.shared.open("dashboard") }
        return true
    }
}
