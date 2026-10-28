import SwiftUI

struct DashboardView: View {
    // Re-render this window's root when the look changes (see Appearance).
    @AppStorage(Prefs.appearance) private var appearanceRaw = Appearance.gallery.rawValue
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.openWindow) private var openWindow

    @AppStorage(Prefs.showSystem) private var showSystem = true
    @AppStorage(Prefs.showCPU) private var showCPU = true
    @AppStorage(Prefs.showMemory) private var showMemory = true
    @AppStorage(Prefs.showDisk) private var showDisk = true
    @AppStorage(Prefs.showPower) private var showPower = true
    @AppStorage(Prefs.showNetwork) private var showNetwork = true
    @AppStorage(Prefs.showApps) private var showApps = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if showSystem { SystemHeader() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 370), spacing: 20, alignment: .top)],
                          alignment: .leading, spacing: 20) {
                    if showCPU { CPUCard() }
                    if showMemory { MemoryCard() }
                    if showApps { TopAppsCard() }
                    if showPower { PowerCard() }
                    if showNetwork { NetworkCard() }
                    if showDisk { DiskCard() }
                }
                if !(showSystem || showCPU || showMemory || showDisk || showPower || showNetwork || showApps) {
                    Text("Every section is hidden. Turn some on in Settings.")
                        .font(Typo.titleItalic(15))
                        .foregroundStyle(Palette.parchment)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
                Fleuron().padding(.horizontal, 120).padding(.top, 4)
            }
            .padding(24)
        }
        .frame(minWidth: 440, minHeight: 500)
        .background(CanvasBackground())
        .cormonStyle()
        .onAppear {
            WindowRouter.shared.register(openWindow)
            monitor.setViewer("dashboard", visible: true)
        }
        .onDisappear { monitor.setViewer("dashboard", visible: false) }
        .toolbar {
            ToolbarItem {
                Button {
                    GlancePanelController.shared.toggle()
                } label: {
                    Label("Glance", systemImage: "rectangle.on.rectangle")
                }
                .help("Show the at-a-glance panel")
            }
            ToolbarItem {
                Button {
                    openWindow(id: "settings")
                } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                }
                .help("Choose metrics, menu bar items, hot corner and alert thresholds")
            }
        }
    }
}

// MARK: - Header

struct SystemHeader: View {
    @EnvironmentObject var m: SystemMonitor

    var body: some View {
        let s = m.system
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    BrandTitle(size: 34)
                    Text("Portrait of a \(s.model.isEmpty ? "Mac" : s.model)")
                        .font(Typo.titleItalic(16)).foregroundStyle(Palette.ivory)
                    Text([s.chip, s.osVersion, s.hostName].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(Typo.caption(12)).foregroundStyle(Palette.parchment)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    StatusPill(status: m.overallStatus)
                    Text(m.overallStatus.motto).font(Typo.titleItalic(12)).foregroundStyle(Palette.parchment)
                }
            }

            HStack(spacing: 28) {
                headerStat("Uptime", Fmt.duration(s.uptime))
                headerStat("Thermal", s.thermalState.label, color: s.thermalState.color)
                headerStat("Processor", Fmt.percent(m.cpu.total), color: Palette.ochre)
                headerStat("Memory", Fmt.percent(m.memory.usedFraction), color: Palette.sienna)
                if m.battery.present { headerStat("Battery", "\(m.battery.percent)%", color: Palette.sapGreen) }
                Spacer()
            }

            Fleuron()

            if m.issues.isEmpty {
                Label("All monitored measures are within healthy bounds.", systemImage: "heart.text.square")
                    .font(Typo.titleItalic(14)).foregroundStyle(Palette.parchment)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(m.issues) { issue in
                        Label(issue.message,
                              systemImage: issue.level == .critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(Typo.body(13, .medium))
                            .foregroundStyle(issue.level == .critical ? Palette.danger : Palette.warn)
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .giltFrame(accent: m.issues.isEmpty ? Palette.gilt : m.overallStatus.color, cornerRadius: 8)
    }

    private func headerStat(_ label: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Typo.titleItalic(12)).foregroundStyle(Palette.parchment)
            Text(value).font(Typo.numeral(17)).foregroundStyle(color ?? Palette.ivory)
        }
    }
}

/// The "CorMon" wordmark; in Canvas it sits on a loose brushstroke highlight.
struct BrandTitle: View {
    var size: CGFloat

    var body: some View {
        let text = Text("CorMon").font(Typo.title(size)).foregroundStyle(Palette.giltLight)
        if Appearance.current == .canvas {
            text.background(alignment: .bottomLeading) {
                BrushStroke(seed: 7, roughness: 0.3)
                    .fill(Palette.sienna.opacity(0.28))
                    .frame(width: size * 4.6, height: size * 0.55)
                    .offset(x: -size * 0.15, y: -size * 0.02)
            }
        } else {
            text
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
        Card(title: "Processor", subtitle: "le cœur battant", icon: "cpu", tint: .cpuTint, detail: coreSummary(c)) {
            HStack(spacing: 20) {
                RingGauge(fraction: c.total, tint: tint) {
                    BigValue(value: Fmt.percent(c.total), caption: "in use")
                }
                .frame(width: 112, height: 112)
                StatGrid(stats: [
                    Stat(label: "User", value: Fmt.percent(c.user, digits: 1)),
                    Stat(label: "System", value: Fmt.percent(c.system, digits: 1)),
                    Stat(label: "Idle", value: Fmt.percent(max(0, 1 - c.total), digits: 1)),
                    Stat(label: "Load 1 · 5 · 15m", value: String(format: "%.2f  %.2f  %.2f", c.load1, c.load5, c.load15))
                ])
            }
            ChartWell(height: 54) {
                Sparkline(values: m.history.cpu, maxValue: 1, tint: .cpuTint)
            }
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
                    LegendDot(color: Palette.leadWhite, text: "Efficiency")
                    LegendDot(color: .cpuTint, text: "Performance")
                }
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { i in
                    let tint: Color = i < efficiencyCount ? Palette.leadWhite : .cpuTint
                    CoreBar(fraction: values[i], tint: tint, seed: 200 + i * 7)
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
        Card(title: "Memory", subtitle: "la mémoire", icon: "memorychip", tint: .memoryTint,
             detail: "\(Fmt.bytes(mem.total)) installed") {
            HStack(spacing: 20) {
                RingGauge(fraction: mem.usedFraction, tint: mem.pressureLevel > 1 ? pressure.color : .memoryTint) {
                    BigValue(value: Fmt.percent(mem.usedFraction), caption: "used")
                }
                .frame(width: 112, height: 112)
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
                    (Double(mem.app) / total, Color.memoryTint),
                    (Double(mem.wired) / total, Palette.ochre),
                    (Double(mem.compressed) / total, Palette.madder)
                ])
                HStack(spacing: 12) {
                    LegendDot(color: .memoryTint, text: "App \(Fmt.bytes(mem.app))")
                    LegendDot(color: Palette.ochre, text: "Wired \(Fmt.bytes(mem.wired))")
                    LegendDot(color: Palette.madder, text: "Compressed \(Fmt.bytes(mem.compressed))")
                }
            }
            ChartWell(height: 44) {
                Sparkline(values: m.history.memory, maxValue: 1, tint: .memoryTint)
            }
        }
    }

    private func pressureInfo(_ level: Int) -> (label: String, color: Color) {
        switch level {
        case 4: return ("Critical", Palette.danger)
        case 2: return ("Elevated", Palette.warn)
        default: return ("Normal", Palette.good)
        }
    }
}

// MARK: - Top apps

struct TopAppsCard: View {
    @EnvironmentObject var m: SystemMonitor
    @AppStorage(Prefs.topAppCount) private var count = 5

    var body: some View {
        Card(title: "Busiest Apps", subtitle: "les ouvriers", icon: "person.3.sequence",
             tint: Appearance.current == .gallery ? Palette.giltLight : Palette.gilt,
             detail: "your processes") {
            AppList(title: "By processor", apps: Array(m.topCPU.prefix(count)), metric: .cpu)
            Fleuron().padding(.horizontal, 40)
            AppList(title: "By memory", apps: Array(m.topMemory.prefix(count)), metric: .memory)
        }
    }
}

struct AppList: View {
    enum Metric { case cpu, memory }
    var title: String?
    var apps: [AppUsage]
    var metric: Metric
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            if let title { SectionLabel(text: title) }
            if apps.isEmpty {
                Text("Gathering…").font(Typo.titleItalic(12)).foregroundStyle(Palette.faded)
            }
            let top = apps.map(value).max() ?? 1
            ForEach(apps) { app in
                AppRow(app: app, value: value(app), top: top, metric: metric, compact: compact)
            }
        }
    }

    private func value(_ app: AppUsage) -> Double {
        metric == .cpu ? app.cpu : Double(app.memory)
    }
}

struct AppRow: View {
    var app: AppUsage
    var value: Double
    var top: Double
    var metric: AppList.Metric
    var compact = false

    var body: some View {
        let tint: Color = metric == .cpu ? .cpuTint : .memoryTint
        HStack(spacing: 8) {
            Image(nsImage: AppIconCache.shared.icon(for: app))
                .resizable()
                .frame(width: compact ? 16 : 20, height: compact ? 16 : 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(app.name).font(Typo.body(compact ? 12 : 13, .medium)).foregroundStyle(Palette.ivory)
                        .lineLimit(1).truncationMode(.middle)
                    if app.processCount > 1 && !compact {
                        Text("×\(app.processCount)").font(Typo.caption(10)).foregroundStyle(Palette.faded)
                    }
                    Spacer(minLength: 6)
                    Text(formatted).font(Typo.numeral(compact ? 12 : 13)).foregroundStyle(Palette.ivory)
                }
                if !compact {
                    BarMeter(fraction: top > 0 ? value / top : 0, tint: tint, height: 3)
                }
            }
        }
        .help(app.executablePath)
    }

    private var formatted: String {
        metric == .cpu ? String(format: app.cpu >= 10 ? "%.0f%%" : "%.1f%%", app.cpu) : Fmt.bytes(app.memory)
    }
}

// MARK: - Disk

struct DiskCard: View {
    @EnvironmentObject var m: SystemMonitor
    @AppStorage(Prefs.diskFreeWarn) private var diskFreeWarn = 10.0

    var body: some View {
        let h = m.diskHealth
        Card(title: "Storage", subtitle: "le disque", icon: "internaldrive", tint: .diskTint,
             detail: h.mediaName.isEmpty ? nil : h.mediaName) {
            if m.volumes.isEmpty {
                Text("Reading volumes…").font(Typo.titleItalic(13)).foregroundStyle(Palette.parchment)
            }
            ForEach(m.volumes) { v in
                let lowSpace = v.freeFraction * 100 < diskFreeWarn
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: v.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                            .foregroundStyle(Palette.parchment).font(.caption)
                        Text(v.name).font(Typo.body(13, .medium))
                        Spacer()
                        Text("\(Fmt.disk(v.available)) free of \(Fmt.disk(v.total))")
                            .font(Typo.numeral(11.5, .regular))
                            .foregroundStyle(lowSpace ? Palette.danger : Palette.parchment)
                    }
                    BarMeter(fraction: v.usedFraction, tint: lowSpace ? Palette.danger : .diskTint, height: 7)
                }
            }

            SectionLabel(text: "Activity").padding(.top, 4)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    LegendDot(color: .diskTint, text: "Read")
                    Text(Fmt.rate(m.diskIO.readRate, bits: false)).font(Typo.numeral(13))
                }
                .frame(width: 90, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    LegendDot(color: Palette.madder, text: "Write")
                    Text(Fmt.rate(m.diskIO.writeRate, bits: false)).font(Typo.numeral(13))
                }
                .frame(width: 90, alignment: .leading)
                let top = max(m.history.diskRead.max() ?? 0, m.history.diskWrite.max() ?? 0, 1)
                ChartWell(height: 40) {
                    ZStack {
                        Sparkline(values: m.history.diskRead, maxValue: top, tint: .diskTint)
                        Sparkline(values: m.history.diskWrite, maxValue: top, tint: Palette.madder, filled: false)
                    }
                }
            }

            HStack {
                SectionLabel(text: "Drive health")
                Spacer()
                Button {
                    m.refreshDiskHealth()
                } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(Palette.gilt)
                }
                .buttonStyle(.borderless)
                .help("Re-check drive health")
            }
            .padding(.top, 4)
            StatGrid(stats: healthStats(h), columns: 3)
            if h.checked && !h.smartctlAvailable {
                Text("For SSD wear, data written and power-on hours, install smartmontools: `brew install smartmontools`")
                    .font(Typo.caption()).foregroundStyle(Palette.faded)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func healthStats(_ h: DiskHealth) -> [Stat] {
        let status = h.smartStatus
        let statusColor: Color = status == "Verified" ? Palette.good
            : (status.lowercased().contains("fail") ? Palette.danger : Palette.parchment)
        var stats = [Stat(label: "SMART status", value: h.checked ? status : "Checking…", color: statusColor)]
        if let wear = h.wearPercent {
            stats.append(Stat(label: "Life used", value: "\(wear)%", color: wear >= 80 ? Palette.warn : nil))
        }
        if let spare = h.availableSpare { stats.append(Stat(label: "Spare", value: "\(spare)%")) }
        if let w = h.dataWritten { stats.append(Stat(label: "Written", value: Fmt.disk(w))) }
        if let r = h.dataRead { stats.append(Stat(label: "Read", value: Fmt.disk(r))) }
        if let hours = h.powerOnHours { stats.append(Stat(label: "Power-on", value: "\(hours.formatted()) h")) }
        if let c = h.powerCycles { stats.append(Stat(label: "Power cycles", value: c.formatted())) }
        if let u = h.unsafeShutdowns { stats.append(Stat(label: "Unsafe shutdowns", value: u.formatted())) }
        if let e = h.mediaErrors { stats.append(Stat(label: "Media errors", value: "\(e)", color: e > 0 ? Palette.danger : nil)) }
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
        Card(title: "Power", subtitle: "l'énergie", icon: batteryIcon(b), tint: .powerTint,
             detail: b.present ? b.stateText : "AC Power") {
            if b.present {
                HStack(spacing: 20) {
                    RingGauge(fraction: Double(b.percent) / 100,
                              tint: b.percent <= 15 && !b.externalConnected ? Palette.danger : .powerTint) {
                        BigValue(value: "\(b.percent)%", caption: timeCaption(b))
                    }
                    .frame(width: 112, height: 112)
                    StatGrid(stats: primaryStats(b))
                }
                StatGrid(stats: detailStats(b), columns: 3)
            } else {
                Text("No internal battery detected.").font(Typo.titleItalic(13)).foregroundStyle(Palette.parchment)
                StatGrid(stats: detailStats(b), columns: 3)
            }
            if m.history.power.contains(where: { $0 > 0 }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SectionLabel(text: "Power draw")
                        Spacer()
                        Text("peak \(Fmt.watts(m.history.power.max() ?? 0))")
                            .font(Typo.numeral(11, .regular)).foregroundStyle(Palette.parchment)
                    }
                    ChartWell(height: 44) {
                        Sparkline(values: m.history.power, tint: .powerTint)
                    }
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
                              color: health * 100 < healthWarn ? Palette.warn : Palette.good))
        }
        stats.append(Stat(label: "Condition", value: b.condition ?? "—",
                          color: (b.condition ?? "Good") == "Good" ? nil : Palette.warn))
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
        Card(title: "Network", subtitle: "le réseau", icon: "network", tint: .networkTint, detail: interfaceSummary(n)) {
            HStack(spacing: 22) {
                rateBlock(symbol: "arrow.down", label: "Download", rate: n.downRate, tint: .networkTint)
                rateBlock(symbol: "arrow.up", label: "Upload", rate: n.upRate, tint: .uploadTint)
                Spacer()
            }
            let top = max(m.history.netDown.max() ?? 0, m.history.netUp.max() ?? 0, 1024)
            ChartWell(height: 58) {
                ZStack {
                    Sparkline(values: m.history.netDown, maxValue: top, tint: .networkTint)
                    Sparkline(values: m.history.netUp, maxValue: top, tint: .uploadTint, filled: false)
                }
            }

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
            IconBadge(symbol: symbol, tint: tint, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(Typo.titleItalic(12)).foregroundStyle(Palette.parchment)
                Text(Fmt.rate(rate, bits: inBits)).font(Typo.numeral(19))
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
        return "\(Self.wifiQuality(rssi)) (\(rssi) dBm)"
    }

    static func wifiQuality(_ rssi: Int) -> String {
        switch rssi {
        case (-55)...: return "Excellent"
        case (-67)...: return "Good"
        case (-75)...: return "Fair"
        default: return "Poor"
        }
    }

    private func wifiColor(_ rssi: Int?) -> Color? {
        guard let rssi else { return nil }
        if rssi >= -67 { return Palette.good }
        if rssi >= -75 { return Palette.warn }
        return Palette.danger
    }
}
