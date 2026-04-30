import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var ecgView: ECGView!
    private var audio: AudioPlayer!
    private var engine: HeartbeatEngine!
    private var server: HookServer!

    private var statusLine: NSMenuItem!
    private var lastEventLine: NSMenuItem!
    private var muteBeatItem: NSMenuItem!
    private var muteAlarmItem: NSMenuItem!
    private var refreshTimer: Timer?

    private static let hooksSnippet: String = {
        let events = [
            "SessionStart", "SessionEnd",
            "UserPromptSubmit",
            "PreToolUse", "PostToolUse", "PostToolUseFailure",
            "SubagentStart", "SubagentStop",
            "Notification", "PermissionRequest", "PermissionDenied",
            "PreCompact", "PostCompact",
            "Stop", "StopFailure"
        ]
        let entries = events.map { e in
            "    \"\(e)\": [{ \"hooks\": [{ \"type\": \"command\", \"command\": \"curl -s -X POST 'http://localhost:7823/heartbeat?e=\(e)' >/dev/null 2>&1 || true\" }] }]"
        }
        return "{\n  \"hooks\": {\n" + entries.joined(separator: ",\n") + "\n  }\n}\n"
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        audio = AudioPlayer()
        audio.muteBeat = UserDefaults.standard.bool(forKey: "muteBeat")
        audio.muteAlarm = UserDefaults.standard.bool(forKey: "muteAlarm")

        statusItem = NSStatusBar.system.statusItem(withLength: 110)
        guard let button = statusItem.button else { return }
        button.title = ""
        ecgView = ECGView(frame: button.bounds)
        ecgView.autoresizingMask = [.width, .height]
        button.addSubview(ecgView)

        engine = HeartbeatEngine(view: ecgView, audio: audio)
        engine.onChange = { [weak self] in self?.updateMenuLines() }

        statusItem.menu = buildMenu()
        updateMenuLines()

        server = HookServer { [weak self] event in
            self?.engine.recordBeat(event: event)
        }
        do {
            try server.start()
        } catch {
            NSLog("ECGBar: hook server failed to start on 7823: \(error)")
            let alert = NSAlert()
            alert.messageText = "ECGBar couldn't bind port 7823"
            alert.informativeText = "Another process is using the port. Quit that process and relaunch ECGBar.\n\n\(error.localizedDescription)"
            alert.runModal()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMenuLines()
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let header = NSMenuItem(title: "ECG Bar", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        statusLine = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        lastEventLine = NSMenuItem(title: "Last beat: —", action: nil, keyEquivalent: "")
        lastEventLine.isEnabled = false
        menu.addItem(lastEventLine)

        menu.addItem(.separator())

        muteBeatItem = NSMenuItem(title: "Mute heartbeat blip", action: #selector(toggleMuteBeat), keyEquivalent: "")
        muteBeatItem.target = self
        muteBeatItem.state = audio.muteBeat ? .on : .off
        menu.addItem(muteBeatItem)

        muteAlarmItem = NSMenuItem(title: "Mute flatline alarm", action: #selector(toggleMuteAlarm), keyEquivalent: "")
        muteAlarmItem.target = self
        muteAlarmItem.state = audio.muteAlarm ? .on : .off
        menu.addItem(muteAlarmItem)

        menu.addItem(.separator())

        let test = NSMenuItem(title: "Send test heartbeat", action: #selector(sendTestBeat), keyEquivalent: "t")
        test.target = self
        menu.addItem(test)

        let install = NSMenuItem(title: "Install Claude Code hooks…", action: #selector(showHooks), keyEquivalent: "")
        install.target = self
        menu.addItem(install)

        let reveal = NSMenuItem(title: "Reveal settings.json", action: #selector(revealSettings), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit ECG Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    private func updateMenuLines() {
        let stateName: String
        switch engine.state {
        case .idle:        stateName = "Idle"
        case .active:      stateName = "Active"
        case .attention:   stateName = "Attention (Claude is waiting)"
        case .armed:       stateName = "Armed (Stop pending)"
        case .flatlining:  stateName = "Flatlining"
        }
        statusLine.title = "Status: \(stateName)"
        if let date = engine.lastEventDate {
            let secs = Int(Date().timeIntervalSince(date))
            lastEventLine.title = "Last beat: \(secs)s ago · \(engine.lastEvent)"
        } else {
            lastEventLine.title = "Last beat: —"
        }
    }

    @objc private func toggleMuteBeat() {
        audio.muteBeat.toggle()
        muteBeatItem.state = audio.muteBeat ? .on : .off
        UserDefaults.standard.set(audio.muteBeat, forKey: "muteBeat")
    }

    @objc private func toggleMuteAlarm() {
        audio.muteAlarm.toggle()
        muteAlarmItem.state = audio.muteAlarm ? .on : .off
        UserDefaults.standard.set(audio.muteAlarm, forKey: "muteAlarm")
    }

    @objc private func sendTestBeat() {
        engine.recordBeat(event: "test")
    }

    @objc private func revealSettings() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func showHooks() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add these hooks to ~/.claude/settings.json"
        alert.informativeText = "Merge the \"hooks\" object below into your existing settings.json. Existing /refresh entries continue to work — the server treats them as heartbeats."

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 280))
        textView.string = Self.hooksSnippet
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        let scroll = NSScrollView(frame: textView.frame)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll

        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Close")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.hooksSnippet, forType: .string)
        }
    }
}
