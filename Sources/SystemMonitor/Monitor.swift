import Foundation
import Combine

// MARK: - Preferences

enum Prefs {
    static let appearance = "appearance"                 // Appearance raw value (gallery / canvas / glass)
    static let refreshInterval = "refreshInterval"
    static let runInBackground = "runInBackground"
    static let legacyShowDockIcon = "showDockIcon"

    static let glanceCorner = "glanceCorner"             // GlanceCorner raw value
    static let glanceDelay = "glanceDelay"               // seconds the pointer must rest in the corner
    static let glanceShowApps = "glanceShowApps"

    static let showApps = "showApps"
    static let groupApps = "groupApps"
    static let topAppCount = "topAppCount"

    static let showSystem = "showSystem"
    static let showCPU = "showCPU"
    static let showMemory = "showMemory"
    static let showDisk = "showDisk"
    static let showPower = "showPower"
    static let showNetwork = "showNetwork"
    static let showPerCore = "showPerCore"

    static let mbIcon = "mbIcon"
    static let mbCPU = "mbCPU"
    static let mbMemory = "mbMemory"
    static let mbNetwork = "mbNetwork"
    static let mbBattery = "mbBattery"
    static let mbPower = "mbPower"
    static let mbDisk = "mbDisk"

    static let cpuWarn = "cpuWarn"                       // %
    static let diskFreeWarn = "diskFreeWarn"             // % free
    static let batteryHealthWarn = "batteryHealthWarn"   // % of design capacity
    static let batteryTempWarn = "batteryTempWarn"       // °C
    static let swapWarnGB = "swapWarnGB"                 // GB

    static let useFahrenheit = "useFahrenheit"
    static let networkInBits = "networkInBits"

    static func registerDefaults() {
        // v1 had "Show icon in Dock"; turning that off meant the same as running in the background.
        // (Checked before registering defaults, which would otherwise mask "never set".)
        let d = UserDefaults.standard
        if d.object(forKey: runInBackground) == nil, d.object(forKey: legacyShowDockIcon) != nil {
            d.set(!d.bool(forKey: legacyShowDockIcon), forKey: runInBackground)
        }
        d.register(defaults: [
            appearance: "gallery",
            refreshInterval: 2.0,
            runInBackground: false,
            glanceCorner: GlanceCorner.bottomLeft.rawValue,
            glanceDelay: 0.35,
            glanceShowApps: true,
            showApps: true, groupApps: true, topAppCount: 5,
            showSystem: true, showCPU: true, showMemory: true, showDisk: true,
            showPower: true, showNetwork: true, showPerCore: true,
            mbIcon: true, mbCPU: true, mbMemory: false, mbNetwork: true,
            mbBattery: false, mbPower: false, mbDisk: false,
            cpuWarn: 85.0, diskFreeWarn: 10.0, batteryHealthWarn: 80.0,
            batteryTempWarn: 40.0, swapWarnGB: 4.0,
            useFahrenheit: false, networkInBits: false
        ])
    }

    static func double(_ key: String) -> Double { UserDefaults.standard.double(forKey: key) }
}

// MARK: - Monitor

/// What the menu bar item shows. Kept separate from the full monitor so the status item
/// only redraws when its visible text actually changes.
final class MenuBarModel: ObservableObject {
    @Published private(set) var text = ""
    @Published private(set) var alert = false

    func update(text: String, alert: Bool) {
        if text != self.text { self.text = text }
        if alert != self.alert { self.alert = alert }
    }
}

final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()

    let menuBar = MenuBarModel()

    // Updated together once per sample, followed by a single objectWillChange,
    // so SwiftUI re-renders once per tick rather than once per property.
    private(set) var cpu = CPUMetrics()
    private(set) var memory = MemoryMetrics()
    private(set) var volumes: [DiskVolume] = []
    private(set) var diskIO = DiskIO()
    private(set) var diskHealth = DiskHealth()
    private(set) var battery = BatteryMetrics()
    private(set) var network = NetworkMetrics()
    private(set) var system = SystemInfo()
    private(set) var topCPU: [AppUsage] = []
    private(set) var topMemory: [AppUsage] = []
    private(set) var history = MetricHistory()
    private(set) var issues: [HealthIssue] = []
    private(set) var lastUpdated: Date?

    private let queue = DispatchQueue(label: "SystemMonitor.collect", qos: .utility)
    private let healthQueue = DispatchQueue(label: "SystemMonitor.health", qos: .background)
    private let collector = Collector()
    private var timer: DispatchSourceTimer?
    private var healthTimer: Timer?
    private var defaultsObserver: NSObjectProtocol?

    /// Windows currently showing detailed data (dashboard, menu panel, glance panel).
    /// Open views that list apps, counted per id. A count (not a set) because switching looks
    /// rebuilds a window's views, and the new onAppear may arrive before the old onDisappear.
    private var viewers: [String: Int] = [:]

    var overallStatus: OverallStatus {
        if issues.contains(where: { $0.level == .critical }) { return .critical }
        return issues.isEmpty ? .healthy : .attention
    }

    func start(interval: Double? = nil) {
        let seconds = max(0.5, interval ?? Prefs.double(Prefs.refreshInterval))
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        // Generous leeway lets macOS batch our wake-ups with other work (saves energy).
        t.schedule(deadline: .now(), repeating: seconds, leeway: .milliseconds(Int(seconds * 150)))
        let collector = self.collector
        t.setEventHandler { [weak self] in
            let snapshot = collector.collect()
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
        t.resume()
        timer = t

        if healthTimer == nil {
            refreshDiskHealth()
            let health = Timer(timeInterval: 600, repeats: true) { [weak self] _ in self?.refreshDiskHealth() }
            health.tolerance = 60
            RunLoop.main.add(health, forMode: .common)
            healthTimer = health
        }
        if defaultsObserver == nil {
            // Menu bar choices take effect immediately rather than at the next sample.
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.updateMenuBar()
            }
        }
    }

    /// Views call this from onAppear/onDisappear. While nothing detailed is visible,
    /// CorMon only samples what the menu bar and health alerts need.
    func setViewer(_ id: String, visible: Bool) {
        let wasDetailed = !viewers.isEmpty
        let count = (viewers[id] ?? 0) + (visible ? 1 : -1)
        viewers[id] = count > 0 ? count : nil
        let detailed = !viewers.isEmpty
        guard detailed != wasDetailed else { return }
        let collector = self.collector
        queue.async { [weak self] in
            collector.detailed = detailed
            guard detailed else { return }
            let snapshot = collector.collect()
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
    }

    func refreshDiskHealth() {
        healthQueue.async { [weak self] in
            let health = DiskHealthReader.read()
            DispatchQueue.main.async {
                guard let self else { return }
                self.objectWillChange.send()
                self.diskHealth = health
                self.evaluate()
            }
        }
        let collector = self.collector
        queue.async { collector.forceVolumeRefresh() }
    }

    private func apply(_ s: Snapshot) {
        objectWillChange.send()
        cpu = s.cpu
        memory = s.memory
        if let v = s.volumes { volumes = v }
        diskIO = s.diskIO
        battery = s.battery
        network = s.network
        system = s.system
        topCPU = s.topCPU
        topMemory = s.topMemory

        history.push(s.cpu.total, \.cpu)
        history.push(s.memory.usedFraction, \.memory)
        history.push(s.network.downRate, \.netDown)
        history.push(s.network.upRate, \.netUp)
        history.push(s.diskIO.readRate, \.diskRead)
        history.push(s.diskIO.writeRate, \.diskWrite)
        history.push(s.battery.systemPowerW ?? abs(s.battery.batteryPowerW ?? 0), \.power)

        lastUpdated = Date()
        evaluate()
        updateMenuBar()
    }

    private func updateMenuBar() {
        let d = UserDefaults.standard
        let bits = d.bool(forKey: Prefs.networkInBits)
        var parts: [String] = []
        if d.bool(forKey: Prefs.mbCPU) { parts.append("CPU \(Fmt.percent(cpu.total))") }
        if d.bool(forKey: Prefs.mbMemory) { parts.append("MEM \(Fmt.percent(memory.usedFraction))") }
        if d.bool(forKey: Prefs.mbDisk), let root = volumes.first { parts.append("SSD \(Fmt.disk(root.available))") }
        if d.bool(forKey: Prefs.mbNetwork) {
            parts.append("↓\(Fmt.compactRate(network.downRate, bits: bits)) ↑\(Fmt.compactRate(network.upRate, bits: bits))")
        }
        if d.bool(forKey: Prefs.mbBattery), battery.present {
            parts.append("\(battery.isCharging ? "⚡︎" : "")\(battery.percent)%")
        }
        if d.bool(forKey: Prefs.mbPower), let w = history.power.last, w > 0 {
            parts.append(String(format: "%.1fW", w))
        }
        menuBar.update(text: parts.joined(separator: "  "), alert: !issues.isEmpty)
    }

    /// Builds the list of health issues from the current readings and user thresholds.
    private func evaluate() {
        var found: [HealthIssue] = []

        let recent = history.cpu.suffix(5)
        if recent.count >= 3 {
            let avg = recent.reduce(0, +) / Double(recent.count)
            if avg * 100 >= Prefs.double(Prefs.cpuWarn) {
                found.append(.init(level: .warning, message: "Sustained CPU load at \(Int(avg * 100))%"))
            }
        }

        switch memory.pressureLevel {
        case 4: found.append(.init(level: .critical, message: "Memory pressure is critical"))
        case 2: found.append(.init(level: .warning, message: "Memory pressure is elevated"))
        default: break
        }
        let swapGB = Double(memory.swapUsed) / 1_073_741_824
        if swapGB >= Prefs.double(Prefs.swapWarnGB) {
            found.append(.init(level: .warning, message: String(format: "Swap usage is %.1f GB", swapGB)))
        }

        let freeWarn = Prefs.double(Prefs.diskFreeWarn)
        for v in volumes {
            let freePct = v.freeFraction * 100
            if freePct < freeWarn {
                found.append(.init(level: freePct < freeWarn / 2 ? .critical : .warning,
                                   message: "\(v.name) has only \(Int(freePct))% free"))
            }
        }
        if diskHealth.smartStatus.lowercased().contains("fail") {
            found.append(.init(level: .critical, message: "Disk SMART status: \(diskHealth.smartStatus)"))
        }
        if let wear = diskHealth.wearPercent, wear >= 80 {
            found.append(.init(level: .warning, message: "SSD wear is at \(wear)%"))
        }
        if let errors = diskHealth.mediaErrors, errors > 0 {
            found.append(.init(level: .warning, message: "SSD reports \(errors) media errors"))
        }

        if battery.present {
            if let health = battery.healthFraction, health * 100 < Prefs.double(Prefs.batteryHealthWarn) {
                found.append(.init(level: .warning, message: "Battery health at \(Int(health * 100))% of design"))
            }
            if let condition = battery.condition, condition != "Good" {
                found.append(.init(level: .warning, message: "Battery condition: \(condition)"))
            }
            if let t = battery.temperatureC, t >= Prefs.double(Prefs.batteryTempWarn) {
                found.append(.init(level: .warning, message: String(format: "Battery temperature is %.0f °C", t)))
            }
        }

        switch system.thermalState {
        case .serious: found.append(.init(level: .warning, message: "Mac is thermally throttling"))
        case .critical: found.append(.init(level: .critical, message: "Thermal state is critical"))
        default: break
        }

        if found != issues { issues = found }
    }
}

// MARK: - Formatting

enum Fmt {
    static func percent(_ fraction: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", fraction * 100)
    }

    static func bytes(_ value: UInt64, style: ByteCountFormatter.CountStyle = .memory) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: style)
    }

    static func disk(_ value: UInt64) -> String { bytes(value, style: .file) }

    static func rate(_ bytesPerSecond: Double, bits: Bool) -> String {
        var v = bits ? bytesPerSecond * 8 : bytesPerSecond
        let units = bits ? ["b/s", "Kb/s", "Mb/s", "Gb/s"] : ["B/s", "KB/s", "MB/s", "GB/s"]
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return String(format: (i > 0 && v < 10) ? "%.1f %@" : "%.0f %@", v, units[i])
    }

    /// Short form for the menu bar, e.g. "1.2M".
    static func compactRate(_ bytesPerSecond: Double, bits: Bool) -> String {
        var v = bits ? bytesPerSecond * 8 : bytesPerSecond
        let units = bits ? ["b", "K", "M", "G"] : ["B", "K", "M", "G"]
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return String(format: (i > 0 && v < 10) ? "%.1f%@" : "%.0f%@", v, units[i])
    }

    static func temperature(_ celsius: Double, fahrenheit: Bool) -> String {
        fahrenheit ? String(format: "%.1f °F", celsius * 9 / 5 + 32) : String(format: "%.1f °C", celsius)
    }

    static func watts(_ w: Double) -> String { String(format: "%.1f W", w) }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let d = total / 86_400, h = (total % 86_400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func minutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
