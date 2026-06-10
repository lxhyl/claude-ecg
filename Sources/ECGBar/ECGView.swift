import AppKit

/// Scrolling ECG trace drawn inside the status-item button.
///
/// New samples feed in from the right edge at 60 Hz. The render ticker pauses
/// automatically once the trace has fully flattened, so an idle ECGBar costs
/// no CPU; the next beat restarts it.
final class ECGView: NSView {
    enum State { case idle, active, attention, armed, flatlining }
    enum BeatStyle { case normal, soft, inverted, doublet }

    var state: State = .idle { didSet { needsDisplay = true } }

    private static let frameInterval: TimeInterval = 1.0 / 60.0

    private var samples: [CGFloat] = []
    private var pulseQueue: [CGFloat] = []
    private var ticker: Timer?
    /// Consecutive ticks that appended a zero sample with an empty queue.
    /// Once it reaches the buffer width, every sample is zero and we can stop drawing.
    private var flatTicks = 0

    /// One heartbeat, sample-by-sample: P wave, PQ segment, QRS complex, ST segment, T wave.
    private static let pulseTemplate: [CGFloat] = {
        let p:     [CGFloat] = [0.00, 0.05, 0.10, 0.05, 0.00]
        let pq:    [CGFloat] = [0.00, 0.00]
        let q:     [CGFloat] = [-0.18]
        let r:     [CGFloat] = [0.55, 0.95, 0.55]
        let s:     [CGFloat] = [-0.28, -0.12]
        let st:    [CGFloat] = [0.00, 0.00, 0.00]
        let t:     [CGFloat] = [0.06, 0.14, 0.20, 0.16, 0.08, 0.02, 0.00]
        return p + pq + q + r + s + st + t
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ensureBufferSize()
    }

    required init?(coder: NSCoder) { fatalError("ECGView is created in code only") }

    deinit { ticker?.invalidate() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        ensureBufferSize()
        needsDisplay = true
    }

    func enqueueBeat(style: BeatStyle = .normal) {
        let template = Self.pulseTemplate
        switch style {
        case .normal:
            pulseQueue.append(contentsOf: template)
        case .soft:
            pulseQueue.append(contentsOf: template.map { $0 * 0.45 })
        case .inverted:
            pulseQueue.append(contentsOf: template.map { -$0 })
        case .doublet:
            pulseQueue.append(contentsOf: template)
            pulseQueue.append(contentsOf: [0, 0, 0])
            pulseQueue.append(contentsOf: template)
        }
        startTicker()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        flatTicks = 0
        ticker = Timer.commonModeTimer(interval: Self.frameInterval, tolerance: Self.frameInterval / 4) { [weak self] _ in
            self?.tick()
        }
    }

    private func ensureBufferSize() {
        let needed = max(1, Int(bounds.width.rounded()))
        if samples.count != needed {
            samples = Array(repeating: 0, count: needed)
        }
    }

    private func tick() {
        ensureBufferSize()
        let next: CGFloat = pulseQueue.isEmpty ? 0 : pulseQueue.removeFirst()
        if !samples.isEmpty {
            samples.removeFirst()
            samples.append(next)
        }
        needsDisplay = true

        if next == 0 && pulseQueue.isEmpty {
            flatTicks += 1
            if flatTicks >= samples.count {
                ticker?.invalidate()
                ticker = nil
            }
        } else {
            flatTicks = 0
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let mid = bounds.midY
        let amplitude = bounds.height * 0.40

        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineJoinStyle = .round
        path.lineCapStyle = .round

        for (i, v) in samples.enumerated() {
            let point = CGPoint(x: CGFloat(i), y: mid + v * amplitude)
            if i == 0 {
                path.move(to: point)
            } else {
                path.line(to: point)
            }
        }

        switch state {
        case .idle:        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
        case .active:      NSColor.systemGreen.setStroke()
        case .attention:   NSColor.systemPurple.setStroke()
        case .armed:       NSColor.systemOrange.setStroke()
        case .flatlining:  NSColor.systemRed.setStroke()
        }
        path.stroke()
    }
}
