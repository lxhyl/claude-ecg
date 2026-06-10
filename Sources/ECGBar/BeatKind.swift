import Foundation

/// How a hook event manifests: the waveform to draw, the sound to play, and
/// what it means for the engine's state machine.
///
/// Pure value logic, kept separate from `HeartbeatEngine` so it is trivially
/// testable.
struct BeatKind: Equatable {
    enum Sound: Equatable { case blip, lowTone, chime }
    enum Consequence: Equatable { case stayActive, demandAttention, armFlatline, flatlineNow }

    let waveform: ECGView.BeatStyle
    let sound: Sound
    let consequence: Consequence

    private init(_ waveform: ECGView.BeatStyle, _ sound: Sound, _ consequence: Consequence) {
        self.waveform = waveform
        self.sound = sound
        self.consequence = consequence
    }

    init(event: String) {
        switch event {
        case "Stop":
            self.init(.normal, .blip, .armFlatline)
        case "StopFailure":
            self.init(.inverted, .lowTone, .armFlatline)
        case "SessionEnd":
            self.init(.normal, .blip, .flatlineNow)
        case "PostToolUseFailure", "PermissionDenied":
            self.init(.inverted, .lowTone, .stayActive)
        case "Notification", "PermissionRequest":
            self.init(.doublet, .chime, .demandAttention)
        default:
            self.init(.normal, .blip, .stayActive)
        }
    }
}
