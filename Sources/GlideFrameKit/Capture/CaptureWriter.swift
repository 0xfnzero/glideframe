@preconcurrency import AVFoundation
@preconcurrency import CoreImage
import CoreMedia
import Foundation
import GlideFrameKit
@preconcurrency import ScreenCaptureKit

public final class CaptureWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    enum WriterError: LocalizedError {
        case cannotAddVideoInput
        case cannotAddAudioInput
        case noSamples
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotAddVideoInput: "The video encoder could not be configured."
            case .cannotAddAudioInput: "The system audio encoder could not be configured."
            case .noSamples: "No screen frames were received. Check Screen Recording permission."
            case .writerFailed(let message): message
            }
        }
    }

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let lock = NSLock()
    private var sessionStart: CMTime?
    private var timeline: CaptureTimeline
    private var isFinishing = false
    private var writtenDuration = CMTime.zero
    private var lastVideoPTS: CMTime?
    private var lastAudioPTS: CMTime?
    private let previewProcessor: CapturePreviewProcessor?

    public init(
        url: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        includeAudio: Bool,
        previewHandler: (@Sendable (CGImage) -> Void)? = nil
    ) throws {
        timeline = CaptureTimeline(frameRate: frameRate)
        previewProcessor = previewHandler.map(CapturePreviewProcessor.init(handler:))
        writer = try AVAssetWriter(outputURL: url, fileType: url.pathExtension.lowercased() == "mp4" ? .mp4 : .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(8_000_000, width * height * frameRate / 5),
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else { throw WriterError.cannotAddVideoInput }
        writer.add(videoInput)

        if includeAudio {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw WriterError.cannotAddAudioInput }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }
        super.init()
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if type == .screen {
            // ScreenCaptureKit also delivers idle/blank status samples. They are
            // valid CMSampleBuffers, but are not encodable video frames.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int,
                  status == SCFrameStatus.complete.rawValue,
                  CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            previewProcessor?.consume(sampleBuffer)
        }
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock()
        defer { lock.unlock() }
        guard !isFinishing, writer.status != .failed else { return }
        guard let shifted = timeline.presentationTime(for: sourcePTS, isVideo: type == .screen) else { return }

        if sessionStart == nil {
            guard type == .screen else { return }
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: .zero)
            sessionStart = sourcePTS
        }
        guard let adjusted = sampleBuffer.retimed(to: shifted) else { return }

        switch type {
        case .screen where videoInput.isReadyForMoreMediaData:
            guard lastVideoPTS.map({ shifted > $0 }) ?? true else { return }
            if videoInput.append(adjusted) {
                lastVideoPTS = shifted
                writtenDuration = max(writtenDuration, shifted)
            } else {
                NSLog("GlideFrame video encoder: %@", String(describing: writer.error))
            }
        case .audio where audioInput?.isReadyForMoreMediaData == true:
            guard lastAudioPTS.map({ shifted > $0 }) ?? true else { return }
            if audioInput?.append(adjusted) == true {
                lastAudioPTS = shifted
            } else {
                NSLog("GlideFrame audio encoder: %@", String(describing: writer.error))
            }
        default:
            break
        }
    }

    public func pause() {
        lock.withLock { timeline.pause() }
    }

    public func resume() {
        lock.withLock {
            timeline.resume()
        }
    }

    public func finish() async throws -> TimeInterval {
        let hasSession: Bool = lock.withLock {
            isFinishing = true
            return sessionStart != nil
        }
        guard hasSession else {
            writer.cancelWriting()
            throw WriterError.noSamples
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw WriterError.writerFailed(writer.error?.localizedDescription ?? "Video encoding failed.")
        }
        return max(0, writtenDuration.seconds)
    }
}

private final class CapturePreviewProcessor: @unchecked Sendable {
    private struct SampleBuffer: @unchecked Sendable {
        let value: CMSampleBuffer
    }

    private let handler: @Sendable (CGImage) -> Void
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let queue = DispatchQueue(label: "app.glideframe.capture.preview", qos: .userInitiated)
    private let lock = NSLock()
    private var lastSubmittedPTS = CMTime.invalid
    private var isProcessing = false

    init(handler: @escaping @Sendable (CGImage) -> Void) {
        self.handler = handler
    }

    func consume(_ sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let shouldProcess = lock.withLock { () -> Bool in
            guard !isProcessing else { return false }
            if lastSubmittedPTS.isValid,
               CMTimeSubtract(pts, lastSubmittedPTS).seconds < 0.125 {
                return false
            }
            lastSubmittedPTS = pts
            isProcessing = true
            return true
        }
        guard shouldProcess else { return }

        let buffer = SampleBuffer(value: sampleBuffer)
        queue.async { [self, buffer] in
            defer { lock.withLock { isProcessing = false } }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer.value) else { return }

            let source = CIImage(cvPixelBuffer: pixelBuffer)
            let longestEdge = max(source.extent.width, source.extent.height)
            let scale = min(1, 1_280 / max(longestEdge, 1))
            let image = scale < 1
                ? source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                : source
            guard let preview = context.createCGImage(image, from: image.extent) else { return }
            handler(preview)
        }
    }
}

private extension CMSampleBuffer {
    func retimed(to presentationTime: CMTime) -> CMSampleBuffer? {
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(self, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timing = Array(repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(
            self,
            entryCount: count,
            arrayToFill: &timing,
            entriesNeededOut: &count
        ) == noErr else { return nil }
        let original = timing[0].presentationTimeStamp
        for index in timing.indices {
            let offset = CMTimeSubtract(timing[index].presentationTimeStamp, original)
            timing[index].presentationTimeStamp = CMTimeAdd(presentationTime, offset)
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeAdd(presentationTime, offset)
            }
        }
        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: self,
            sampleTimingEntryCount: count,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        ) == noErr else { return nil }
        return copy
    }
}
