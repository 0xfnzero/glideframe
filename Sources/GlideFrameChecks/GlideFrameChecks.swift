import Foundation
import GlideFrameKit

@main
struct GlideFrameChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(rootURL: root)
        let created = try await repository.createProject(title: "Verification")
        var manifest = created.manifest
        manifest.duration = 42
        try await repository.save(manifest, at: created.packageURL)
        let loaded = try await repository.load(at: created.packageURL)
        precondition(loaded.duration == 42)

        let events = [
            PointerEvent(time: 1, x: 0.2, y: 0.4, kind: .click),
            PointerEvent(time: 1.4, x: 0.6, y: 0.7, kind: .click),
            PointerEvent(time: 3, x: 2, y: -1, kind: .click)
        ]
        let keyframes = AutoPolish.zoomKeyframes(from: events)
        precondition(keyframes.count == 8)
        precondition(keyframes[5].focusX == 1 && keyframes[5].focusY == 0)

        let clips = [
            ClipEdit(sourceRange: .init(start: 0, duration: 5)),
            ClipEdit(sourceRange: .init(start: 5, duration: 3), isRemoved: true),
            ClipEdit(sourceRange: .init(start: 8, duration: 4))
        ]
        precondition(ProjectTimeline.sourceTime(for: 6, clips: clips) == 9)
        print("GlideFrameKit checks passed")
    }
}
