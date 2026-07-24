import Foundation

public struct ProjectSummary: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var updatedAt: Date
    public var duration: TimeInterval
    public var packageURL: URL
}

public struct RecoveryJournal: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case preparing, recording, finalizing, interrupted }

    public var projectID: UUID
    public var state: State
    public var startedAt: Date
    public var sourcePaths: [String]

    public init(projectID: UUID, state: State, startedAt: Date, sourcePaths: [String]) {
        self.projectID = projectID
        self.state = state
        self.startedAt = startedAt
        self.sourcePaths = sourcePaths
    }
}

public actor ProjectRepository {
    public enum RepositoryError: LocalizedError {
        case unsupportedSchema(Int)
        case invalidPackage(URL)

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version): "Unsupported project schema version \(version)."
            case .invalidPackage(let url): "Invalid project package at \(url.path)."
            }
        }
    }

    public let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
        self.encoder = JSONEncoder.screenVedio
        self.decoder = JSONDecoder.screenVedio
    }

    public static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let movies = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first!
        return movies.appending(path: "GlideFrame/Projects", directoryHint: .isDirectory)
    }

    @discardableResult
    public func createProject(title: String) throws -> (manifest: ProjectManifest, packageURL: URL) {
        try ensureRoot()
        let manifest = ProjectManifest(title: title)
        let packageURL = rootURL.appending(path: "\(manifest.id.uuidString).svproject", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: packageURL.appending(path: "Sources"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: packageURL.appending(path: "Exports"), withIntermediateDirectories: true)
        try save(manifest, at: packageURL)
        return (manifest, packageURL)
    }

    public func save(_ manifest: ProjectManifest, at packageURL: URL) throws {
        var copy = manifest
        copy.updatedAt = Date()
        let destination = packageURL.appending(path: "manifest.json")
        let temporary = packageURL.appending(path: "manifest.json.tmp")
        try encoder.encode(copy).write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    public func load(at packageURL: URL) throws -> ProjectManifest {
        let manifestURL = packageURL.appending(path: "manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw RepositoryError.invalidPackage(packageURL)
        }
        let manifest = try decoder.decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.schemaVersion <= ProjectManifest.currentSchemaVersion else {
            throw RepositoryError.unsupportedSchema(manifest.schemaVersion)
        }
        return manifest
    }

    public func listProjects() throws -> [ProjectSummary] {
        try ensureRoot()
        return try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "svproject" }
        .compactMap { url in
            guard let manifest = try? load(at: url) else { return nil }
            return ProjectSummary(
                id: manifest.id,
                title: manifest.title,
                updatedAt: manifest.updatedAt,
                duration: manifest.duration,
                packageURL: url
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func writeRecoveryJournal(_ journal: RecoveryJournal, at packageURL: URL) throws {
        let url = packageURL.appending(path: "recovery.json")
        try encoder.encode(journal).write(to: url, options: .atomic)
    }

    public func clearRecoveryJournal(at packageURL: URL) throws {
        let url = packageURL.appending(path: "recovery.json")
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    public func recoverInterruptedProjects() throws -> [ProjectSummary] {
        let projects = try listProjects()
        var recovered: [ProjectSummary] = []
        for project in projects {
            let journalURL = project.packageURL.appending(path: "recovery.json")
            guard fileManager.fileExists(atPath: journalURL.path),
                  var journal = try? decoder.decode(RecoveryJournal.self, from: Data(contentsOf: journalURL))
            else { continue }
            journal.state = .interrupted
            try encoder.encode(journal).write(to: journalURL, options: .atomic)
            recovered.append(project)
        }
        return recovered
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
}

private extension JSONEncoder {
    static var screenVedio: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var screenVedio: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
