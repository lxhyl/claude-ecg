import Foundation

extension Timer {
    /// Schedules a timer on the main run loop in `.common` modes.
    ///
    /// `Timer.scheduledTimer` registers in `.default` mode only, which stalls while
    /// AppKit tracks a menu — freezing the ECG trace and delaying the flatline
    /// countdown whenever any menu is open. `.common` modes keep firing throughout.
    /// Must be called from the main thread.
    @discardableResult
    static func commonModeTimer(interval: TimeInterval,
                                repeats: Bool = true,
                                tolerance: TimeInterval = 0,
                                block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
