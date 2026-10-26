import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            DashboardSettings()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            MenuBarSettings()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            AlertSettings()
                .tabItem { Label("Alerts", systemImage: "exclamationmark.triangle") }
        }
        .frame(width: 500, height: 420)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage(Prefs.refreshInterval) private var refreshInterval = 2.0
    @AppStorage(Prefs.showDockIcon) private var showDockIcon = true
    @AppStorage(Prefs.useFahrenheit) private var useFahrenheit = false
    @AppStorage(Prefs.networkInBits) private var networkInBits = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Updates") {
                Picker("Refresh every", selection: $refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                }
                .onChange(of: refreshInterval) { value in monitor.start(interval: value) }
            }
            Section("App") {
                Toggle("Show icon in Dock", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { show in
                        NSApp.setActivationPolicy(show ? .regular : .accessory)
                        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
                    }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
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
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        let isEnabled = service.status == .enabled
        guard enabled != isEnabled else { return }
        do {
            if enabled { try service.register() } else { try service.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription). Run the app from the built .app bundle."
            launchAtLogin = service.status == .enabled
        }
    }
}

struct DashboardSettings: View {
    @AppStorage(Prefs.showSystem) private var showSystem = true
    @AppStorage(Prefs.showCPU) private var showCPU = true
    @AppStorage(Prefs.showMemory) private var showMemory = true
    @AppStorage(Prefs.showDisk) private var showDisk = true
    @AppStorage(Prefs.showPower) private var showPower = true
    @AppStorage(Prefs.showNetwork) private var showNetwork = true
    @AppStorage(Prefs.showPerCore) private var showPerCore = true

    var body: some View {
        Form {
            Section {
                Toggle("System health summary", isOn: $showSystem)
                Toggle("CPU", isOn: $showCPU)
                Toggle("Show per-core usage", isOn: $showPerCore)
                    .padding(.leading, 18)
                    .disabled(!showCPU)
                Toggle("Memory", isOn: $showMemory)
                Toggle("Disk usage & health", isOn: $showDisk)
                Toggle("Power & battery", isOn: $showPower)
                Toggle("Network", isOn: $showNetwork)
            } header: {
                Text("Sections")
            } footer: {
                Text("Hidden sections are also removed from the menu bar panel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section {
                Toggle("Status icon", isOn: $mbIcon)
                Toggle("CPU usage", isOn: $mbCPU)
                Toggle("Memory usage", isOn: $mbMemory)
                Toggle("Network speed (↓ / ↑)", isOn: $mbNetwork)
                Toggle("Battery percentage", isOn: $mbBattery)
                Toggle("Power draw (watts)", isOn: $mbPower)
                Toggle("Free disk space", isOn: $mbDisk)
            } header: {
                Text("Show in menu bar")
            } footer: {
                Text("The icon turns into a warning symbol when any health alert is active.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct AlertSettings: View {
    @EnvironmentObject var monitor: SystemMonitor
    @AppStorage(Prefs.cpuWarn) private var cpuWarn = 85.0
    @AppStorage(Prefs.swapWarnGB) private var swapWarnGB = 4.0
    @AppStorage(Prefs.diskFreeWarn) private var diskFreeWarn = 10.0
    @AppStorage(Prefs.batteryHealthWarn) private var batteryHealthWarn = 80.0
    @AppStorage(Prefs.batteryTempWarn) private var batteryTempWarn = 40.0

    var body: some View {
        Form {
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
                Text("Memory pressure, SMART failures, SSD wear ≥ 80% and thermal throttling are always flagged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Defaults") {
                    cpuWarn = 85; swapWarnGB = 4; diskFreeWarn = 10
                    batteryHealthWarn = 80; batteryTempWarn = 40
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
