import Foundation
import XCTest
@testable import GlideFrameKit

final class ProjectModelTests: XCTestCase {
    func testProjectRoundTripAndRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(rootURL: root)
        let created = try await repository.createProject(title: "Demo")
        var manifest = created.manifest
        manifest.duration = 42
        try await repository.save(manifest, at: created.packageURL)

        let loaded = try await repository.load(at: created.packageURL)
        XCTAssertEqual(loaded.title, "Demo")
        XCTAssertEqual(loaded.duration, 42)

        let journal = RecoveryJournal(
            projectID: manifest.id,
            state: .recording,
            startedAt: Date(),
            sourcePaths: ["Sources/screen.mov"]
        )
        try await repository.writeRecoveryJournal(journal, at: created.packageURL)
        let recovered = try await repository.recoverInterruptedProjects()
        XCTAssertEqual(recovered.map(\.id), [manifest.id])
    }

    func testAutoPolishDebouncesClicksAndClampsFocus() {
        let events = [
            PointerEvent(time: 1, x: 0.2, y: 0.4, kind: .click),
            PointerEvent(time: 1.4, x: 0.6, y: 0.7, kind: .click),
            PointerEvent(time: 3, x: 2, y: -1, kind: .click)
        ]
        let keyframes = AutoPolish.zoomKeyframes(from: events)
        XCTAssertEqual(keyframes.count, 8)
        XCTAssertEqual(keyframes[1].scale, 1.45)
        XCTAssertEqual(keyframes[5].focusX, 1)
        XCTAssertEqual(keyframes[5].focusY, 0)
    }

    func testTimelineMapsAcrossRemovedClips() {
        let clips = [
            ClipEdit(sourceRange: .init(start: 0, duration: 5)),
            ClipEdit(sourceRange: .init(start: 5, duration: 3), isRemoved: true),
            ClipEdit(sourceRange: .init(start: 8, duration: 4))
        ]
        XCTAssertEqual(ProjectTimeline.sourceTime(for: 6, clips: clips), 9)
    }
}
