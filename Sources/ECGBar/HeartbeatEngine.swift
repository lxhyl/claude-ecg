import Foundation

final class HeartbeatEngine {
    let view: ECGView
    let audio: AudioPlayer

    var onChange: (() -> Void)?

    private(set) var lastEvent: String = "—"
    private(set) var lastEventDate: Date?
    private(set) var state: ECGView.State = .idle

    private var armTimer: Timer?
    private var idleTimer: Timer?
    private var fillerTimer: Timer?
    private let armInterval: TimeInterval = 3.0
    private let fillerInterval: TimeInterval = 2.0
    init(view: ECGView, audio: AudioPlayer) {
        self.view = view
        self.audio = audio
        fillerTimer = Timer.scheduledTimer(withTimeInterval: fillerInterval, repeats: true) { [weak self] _ in
            self?.tickFiller()
        }
    }

    private func tickFiller() {
        guard state == .active || state == .attention else { return }
        let last = lastEventDate ?? .distantPast
        if Date().timeIntervalSince(last) >= fillerInterval {
            view.enqueueBeat(style: .soft)
        }
    }

    func recordBeat(event: String) {
        DispatchQueue.main.async { [weak self] in
            self?.handle(event: event)
        }
    }

    private func handle(event: String) {
        lastEvent = event
        lastEventDate = Date()
        armTimer?.invalidate(); armTimer = nil
        idleTimer?.invalidate(); idleTimer = nil

        switch event {
        case "Stop":
            view.enqueueBeat(style: .normal)
            audio.playBeat()
            transition(to: .armed)
            armTimer = Timer.scheduledTimer(withTimeInterval: armInterval, repeats: false) { [weak self] _ in
                self?.fireFlatline()
            }

        case "StopFailure":
            view.enqueueBeat(style: .inverted)
            audio.playArrhythmia()
            transition(to: .armed)
            armTimer = Timer.scheduledTimer(withTimeInterval: armInterval, repeats: false) { [weak self] _ in
                self?.fireFlatline()
            }

        case "SessionEnd":
            view.enqueueBeat(style: .normal)
            audio.playBeat()
            fireFlatline()

        case "PostToolUseFailure", "PermissionDenied":
            view.enqueueBeat(style: .inverted)
            audio.playArrhythmia()
            transition(to: .active)

        case "Notification", "PermissionRequest":
            view.enqueueBeat(style: .doublet)
            audio.playAttention()
            transition(to: .attention)

        default:
            view.enqueueBeat(style: .normal)
            audio.playBeat()
            transition(to: .active)
        }
        onChange?()
    }

    private func fireFlatline() {
        transition(to: .flatlining)
        audio.playAlarm()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 2.7, repeats: false) { [weak self] _ in
            self?.transition(to: .idle)
            self?.onChange?()
        }
        onChange?()
    }

    private func transition(to newState: ECGView.State) {
        guard newState != state else { return }
        state = newState
        view.state = newState
    }
}
