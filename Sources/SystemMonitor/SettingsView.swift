import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    // Re-render this window's root when the look changes (see Appearance).
    @AppStorage(Prefs.appearance) private var appearanceRaw = Appearance.gallery.rawValue
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: HeartMonitorGlyph.normal)
                    .renderingMode(.template)
                    .foregroundStyle(Palette.giltLight)
                Text("Customize CorMon").font(Typo.title(22)).foregroundStyle(Palette.giltLight)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 8)

            TabView {
                GeneralSettings()
                    .tabItem { Label("General", systemImage: "gearshape") }
                GlanceSettings()
                    .tabItem { Label("Hot Corner", systemImage: "rectangle.on.rectangle") }
                DashboardSettings()
                    .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                MenuBarSettings()
                    .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                AlertSettings()
                    .tabItem { Label("Alerts", systemImage: "exclamationmark.triangle") }
            }
            .padding([.horizontal, .bottom], 14)
        }
        .frame(width: 560, height: 520)
        .background(CanvasBackground())
        .cormonStyle()
    }
}

/// Shared look for each settings page.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .font(Typo.body(13))
    }
}

private struct Footnote: View {
    var text: String
    var body: some View {
        Text(text).font(Typo.titleItalic(12)).foregroundStyle(Palette.parchment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage(Prefs.appearance) private var appearance = Appearance.gallery.rawValue
    @AppStorage(Prefs.refreshInterval) private var refreshInterval = 2.0
    @AppStorage(Prefs.runInBackground) private var runInBackground = false
    @AppStorage(Prefs.useFahrenheit) private var useFahrenheit = false
    @AppStorage(Prefs.networkInBits) private var networkInBits = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        SettingsPage {
            Section {
                Picker("Look", selection: $appearance) {
                    ForEach(Appearance.allCases) { look in
                        (Text(look.title) + Text("  ·  \(look.summary)").foregroundColor(Palette.parchment))
                            .tag(look.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Appearance")
            } footer: {
                Footnote(text: "Applies to the dashboard, menu bar panel, glance panel and this window. Gallery is always dark and Canvas always light; Mac Glass follows your Light/Dark setting and accent color.")
            }
            Section {
                Toggle("Run in the background", isOn: $runInBackground)
                    .onChange(of: runInBackground) { on in AppMode.apply(runInBackground: on) }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(Typo.caption()).foregroundStyle(Palette.danger)
                }
            } header: {
                Text("Running")
            } footer: {
                Footnote(text: "In the background CorMon has no Dock icon and starts without opening the dashboard. It keeps measuring and stays available from the menu bar and your hot corner. Combine with Launch at login to have it always on.")
            }
            Section("Updates") {
                Picker("Refresh every", selection: $refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
                .onChange(of: refreshInterval) { value in monitor.start(interval: value) }
            }
            Section("Units") {
                Picker("Temperature", selection: $useFahrenheit) {
                    Text("Celsius").tag(false)
                    Text("Fahrenheit").tag(true)
                }
                Picker("Network speed", selection: $networkInBits) {
                    Text("Bytes (MB/s)").tag(false)
                    Text("Bits (Mb/s)").tag(true)
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        guard enabled != (service.status == .enabled) else { return }
        do {
            if enabled { try service.register() } else { try service.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription). Run CorMon from the built .app (ideally in /Applications)."
            launchAtLogin = service.status == .enabled
        }
    }
}

struct GlanceSettings: View {
    @AppStorage(Prefs.glanceCorner) private var corner = GlanceCorner.bottomLeft.rawValue
    @AppStorage(Prefs.glanceDelay) private var delay = 0.35
    @AppStorage(Prefs.glanceShowApps) private var showApps = true

    var body: some View {
        SettingsPage {
            Section {
                Picker("Hot corner", selection: $corner) {
                    ForEach(GlanceCorner.allCases) { c in
                        Text(c.label).tag(c.rawValue)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Delay before opening")
                        Spacer()
                        Text(String(format: "%.2f s", delay)).font(Typo.numeral(12, .regular))
                            .foregroundStyle(Palette.parchment)
                    }
                    Slider(value: $delay, in: 0...1.5, step: 0.05)
                }
                .disabled(corner == GlanceCorner.off.rawValue)
                Toggle("Show busiest apps in the panel", isOn: $showApps)
                Button("Preview Glance Panel") { GlancePanelController.shared.toggle() }
            } header: {
                Text("At-a-glance panel")
            } footer: {
                Footnote(text: "Rest the pointer in the chosen corner to open a small panel with the essentials; it fades away when you move off it. You can also open it from the menu bar or with ⇧⌘G while CorMon is in front.")
            }
            Section {
                Footnote(text: "macOS only lists its own actions under Hot Corners, so CorMon watches the corner itself. If you've assigned a macOS action to the same corner, both will fire — clear it in System Settings › Desktop & Dock › Hot Corners.")
                Button("Open Desktop & Dock Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("Avoiding conflicts")
            }
        }
    }
}

struct DashboardSettings: View {
    @AppStorage(Prefs.showSystem) private var showSystem = true
    @AppStorage(Prefs.showCPU) private var showCPU = true
    @AppStorage(Prefs.showMemory) private var showMemory = true
    @AppStorage(Prefs.showApps) private var showApps = true
    @AppStorage(Prefs.showDisk) private var showDisk = true
    @AppStorage(Prefs.showPower) private var showPower = true
    @AppStorage(Prefs.showNetwork) private var showNetwork = true
    @AppStorage(Prefs.showPerCore) private var showPerCore = true
    @AppStorage(Prefs.groupApps) private var groupApps = true
    @AppStorage(Prefs.topAppCount) private var topAppCount = 5

    var body: some View {
        SettingsPage {
            Section {
                Toggle("System health summary", isOn: $showSystem)
                Toggle("Processor", isOn: $showCPU)
                Toggle("Show per-core usage", isOn: $showPerCore)
                    .padding(.leading, 18)
                    .disabled(!showCPU)
                Toggle("Memory", isOn: $showMemory)
                Toggle("Busiest apps", isOn: $showApps)
                Toggle("Storage usage & health", isOn: $showDisk)
                Toggle("Power & battery", isOn: $showPower)
                Toggle("Network", isOn: $showNetwork)
            } header: {
                Text("Sections")
            } footer: {
                Footnote(text: "Hidden sections are also removed from the menu bar panel.")
            }
            Section {
                Stepper(value: $topAppCount, in: 3...12) {
                    HStack {
                        Text("Apps listed")
                        Spacer()
                        Text("\(topAppCount)").font(Typo.numeral(13, .regular)).foregroundStyle(Palette.parchment)
                    }
                }
                Toggle("Group helper processes into their app", isOn: $groupApps)
            } header: {
                Text("Busiest apps")
            } footer: {
                Footnote(text: "Processor is shown per core, like Activity Monitor (200% = two cores busy). Memory is each app's real footprint. Only processes you own are listed; system daemons need administrator rights to read.")
            }
        }
    }
}

struct MenuBarSettings: View {
    @AppStorage(Prefs.mbIcon) private var mbIcon = true
    @AppStorage(Prefs.mbCPU) private var mbCPU = true
    @AppStorage(Prefs.mbMemory) private var mbMemory = false
    @AppStorage(Prefs.mbNetwork) private var mbNetwork = true
    @AppStorage(Prefs.mbBattery) private var mbBattery = false
    @AppStorage(Prefs.mbPower) private var mbPower = false
    @AppStorage(Prefs.mbDisk) private var mbDisk = false

    var body: some View {
        SettingsPage {
            Section {
                Toggle("Heart-monitor icon", isOn: $mbIcon)
                Toggle("CPU usage", isOn: $mbCPU)
                Toggle("Memory usage", isOn: $mbMemory)
                Toggle("Network speed (↓ / ↑)", isOn: $mbNetwork)
                Toggle("Battery percentage", isOn: $mbBattery)
                Toggle("Power draw (watts)", isOn: $mbPower)
                Toggle("Free disk space", isOn: $mbDisk)
            } header: {
                Text("Show in menu bar")
            } footer: {
                Footnote(text: "A dot appears on the heart monitor when any health alert is active. The icon is always shown if nothing else is selected.")
            }
        }
    }
}

struct AlertSettings: View {
    @AppStorage(Prefs.cpuWarn) private var cpuWarn = 85.0
    @AppStorage(Prefs.swapWarnGB) private var swapWarnGB = 4.0
    @AppStorage(Prefs.diskFreeWarn) private var diskFreeWarn = 10.0
    @AppStorage(Prefs.batteryHealthWarn) private var batteryHealthWarn = 80.0
    @AppStorage(Prefs.batteryTempWarn) private var batteryTempWarn = 40.0

    var body: some View {
        SettingsPage {
            Section {
                Stepper(value: $cpuWarn, in: 50...100, step: 5) {
                    row("Sustained CPU load above", "\(Int(cpuWarn))%")
                }
                Stepper(value: $swapWarnGB, in: 1...32, step: 1) {
                    row("Swap usage above", "\(Int(swapWarnGB)) GB")
                }
                Stepper(value: $diskFreeWarn, in: 5...50, step: 5) {
                    row("Free disk space below", "\(Int(diskFreeWarn))%")
                }
                Stepper(value: $batteryHealthWarn, in: 50...95, step: 5) {
                    row("Battery health below", "\(Int(batteryHealthWarn))%")
                }
                Stepper(value: $batteryTempWarn, in: 30...50, step: 1) {
                    row("Battery temperature above", "\(Int(batteryTempWarn)) °C")
                }
            } header: {
                Text("Flag a health issue when…")
            } footer: {
                Footnote(text: "Memory pressure, SMART failures, SSD wear ≥ 80% and thermal throttling are always flagged.")
            }
            Section {
                Button("Restore Defaults") {
                    cpuWarn = 85; swapWarnGB = 4; diskFreeWarn = 10
                    batteryHealthWarn = 80; batteryTempWarn = 40
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).font(Typo.numeral(13, .regular)).foregroundStyle(Palette.parchment)
        }
    }
}
