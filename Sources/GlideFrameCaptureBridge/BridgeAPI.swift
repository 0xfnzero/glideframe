import AppKit
import CoreGraphics
import Foundation
import GlideFrameCapture
import GlideFrameKit

// Requests and recording run inside Tauri, under one macOS privacy identity.
@MainActor
private final class BridgeRuntime {
    static let shared = BridgeRuntime()
    private var recorder: MacNativeRecorder?
    private let converter = FFmpegConversionService()

    func call(_ command: String, arguments: Data) async throws -> Data {
        switch command {
        case "conversion-status": return try encode(try await converter.inspectToolchain().version)
        case "cancel-conversion": await converter.cancel(); return try encode(true)
        case "convert-media":
            let args = try JSONDecoder().decode(ConversionArguments.self, from: arguments)
            try await converter.convert(input: URL(filePath: args.input), output: URL(filePath: args.output), settings: args.settings) { _ in }
            return try encode(args.output)
        case "screen-capture-status": return try encode(CGPreflightScreenCaptureAccess())
        case "request-screen-capture-access": return try encode(CGRequestScreenCaptureAccess())
        case "list-capture-sources": return try encode(await MacCaptureSourceProvider.captureSources())
        case "list-audio-devices": return try encode(MacCaptureSourceProvider.audioDevices())
        case "list-camera-devices": return try encode(MacCaptureSourceProvider.cameraDevices())
        case "start-recording":
            guard recorder == nil else { throw HelperError.writerFailed("Another recording is already active.") }
            let args = try JSONDecoder().decode(StartArguments.self, from: arguments)
            let recorder = MacNativeRecorder()
            try await recorder.start(options: args.options, target: args.target, projectURL: URL(filePath: args.projectPath))
            self.recorder = recorder
            return try encode(true)
        case "pause-recording": recorder?.pause(); return try encode(true)
        case "resume-recording": recorder?.resume(); return try encode(true)
        case "stop-recording":
            guard let recorder else { throw HelperError.targetMissing }
            let result = try await recorder.stop()
            self.recorder = nil
            return try encode(result)
        case "export-project":
            let args = try JSONDecoder().decode(ExportArguments.self, from: arguments)
            let projectURL = URL(filePath: args.projectPath)
            var manifest = try await ProjectRepository().load(at: projectURL)
            switch args.preset {
            case "project": break
            case "hd": manifest.exportPreset = .hd
            case "ultraHD": manifest.exportPreset = .ultraHD
            case "source":
                if let screen = manifest.sources.first(where: { $0.kind == .screen }) {
                    manifest.exportPreset.width = screen.width ?? 1920
                    manifest.exportPreset.height = screen.height ?? 1080
                    manifest.canvas.padding = 0
                    manifest.canvas.aspectRatio = manifest.exportPreset.width == manifest.exportPreset.height ? .square : manifest.exportPreset.width > manifest.exportPreset.height ? .landscape : .portrait
                }
            default: throw HelperError.unsupportedCommand(args.preset)
            }
            let destination = URL(filePath: args.destination)
            try? FileManager.default.removeItem(at: destination)
            try await ExportService().export(manifest: manifest, packageURL: projectURL, destination: destination)
            return try encode(destination.path)
        default: throw HelperError.unsupportedCommand(command)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}

private struct StartArguments: Decodable {
    let options: HelperRecordingOptions
    let target: HelperCaptureSource
    let projectPath: String
}
private struct ConversionArguments: Decodable {
    let input: String
    let output: String
    let settings: MediaConversionSettings
}
private struct ExportArguments: Decodable {
    let projectPath: String
    let destination: String
    let preset: String
}
private final class BridgeReply: @unchecked Sendable {
    let ready = DispatchSemaphore(value: 0)
    var data = Data()
}

// Called from Rust's blocking pool; the main thread remains available to AppKit.
@_cdecl("glideframe_bridge_call")
public func glideframeBridgeCall(_ command: UnsafePointer<CChar>, _ json: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    let command = String(cString: command)
    let arguments = Data(String(cString: json).utf8)
    let reply = BridgeReply()
    Task { @MainActor in
        do {
            let value = try await BridgeRuntime.shared.call(command, arguments: arguments)
            let object = try JSONSerialization.jsonObject(with: value, options: [.fragmentsAllowed])
            reply.data = try JSONSerialization.data(withJSONObject: ["value": object], options: [.fragmentsAllowed])
        } catch {
            reply.data = (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data("{\"error\":\"Capture failed\"}".utf8)
        }
        reply.ready.signal()
    }
    reply.ready.wait()
    return strdup(String(decoding: reply.data, as: UTF8.self))
}
@_cdecl("glideframe_bridge_free")
public func glideframeBridgeFree(_ pointer: UnsafeMutablePointer<CChar>?) { free(pointer) }
