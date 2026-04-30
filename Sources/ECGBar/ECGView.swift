import AppKit

final class ECGView: NSView {
    enum State { case idle, active, attention, armed, flatlining }
    enum BeatStyle { case normal, soft, inverted, doublet }

    var state: State = .idle { didSet { needsDisplay = true } }

    private var samples: [CGFloat] = []
    private var pulseQueue: [CGFloat] = []
    private var ticker: Timer?

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
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { ticker?.invalidate() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        ensureBufferSize()
    }

    func enqueueBeat(style: BeatStyle = .normal) {
        let t = Self.pulseTemplate
        switch style {
        case .normal:
            pulseQueue.append(contentsOf: t)
        case .soft:
            pulseQueue.append(contentsOf: t.map { $0 * 0.45 })
        case .inverted:
            pulseQueue.append(contentsOf: t.map { -$0 })
        case .doublet:
            pulseQueue.append(contentsOf: t)
            pulseQueue.append(contentsOf: [0, 0, 0])
            pulseQueue.append(contentsOf: t)
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
            let x = CGFloat(i)
            let y = mid + v * amplitude
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.line(to: CGPoint(x: x, y: y))
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
