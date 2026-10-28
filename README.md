<p align="center"><img src="Resources/AppIcon.png" width="160" alt="CorMon icon"></p>

# CorMon

*A portrait of your Mac.* A lightweight, native SwiftUI system monitor for macOS, painted in the warm umbers, ochres and gilt frames of 19th-century academic oil painting (after Fernand Cormon). It lives in the menu bar, slides out of a hot corner, and opens a full dashboard. No dependencies, no daemons, no admin rights.

## Install & update

Requires macOS 13 (Ventura) or newer, Xcode or the Command Line Tools (`xcode-select --install`), and access to this private repo (`gh auth login`).

**First time:**
```bash
git clone https://github.com/jeremykjackson/CorMon.git ~/CorMon
~/CorMon/install.sh
```

**Every update after that:**
```bash
~/CorMon/install.sh
```

The installer pulls the latest code from GitHub, builds it, quits the running copy, installs `CorMon.app` into `/Applications` and relaunches it. If you're already on the latest version it says so and skips the build. Your settings and the login item carry over.

| Option | What it does |
|---|---|
| `--force` | Rebuild and reinstall even if already up to date |
| `--no-launch` | Don't open CorMon afterwards |
| `--dir PATH` | Keep the source somewhere other than `~/CorMon` |

Tip: add `alias cormon-update="~/CorMon/install.sh"` to `~/.zshrc` to update with one word.

To build without installing, run `./build.sh`. It produces `build/CorMon.app`, which is ad-hoc signed and not notarized.

## What's new in 3.0 — the V2 redesign: choose your look

CorMon now comes in three looks. Pick one in **Settings › General › Appearance**; it applies to the dashboard, menu bar panel, glance panel and settings window, and switches instantly. Every feature works the same in all three.

| Look | What it's like |
|---|---|
| **Gallery** (default) | The original: umber grounds, gilt picture frames, Baskerville titles, earth pigments. Always dark. |
| **Canvas** | Light and painterly, designed to sit comfortably next to any modern app. Warm watercolor paper with loose pigment washes; ring gauges painted as ensō brush circles, meters as loaded-brush swipes with bristle texture, graphs as layered ink strokes, section icons on dabs of paint. New York titles with SF Rounded numerals. Strokes are seeded, so they keep their shape instead of flickering on each refresh. Always light. |
| **Mac Glass** | Mirrors macOS: SF Pro, SF Symbols, system colors and your accent color, follows Light/Dark mode. Panels use real **Liquid Glass** on macOS 26 Tahoe when built with Xcode 26 / Command Line Tools 26, and translucent materials on earlier systems. |

## What's new in 2.0

- **Hot-corner glance panel**: rest the pointer in a chosen screen corner and a small framed panel shows CPU, memory, battery, disk, network, alerts and the busiest apps. It fades away when you move off it. Also available from the menu bar or ⇧⌘G.
- **Run in the background**: no Dock icon, starts without opening the dashboard, keeps measuring from the menu bar and hot corner.
- **Busiest apps**: top apps by processor (per-core %, like Activity Monitor) and by memory footprint, with helper processes folded into their app.
- **New look**: canvas texture, chiaroscuro lighting, gilt-framed panels, Baskerville titles, earth-pigment colors.
- **New icon**: a heart monitor with a yellow trace on dark green; the menu bar shows a white heart-monitor glyph (with a dot when an alert is active).

## Energy use

CorMon is built to stay out of the way:

- Cheap kernel counters (CPU, memory, network bytes, disk I/O) are read every refresh so the menu bar stays live.
- Battery, Wi-Fi, IP address and volume capacity refresh on slower schedules (5–120 s). The per-app scan runs only while a window that lists apps is open.
- With every window closed, CorMon only samples what the menu bar and health alerts need. The menu bar item redraws only when its text changes.
- The UI updates once per sample, without animations or live shadows. The glance panel's view is torn down whenever it's hidden.
- Timers use generous leeway so macOS can batch wake-ups.

If you want it lighter still, set **Refresh every** to 5 seconds in Settings.

## What it shows

| Section | Metrics |
|---|---|
| **Health summary** | Overall status, active alerts, model, chip, macOS, uptime, thermal state |
| **Processor** | Total / user / system / idle, load averages, history, per-core bars (efficiency vs performance cores) |
| **Memory** | Used %, memory pressure, app / wired / compressed, cached files, swap |
| **Busiest apps** | Top N apps by CPU and by memory, with icons and process counts |
| **Storage** | Every volume's free space, read/write throughput, SMART status; with `brew install smartmontools`: SSD life used, spare, data written/read, power-on hours, unsafe shutdowns, media errors |
| **Power** | Battery %, time remaining, health vs design capacity, cycle count, condition, temperature, voltage, battery in/out watts, system power draw, adapter, Low Power Mode |
| **Network** | Download / upload speed and history, session and since-boot totals, primary interface, local IP, Wi-Fi signal, noise, SNR, link rate |

## Customization (⌘, or "Customize…")

- **General**: appearance (Gallery, Canvas or Mac Glass), run in the background, launch at login, refresh rate, °C/°F, bytes/bits
- **Hot Corner**: which corner (or off), opening delay, include busiest apps, shortcut to clear a conflicting macOS hot corner
- **Dashboard**: show/hide each section, per-core bars, number of apps listed, group helpers into apps
- **Menu Bar**: heart-monitor icon, CPU, memory, network, battery %, watts, free disk
- **Alerts**: thresholds for CPU load, swap, low disk space, battery health and temperature

## Notes

- macOS only lists Apple's own actions in System Settings › Hot Corners, so CorMon watches the corner itself (pointer position polling; no Accessibility permission needed). If macOS also has an action on that corner, both will fire. Pick a free corner or clear the macOS one.
- The busiest-apps list covers processes you own. System daemons need administrator rights to read.
- CPU/GPU die temperatures and fan speeds need private SMC interfaces on Apple Silicon, so CorMon shows the system thermal state instead.

## Project layout

```
Package.swift
install.sh                   → pulls the latest, builds and installs into /Applications
build.sh                     → builds build/CorMon.app
Resources/                   Info.plist, AppIcon.icns, AppIcon.png
Tools/make_icon.py           regenerates the app icon
Sources/SystemMonitor/
  SystemMonitorApp.swift     app entry, windows, menu bar item, background mode
  Glance.swift               hot-corner watcher and at-a-glance panel
  Monitor.swift              sampling loop, history, health rules, prefs, formatting
  Collectors.swift           Mach/sysctl/IOKit/CoreWLAN readers
  Processes.swift            per-app CPU & memory sampling (libproc)
  Models.swift               metric data types
  Theme.swift                looks (Gallery / Canvas / Mac Glass): palettes, type, grounds, frames, menu bar glyph
  Brush.swift                brushstroke shapes, painted rings and bars for the Canvas look
  Components.swift           gauges, sparklines, bars, cards
  DashboardView.swift        dashboard window and section cards
  MenuBarViews.swift         menu bar label + drop-down panel
  SettingsView.swift         customization window
```
