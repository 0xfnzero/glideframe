@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import QuartzCore
import GlideFrameKit

public actor ExportService {
    public init() {}
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

    public func export(manifest: ProjectManifest, packageURL: URL, destination: URL) async throws {
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
            input.setVolume(Float(volume(for: .systemAudio, in: manifest)), at: .zero)
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
        let track = manifest.tracks.first(where: { $0.kind == kind })
            ?? (kind == .systemAudio ? manifest.tracks.first(where: { $0.kind == .screen }) : nil)
        return track.map { $0.isEnabled ? $0.volume : 0 } ?? 0
    }

    private func makeVideoComposition(
        track: AVCompositionTrack,
        sourceSize: CGSize,
        manifest: ProjectManifest,
        duration: CMTime
    ) -> AVMutableVideoComposition {
        let preset = manifest.exportPreset
        let dimensions: (Int, Int) = switch manifest.canvas.aspectRatio {
        case .landscape: (max(preset.width, preset.height), min(preset.width, preset.height))
        case .portrait: (min(preset.width, preset.height), max(preset.width, preset.height))
        case .square: (min(preset.width, preset.height), min(preset.width, preset.height))
        }
        let renderSize = CGSize(width: dimensions.0, height: dimensions.1)
        let padding = min(CGFloat(manifest.canvas.padding), min(renderSize.width, renderSize.height) / 3)
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
        let clips = manifest.editGraph.clips.isEmpty
            ? [ClipEdit(sourceRange: .init(start: 0, duration: manifest.duration))]
            : manifest.editGraph.clips.filter { !$0.isRemoved }
        var cursor: Double = 0
        var outputFrames: [(time: Double, frame: ZoomKeyframe)] = []
        for clip in clips {
            if let previous = manifest.editGraph.zoomKeyframes.last(where: { $0.time <= clip.sourceRange.start }) {
                outputFrames.append((cursor, previous))
            } else {
                outputFrames.append((cursor, ZoomKeyframe(time: 0, scale: 1, focusX: 0.5, focusY: 0.5)))
            }
            for frame in manifest.editGraph.zoomKeyframes where frame.time > clip.sourceRange.start && frame.time < clip.sourceRange.end {
                outputFrames.append((cursor + frame.time - clip.sourceRange.start, frame))
            }
            cursor += clip.sourceRange.duration
        }
        for output in outputFrames {
            let frame = output.frame
            let scale = CGFloat(frame.scale)
            let focus = CGPoint(x: fitted.width * frame.focusX, y: fitted.height * frame.focusY)
            let transform = base
                .translatedBy(x: focus.x / fit, y: focus.y / fit)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -focus.x / fit, y: -focus.y / fit)
            layer.setTransform(transform, at: CMTime(seconds: output.time, preferredTimescale: 600))
        }
        instruction.layerInstructions = [layer]
        let composition = AVMutableVideoComposition()
        composition.instructions = [instruction]
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(preset.frameRate))
        if manifest.canvas.cornerRadius > 0 || manifest.canvas.shadow > 0 {
            let parent = CALayer()
            parent.frame = CGRect(origin: .zero, size: renderSize)
            parent.backgroundColor = manifest.canvas.background.cgColor
            let video = CALayer()
            video.frame = parent.bounds
            let rect = CGRect(origin: origin, size: fitted)
            let path = CGPath(roundedRect: rect, cornerWidth: manifest.canvas.cornerRadius, cornerHeight: manifest.canvas.cornerRadius, transform: nil)
            let mask = CAShapeLayer()
            mask.path = path
            video.mask = mask
            let shadow = CALayer()
            shadow.frame = parent.bounds
            shadow.shadowPath = path
            shadow.shadowColor = CGColor(gray: 0, alpha: 1)
            shadow.shadowOpacity = Float(manifest.canvas.shadow)
            shadow.shadowRadius = 20
            shadow.shadowOffset = CGSize(width: 0, height: -8)
            parent.addSublayer(shadow)
            parent.addSublayer(video)
            composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)
        }
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
