import Foundation
import XCTest
@testable import GlideFrameKit

final class ProjectModelTests: XCTestCase {
    func testReadsTauriFieldNamesAndNestedProjects() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(rootURL: root)
        let created = try await repository.createProject(title: "Tauri compatibility")
        var manifest = created.manifest
        let source = MediaSource(kind: .screen, relativePath: "media/screen.mp4", duration: 3)
        manifest.sources = [source]
        manifest.tracks = [.init(sourceID: source.id, kind: .screen)]
        try await repository.save(manifest, at: created.packageURL)
        let url = created.packageURL.appending(path: "manifest.json")
        var json = try String(contentsOf: url, encoding: .utf8)
        json = json.replacingOccurrences(of: "sourceID", with: "sourceId")
        // Earlier Rust builds emitted fractional RFC 3339 dates.
        json = json.replacingOccurrences(of: "Z\"", with: ".123Z\"")
        try json.write(to: url, atomically: true, encoding: .utf8)
        let nested = root.appending(path: "2026-10-27")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let moved = nested.appending(path: created.packageURL.lastPathComponent)
        try FileManager.default.moveItem(at: created.packageURL, to: moved)
        let loaded = try await repository.load(at: moved)
        XCTAssertEqual(loaded.tracks.first?.sourceID, source.id)
        let summaries = try await repository.listProjects()
        XCTAssertEqual(summaries.map(\.id), [manifest.id])
    }
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

    func testRecoverySkipsLiveOwnerAndRecoversExitedOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ProjectRepository(rootURL: root)
        let created = try await repository.createProject(title: "Active in another client")
        var journal = RecoveryJournal(projectID: created.manifest.id, state: .recording,
            startedAt: Date(), sourcePaths: ["media/screen.mp4"],
            ownerProcessID: ProcessInfo.processInfo.processIdentifier)
        try await repository.writeRecoveryJournal(journal, at: created.packageURL)
        let live = try await repository.recoverInterruptedProjects()
        XCTAssertTrue(live.isEmpty)
        journal.ownerProcessID = Int32.max
        try await repository.writeRecoveryJournal(journal, at: created.packageURL)
        let exited = try await repository.recoverInterruptedProjects()
        XCTAssertEqual(exited.map(\.id), [created.manifest.id])
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
