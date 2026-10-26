import SwiftUI
import AppKit

/// Text shown in the menu bar. Built as a single string so it renders cleanly in the status item.
struct MenuBarLabel: View {
    @ObservedObject var monitor: SystemMonitor

    @AppStorage(Prefs.mbIcon) private var showIcon = true
    @AppStorage(Prefs.mbCPU) private var showCPU = true
    @AppStorage(Prefs.mbMemory) private var showMemory = false
    @AppStorage(Prefs.mbNetwork) private var showNetwork = true
    @AppStorage(Prefs.mbBattery) private var showBattery = false
    @AppStorage(Prefs.mbPower) private var showPower = false
    @AppStorage(Prefs.mbDisk) private var showDisk = false
    @AppStorage(Prefs.networkInBits) private var inBits = false

    var body: some View {
        let text = composed
        if text.isEmpty {
            Image(systemName: icon)
        } else if showIcon {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(text).monospacedDigit()
            }
        } else {
            Text(text).monospacedDigit()
        }
    }

    private var icon: String {
        switch monitor.overallStatus {
        case .healthy: return "gauge.with.dots.needle.33percent"
        case .attention: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    private var composed: String {
        var parts: [String] = []
        if showCPU { parts.append("CPU \(Fmt.percent(monitor.cpu.total))") }
        if showMemory { parts.append("MEM \(Fmt.percent(monitor.memory.usedFraction))") }
        if showDisk, let root = monitor.volumes.first {
            parts.append("SSD \(Fmt.disk(root.available))")
        }
        if showNetwork {
            parts.append("↓\(Fmt.compactRate(monitor.network.downRate, bits: inBits)) ↑\(Fmt.compactRate(monitor.network.upRate, bits: inBits))")
        }
        if showBattery, monitor.battery.present {
            parts.append("\(monitor.battery.isCharging ? "⚡︎" : "")\(monitor.battery.percent)%")
        }
        if showPower, let w = monitor.history.power.last, w > 0 {
            parts.append(String(format: "%.1fW", w))
        }
        return parts.joined(separator: "  ")
    }
}

/// The panel that drops down from the menu bar item.
struct MenuPopoverView: View {
    @EnvironmentObject var m: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    @AppStorage(Prefs.showCPU) private var showCPU = true
    @AppStorage(Prefs.showMemory) private var showMemory = true
    @AppStorage(Prefs.showDisk) private var showDisk = true
    @AppStorage(Prefs.showPower) private var showPower = true
    @AppStorage(Prefs.showNetwork) private var showNetwork = true
    @AppStorage(Prefs.networkInBits) private var inBits = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.system.model.isEmpty ? "System Monitor" : m.system.model).font(.headline).lineLimit(1)
                    Text("Up \(Fmt.duration(m.system.uptime)) · Thermal \(m.system.thermalState.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: m.overallStatus)
            }

            if !m.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(m.issues.prefix(3)) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(issue.level == .critical ? Color.red : Color.orange)
                    }
                }
            }

            Divider()

            if showCPU {
                CompactRow(icon: "cpu", title: "CPU", tint: .cpuTint,
                           value: Fmt.percent(m.cpu.total),
                           subtitle: String(format: "Load %.2f", m.cpu.load1)) {
                    Sparkline(values: m.history.cpu, maxValue: 1, tint: .cpuTint)
                }
            }
            if showMemory {
                CompactRow(icon: "memorychip", title: "Memory", tint: .memoryTint,
                           value: Fmt.percent(m.memory.usedFraction),
                           subtitle: "\(Fmt.bytes(m.memory.used)) of \(Fmt.bytes(m.memory.total))") {
                    Sparkline(values: m.history.memory, maxValue: 1, tint: .memoryTint)
                }
            }
            if showDisk, let root = m.volumes.first {
                CompactRow(icon: "internaldrive", title: root.name, tint: .diskTint,
                           value: Fmt.percent(root.usedFraction),
                           subtitle: "\(Fmt.disk(root.available)) free · SMART \(m.diskHealth.smartStatus)") {
                    BarMeter(fraction: root.usedFraction, tint: .diskTint).frame(maxHeight: .infinity)
                }
            }
            if showPower {
                let b = m.battery
                CompactRow(icon: b.isCharging ? "battery.100.bolt" : (b.present ? "battery.75" : "powerplug"),
                           title: b.present ? "Battery" : "Power", tint: .powerTint,
                           value: b.present ? "\(b.percent)%" : (b.systemPowerW.map(Fmt.watts) ?? "AC"),
                           subtitle: powerSubtitle(b)) {
                    Sparkline(values: m.history.power, tint: .powerTint)
                }
            }
            if showNetwork {
                CompactRow(icon: "network", title: "Network", tint: .networkTint,
                           value: "↓ \(Fmt.rate(m.network.downRate, bits: inBits))",
                           subtitle: "↑ \(Fmt.rate(m.network.upRate, bits: inBits)) · \(m.network.primaryInterface ?? "offline")") {
                    let top = max(m.history.netDown.max() ?? 0, m.history.netUp.max() ?? 0, 1024)
                    ZStack {
                        Sparkline(values: m.history.netDown, maxValue: top, tint: .networkTint)
                        Sparkline(values: m.history.netUp, maxValue: top, tint: .uploadTint, filled: false)
                    }
                }
            }

            Divider()

            HStack {
                Button("Open Dashboard") { open("dashboard") }
                    .keyboardShortcut("d")
                Button("Customize…") { open("settings") }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }

    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func powerSubtitle(_ b: BatteryMetrics) -> String {
        guard b.present else { return "No battery" }
        var parts = [b.stateText]
        if let h = b.healthFraction { parts.append("Health \(Fmt.percent(h))") }
        if let c = b.cycleCount { parts.append("\(c) cycles") }
        return parts.joined(separator: " · ")
    }
}

struct CompactRow<Graph: View>: View {
    var icon: String
    var title: String
    var tint: Color
    var value: String
    var subtitle: String
    @ViewBuilder var graph: Graph

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    Text(value).font(.system(.callout, design: .rounded).weight(.semibold)).monospacedDigit()
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            graph.frame(width: 70, height: 24)
        }
    }
}
