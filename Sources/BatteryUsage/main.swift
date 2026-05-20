import AppKit
import Foundation
import ServiceManagement

struct BatterySnapshot {
    let percent: String
    let state: String
    let eta: String?
    let source: String

    var statusTitle: String {
        switch state {
        case "discharging":
            return "\(percent) \(eta ?? "--")"
        case "charging":
            if let eta {
                return "\(percent) +\(eta)"
            }
            return "\(percent) charging"
        case "charged":
            return "\(percent) full"
        default:
            return state.isEmpty ? percent : "\(percent) \(state)"
        }
    }

    var detailLabel: String {
        switch state {
        case "charging":
            return eta.map { "Time to full: \($0)" } ?? "Charging"
        case "discharging":
            return eta.map { "Estimate remaining: \($0)" } ?? "No estimate available"
        case "charged":
            return "Fully charged"
        default:
            return state.isEmpty ? "Unknown status" : state.capitalized
        }
    }
}

struct ProcessUsage {
    let pid: String
    let cpu: String
    let memory: String
    let command: String

    var displayName: String {
        humanProcessName(command)
    }
}

enum BatteryReader {
    static func snapshot() -> BatterySnapshot? {
        let output = run("/usr/bin/pmset", ["-g", "batt"])
        let lines = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.count >= 2 else { return nil }

        let source = lines[0]
            .replacingOccurrences(of: "Now drawing from '", with: "")
            .replacingOccurrences(of: "'", with: "")

        let batteryLine = lines[1]
        guard let percent = firstMatch(#"(\d+)%"#, in: batteryLine) else {
            return nil
        }

        let parts = batteryLine
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let state = parts.count > 1 ? parts[1].lowercased() : "unknown"
        var eta: String?

        if parts.count > 2 {
            let rawETA = parts[2]
            if !rawETA.contains("no estimate"), rawETA.range(of: #"^\d+:\d{2}$"#, options: .regularExpression) != nil {
                eta = rawETA
            } else if !rawETA.contains("no estimate") {
                eta = firstMatch(#"(\d+:\d{2})"#, in: rawETA)
            }
        }

        if state == "charging", eta == nil {
            eta = averageTimeToFull()
        }

        return BatterySnapshot(percent: "\(percent)%", state: state, eta: eta, source: source)
    }

    static func topEnergyUsers(limit: Int = 5) -> [ProcessUsage] {
        let output = run("/bin/ps", ["-A", "-r", "-o", "pid=,pcpu=,pmem=,comm="])
        return output
            .split(separator: "\n")
            .compactMap { parseProcessLine(String($0)) }
            .filter { process in
                let excluded = ["/ps", "/awk", "/sed", "/sort", "/head", "/tail", "/zsh"]
                if excluded.contains(where: { process.command.hasSuffix($0) }) {
                    return false
                }
                return !process.command.contains("battery-estimate.1m.sh")
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func averageTimeToFull() -> String? {
        let output = run("/usr/sbin/ioreg", ["-r", "-n", "AppleSmartBattery"])
        guard let minutesString = firstMatch(#""AvgTimeToFull" = (\d+)"#, in: output),
              let minutes = Int(minutesString),
              minutes != 65535 else {
            return nil
        }

        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private static func parseProcessLine(_ line: String) -> ProcessUsage? {
        let parts = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 4 else {
            return nil
        }

        let command = String(parts[3]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }

        return ProcessUsage(
            pid: String(parts[0]),
            cpu: String(parts[1]),
            memory: String(parts[2]),
            command: command
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var snapshot: BatterySnapshot?
    private var topUsers: [ProcessUsage] = []
    private var didStart = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        NSApp.setActivationPolicy(.accessory)
        configureStatusButton()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        statusItem.length = NSStatusItem.variableLength
        button.image = nil
        button.imagePosition = .noImage
        button.toolTip = "Battery Usage"
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    }

    @objc private func refresh() {
        snapshot = BatteryReader.snapshot()
        topUsers = BatteryReader.topEnergyUsers()

        statusItem.length = NSStatusItem.variableLength
        if let snapshot {
            statusItem.button?.title = "Battery \(snapshot.statusTitle)"
            statusItem.button?.image = nil
        } else {
            statusItem.button?.title = " Battery --"
            statusItem.button?.image = nil
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        if let snapshot {
            menu.addItem(headerItem(snapshot))
            menu.addItem(.separator())
            menu.addItem(disabledItem("Battery: \(snapshot.percent)", symbol: "battery.75percent"))
            menu.addItem(disabledItem("Status: \(snapshot.state.capitalized)", symbol: statusSymbol(snapshot.state)))
            menu.addItem(disabledItem(snapshot.detailLabel, symbol: "clock"))
            if !snapshot.source.isEmpty {
                menu.addItem(disabledItem("Source: \(snapshot.source)", symbol: "powerplug"))
            }
        } else {
            menu.addItem(disabledItem("Unable to read battery state", symbol: "exclamationmark.triangle"))
        }

        menu.addItem(.separator())
        menu.addItem(sectionTitle("Top Energy Users"))

        if topUsers.isEmpty {
            menu.addItem(disabledItem("No process data available", symbol: "minus.circle"))
        } else {
            for process in topUsers {
                let item = NSMenuItem(
                    title: "\(process.displayName): \(process.cpu)% CPU, \(process.memory)% RAM",
                    action: #selector(openActivityMonitor),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = process.pid
                item.image = NSWorkspace.shared.icon(forFile: process.command)
                item.toolTip = "PID \(process.pid)"
                menu.addItem(item)

                let pidItem = disabledItem("PID \(process.pid)", symbol: nil)
                pidItem.indentationLevel = 1
                menu.addItem(pidItem)
            }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Refresh", symbol: "arrow.clockwise", action: #selector(refresh)))
        menu.addItem(actionItem("Open Activity Monitor", symbol: "waveform.path.ecg", action: #selector(openActivityMonitor)))

        if #available(macOS 13.0, *) {
            let loginItem = actionItem("Open at Login", symbol: "checkmark.circle", action: #selector(toggleLaunchAtLogin))
            loginItem.state = launchAtLoginEnabled ? .on : .off
            menu.addItem(loginItem)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Battery Usage", symbol: "power", action: #selector(quit)))

        statusItem.menu = menu
    }

    private func headerItem(_ snapshot: BatterySnapshot) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 3
        view.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 8, right: 18)

        let title = NSTextField(labelWithString: snapshot.statusTitle)
        title.font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: snapshot.detailLabel)
        subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        view.addArrangedSubview(title)
        view.addArrangedSubview(subtitle)
        item.view = view
        return item
    }

    private func sectionTitle(_ title: String) -> NSMenuItem {
        let item = disabledItem(title.uppercased(), symbol: nil)
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 0.4
            ]
        )
        return item
    }

    private func disabledItem(_ title: String, symbol: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        }
        return item
    }

    private func actionItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func symbolForBattery(_ snapshot: BatterySnapshot) -> NSImage? {
        if snapshot.state == "charging" {
            return NSImage(systemSymbolName: "battery.100percent.bolt", accessibilityDescription: "Charging")
        }

        let numericPercent = Int(snapshot.percent.replacingOccurrences(of: "%", with: "")) ?? 0
        let symbol: String
        switch numericPercent {
        case 0..<25:
            symbol = "battery.25percent"
        case 25..<50:
            symbol = "battery.50percent"
        case 50..<75:
            symbol = "battery.75percent"
        default:
            symbol = "battery.100percent"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: "Battery")
    }

    private func statusSymbol(_ state: String) -> String {
        switch state {
        case "charging":
            return "bolt.fill"
        case "discharging":
            return "battery.75percent"
        case "charged":
            return "checkmark.circle"
        default:
            return "questionmark.circle"
        }
    }

    @available(macOS 13.0, *)
    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }

        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(
                title: "Open at Login",
                message: "macOS could not update the login item. Install Battery Usage in /Applications, then try again."
            )
        }

        rebuildMenu()
    }

    @objc private func openActivityMonitor() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }
}

func run(_ launchPath: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments

    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()

    do {
        try process.run()
    } catch {
        return ""
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func firstMatch(_ pattern: String, in string: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: string) else {
        return nil
    }
    return String(string[range])
}

func humanProcessName(_ raw: String) -> String {
    let url = URL(fileURLWithPath: raw)
    var name = url.lastPathComponent
    var appName = ""

    if let appRange = raw.range(of: ".app/") {
        let appPath = String(raw[..<appRange.lowerBound]) + ".app"
        appName = URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
    }

    switch name {
    case "Electron Helper", "Electron Helper (Renderer)", "Codex Helper", "Codex Helper (Renderer)", "Discord Helper (Renderer)", "plugin-container":
        if !appName.isEmpty, appName != name {
            name = "\(appName) (\(name))"
        }
    default:
        if !appName.isEmpty, name.lowercased() == appName.lowercased() {
            name = appName
        }
    }

    return name
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
delegate.start()
application.run()
