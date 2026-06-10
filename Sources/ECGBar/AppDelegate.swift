import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let statusItemWidth: CGFloat = 110
    private static let menuRefreshInterval: TimeInterval = 1.0

    private var statusItem: NSStatusItem!
    private var ecgView: ECGView!
    private var audio: AudioPlayer!
    private var engine: HeartbeatEngine!
    private var server: HookServer!

    private var statusLine: NSMenuItem!
    private var lastEventLine: NSMenuItem!
    private var muteBeatItem: NSMenuItem!
    private var muteAlarmItem: NSMenuItem!
    /// Keeps the "Last beat: Xs ago" line ticking — only runs while the menu is open.
    private var menuRefreshTimer: Timer?

    private let port = AppConfig.port
    private lazy var hooksSnippet = HooksSnippet.render(port: port)

    func applicationDidFinishLaunching(_ notification: Notification) {
        audio = AudioPlayer()
        audio.muteBeat = UserDefaults.standard.bool(forKey: AppConfig.DefaultsKey.muteBeat)
        audio.muteAlarm = UserDefaults.standard.bool(forKey: AppConfig.DefaultsKey.muteAlarm)

        statusItem = NSStatusBar.system.statusItem(withLength: Self.statusItemWidth)
        guard let button = statusItem.button else {
            NSLog("ECGBar: no status item button available; quitting")
            NSApp.terminate(nil)
            return
        }
        button.toolTip = "ECGBar — Claude Code activity"
        ecgView = ECGView(frame: button.bounds)
        ecgView.autoresizingMask = [.width, .height]
        button.addSubview(ecgView)

        engine = HeartbeatEngine(view: ecgView, audio: audio)
        engine.onChange = { [weak self] in self?.updateMenuLines() }

        statusItem.menu = buildMenu()
        updateMenuLines()
        startServer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func startServer() {
        server = HookServer { [weak self] event in
            self?.engine.recordBeat(event: event)
        }
        do {
            try server.start(port: port) { [weak self] error in
                self?.presentServerFailure(error)
            }
        } catch {
            presentServerFailure(error)
        }
    }

    private func presentServerFailure(_ error: Error) {
        NSLog("ECGBar: hook server failed to start on \(port): \(error)")
        let alert = NSAlert()
        alert.messageText = "ECGBar couldn't listen on port \(port)"
        alert.informativeText = "Another process is probably using the port. Quit it and relaunch ECGBar, or pick a different port (see README → Configuration).\n\n\(error.localizedDescription)"
        alert.runModal()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let header = NSMenuItem(title: "ECG Bar v\(AppConfig.version)", action: nil, keyEquivalent: "")
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

        let github = NSMenuItem(title: "ECGBar on GitHub", action: #selector(openRepository), keyEquivalent: "")
        github.target = self
        menu.addItem(github)

        let quit = NSMenuItem(title: "Quit ECG Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuLines()
        menuRefreshTimer = Timer.commonModeTimer(interval: Self.menuRefreshInterval, tolerance: 0.1) { [weak self] _ in
            self?.updateMenuLines()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }

    private func updateMenuLines() {
        guard statusLine != nil else { return }
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

    // MARK: - Actions

    @objc private func toggleMuteBeat() {
        audio.muteBeat.toggle()
        muteBeatItem.state = audio.muteBeat ? .on : .off
        UserDefaults.standard.set(audio.muteBeat, forKey: AppConfig.DefaultsKey.muteBeat)
    }

    @objc private func toggleMuteAlarm() {
        audio.muteAlarm.toggle()
        muteAlarmItem.state = audio.muteAlarm ? .on : .off
        UserDefaults.standard.set(audio.muteAlarm, forKey: AppConfig.DefaultsKey.muteAlarm)
    }

    @objc private func sendTestBeat() {
        engine.recordBeat(event: "test")
    }

    @objc private func revealSettings() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(AppConfig.repositoryURL)
    }

    @objc private func showHooks() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Add these hooks to ~/.claude/settings.json"
        alert.informativeText = "Merge the \"hooks\" object below into your existing settings.json. Existing /refresh entries continue to work — the server treats them as heartbeats."

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 280))
        textView.string = hooksSnippet
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
            NSPasteboard.general.setString(hooksSnippet, forType: .string)
        }
    }
}
