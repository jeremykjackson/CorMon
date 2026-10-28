import SwiftUI
import AppKit

/// The menu bar item: a white heart-monitor glyph plus any readouts the user picked.
/// It observes only the small MenuBarModel, so it redraws only when its text changes.
struct MenuBarLabel: View {
    @ObservedObject var model: MenuBarModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.mbIcon) private var showIcon = true

    var body: some View {
        let text = model.text
        Group {
            if text.isEmpty || showIcon {
                HStack(spacing: 4) {
                    Image(nsImage: model.alert ? HeartMonitorGlyph.alert : HeartMonitorGlyph.normal)
                    if !text.isEmpty { Text(text).monospacedDigit() }
                }
            } else {
                Text(text).monospacedDigit()
            }
        }
        .onAppear { WindowRouter.shared.register(openWindow) }
    }
}

/// The panel that drops down from the menu bar item.
struct MenuPopoverView: View {
    // Re-render this window's root when the look changes (see Appearance).
    @AppStorage(Prefs.appearance) private var appearanceRaw = Appearance.gallery.rawValue
    @EnvironmentObject var m: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    @AppStorage(Prefs.showCPU) private var showCPU = true
    @AppStorage(Prefs.showMemory) private var showMemory = true
    @AppStorage(Prefs.showDisk) private var showDisk = true
    @AppStorage(Prefs.showPower) private var showPower = true
    @AppStorage(Prefs.showNetwork) private var showNetwork = true
    @AppStorage(Prefs.showApps) private var showApps = true
    @AppStorage(Prefs.networkInBits) private var inBits = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    BrandTitle(size: 20)
                    Text(m.system.model.isEmpty ? "System Monitor" : m.system.model)
                        .font(Typo.titleItalic(12)).foregroundStyle(Palette.ivory).lineLimit(1)
                    Text("Up \(Fmt.duration(m.system.uptime)) · Thermal \(m.system.thermalState.label)")
                        .font(Typo.caption()).foregroundStyle(Palette.parchment)
                }
                Spacer()
                StatusPill(status: m.overallStatus)
            }

            if !m.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(m.issues.prefix(3)) { issue in
                        Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                            .font(Typo.body(11.5, .medium))
                            .foregroundStyle(issue.level == .critical ? Palette.danger : Palette.warn)
                    }
                }
            }

            Fleuron()

            if showCPU {
                CompactRow(icon: "cpu", title: "Processor", tint: .cpuTint,
                           value: Fmt.percent(m.cpu.total),
                           subtitle: String(format: "load %.2f", m.cpu.load1)) {
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
            if showApps {
                Fleuron()
                HStack(alignment: .top, spacing: 14) {
                    AppList(title: "Top processor", apps: Array(m.topCPU.prefix(3)), metric: .cpu, compact: true)
                    AppList(title: "Top memory", apps: Array(m.topMemory.prefix(3)), metric: .memory, compact: true)
                }
            }

            Fleuron()

            HStack(spacing: 14) {
                Button("Dashboard") { open("dashboard") }
                    .keyboardShortcut("d")
                Button("Glance") { GlancePanelController.shared.toggle() }
                    .keyboardShortcut("g")
                Button("Customize…") { open("settings") }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .font(Typo.body(12.5, .medium))
            .foregroundStyle(Palette.gilt)
        }
        .padding(16)
        .frame(width: 360)
        .background(CanvasBackground())
        .cormonStyle()
        .onAppear {
            WindowRouter.shared.register(openWindow)
            m.setViewer("menu", visible: true)
        }
        .onDisappear { m.setViewer("menu", visible: false) }
    }

    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func powerSubtitle(_ b: BatteryMetrics) -> String {
        guard b.present else { return "No battery" }
        var parts = [b.stateText]
        if let h = b.healthFraction { parts.append("health \(Fmt.percent(h))") }
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
            IconBadge(symbol: icon, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(Typo.title(14)).foregroundStyle(Palette.ivory).lineLimit(1)
                    Spacer()
                    Text(value).font(Typo.numeral(13.5)).foregroundStyle(Palette.ivory)
                }
                Text(subtitle).font(Typo.titleItalic(11.5)).foregroundStyle(Palette.parchment).lineLimit(1)
            }
            ChartWell(height: 26) { graph }
                .frame(width: 74)
        }
    }
}
