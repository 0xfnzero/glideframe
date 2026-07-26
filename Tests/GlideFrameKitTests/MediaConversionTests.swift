import Foundation
import XCTest
@testable import GlideFrameKit

final class MediaConversionTests: XCTestCase {
    private let input = URL(filePath: "/tmp/input.mov")

    func testEveryOutputFormatHasACompatibleDefaultCodec() {
        for format in MediaOutputFormat.allCases {
            XCTAssertFalse(format.compatibleCodecs.isEmpty)
            XCTAssertTrue(format.compatibleCodecs.contains(format.defaultCodec))
            XCTAssertFalse(format.fileExtension.isEmpty)
        }
    }

    func testWebMUsesVP9AndOpus() throws {
        let settings = MediaConversionSettings(format: .webm, codec: .vp9)
        let arguments = try FFmpegCommandBuilder.arguments(
            input: input,
            output: URL(filePath: "/tmp/output.webm"),
            settings: settings
        )

        XCTAssertTrue(arguments.containsSubsequence(["-c:v", "libvpx-vp9"]))
        XCTAssertTrue(arguments.containsSubsequence(["-c:a", "libopus"]))
        XCTAssertEqual(arguments.last, "/tmp/output.webm")
    }

    func testAudioOutputRemovesVideo() throws {
        let settings = MediaConversionSettings(format: .mp3, codec: .mp3)
        let arguments = try FFmpegCommandBuilder.arguments(
            input: input,
            output: URL(filePath: "/tmp/output.mp3"),
            settings: settings
        )

        XCTAssertTrue(arguments.contains("-vn"))
        XCTAssertTrue(arguments.containsSubsequence(["-c:a", "libmp3lame"]))
        XCTAssertFalse(arguments.contains("-c:v"))
    }

    func testGIFUsesPaletteAndNoAudio() throws {
        let settings = MediaConversionSettings(
            format: .gif,
            codec: .gif,
            resolution: .hd720,
            frameRate: .fps24,
            quality: .balanced,
            includeAudio: false
        )
        let arguments = try FFmpegCommandBuilder.arguments(
            input: input,
            output: URL(filePath: "/tmp/output.gif"),
            settings: settings
        )

        let filterIndex = try XCTUnwrap(arguments.firstIndex(of: "-filter_complex"))
        XCTAssertTrue(arguments[filterIndex + 1].contains("palettegen"))
        XCTAssertTrue(arguments[filterIndex + 1].contains("fps=24"))
        XCTAssertTrue(arguments.contains("-an"))
    }

    func testRejectsIncompatibleCodec() {
        let settings = MediaConversionSettings(format: .webm, codec: .hevc)
        XCTAssertThrowsError(try FFmpegCommandBuilder.arguments(
            input: input,
            output: URL(filePath: "/tmp/output.webm"),
            settings: settings
        )) { error in
            XCTAssertEqual(
                error as? FFmpegCommandBuilder.BuilderError,
                .incompatibleCodec(format: .webm, codec: .hevc)
            )
        }
    }

    func testFFmpegServiceConvertsEveryOutputFormat() async throws {
        let service = FFmpegConversionService()
        let toolchain: FFmpegToolchain
        do {
            toolchain = try await service.inspectToolchain()
        } catch {
            throw XCTSkip("FFmpeg integration test skipped: \(error.localizedDescription)")
        }

        let root = FileManager.default.temporaryDirectory
            .appending(path: "glideframe-conversion-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source.mp4")
        try runProcess(toolchain.ffmpegURL, arguments: [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=size=320x180:rate=24",
            "-f", "lavfi", "-i", "sine=frequency=1000:sample_rate=48000",
            "-t", "1", "-shortest",
            "-c:v", "mpeg4", "-q:v", "4", "-c:a", "aac",
            source.path
        ])

        var convertedOutputs: [(format: MediaOutputFormat, url: URL)] = []
        for format in MediaOutputFormat.allCases {
            let codec = format.defaultCodec
            guard toolchain.encoders.contains(codec.requiredEncoder) else { continue }
            let output = root.appending(path: "output.\(format.fileExtension)")
            let progress = ProgressRecorder()
            let settings = MediaConversionSettings(
                format: format,
                codec: codec,
                resolution: .source,
                frameRate: .source,
                quality: .compact,
                includeAudio: format.kind == .video
            )
            try await service.convert(input: source, output: output, settings: settings) { value in
                await progress.append(value)
            }

            let values = await progress.values
            XCTAssertEqual(values.last, 1, "Missing completion progress for \(format.displayName)")
            let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertGreaterThan(size, 0, "Empty output for \(format.displayName)")
            convertedOutputs.append((format, output))
        }

        for converted in convertedOutputs {
            let isAudio = converted.format.kind == .audio
            let roundTripFormat: MediaOutputFormat = isAudio ? .wav : .mp4
            let roundTripSettings = MediaConversionSettings(
                format: roundTripFormat,
                codec: roundTripFormat.defaultCodec,
                resolution: .source,
                frameRate: .source,
                quality: .compact,
                includeAudio: !isAudio
            )
            let roundTripOutput = root.appending(
                path: "roundtrip-\(converted.format.fileExtension).\(roundTripFormat.fileExtension)"
            )
            try await service.convert(
                input: converted.url,
                output: roundTripOutput,
                settings: roundTripSettings
            ) { _ in }
            let size = try roundTripOutput.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertGreaterThan(size, 0, "Could not read \(converted.format.displayName) as an input")
        }

        for format in MediaOutputFormat.allCases where format.kind == .video {
            for codec in format.compatibleCodecs.dropFirst() where toolchain.encoders.contains(codec.requiredEncoder) {
                let output = root.appending(path: "codec-\(format.fileExtension)-\(codec.rawValue).\(format.fileExtension)")
                let settings = MediaConversionSettings(
                    format: format,
                    codec: codec,
                    resolution: .source,
                    frameRate: .source,
                    quality: .compact,
                    includeAudio: true
                )
                try await service.convert(input: source, output: output, settings: settings) { _ in }
                let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                XCTAssertGreaterThan(size, 0, "Failed \(format.displayName) with \(codec.displayName)")
            }
        }
    }

    private func runProcess(_ executable: URL, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MediaConversionTests",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: errorData, as: UTF8.self)]
            )
        }
    }
}

private actor ProgressRecorder {
    private(set) var values: [Double] = []

    func append(_ value: Double) {
        values.append(value)
    }
}

private extension Array where Element == String {
    func containsSubsequence(_ values: [String]) -> Bool {
        guard values.count <= count else { return false }
        return indices.contains { index in
            let end = index + values.count
            guard end <= count else { return false }
            return Array(self[index..<end]) == values
        }
    }
}
