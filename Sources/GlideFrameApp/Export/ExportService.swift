@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import GlideFrameKit

actor ExportService {
    enum ExportError: LocalizedError {
        case screenSourceMissing
        case videoTrackMissing
        case cannotCreateTrack
        case cannotCreateExporter
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .screenSourceMissing: "The project has no screen recording."
            case .videoTrackMissing: "The screen recording has no video track."
            case .cannotCreateTrack: "The export timeline could not be created."
            case .cannotCreateExporter: "The selected export codec is unavailable."
            case .exportFailed(let message): message
            }
        }
    }

    func export(manifest: ProjectManifest, packageURL: URL, destination: URL) async throws {
        guard let source = manifest.sources.first(where: { $0.kind == .screen }) else { throw ExportError.screenSourceMissing }
        let asset = AVURLAsset(url: packageURL.appending(path: source.relativePath))
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first else { throw ExportError.videoTrackMissing }
        let composition = AVMutableComposition()
        guard let destinationVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.cannotCreateTrack
        }
        let sourceSystemAudio = try await asset.loadTracks(withMediaType: .audio).first
        let destinationSystemAudio = sourceSystemAudio.flatMap { _ in
            composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        }
        var microphoneAudio: (source: AVAssetTrack, destination: AVMutableCompositionTrack)?
        if let microphone = manifest.sources.first(where: { $0.kind == .microphone }) {
            let microphoneAsset = AVURLAsset(url: packageURL.appending(path: microphone.relativePath))
            if let source = try await microphoneAsset.loadTracks(withMediaType: .audio).first,
               let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                microphoneAudio = (source, destination)
            }
        }

        let clips = manifest.editGraph.clips.isEmpty
            ? [ClipEdit(sourceRange: .init(start: 0, duration: manifest.duration))]
            : manifest.editGraph.clips.filter { !$0.isRemoved }
        var cursor = CMTime.zero
        for clip in clips {
            let range = CMTimeRange(
                start: CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600),
                duration: CMTime(seconds: clip.sourceRange.duration, preferredTimescale: 600)
            )
            try destinationVideo.insertTimeRange(range, of: sourceVideo, at: cursor)
            if let sourceSystemAudio, let destinationSystemAudio {
                try destinationSystemAudio.insertTimeRange(range, of: sourceSystemAudio, at: cursor)
            }
            if let microphoneAudio {
                try microphoneAudio.destination.insertTimeRange(range, of: microphoneAudio.source, at: cursor)
            }
            cursor = CMTimeAdd(cursor, range.duration)
        }

        let naturalSize = try await sourceVideo.load(.naturalSize)
        let preferredTransform = try await sourceVideo.load(.preferredTransform)
        destinationVideo.preferredTransform = preferredTransform
        let videoComposition = makeVideoComposition(
            track: destinationVideo,
            sourceSize: naturalSize.applying(preferredTransform).absoluteSize,
            manifest: manifest,
            duration: cursor
        )

        let preset = manifest.exportPreset.codec == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else { throw ExportError.cannotCreateExporter }
        exporter.outputURL = destination
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition
        exporter.audioMix = makeAudioMix(
            manifest: manifest,
            systemAudio: destinationSystemAudio,
            microphone: microphoneAudio?.destination
        )
        await exporter.export()
        guard exporter.status == .completed else {
            throw ExportError.exportFailed(exporter.error?.localizedDescription ?? "Export failed.")
        }
    }

    private func makeAudioMix(
        manifest: ProjectManifest,
        systemAudio: AVCompositionTrack?,
        microphone: AVCompositionTrack?
    ) -> AVAudioMix? {
        var parameters: [AVAudioMixInputParameters] = []
        if let systemAudio {
            let input = AVMutableAudioMixInputParameters(track: systemAudio)
            input.setVolume(Float(volume(for: .screen, in: manifest)), at: .zero)
            parameters.append(input)
        }
        if let microphone {
            let input = AVMutableAudioMixInputParameters(track: microphone)
            input.setVolume(Float(volume(for: .microphone, in: manifest)), at: .zero)
            parameters.append(input)
        }
        guard !parameters.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = parameters
        return mix
    }

    private func volume(for kind: MediaSource.Kind, in manifest: ProjectManifest) -> Double {
        manifest.tracks.first(where: { $0.kind == kind && $0.isEnabled })?.volume ?? (kind == .screen ? 1 : 0)
    }

    private func makeVideoComposition(
        track: AVCompositionTrack,
        sourceSize: CGSize,
        manifest: ProjectManifest,
        duration: CMTime
    ) -> AVMutableVideoComposition {
        let preset = manifest.exportPreset
        let renderSize = CGSize(width: preset.width, height: preset.height)
        let padding = CGFloat(manifest.canvas.padding)
        let available = CGSize(width: renderSize.width - padding * 2, height: renderSize.height - padding * 2)
        let fit = min(available.width / sourceSize.width, available.height / sourceSize.height)
        let fitted = CGSize(width: sourceSize.width * fit, height: sourceSize.height * fit)
        let origin = CGPoint(x: (renderSize.width - fitted.width) / 2, y: (renderSize.height - fitted.height) / 2)
        let base = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: fit, y: fit)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.backgroundColor = manifest.canvas.background.cgColor
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(base, at: .zero)
        for frame in manifest.editGraph.zoomKeyframes where frame.time <= duration.seconds {
            let scale = CGFloat(frame.scale)
            let focus = CGPoint(x: renderSize.width * frame.focusX, y: renderSize.height * frame.focusY)
            let transform = base
                .translatedBy(x: focus.x / fit, y: focus.y / fit)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -focus.x / fit, y: -focus.y / fit)
            layer.setTransform(transform, at: CMTime(seconds: frame.time, preferredTimescale: 600))
        }
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))
        return composition
    }
}

private extension CGSize {
    var absoluteSize: CGSize { CGSize(width: abs(width), height: abs(height)) }
}

private extension CanvasStyle.Background {
    var cgColor: CGColor {
        switch self {
        case .graphite: CGColor(red: 0.055, green: 0.063, blue: 0.075, alpha: 1)
        case .daylight: CGColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 1)
        case .mint: CGColor(red: 0.16, green: 0.42, blue: 0.36, alpha: 1)
        case .coral: CGColor(red: 0.78, green: 0.24, blue: 0.22, alpha: 1)
        }
    }
}
