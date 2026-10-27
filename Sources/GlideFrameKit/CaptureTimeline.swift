import CoreMedia

/// Maps capture timestamps onto a continuous timeline, excluding paused input.
public struct CaptureTimeline {
    private var origin: CMTime?
    private var lastSourceTime: CMTime?
    private var pauseOffset = CMTime.zero
    private var paused = false
    private var resumePending = false
    private let frameInterval: CMTime

    public init(frameRate: Int) {
        frameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    }
    public mutating func pause() { paused = true }
    public mutating func resume() {
        guard paused else { return }
        paused = false
        resumePending = true
    }
    public mutating func presentationTime(for sourceTime: CMTime, isVideo: Bool) -> CMTime? {
        guard !paused else { return nil }
        if origin == nil {
            guard isVideo else { return nil }
            origin = sourceTime
        }
        if resumePending, let lastSourceTime {
            let gap = sourceTime - lastSourceTime - frameInterval
            if gap > .zero { pauseOffset = pauseOffset + gap }
            resumePending = false
        }
        lastSourceTime = max(lastSourceTime ?? sourceTime, sourceTime)
        let time = sourceTime - origin! - pauseOffset
        return time >= .zero ? time : nil
    }
}
