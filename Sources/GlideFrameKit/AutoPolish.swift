import Foundation

public enum AutoPolish {
    public static func zoomKeyframes(
        from events: [PointerEvent],
        minimumGap: TimeInterval = 1.25,
        scale: Double = 1.45
    ) -> [ZoomKeyframe] {
        let clicks = events
            .filter { $0.kind == .click }
            .sorted { $0.time < $1.time }

        var accepted: [PointerEvent] = []
        for click in clicks where accepted.last.map({ click.time - $0.time >= minimumGap }) ?? true {
            accepted.append(click)
        }

        return accepted.flatMap { click in
            let leadIn = max(0, click.time - 0.22)
            return [
                ZoomKeyframe(time: leadIn, scale: 1, focusX: click.x, focusY: click.y),
                ZoomKeyframe(time: click.time, scale: scale, focusX: click.x, focusY: click.y),
                ZoomKeyframe(time: click.time + 0.72, scale: scale, focusX: click.x, focusY: click.y),
                ZoomKeyframe(time: click.time + 1.05, scale: 1, focusX: click.x, focusY: click.y)
            ]
        }
    }
}

public enum ProjectTimeline {
    public static func outputDuration(for manifest: ProjectManifest) -> TimeInterval {
        if manifest.editGraph.clips.isEmpty { return manifest.duration }
        return manifest.editGraph.clips
            .filter { !$0.isRemoved }
            .reduce(0) { $0 + $1.sourceRange.duration }
    }

    public static func sourceTime(for outputTime: TimeInterval, clips: [ClipEdit]) -> TimeInterval? {
        var cursor: TimeInterval = 0
        for clip in clips where !clip.isRemoved {
            let next = cursor + clip.sourceRange.duration
            if outputTime >= cursor && outputTime <= next {
                return clip.sourceRange.start + (outputTime - cursor)
            }
            cursor = next
        }
        return nil
    }
}
