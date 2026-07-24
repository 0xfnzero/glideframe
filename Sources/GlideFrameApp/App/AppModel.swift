import AppKit
import Foundation
import GlideFrameKit
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [ProjectSummary] = []
    @Published var selectedManifest: ProjectManifest?
    @Published var selectedPackageURL: URL?
    @Published var recordingOptions = RecordingOptions()
    @Published var showsRecordingSetup = false
    @Published var isExporting = false
    @Published var notice: AppNotice?
    @Published var recoveredProjectCount = 0

    let recordingEngine = RecordingEngine()
    private let repository = ProjectRepository()
    private let exporter = ExportService()
    private var activeManifest: ProjectManifest?
    private var activePackageURL: URL?
    private var autosaveTask: Task<Void, Never>?

    func bootstrap() async {
        do {
            recoveredProjectCount = try await repository.recoverInterruptedProjects().count
            try await reloadProjects()
            try await recordingEngine.refreshTargets()
            recordingOptions.targetID = recordingEngine.targets.first?.id
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func reloadTargets() async {
        do {
            try await recordingEngine.refreshTargets()
            if !recordingEngine.targets.contains(where: { $0.id == recordingOptions.targetID }) {
                recordingOptions.targetID = recordingEngine.targets.first?.id
            }
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func select(_ summary: ProjectSummary) async {
        do {
            selectedManifest = try await repository.load(at: summary.packageURL)
            selectedPackageURL = summary.packageURL
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func startRecording() async {
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, HH:mm"
            let created = try await repository.createProject(title: "Recording \(formatter.string(from: Date()))")
            activeManifest = created.manifest
            activePackageURL = created.packageURL
            try await repository.writeRecoveryJournal(
                .init(projectID: created.manifest.id, state: .preparing, startedAt: Date(), sourcePaths: ["Sources"]),
                at: created.packageURL
            )
            try await recordingEngine.start(options: recordingOptions, packageURL: created.packageURL)
            try await repository.writeRecoveryJournal(
                .init(projectID: created.manifest.id, state: .recording, startedAt: Date(), sourcePaths: ["Sources"]),
                at: created.packageURL
            )
            showsRecordingSetup = false
        } catch {
            if let activePackageURL { try? await repository.clearRecoveryJournal(at: activePackageURL) }
            notice = .error(error.localizedDescription)
        }
    }

    func stopRecording() async {
        guard var manifest = activeManifest, let packageURL = activePackageURL else { return }
        do {
            let result = try await recordingEngine.stop()
            manifest.duration = result.duration
            manifest.sources = result.sources
            manifest.tracks = result.sources.map { .init(sourceID: $0.id, kind: $0.kind) }
            manifest.pointerEvents = result.events
            manifest.editGraph.clips = [.init(sourceRange: .init(start: 0, duration: result.duration))]
            manifest.editGraph.zoomKeyframes = AutoPolish.zoomKeyframes(from: result.events)
            try await repository.save(manifest, at: packageURL)
            try await repository.clearRecoveryJournal(at: packageURL)
            activeManifest = nil
            activePackageURL = nil
            try await reloadProjects()
            selectedManifest = try await repository.load(at: packageURL)
            selectedPackageURL = packageURL
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func updateManifest(_ update: (inout ProjectManifest) -> Void) {
        guard var manifest = selectedManifest else { return }
        update(&manifest)
        manifest.updatedAt = Date()
        selectedManifest = manifest
        scheduleAutosave()
    }

    func applyAutoPolish() {
        updateManifest { manifest in
            manifest.editGraph.zoomKeyframes = AutoPolish.zoomKeyframes(from: manifest.pointerEvents)
        }
        notice = .success(tr("auto_polish_applied"))
    }

    func export() async {
        guard let manifest = selectedManifest, let packageURL = selectedPackageURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(manifest.title).mp4"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            try? FileManager.default.removeItem(at: destination)
            try await exporter.export(manifest: manifest, packageURL: packageURL, destination: destination)
            notice = .success(tr("export_complete"))
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            notice = .error(error.localizedDescription)
        }
    }

    func revealProject() {
        guard let selectedPackageURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedPackageURL])
    }

    func sourceURL(kind: MediaSource.Kind = .screen) -> URL? {
        guard let packageURL = selectedPackageURL,
              let source = selectedManifest?.sources.first(where: { $0.kind == kind })
        else { return nil }
        return packageURL.appending(path: source.relativePath)
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self,
                  let manifest = self.selectedManifest,
                  let packageURL = self.selectedPackageURL
            else { return }
            do {
                try await self.repository.save(manifest, at: packageURL)
                try await self.reloadProjects()
            } catch {
                self.notice = .error(error.localizedDescription)
            }
        }
    }

    private func reloadProjects() async throws {
        projects = try await repository.listProjects()
    }
}

struct AppNotice: Identifiable, Equatable {
    enum Kind { case success, error }
    let id = UUID()
    let kind: Kind
    let message: String

    static func success(_ message: String) -> AppNotice { .init(kind: .success, message: message) }
    static func error(_ message: String) -> AppNotice { .init(kind: .error, message: message) }
}
