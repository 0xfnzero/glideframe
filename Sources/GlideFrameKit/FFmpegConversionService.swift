import Foundation
public struct FFmpegToolchain: Equatable, Sendable {
    public let ffmpegURL: URL
    public let ffprobeURL: URL
    public let version: String
    public let encoders: Set<String>
}

public actor FFmpegConversionService {
    public enum ConversionError: LocalizedError {
        case ffmpegMissing
        case ffprobeMissing
        case encoderUnavailable(String)
        case probeFailed(String)
        case conversionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .ffmpegMissing:
                "FFmpeg was not found. Install it with Homebrew or bundle it in GlideFrame.app/Contents/Resources/Tools."
            case .ffprobeMissing:
                "ffprobe was not found next to FFmpeg."
            case .encoderUnavailable(let encoder):
                "This FFmpeg build does not provide the \(encoder) encoder."
            case .probeFailed(let message), .conversionFailed(let message):
                message
            }
        }
    }

    private var cachedToolchain: FFmpegToolchain?
    private var activeProcess: Process?

    public init() {}

    public func inspectToolchain(force: Bool = false) throws -> FFmpegToolchain {
        if !force, let cachedToolchain { return cachedToolchain }
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        let bundledFFmpeg = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "Tools")
        let ffmpegCandidates = [
            environment["GLIDEFRAME_FFMPEG_PATH"].map { URL(filePath: $0) },
            bundledFFmpeg,
            URL(filePath: "/opt/homebrew/bin/ffmpeg"),
            URL(filePath: "/usr/local/bin/ffmpeg")
        ].compactMap { $0 }
        guard let ffmpegURL = ffmpegCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw ConversionError.ffmpegMissing
        }

        let bundledFFprobe = Bundle.main.url(forResource: "ffprobe", withExtension: nil, subdirectory: "Tools")
        let ffprobeCandidates = [
            environment["GLIDEFRAME_FFPROBE_PATH"].map { URL(filePath: $0) },
            bundledFFprobe,
            ffmpegURL.deletingLastPathComponent().appending(path: "ffprobe"),
            URL(filePath: "/opt/homebrew/bin/ffprobe"),
            URL(filePath: "/usr/local/bin/ffprobe")
        ].compactMap { $0 }
        guard let ffprobeURL = ffprobeCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
            throw ConversionError.ffprobeMissing
        }

        let versionOutput = try runAndCapture(ffmpegURL, arguments: ["-hide_banner", "-version"])
        let version = versionOutput.split(separator: "\n").first.map(String.init) ?? "FFmpeg"
        let encoderOutput = try runAndCapture(ffmpegURL, arguments: ["-hide_banner", "-encoders"])
        let encoders = Set(encoderOutput.split(separator: "\n").compactMap { line -> String? in
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count >= 2, fields[0].count == 6 else { return nil }
            return String(fields[1])
        })
        let toolchain = FFmpegToolchain(
            ffmpegURL: ffmpegURL,
            ffprobeURL: ffprobeURL,
            version: version,
            encoders: encoders
        )
        cachedToolchain = toolchain
        return toolchain
    }

    public func convert(
        input: URL,
        output: URL,
        settings: MediaConversionSettings,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let toolchain = try inspectToolchain()
        guard toolchain.encoders.contains(settings.codec.requiredEncoder) else {
            throw ConversionError.encoderUnavailable(settings.codec.requiredEncoder)
        }
        let duration = try probeDuration(input, using: toolchain.ffprobeURL)
        let arguments = try FFmpegCommandBuilder.arguments(input: input, output: output, settings: settings)
        let process = Process()
        let progressPipe = Pipe()
        let errorURL = FileManager.default.temporaryDirectory
            .appending(path: "glideframe-ffmpeg-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            activeProcess = nil
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorURL)
        }

        process.executableURL = toolchain.ffmpegURL
        process.arguments = arguments
        process.standardOutput = progressPipe
        process.standardError = errorHandle

        let termination = ProcessTermination()
        process.terminationHandler = { process in
            let status = process.terminationStatus
            Task { await termination.finish(status) }
        }
        activeProcess = process
        do {
            try process.run()
        } catch {
            throw ConversionError.conversionFailed(error.localizedDescription)
        }

        let progressTask = Task {
            do {
                for try await line in progressPipe.fileHandleForReading.bytes.lines {
                    guard !Task.isCancelled else { return }
                    if let fraction = Self.progressFraction(line: line, duration: duration) {
                        await progress(fraction)
                    }
                }
            } catch {
                // The pipe closes normally when FFmpeg exits or is cancelled.
            }
        }

        let status = await termination.value()
        await progressTask.value
        try? errorHandle.synchronize()
        if status == 0 {
            await progress(1)
            return
        }

        let detail = Self.errorTail(at: errorURL)
        if status == SIGTERM || Task.isCancelled {
            throw CancellationError()
        }
        throw ConversionError.conversionFailed(detail.isEmpty ? "FFmpeg exited with status \(status)." : detail)
    }

    public func cancel() {
        guard let activeProcess, activeProcess.isRunning else { return }
        activeProcess.terminate()
    }

    private func probeDuration(_ input: URL, using ffprobeURL: URL) throws -> TimeInterval {
        let output = try runAndCapture(ffprobeURL, arguments: [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            input.path
        ])
        guard let duration = TimeInterval(output.trimmingCharacters(in: .whitespacesAndNewlines)), duration > 0 else {
            throw ConversionError.probeFailed("The input duration could not be read.")
        }
        return duration
    }

    private func runAndCapture(_ executable: URL, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let message = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ConversionError.probeFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return message
    }

    nonisolated private static func progressFraction(line: String, duration: TimeInterval) -> Double? {
        let prefixes = ["out_time_us=", "out_time_ms="]
        guard let prefix = prefixes.first(where: { line.hasPrefix($0) }),
              let microseconds = Double(line.dropFirst(prefix.count))
        else { return nil }
        return min(max(microseconds / 1_000_000 / duration, 0), 0.999)
    }

    nonisolated private static func errorTail(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let tail = data.suffix(8_000)
        return String(decoding: tail, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor ProcessTermination {
    private var status: Int32?
    private var continuations: [CheckedContinuation<Int32, Never>] = []

    func finish(_ status: Int32) {
        guard self.status == nil else { return }
        self.status = status
        continuations.forEach { $0.resume(returning: status) }
        continuations.removeAll()
    }

    func value() async -> Int32 {
        if let status { return status }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
