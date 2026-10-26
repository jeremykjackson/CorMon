import Foundation
import Darwin

/// One row in the "top apps" lists: either a whole app (helpers folded in) or a single process.
struct AppUsage: Identifiable, Equatable {
    let id: String
    var name: String
    var bundlePath: String?     // the .app bundle, used for the icon
    var executablePath: String
    var cpu: Double = 0         // percent of ONE core, like Activity Monitor (can exceed 100)
    var memory: UInt64 = 0      // physical footprint, bytes
    var processCount: Int = 0
}

/// Samples per-process CPU time and memory footprint with libproc.
///
/// Without root privileges macOS only lets us read processes owned by the current user,
/// which covers every app you launch. System daemons (WindowServer, kernel_task…) are skipped.
final class ProcessSampler {
    private var previousCPU: [pid_t: UInt64] = [:]   // nanoseconds of CPU time
    private var lastSample: UInt64?                   // nanoseconds, monotonic
    private var pathCache: [pid_t: String] = [:]
    private let ticksToNanos: (numer: UInt64, denom: UInt64)

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        ticksToNanos = (UInt64(max(timebase.numer, 1)), UInt64(max(timebase.denom, 1)))
    }

    /// Forgets the previous sample, so the next one starts a fresh measuring window
    /// instead of averaging over a long pause.
    func reset() {
        previousCPU = [:]
        lastSample = nil
    }

    func sample(groupByApp: Bool) -> [AppUsage] {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let elapsed = lastSample.map { now > $0 ? Double(now - $0) : 0 } ?? 0

        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let found = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard found > 0 else { return [] }

        var currentCPU: [pid_t: UInt64] = [:]
        var rows: [String: AppUsage] = [:]

        for pid in pids.prefix(Int(found)) where pid > 0 {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard result == 0 else { continue }   // not ours to read

            // rusage CPU times are in Mach ticks (≠ ns on Apple Silicon).
            let ticks = info.ri_user_time &+ info.ri_system_time
            let cpuNanos = ticks.multipliedReportingOverflow(by: ticksToNanos.numer).partialValue / ticksToNanos.denom
            currentCPU[pid] = cpuNanos

            var cpuPercent = 0.0
            if elapsed > 0, let previous = previousCPU[pid], cpuNanos >= previous {
                cpuPercent = Double(cpuNanos - previous) / elapsed * 100
            }

            let path = pathCache[pid] ?? Self.executablePath(pid)
            pathCache[pid] = path
            let identity = Self.identity(pid: pid, path: path, groupByApp: groupByApp)

            var row = rows[identity.key] ?? AppUsage(id: identity.key, name: identity.name,
                                                     bundlePath: identity.bundle, executablePath: path)
            row.cpu += cpuPercent
            row.memory += info.ri_phys_footprint
            row.processCount += 1
            rows[identity.key] = row
        }

        previousCPU = currentCPU
        lastSample = now
        pathCache = pathCache.filter { currentCPU[$0.key] != nil }
        return Array(rows.values)
    }

    private static func executablePath(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length > 0 { return String(cString: buffer) }
        var nameBuffer = [CChar](repeating: 0, count: 256)
        if proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 { return String(cString: nameBuffer) }
        return "pid \(pid)"
    }

    /// Folds helper processes into the outermost .app bundle they live in
    /// (e.g. "Google Chrome Helper (Renderer)" → "Google Chrome").
    private static func identity(pid: pid_t, path: String, groupByApp: Bool) -> (key: String, name: String, bundle: String?) {
        var bundle: String?
        if let range = path.range(of: ".app/") {
            bundle = String(path[..<range.upperBound].dropLast())
        } else if path.hasSuffix(".app") {
            bundle = path
        }
        let processName = (path as NSString).lastPathComponent

        if groupByApp, let bundle {
            let appName = ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
            return ("app:" + bundle, appName, bundle)
        }
        if groupByApp {
            return ("proc:" + processName, processName, nil)
        }
        return ("pid:\(pid)", processName, bundle)
    }
}
