import Foundation

/// Routes incoming hook events to waveform, sound, and state transitions.
///
/// States: `idle → active ⇄ attention`, then `Stop`/`StopFailure` arms a grace
/// timer (`armed`); if nothing else arrives the trace flatlines with an alarm
/// and settles back to `idle`.
final class HeartbeatEngine {
    /// Grace period after Stop/StopFailure; any new event within it cancels the alarm.
    static let armGracePeriod: TimeInterval = 3.0
    /// Cadence of the soft "resting rate" filler beat while a long tool call runs.
    static let fillerInterval: TimeInterval = 2.0
    /// With no events at all for this long, give up and go quietly idle (no alarm) —
    /// covers sessions that die without ever sending Stop/SessionEnd.
    static let activityTimeout: TimeInterval = 600

    private let view: ECGView
    private let audio: AudioPlayer

    var onChange: (() -> Void)?

    private(set) var lastEvent: String = "—"
    private(set) var lastEventDate: Date?
    private(set) var state: ECGView.State = .idle

    private var armTimer: Timer?
    private var idleTimer: Timer?
    private var fillerTimer: Timer?

    init(view: ECGView, audio: AudioPlayer) {
        self.view = view
        self.audio = audio
        fillerTimer = Timer.commonModeTimer(interval: Self.fillerInterval, tolerance: 0.25) { [weak self] _ in
            self?.tickFiller()
        }
    }

    deinit {
        armTimer?.invalidate()
        idleTimer?.invalidate()
        fillerTimer?.invalidate()
    }

    /// Thread-safe entry point — the hook server calls this from its own queue.
    func recordBeat(event: String) {
        DispatchQueue.main.async { [weak self] in
            self?.handle(event: event)
        }
    }

    private func tickFiller() {
        guard state == .active || state == .attention else { return }
        let sinceLast = Date().timeIntervalSince(lastEventDate ?? .distantPast)
        if state == .active && sinceLast >= Self.activityTimeout {
            transition(to: .idle)
            onChange?()
            return
        }
        if sinceLast >= Self.fillerInterval {
            view.enqueueBeat(style: .soft)
        }
    }

    private func handle(event: String) {
        lastEvent = event
        lastEventDate = Date()
        armTimer?.invalidate(); armTimer = nil
        idleTimer?.invalidate(); idleTimer = nil

        let beat = BeatKind(event: event)
        view.enqueueBeat(style: beat.waveform)

        switch beat.sound {
        case .blip:    audio.playBeat()
        case .lowTone: audio.playArrhythmia()
        case .chime:   audio.playAttention()
        }

        switch beat.consequence {
        case .stayActive:
            transition(to: .active)
        case .demandAttention:
            transition(to: .attention)
        case .armFlatline:
            transition(to: .armed)
            armTimer = Timer.commonModeTimer(interval: Self.armGracePeriod, repeats: false) { [weak self] _ in
                self?.fireFlatline()
            }
        case .flatlineNow:
            fireFlatline()
        }
        onChange?()
    }

    private func fireFlatline() {
        transition(to: .flatlining)
        audio.playAlarm()
        idleTimer = Timer.commonModeTimer(interval: AudioPlayer.alarmDuration + 0.2, repeats: false) { [weak self] _ in
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
