import AppKit
import Foundation
import GlideFrameKit
import UniformTypeIdentifiers

@MainActor
final class FormatConverterModel: ObservableObject {
    enum ToolchainState: Equatable {
        case checking
        case available(version: String)
        case unavailable(message: String)
    }

    enum JobStatus: Equatable {
        case ready
        case converting
        case completed
        case failed(String)
        case cancelled
    }

    struct Job: Identifiable, Equatable {
        let id: UUID
        let inputURL: URL
        let inputBytes: Int64
        var outputURL: URL?
        var progress: Double
        var status: JobStatus

        init(inputURL: URL) {
            id = UUID()
            self.inputURL = inputURL
            inputBytes = (try? inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            outputURL = nil
            progress = 0
            status = .ready
        }
    }

    @Published var settings = MediaConversionSettings()
    @Published var jobs: [Job] = []
    @Published var outputDirectory: URL
    @Published private(set) var toolchainState: ToolchainState = .checking
    @Published private(set) var isConverting = false

    private let service = FFmpegConversionService()
    private var queueTask: Task<Void, Never>?

    init() {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        outputDirectory = movies.appending(path: "GlideFrame/Conversions", directoryHint: .isDirectory)
    }

    var canStart: Bool {
        guard case .available = toolchainState, !isConverting else { return false }
        return jobs.contains { job in
            switch job.status {
            case .ready, .failed, .cancelled: true
            case .converting, .completed: false
            }
        }
    }

    var completedCount: Int { jobs.count(where: { $0.status == .completed }) }

    func refreshToolchain(force: Bool = false) async {
        toolchainState = .checking
        do {
            let toolchain = try await service.inspectToolchain(force: force)
            let version = toolchain.version
                .replacingOccurrences(of: "ffmpeg version ", with: "")
                .split(separator: " ")
                .first
                .map(String.init) ?? toolchain.version
            toolchainState = .available(version: version)
        } catch {
            toolchainState = .unavailable(message: error.localizedDescription)
        }
    }

    func chooseInputs() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.data]
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func add(_ urls: [URL]) {
        let existing = Set(jobs.map { $0.inputURL.standardizedFileURL })
        jobs += urls
            .filter { !existing.contains($0.standardizedFileURL) }
            .map(Job.init)
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectory = url
    }

    func updateFormat(_ format: MediaOutputFormat) {
        let previousKind = settings.format.kind
        settings.format = format
        if !format.compatibleCodecs.contains(settings.codec) {
            settings.codec = format.defaultCodec
        }
        if format.kind == .video, previousKind != .video {
            settings.includeAudio = true
        } else if format.kind != .video {
            settings.includeAudio = false
        }
    }

    func remove(_ id: UUID) {
        guard jobs.first(where: { $0.id == id })?.status != .converting else { return }
        jobs.removeAll { $0.id == id }
    }

    func clearCompleted() {
        jobs.removeAll { $0.status == .completed }
    }

    func start() {
        guard canStart else { return }
        isConverting = true
        let conversionSettings = settings
        queueTask = Task { [weak self] in
            await self?.runQueue(settings: conversionSettings)
        }
    }

    func cancel() {
        queueTask?.cancel()
        Task { await service.cancel() }
    }

    func reveal(_ job: Job) {
        guard let outputURL = job.outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
    }

    private func runQueue(settings: MediaConversionSettings) async {
        defer {
            isConverting = false
            queueTask = nil
        }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let jobIDs = jobs.compactMap { job -> UUID? in
            switch job.status {
            case .ready, .failed, .cancelled: job.id
            case .converting, .completed: nil
            }
        }
        for id in jobIDs {
            guard !Task.isCancelled, let index = jobs.firstIndex(where: { $0.id == id }) else { break }
            let inputURL = jobs[index].inputURL
            let outputURL = uniqueOutputURL(for: inputURL, format: settings.format)
            jobs[index].status = .converting
            jobs[index].progress = 0
            jobs[index].outputURL = outputURL

            do {
                try await service.convert(
                    input: inputURL,
                    output: outputURL,
                    settings: settings
                ) { [weak self] progress in
                    await self?.setProgress(progress, for: id)
                }
                guard let completedIndex = jobs.firstIndex(where: { $0.id == id }) else { continue }
                jobs[completedIndex].progress = 1
                jobs[completedIndex].status = .completed
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: outputURL)
                if let cancelledIndex = jobs.firstIndex(where: { $0.id == id }) {
                    jobs[cancelledIndex].status = .cancelled
                }
                break
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                if let failedIndex = jobs.firstIndex(where: { $0.id == id }) {
                    jobs[failedIndex].status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func setProgress(_ progress: Double, for id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status == .converting else { return }
        jobs[index].progress = progress
    }

    private func uniqueOutputURL(for input: URL, format: MediaOutputFormat) -> URL {
        let baseName = input.deletingPathExtension().lastPathComponent
        let inputExtension = input.pathExtension.lowercased()
        let suffix = inputExtension == format.fileExtension ? "-converted" : ""
        var candidate = outputDirectory.appending(path: "\(baseName)\(suffix).\(format.fileExtension)")
        var sequence = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = outputDirectory.appending(path: "\(baseName)\(suffix)-\(sequence).\(format.fileExtension)")
            sequence += 1
        }
        return candidate
    }
}
