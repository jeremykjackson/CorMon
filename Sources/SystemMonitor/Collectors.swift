import Foundation
import Darwin
import IOKit
import IOKit.ps
import CoreWLAN
import SystemConfiguration

// MARK: - Helpers

enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == 4 { return Int(Int32(truncatingIfNeeded: value)) }
        return Int(value)
    }
}

enum Shell {
    /// Runs a command and returns stdout. Used only for slow, infrequent reads (disk health).
    static func run(_ path: String, _ args: [String]) -> Data? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}

// MARK: - CPU

final class CPUSampler {
    private var previous: [[UInt32]] = []

    func sample() -> (total: Double, user: Double, system: Double, perCore: [Double]) {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &infoArray, &infoCount) == KERN_SUCCESS,
              let info = infoArray else { return (0, 0, 0, []) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var current: [[UInt32]] = []
        for i in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * i
            current.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ])
        }
        defer { previous = current }
        guard previous.count == current.count else {
            return (0, 0, 0, Array(repeating: 0, count: current.count))
        }

        var perCore: [Double] = []
        var totalUser = 0.0, totalSystem = 0.0, totalAll = 0.0
        for (c, p) in zip(current, previous) {
            let user = Double(c[0] &- p[0]) + Double(c[3] &- p[3])
            let system = Double(c[1] &- p[1])
            let idle = Double(c[2] &- p[2])
            let all = user + system + idle
            perCore.append(all > 0 ? (user + system) / all : 0)
            totalUser += user; totalSystem += system; totalAll += all
        }
        guard totalAll > 0 else { return (0, 0, 0, perCore) }
        return ((totalUser + totalSystem) / totalAll, totalUser / totalAll, totalSystem / totalAll, perCore)
    }
}

// MARK: - Memory

enum MemoryReader {
    static func read() -> MemoryMetrics {
        var m = MemoryMetrics()
        m.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let capacity = Int(count)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = UInt64(vm_kernel_page_size)
            let internalPages = UInt64(stats.internal_page_count)
            let purgeable = UInt64(stats.purgeable_count)
            m.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
            m.wired = UInt64(stats.wire_count) * page
            m.compressed = UInt64(stats.compressor_page_count) * page
            m.cached = (UInt64(stats.external_page_count) + purgeable) * page
            m.used = m.app + m.wired + m.compressed
        }

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            m.swapUsed = swap.xsu_used
            m.swapTotal = swap.xsu_total
        }
        m.pressureLevel = Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1
        return m
    }
}

// MARK: - Disk

enum DiskReader {
    static func volumes() -> [DiskVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
            .volumeIsRootFileSystemKey, .volumeIsBrowsableKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }

        var result: [DiskVolume] = []
        for url in urls {
            let path = url.path
            guard path == "/" || path.hasPrefix("/Volumes/") else { continue }
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.volumeIsBrowsable == false { continue }
            let total = UInt64(max(v.volumeTotalCapacity ?? 0, 0))
            guard total > 0 else { continue }
            var available = UInt64(max(v.volumeAvailableCapacity ?? 0, 0))
            if let important = v.volumeAvailableCapacityForImportantUsage, important > 0 {
                available = UInt64(important)   // matches Finder's "available" (includes purgeable)
            }
            result.append(DiskVolume(
                name: v.volumeName ?? url.lastPathComponent,
                mountPath: path,
                total: total,
                available: available,
                isInternal: v.volumeIsInternal ?? false,
                isRoot: v.volumeIsRootFileSystem ?? (path == "/")))
        }
        return result.sorted { $0.isRoot && !$1.isRoot }
    }
}

final class DiskIOSampler {
    private var previous: (read: UInt64, write: UInt64, time: TimeInterval)?

    func sample() -> DiskIO {
        let totals = Self.totals()
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (totals.read, totals.write, now) }
        guard let p = previous, now > p.time else { return DiskIO() }
        let dt = now - p.time
        let r = totals.read >= p.read ? totals.read - p.read : 0
        let w = totals.write >= p.write ? totals.write - p.write : 0
        return DiskIO(readRate: Double(r) / dt, writeRate: Double(w) / dt)
    }

    private static func totals() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, write: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString,
                                                           kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return (read, write)
    }
}

enum DiskHealthReader {
    static let smartctlPaths = ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl", "/opt/local/bin/smartctl"]

    static func read() -> DiskHealth {
        var h = DiskHealth()
        h.checked = true
        if let data = Shell.run("/usr/sbin/diskutil", ["info", "-plist", "disk0"]),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            h.smartStatus = plist["SMARTStatus"] as? String ?? "Unknown"
            h.mediaName = plist["MediaName"] as? String ?? ""
        } else {
            h.smartStatus = "Unknown"
        }

        // Optional: richer NVMe health (wear, TB written) when smartmontools is installed.
        if let path = smartctlPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            h.smartctlAvailable = true
            if let data = Shell.run(path, ["-a", "-j", "/dev/disk0"]),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let log = json["nvme_smart_health_information_log"] as? [String: Any] {
                func n(_ key: String) -> NSNumber? { log[key] as? NSNumber }
                h.wearPercent = n("percentage_used")?.intValue
                h.availableSpare = n("available_spare")?.intValue
                h.dataWritten = n("data_units_written").map { $0.uint64Value * 512_000 }
                h.dataRead = n("data_units_read").map { $0.uint64Value * 512_000 }
                h.powerOnHours = n("power_on_hours")?.intValue
                h.powerCycles = n("power_cycles")?.intValue
                h.unsafeShutdowns = n("unsafe_shutdowns")?.intValue
                h.mediaErrors = n("media_errors")?.intValue
            }
        }
        return h
    }
}

// MARK: - Power / Battery

enum PowerReader {
    static func read() -> BatteryMetrics {
        var b = BatteryMetrics()
        b.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Public power-source API: percentage, state, condition, time remaining.
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                        .takeUnretainedValue() as? [String: Any],
                      (desc["Type"] as? String) == "InternalBattery" else { continue }
                b.present = true
                let current = desc["Current Capacity"] as? Int ?? 0
                let maxCap = desc["Max Capacity"] as? Int ?? 100
                b.percent = maxCap > 0 ? Int((Double(current) / Double(maxCap) * 100).rounded()) : current
                b.isCharging = desc["Is Charging"] as? Bool ?? false
                b.fullyCharged = desc["Is Charged"] as? Bool ?? false
                b.externalConnected = (desc["Power Source State"] as? String) == "AC Power"
                b.condition = desc["BatteryHealth"] as? String
                let toEmpty = desc["Time to Empty"] as? Int ?? -1
                let toFull = desc["Time to Full Charge"] as? Int ?? -1
                if b.isCharging, toFull > 0 { b.minutesRemaining = toFull }
                else if !b.externalConnected, toEmpty > 0 { b.minutesRemaining = toEmpty }
            }
        }

        // Detailed battery registry: capacities, cycles, temperature, electrical readings.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let props = unmanaged?.takeRetainedValue() as? [String: Any] {
                func int(_ key: String) -> Int? {
                    (props[key] as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) }
                }
                if !b.present { b.present = props["BatteryInstalled"] as? Bool ?? false }
                b.externalConnected = props["ExternalConnected"] as? Bool ?? b.externalConnected
                b.cycleCount = int("CycleCount")
                b.designCapacity = int("DesignCapacity")
                if let raw = int("AppleRawMaxCapacity") { b.maxCapacity = raw }
                else if let m = int("MaxCapacity"), m > 100 { b.maxCapacity = m }   // Intel reports mAh here
                b.currentCapacity = int("AppleRawCurrentCapacity")
                if let t = int("Temperature") { b.temperatureC = Double(t) / 100 }
                if let v = int("Voltage") { b.voltage = Double(v) / 1000 }
                if let a = int("InstantAmperage") ?? int("Amperage") { b.amperage = Double(a) / 1000 }

                if b.externalConnected, let adapter = props["AdapterDetails"] as? [String: Any] {
                    if let w = (adapter["Watts"] as? NSNumber)?.intValue, w > 0 { b.adapterWatts = w }
                    b.adapterName = (adapter["Name"] as? String) ?? (adapter["Description"] as? String)
                }
                if let telemetry = props["PowerTelemetryData"] as? [String: Any] {
                    let load = (telemetry["SystemLoad"] as? NSNumber)?.doubleValue ?? 0
                    let powerIn = (telemetry["SystemPowerIn"] as? NSNumber)?.doubleValue ?? 0
                    if load > 0 { b.systemPowerW = load / 1000 }
                    else if powerIn > 0 { b.systemPowerW = powerIn / 1000 }
                }
                if b.percent == 0, let pct = int("CurrentCapacity"), pct <= 100 { b.percent = pct }
            }
        }

        if b.systemPowerW == nil, !b.externalConnected, let p = b.batteryPowerW {
            b.systemPowerW = abs(p)
        }
        return b
    }
}

// MARK: - Network

final class NetworkSampler {
    private var previous: [String: (rx: UInt64, tx: UInt64)] = [:]
    private var lastTime: TimeInterval?
    private var sessionDown: UInt64 = 0
    private var sessionUp: UInt64 = 0

    func sample() -> NetworkMetrics {
        var m = NetworkMetrics()
        let now = ProcessInfo.processInfo.systemUptime
        let counters = Self.readCounters()
        let dt = lastTime.map { now - $0 } ?? 0

        var active: [InterfaceRate] = []
        for (name, c) in counters where Self.isCounted(name) {
            m.bootDown += c.rx
            m.bootUp += c.tx
            guard let p = previous[name], dt > 0 else { continue }
            let dRx = c.rx >= p.rx ? c.rx - p.rx : 0
            let dTx = c.tx >= p.tx ? c.tx - p.tx : 0
            sessionDown += dRx
            sessionUp += dTx
            let rate = InterfaceRate(name: name, down: Double(dRx) / dt, up: Double(dTx) / dt)
            m.downRate += rate.down
            m.upRate += rate.up
            if dRx + dTx > 0 { active.append(rate) }
        }
        previous = counters
        lastTime = now
        m.sessionDown = sessionDown
        m.sessionUp = sessionUp
        m.active = active.sorted { $0.down + $0.up > $1.down + $1.up }

        if let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            m.primaryInterface = global["PrimaryInterface"] as? String
        }
        if let iface = m.primaryInterface { m.localIP = Self.ipv4Address(for: iface) }

        if let wifi = CWWiFiClient.shared().interface() {
            m.wifiInterface = wifi.interfaceName
            let rssi = wifi.rssiValue()
            if rssi != 0 {
                m.wifiRSSI = rssi
                m.wifiNoise = wifi.noiseMeasurement()
                m.wifiTxRate = wifi.transmitRate()
            }
        }
        return m
    }

    /// Physical traffic only — skips loopback, VPN tunnels (would double-count) and AWDL.
    private static func isCounted(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    /// 64-bit per-interface byte counters via NET_RT_IFLIST2 (getifaddrs only has 32-bit counters).
    private static func readCounters() -> [String: (rx: UInt64, tx: UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: (rx: UInt64, tx: UInt64)] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                if messageLength <= 0 { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let h2 = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if if_indextoname(UInt32(h2.ifm_index), &nameBuffer) != nil {
                        result[String(cString: nameBuffer)] = (rx: h2.ifm_data.ifi_ibytes, tx: h2.ifm_data.ifi_obytes)
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    private static func ipv4Address(for interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let ifa = entry.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name) == interface {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            cursor = ifa.ifa_next
        }
        return nil
    }
}

// MARK: - System info

enum SystemInfoReader {
    static let staticInfo: (model: String, chip: String, os: String, host: String) = {
        var model = Sysctl.string("hw.model") ?? "Mac"
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if entry != 0 {
            if let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString,
                                                          kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
                let name = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
                if !name.isEmpty { model = name }
            }
            IOObjectRelease(entry)
        }
        let chip = Sysctl.string("machdep.cpu.brand_string") ?? "Unknown CPU"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        let host = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? ProcessInfo.processInfo.hostName
        return (model, chip, os, host)
    }()

    static func read() -> SystemInfo {
        var s = SystemInfo()
        let info = staticInfo
        s.model = info.model
        s.chip = info.chip
        s.osVersion = info.os
        s.hostName = info.host
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 {
            s.uptime = Date().timeIntervalSince1970 - Double(boot.tv_sec)
        }
        s.thermalState = ProcessInfo.processInfo.thermalState
        return s
    }
}

// MARK: - Snapshot collector

struct Snapshot {
    var cpu: CPUMetrics
    var memory: MemoryMetrics
    var volumes: [DiskVolume]?
    var diskIO: DiskIO
    var battery: BatteryMetrics
    var network: NetworkMetrics
    var system: SystemInfo
}

/// Owns the stateful samplers. Only ever used from the monitor's serial background queue.
final class Collector {
    private let cpuSampler = CPUSampler()
    private let diskIOSampler = DiskIOSampler()
    private let networkSampler = NetworkSampler()
    private var lastVolumeRead: TimeInterval = -.infinity

    private lazy var cpuStatic: (brand: String, cores: Int, p: Int?, e: Int?) = (
        Sysctl.string("machdep.cpu.brand_string") ?? "",
        ProcessInfo.processInfo.activeProcessorCount,
        Sysctl.int("hw.perflevel0.logicalcpu"),
        Sysctl.int("hw.perflevel1.logicalcpu")
    )

    func collect() -> Snapshot {
        let usage = cpuSampler.sample()
        var cpu = CPUMetrics()
        cpu.total = usage.total
        cpu.user = usage.user
        cpu.system = usage.system
        cpu.perCore = usage.perCore
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { cpu.load1 = loads[0]; cpu.load5 = loads[1]; cpu.load15 = loads[2] }
        cpu.brand = cpuStatic.brand
        cpu.coreCount = cpuStatic.cores
        cpu.performanceCores = cpuStatic.p
        cpu.efficiencyCores = cpuStatic.e

        // Volume capacity changes slowly; refresh every 15 s.
        let now = ProcessInfo.processInfo.systemUptime
        var volumes: [DiskVolume]?
        if now - lastVolumeRead >= 15 {
            volumes = DiskReader.volumes()
            lastVolumeRead = now
        }

        return Snapshot(
            cpu: cpu,
            memory: MemoryReader.read(),
            volumes: volumes,
            diskIO: diskIOSampler.sample(),
            battery: PowerReader.read(),
            network: networkSampler.sample(),
            system: SystemInfoReader.read())
    }

    func forceVolumeRefresh() { lastVolumeRead = -.infinity }
}
