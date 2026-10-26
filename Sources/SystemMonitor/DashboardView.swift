import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    @AppStorage(Prefs.showSystem) private var showSystem = true
    @AppStorage(Prefs.showCPU) private var showCPU = true
    @AppStorage(Prefs.showMemory) private var showMemory = true
    @AppStorage(Prefs.showDisk) private var showDisk = true
    @AppStorage(Prefs.showPower) private var showPower = true
    @AppStorage(Prefs.showNetwork) private var showNetwork = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showSystem { SystemHeader() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)],
                          alignment: .leading, spacing: 16) {
                    if showCPU { CPUCard() }
                    if showMemory { MemoryCard() }
                    if showPower { PowerCard() }
                    if showNetwork { NetworkCard() }
                    if showDisk { DiskCard() }
                }
                if !(showSystem || showCPU || showMemory || showDisk || showPower || showNetwork) {
                    Text("All sections are hidden. Turn some on in Settings.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 420, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
                .help("Choose metrics, menu bar items and alert thresholds")
            }
        }
    }
}

// MARK: - Header

struct SystemHeader: View {
    @EnvironmentObject var m: SystemMonitor

    var body: some View {
        let s = m.system
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.model.isEmpty ? "Mac" : s.model).font(.title2.weight(.semibold))
                    Text([s.chip, s.osVersion, s.hostName].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: m.overallStatus)
            }

            HStack(spacing: 24) {
                headerStat("Uptime", Fmt.duration(s.uptime))
                headerStat("Thermal", s.thermalState.label, color: s.thermalState.color)
                headerStat("CPU", Fmt.percent(m.cpu.total))
                headerStat("Memory", Fmt.percent(m.memory.usedFraction))
                if m.battery.present { headerStat("Battery", "\(m.battery.percent)%") }
                Spacer()
            }

            if m.issues.isEmpty {
                Label("All monitored metrics are within normal ranges.", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(m.issues) { issue in
                        Label(issue.message,
                              systemImage: issue.level == .critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(issue.level == .critical ? Color.red : Color.orange)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(m.overallStatus.color.opacity(m.issues.isEmpty ? 0.07 : 0.4)))
    }

    private func headerStat(_ label: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(color ?? .primary)
        }
    }
}

// MARK: - CPU

struct CPUCard: View {
    @EnvironmentObject var m: SystemMonitor
    @AppStorage(Prefs.showPerCore) private var showPerCore = true
    @AppStorage(Prefs.cpuWarn) private var cpuWarn = 85.0

    var body: some View {
        let c = m.cpu
        let tint = loadColor(c.total, warn: cpuWarn / 100 * 0.85, critical: cpuWarn / 100, base: .cpuTint)
        Card(title: "CPU", icon: "cpu", tint: .cpuTint, detail: coreSummary(c)) {
            HStack(spacing: 18) {
                RingGauge(fraction: c.total, tint: tint) {
                    BigValue(value: Fmt.percent(c.total), caption: "in use")
                }
                .frame(width: 104, height: 104)
                StatGrid(stats: [
                    Stat(label: "User", value: Fmt.percent(c.user, digits: 1)),
                    Stat(label: "System", value: Fmt.percent(c.system, digits: 1)),
                    Stat(label: "Idle", value: Fmt.percent(max(0, 1 - c.total), digits: 1)),
                    Stat(label: "Load (1/5/15m)", value: String(format: "%.2f  %.2f  %.2f", c.load1, c.load5, c.load15))
                ])
            }
            Sparkline(values: m.history.cpu, maxValue: 1, tint: .cpuTint).frame(height: 44)
            if showPerCore && !c.perCore.isEmpty {
                PerCoreBars(values: c.perCore, efficiencyCount: c.efficiencyCores ?? 0)
            }
        }
    }

    private func coreSummary(_ c: CPUMetrics) -> String {
        if let p = c.performanceCores, let e = c.efficiencyCores, e > 0 {
            return "\(c.brand.replacingOccurrences(of: "Apple ", with: "")) · \(p)P + \(e)E"
        }
        return "\(c.coreCount) cores"
    }
}

struct PerCoreBars: View {
    var values: [Double]
    var efficiencyCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "Per core")
                Spacer()
                if efficiencyCount > 0 {
                    LegendDot(color: .cyan, text: "Efficiency")
                    LegendDot(color: .cpuTint, text: "Performance")
                }
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    let tint: Color = i < efficiencyCount ? .cyan : .cpuTint
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.12))
                        RoundedRectangle(cornerRadius: 2).fill(tint)
                            .frame(height: max(2, 34 * min(values[i], 1)))
                            .animation(.easeOut(duration: 0.3), value: values[i])
                    }
                    .frame(height: 34)
                    .frame(maxWidth: .infinity)
                    .help("Core \(i): \(Fmt.percent(values[i]))")
                }
            }
        }
    }
}

// MARK: - Memory

struct MemoryCard: View {
    @EnvironmentObject var m: SystemMonitor

    var body: some View {
        let mem = m.memory
        let pressure = pressureInfo(mem.pressureLevel)
        Card(title: "Memory", icon: "memorychip", tint: .memoryTint, detail: "\(Fmt.bytes(mem.total)) installed") {
            HStack(spacing: 18) {
                RingGauge(fraction: mem.usedFraction, tint: pressure.color == .green ? .memoryTint : pressure.color) {
                    BigValue(value: Fmt.percent(mem.usedFraction), caption: "used")
                }
                .frame(width: 104, height: 104)
                StatGrid(stats: [
                    Stat(label: "Used", value: Fmt.bytes(mem.used)),
                    Stat(label: "Pressure", value: pressure.label, color: pressure.color),
                    Stat(label: "Cached files", value: Fmt.bytes(mem.cached)),
                    Stat(label: "Swap used", value: mem.swapTotal > 0 ? Fmt.bytes(mem.swapUsed) : "None")
                ])
            }
            let total = Double(max(mem.total, 1))
            VStack(alignment: .leading, spacing: 6) {
                SegmentedBar(segments: [
                    (Double(mem.app) / total, .memoryTint),
                    (Double(mem.wired) / total, .indigo),
                    (Double(mem.compressed) / total, .pink)
                ])
                HStack(spacing: 12) {
                    LegendDot(color: .memoryTint, text: "App \(Fmt.bytes(mem.app))")
                    LegendDot(color: .indigo, text: "Wired \(Fmt.bytes(mem.wired))")
                    LegendDot(color: .pink, text: "Compressed \(Fmt.bytes(mem.compressed))")
                }
            }
            Sparkline(values: m.history.memory, maxValue: 1, tint: .memoryTint).frame(height: 36)
        }
    }

    private func pressureInfo(_ level: Int) -> (label: String, color: Color) {
        switch level {
        case 4: return ("Critical", .red)
        case 2: return ("Elevated", .orange)
        default: return ("Normal", .green)
        }
    }
}

// MARK: - Disk

struct DiskCard: View {
    @EnvironmentObject var m: SystemMonitor
    @AppStorage(Prefs.diskFreeWarn) private var diskFreeWarn = 10.0

    var body: some View {
        let h = m.diskHealth
        Card(title: "Disk", icon: "internaldrive", tint: .diskTint, detail: h.mediaName.isEmpty ? nil : h.mediaName) {
            if m.volumes.isEmpty {
                Text("Reading volumes…").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(m.volumes) { v in
                let lowSpace = v.freeFraction * 100 < diskFreeWarn
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: v.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                            .foregroundStyle(.secondary).font(.caption)
                        Text(v.name).font(.callout.weight(.medium))
                        Spacer()
                        Text("\(Fmt.disk(v.available)) free of \(Fmt.disk(v.total))")
                            .font(.caption).foregroundStyle(lowSpace ? Color.red : .secondary).monospacedDigit()
                    }
                    BarMeter(fraction: v.usedFraction, tint: lowSpace ? .red : .diskTint, height: 7)
                }
            }

            Divider()
            SectionLabel(text: "Activity")
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    LegendDot(color: .diskTint, text: "Read")
                    Text(Fmt.rate(m.diskIO.readRate, bits: false)).font(.callout.weight(.medium)).monospacedDigit()
                }
                .frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    LegendDot(color: .red, text: "Write")
                    Text(Fmt.rate(m.diskIO.writeRate, bits: false)).font(.callout.weight(.medium)).monospacedDigit()
                }
                .frame(width: 90, alignment: .leading)
                let top = max(m.history.diskRead.max() ?? 0, m.history.diskWrite.max() ?? 0, 1)
                ZStack {
                    Sparkline(values: m.history.diskRead, maxValue: top, tint: .diskTint)
                    Sparkline(values: m.history.diskWrite, maxValue: top, tint: .red, filled: false)
                }
                .frame(height: 34)
            }

            Divider()
            HStack {
                SectionLabel(text: "Drive health")
                Spacer()
                Button {
                    m.refreshDiskHealth()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Re-check drive health")
            }
            StatGrid(stats: healthStats(h), columns: 3)
            if h.checked && !h.smartctlAvailable {
                Text("For SSD wear, data written and power-on hours, install smartmontools: `brew install smartmontools`")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func healthStats(_ h: DiskHealth) -> [Stat] {
        let status = h.smartStatus
        let statusColor: Color = status == "Verified" ? .green : (status.lowercased().contains("fail") ? .red : .secondary)
        var stats = [Stat(label: "SMART status", value: h.checked ? status : "Checking…", color: statusColor)]
        if let wear = h.wearPercent {
            stats.append(Stat(label: "Life used", value: "\(wear)%", color: wear >= 80 ? .orange : nil))
        }
        if let spare = h.availableSpare { stats.append(Stat(label: "Spare", value: "\(spare)%")) }
        if let w = h.dataWritten { stats.append(Stat(label: "Written", value: Fmt.disk(w))) }
        if let r = h.dataRead { stats.append(Stat(label: "Read", value: Fmt.disk(r))) }
        if let hours = h.powerOnHours { stats.append(Stat(label: "Power-on", value: "\(hours.formatted()) h")) }
        if let c = h.powerCycles { stats.append(Stat(label: "Power cycles", value: c.formatted())) }
        if let u = h.unsafeShutdowns { stats.append(Stat(label: "Unsafe shutdowns", value: u.formatted())) }
        if let e = h.mediaErrors { stats.append(Stat(label: "Media errors", value: "\(e)", color: e > 0 ? .red : nil)) }
        return stats
    }
}

// MARK: - Power

struct PowerCard: View {
    @EnvironmentObject var m: SystemMonitor
    @AppStorage(Prefs.useFahrenheit) private var useFahrenheit = false
    @AppStorage(Prefs.batteryHealthWarn) private var healthWarn = 80.0

    var body: some View {
        let b = m.battery
        Card(title: "Power", icon: batteryIcon(b), tint: .powerTint, detail: b.present ? b.stateText : "AC Power") {
            if b.present {
                HStack(spacing: 18) {
                    RingGauge(fraction: Double(b.percent) / 100,
                              tint: b.percent <= 15 && !b.externalConnected ? .red : .powerTint) {
                        BigValue(value: "\(b.percent)%", caption: timeCaption(b))
                    }
                    .frame(width: 104, height: 104)
                    StatGrid(stats: primaryStats(b))
                }
                Divider()
                StatGrid(stats: detailStats(b), columns: 3)
            } else {
                Text("No internal battery detected.").font(.callout).foregroundStyle(.secondary)
                StatGrid(stats: detailStats(b), columns: 3)
            }
            if m.history.power.contains(where: { $0 > 0 }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SectionLabel(text: "Power draw")
                        Spacer()
                        Text("peak \(Fmt.watts(m.history.power.max() ?? 0))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Sparkline(values: m.history.power, tint: .powerTint).frame(height: 36)
                }
            }
        }
    }

    private func batteryIcon(_ b: BatteryMetrics) -> String {
        guard b.present else { return "powerplug" }
        if b.isCharging { return "battery.100.bolt" }
        switch b.percent {
        case 76...: return "battery.100"
        case 51...75: return "battery.75"
        case 26...50: return "battery.50"
        case 11...25: return "battery.25"
        default: return "battery.0"
        }
    }

    private func timeCaption(_ b: BatteryMetrics) -> String {
        if let mins = b.minutesRemaining { return b.isCharging ? "\(Fmt.minutes(mins)) to full" : "\(Fmt.minutes(mins)) left" }
        return b.stateText.lowercased()
    }

    private func primaryStats(_ b: BatteryMetrics) -> [Stat] {
        var stats: [Stat] = []
        if let health = b.healthFraction {
            stats.append(Stat(label: "Health", value: Fmt.percent(health),
                              color: health * 100 < healthWarn ? .orange : .green))
        }
        stats.append(Stat(label: "Condition", value: b.condition ?? "—",
                          color: (b.condition ?? "Good") == "Good" ? nil : .orange))
        if let cycles = b.cycleCount { stats.append(Stat(label: "Cycle count", value: "\(cycles)")) }
        if let t = b.temperatureC {
            stats.append(Stat(label: "Temperature", value: Fmt.temperature(t, fahrenheit: useFahrenheit)))
        }
        return stats
    }

    private func detailStats(_ b: BatteryMetrics) -> [Stat] {
        var stats: [Stat] = []
        if let maxC = b.maxCapacity, let design = b.designCapacity {
            stats.append(Stat(label: "Full charge", value: "\(maxC) / \(design) mAh"))
        }
        if let cur = b.currentCapacity { stats.append(Stat(label: "Remaining", value: "\(cur) mAh")) }
        if let v = b.voltage { stats.append(Stat(label: "Voltage", value: String(format: "%.2f V", v))) }
        if let p = b.batteryPowerW, b.present {
            stats.append(Stat(label: p < 0 ? "Battery out" : "Battery in", value: Fmt.watts(abs(p))))
        }
        if let sys = b.systemPowerW { stats.append(Stat(label: "System power", value: Fmt.watts(sys))) }
        if b.externalConnected {
            let adapter = [b.adapterWatts.map { "\($0) W" }, b.adapterName].compactMap { $0 }.joined(separator: " ")
            stats.append(Stat(label: "Adapter", value: adapter.isEmpty ? "Connected" : adapter))
        }
        stats.append(Stat(label: "Low Power Mode", value: b.lowPowerMode ? "On" : "Off"))
        return stats
    }
}

// MARK: - Network

struct NetworkCard: View {
    @EnvironmentObject var m: SystemMonitor
    @AppStorage(Prefs.networkInBits) private var inBits = false

    var body: some View {
        let n = m.network
        Card(title: "Network", icon: "network", tint: .networkTint, detail: interfaceSummary(n)) {
            HStack(spacing: 20) {
                rateBlock(symbol: "arrow.down", label: "Download", rate: n.downRate, tint: .networkTint)
                rateBlock(symbol: "arrow.up", label: "Upload", rate: n.upRate, tint: .uploadTint)
                Spacer()
            }
            let top = max(m.history.netDown.max() ?? 0, m.history.netUp.max() ?? 0, 1024)
            ZStack {
                Sparkline(values: m.history.netDown, maxValue: top, tint: .networkTint)
                Sparkline(values: m.history.netUp, maxValue: top, tint: .uploadTint, filled: false)
            }
            .frame(height: 48)

            StatGrid(stats: [
                Stat(label: "Session ↓ / ↑", value: "\(Fmt.disk(n.sessionDown)) / \(Fmt.disk(n.sessionUp))"),
                Stat(label: "Since boot ↓ / ↑", value: "\(Fmt.disk(n.bootDown)) / \(Fmt.disk(n.bootUp))"),
                Stat(label: "Local IP", value: n.localIP ?? "Not connected"),
                Stat(label: "Wi-Fi signal", value: wifiText(n), color: wifiColor(n.wifiRSSI))
            ])
            if let noise = n.wifiNoise, let rssi = n.wifiRSSI {
                StatGrid(stats: [
                    Stat(label: "SNR", value: "\(rssi - noise) dB"),
                    Stat(label: "Noise", value: "\(noise) dBm"),
                    Stat(label: "Link rate", value: n.wifiTxRate.map { String(format: "%.0f Mbps", $0) } ?? "—")
                ], columns: 3)
            }
        }
    }

    private func rateBlock(symbol: String, label: String, rate: Double, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(Fmt.rate(rate, bits: inBits))
                    .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
            }
        }
    }

    private func interfaceSummary(_ n: NetworkMetrics) -> String? {
        guard let iface = n.primaryInterface else { return "Offline" }
        if iface == n.wifiInterface { return "Wi-Fi (\(iface))" }
        return iface
    }

    private func wifiText(_ n: NetworkMetrics) -> String {
        guard let rssi = n.wifiRSSI else { return "Off / not joined" }
        return "\(wifiQuality(rssi)) (\(rssi) dBm)"
    }

    private func wifiQuality(_ rssi: Int) -> String {
        switch rssi {
        case (-55)...: return "Excellent"
        case (-67)...: return "Good"
        case (-75)...: return "Fair"
        default: return "Poor"
        }
    }

    private func wifiColor(_ rssi: Int?) -> Color? {
        guard let rssi else { return nil }
        if rssi >= -67 { return .green }
        if rssi >= -75 { return .orange }
        return .red
    }
}
