# System Monitor v1 (macOS)

A lightweight, native SwiftUI system monitor for your MacBook Pro. It lives in the menu bar and opens a full dashboard window. No dependencies, no background daemons, no admin rights.

## Build & run

Requires macOS 13 (Ventura) or newer and Xcode or the Command Line Tools (`xcode-select --install`).

```bash
cd SystemMonitor
chmod +x build.sh
./build.sh
open "build/System Monitor.app"
```

To keep it: `cp -R "build/System Monitor.app" /Applications/`

Because it's ad-hoc signed (not notarized), the first launch from Finder may need right-click → **Open**.

## What it shows

| Section | Metrics |
|---|---|
| **System health** | Overall status (Healthy / Needs Attention / Critical), active alerts, model, chip, macOS version, uptime, thermal state |
| **CPU** | Total / user / system / idle %, load averages, 90-sample history, per-core bars (Efficiency vs Performance cores on Apple Silicon) |
| **Memory** | Used %, memory pressure, app / wired / compressed breakdown, cached files, swap |
| **Disk** | Every mounted volume (free / total, matching Finder), live read/write throughput, SMART status. With `brew install smartmontools`: SSD life used, spare, TB written/read, power-on hours, power cycles, unsafe shutdowns, media errors |
| **Power** | Battery %, charging state, time remaining, health % (full-charge vs design capacity), cycle count, condition, temperature, voltage, battery in/out watts, whole-system power draw, adapter wattage, Low Power Mode |
| **Network** | Download / upload speed, history graph, session and since-boot totals, primary interface, local IP, Wi-Fi signal (RSSI, noise, SNR, link rate) |

## Customization (⌘, or "Customize…")

- **General** — refresh rate (1/2/5/10 s), Dock icon on/off (menu-bar-only mode), launch at login, °C/°F, bytes/bits for network speed
- **Dashboard** — show/hide each section and per-core bars
- **Menu Bar** — choose what appears in the menu bar: status icon, CPU, memory, network ↓/↑, battery %, watts, free disk
- **Alerts** — thresholds for sustained CPU load, swap, low disk space, battery health and battery temperature

## Notes / v1 limitations

- CPU/GPU die temperatures and fan speeds use private SMC interfaces on Apple Silicon, so v1 reports the system thermal state instead.
- Wi-Fi network name (SSID) needs Location Services permission, so it's not shown.
- Per-process lists (top CPU/memory apps) are a good candidate for v2.

## Project layout

```
Package.swift
build.sh                     → builds build/System Monitor.app
Resources/Info.plist
Sources/SystemMonitor/
  SystemMonitorApp.swift     app entry, windows, menu bar item
  Monitor.swift              sampling loop, history, health rules, prefs, formatting
  Collectors.swift           Mach/sysctl/IOKit/CoreWLAN readers
  Models.swift               metric data types
  DashboardView.swift        dashboard window and section cards
  MenuBarViews.swift         menu bar label + drop-down panel
  SettingsView.swift         customization window
  Components.swift           gauges, sparklines, bars, cards
```
