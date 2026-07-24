import Foundation

public struct ProjectManifest: Codable, Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var duration: TimeInterval
    public var canvas: CanvasStyle
    public var sources: [MediaSource]
    public var tracks: [MediaTrack]
    public var editGraph: EditGraph
    public var pointerEvents: [PointerEvent]
    public var captions: [CaptionCue]
    public var exportPreset: ExportPreset

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        duration: TimeInterval = 0,
        canvas: CanvasStyle = .default,
        sources: [MediaSource] = [],
        tracks: [MediaTrack] = [],
        editGraph: EditGraph = .init(),
        pointerEvents: [PointerEvent] = [],
        captions: [CaptionCue] = [],
        exportPreset: ExportPreset = .hd
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.canvas = canvas
        self.sources = sources
        self.tracks = tracks
        self.editGraph = editGraph
        self.pointerEvents = pointerEvents
        self.captions = captions
        self.exportPreset = exportPreset
    }
}

public struct MediaSource: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case screen, systemAudio, microphone, camera
    }

    public var id: UUID
    public var kind: Kind
    public var relativePath: String
    public var duration: TimeInterval
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        relativePath: String,
        duration: TimeInterval = 0,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
    }
}

public struct MediaTrack: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceID: UUID
    public var kind: MediaSource.Kind
    public var isEnabled: Bool
    public var volume: Double

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        kind: MediaSource.Kind,
        isEnabled: Bool = true,
        volume: Double = 1
    ) {
        self.id = id
        self.sourceID = sourceID
        self.kind = kind
        self.isEnabled = isEnabled
        self.volume = volume
    }
}

public struct EditGraph: Codable, Equatable, Sendable {
    public var clips: [ClipEdit]
    public var zoomKeyframes: [ZoomKeyframe]
    public var cameraLayout: CameraLayout
    public var removeSilence: Bool
    public var noiseReduction: Double

    public init(
        clips: [ClipEdit] = [],
        zoomKeyframes: [ZoomKeyframe] = [],
        cameraLayout: CameraLayout = .bubbleBottomRight,
        removeSilence: Bool = false,
        noiseReduction: Double = 0.35
    ) {
        self.clips = clips
        self.zoomKeyframes = zoomKeyframes
        self.cameraLayout = cameraLayout
        self.removeSilence = removeSilence
        self.noiseReduction = noiseReduction
    }
}

public struct ClipEdit: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sourceRange: MediaTimeRange
    public var isRemoved: Bool

    public init(id: UUID = UUID(), sourceRange: MediaTimeRange, isRemoved: Bool = false) {
        self.id = id
        self.sourceRange = sourceRange
        self.isRemoved = isRemoved
    }
}

public struct MediaTimeRange: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var duration: TimeInterval
    public var end: TimeInterval { start + duration }

    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = max(0, start)
        self.duration = max(0, duration)
    }
}

public struct ZoomKeyframe: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var time: TimeInterval
    public var scale: Double
    public var focusX: Double
    public var focusY: Double

    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        scale: Double,
        focusX: Double,
        focusY: Double
    ) {
        self.id = id
        self.time = max(0, time)
        self.scale = max(1, scale)
        self.focusX = min(max(focusX, 0), 1)
        self.focusY = min(max(focusY, 0), 1)
    }
}

public struct PointerEvent: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case move, click }

    public var id: UUID
    public var time: TimeInterval
    public var x: Double
    public var y: Double
    public var kind: Kind

    public init(id: UUID = UUID(), time: TimeInterval, x: Double, y: Double, kind: Kind) {
        self.id = id
        self.time = max(0, time)
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.kind = kind
    }
}

public struct CaptionCue: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var range: MediaTimeRange
    public var text: String
    public var translatedText: String?

    public init(id: UUID = UUID(), range: MediaTimeRange, text: String, translatedText: String? = nil) {
        self.id = id
        self.range = range
        self.text = text
        self.translatedText = translatedText
    }
}

public struct CanvasStyle: Codable, Equatable, Sendable {
    public enum AspectRatio: String, Codable, CaseIterable, Sendable { case landscape, portrait, square }
    public enum Background: String, Codable, CaseIterable, Sendable { case graphite, daylight, mint, coral }

    public var aspectRatio: AspectRatio
    public var background: Background
    public var padding: Double
    public var cornerRadius: Double
    public var shadow: Double

    public init(
        aspectRatio: AspectRatio = .landscape,
        background: Background = .graphite,
        padding: Double = 64,
        cornerRadius: Double = 18,
        shadow: Double = 0.28
    ) {
        self.aspectRatio = aspectRatio
        self.background = background
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }

    public static let `default` = CanvasStyle()
}

public enum CameraLayout: String, Codable, CaseIterable, Sendable {
    case hidden, bubbleBottomRight, bubbleBottomLeft, sideBySide
}

public struct ExportPreset: Codable, Equatable, Sendable {
    public enum Codec: String, Codable, CaseIterable, Sendable { case h264, hevc }

    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var codec: Codec

    public init(width: Int, height: Int, frameRate: Int, codec: Codec) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
    }

    public static let hd = ExportPreset(width: 1920, height: 1080, frameRate: 30, codec: .h264)
    public static let ultraHD = ExportPreset(width: 3840, height: 2160, frameRate: 60, codec: .hevc)
}
