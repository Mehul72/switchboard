import Foundation

/// Runs event taps away from the main thread.
///
/// An active tap holds every matching event, in every app, until its callback
/// returns. On the main run loop that turned any stall in Switchboard into
/// lag for the whole Mac: scrolling for the wheel tap, typing for the
/// Command-Tab tap.
final class EventTapThread: @unchecked Sendable {
    static let shared = EventTapThread()

    private let runLoop: CFRunLoop

    private init() {
        let thread = RunLoopThread()
        thread.name = "com.Mehul72.switchboard.event-taps"
        thread.qualityOfService = .userInteractive
        thread.start()
        runLoop = thread.waitForRunLoop()
    }

    /// True when called from the tap thread, which is where callbacks run.
    var isCurrent: Bool { CFEqual(CFRunLoopGetCurrent(), runLoop) }

    func add(_ source: CFRunLoopSource) {
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CFRunLoopWakeUp(runLoop)
    }

    /// Returns once the source is gone and no callback of it is running.
    func remove(_ source: CFRunLoopSource) {
        perform { CFRunLoopRemoveSource(self.runLoop, source, .commonModes) }
    }

    /// Runs `work` on the tap thread and waits for it.
    ///
    /// Callbacks run on this thread one at a time, so work done here cannot
    /// overlap one. That is what makes it safe to release a tap's state
    /// straight afterwards.
    func perform(_ work: @escaping () -> Void) {
        guard !isCurrent else {
            work()
            return
        }
        let finished = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
            work()
            finished.signal()
        }
        CFRunLoopWakeUp(runLoop)
        finished.wait()
    }
}

private final class RunLoopThread: Thread {
    private let started = DispatchSemaphore(value: 0)
    private var runLoop: CFRunLoop?

    func waitForRunLoop() -> CFRunLoop {
        started.wait()
        // Set before the semaphore is signalled, on the thread itself.
        return runLoop!
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A run loop with nothing to wait on returns at once. This port is
        // never signalled; it keeps the loop waiting between taps.
        RunLoop.current.add(NSMachPort(), forMode: .common)
        started.signal()
        CFRunLoopRun()
    }
}
