import Foundation

public enum MediaOutputKind: String, Codable, Sendable {
    case video
    case animatedImage
    case audio
}

public enum MediaCodec: String, CaseIterable, Codable, Identifiable, Sendable {
    case h264
    case hevc
    case proRes
    case vp9
    case av1
    case mpeg4
    case wmv2
    case flv
    case gif
    case aac
    case mp3
    case pcm
    case flac
    case opus

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .h264: "H.264"
        case .hevc: "H.265 / HEVC"
        case .proRes: "Apple ProRes 422 HQ"
        case .vp9: "VP9"
        case .av1: "AV1"
        case .mpeg4: "MPEG-4 Part 2"
        case .wmv2: "Windows Media Video 8"
        case .flv: "Sorenson Spark"
        case .gif: "GIF"
        case .aac: "AAC"
        case .mp3: "MP3"
        case .pcm: "PCM 16-bit"
        case .flac: "FLAC"
        case .opus: "Opus"
        }
    }

    public var requiredEncoder: String {
        switch self {
        case .h264: "h264_videotoolbox"
        case .hevc: "hevc_videotoolbox"
        case .proRes: "prores_ks"
        case .vp9: "libvpx-vp9"
        case .av1: "libsvtav1"
        case .mpeg4: "mpeg4"
        case .wmv2: "wmv2"
        case .flv: "flv"
        case .gif: "gif"
        case .aac: "aac"
        case .mp3: "libmp3lame"
        case .pcm: "pcm_s16le"
        case .flac: "flac"
        case .opus: "libopus"
        }
    }
}

public enum MediaOutputFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case mp4
    case mov
    case mkv
    case webm
    case avi
    case m4v
    case mpegTS
    case wmv
    case flv
    case gif
    case mp3
    case m4a
    case wav
    case flac
    case ogg
    case opus

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mp4: "MP4"
        case .mov: "QuickTime MOV"
        case .mkv: "Matroska MKV"
        case .webm: "WebM"
        case .avi: "AVI"
        case .m4v: "M4V"
        case .mpegTS: "MPEG-TS"
        case .wmv: "Windows Media WMV"
        case .flv: "Flash Video FLV"
        case .gif: "Animated GIF"
        case .mp3: "MP3 Audio"
        case .m4a: "M4A Audio"
        case .wav: "WAV Audio"
        case .flac: "FLAC Audio"
        case .ogg: "Ogg Opus Audio"
        case .opus: "Opus Audio"
        }
    }

    public var fileExtension: String {
        switch self {
        case .mpegTS: "ts"
        default: rawValue.lowercased()
        }
    }

    public var kind: MediaOutputKind {
        switch self {
        case .gif: .animatedImage
        case .mp3, .m4a, .wav, .flac, .ogg, .opus: .audio
        default: .video
        }
    }

    public var compatibleCodecs: [MediaCodec] {
        switch self {
        case .mp4: [.h264, .hevc]
        case .m4v: [.h264]
        case .mov: [.h264, .hevc, .proRes]
        case .mkv: [.h264, .hevc, .vp9, .av1, .proRes]
        case .webm: [.vp9, .av1]
        case .avi: [.mpeg4]
        case .mpegTS: [.h264, .hevc]
        case .wmv: [.wmv2]
        case .flv: [.flv]
        case .gif: [.gif]
        case .mp3: [.mp3]
        case .m4a: [.aac]
        case .wav: [.pcm]
        case .flac: [.flac]
        case .ogg, .opus: [.opus]
        }
    }

    public var defaultCodec: MediaCodec { compatibleCodecs[0] }
}

public enum ConversionResolution: String, CaseIterable, Codable, Identifiable, Sendable {
    case source
    case uhd2160
    case fullHD1080
    case hd720
    case sd480

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .source: "Source"
        case .uhd2160: "4K"
        case .fullHD1080: "1080p"
        case .hd720: "720p"
        case .sd480: "480p"
        }
    }

    public var dimensions: (width: Int, height: Int)? {
        switch self {
        case .source: nil
        case .uhd2160: (3840, 2160)
        case .fullHD1080: (1920, 1080)
        case .hd720: (1280, 720)
        case .sd480: (854, 480)
        }
    }
}

public enum ConversionFrameRate: String, CaseIterable, Codable, Identifiable, Sendable {
    case source
    case fps60
    case fps30
    case fps24

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .source: "Source"
        case .fps60: "60 fps"
        case .fps30: "30 fps"
        case .fps24: "24 fps"
        }
    }

    public var value: Int? {
        switch self {
        case .source: nil
        case .fps60: 60
        case .fps30: 30
        case .fps24: 24
        }
    }
}

public enum ConversionQuality: String, CaseIterable, Codable, Identifiable, Sendable {
    case high
    case balanced
    case compact

    public var id: String { rawValue }
}

public struct MediaConversionSettings: Codable, Equatable, Sendable {
    public var format: MediaOutputFormat
    public var codec: MediaCodec
    public var resolution: ConversionResolution
    public var frameRate: ConversionFrameRate
    public var quality: ConversionQuality
    public var includeAudio: Bool

    public init(
        format: MediaOutputFormat = .mp4,
        codec: MediaCodec = .h264,
        resolution: ConversionResolution = .source,
        frameRate: ConversionFrameRate = .source,
        quality: ConversionQuality = .balanced,
        includeAudio: Bool = true
    ) {
        self.format = format
        self.codec = codec
        self.resolution = resolution
        self.frameRate = frameRate
        self.quality = quality
        self.includeAudio = includeAudio
    }
}

public enum FFmpegCommandBuilder {
    public enum BuilderError: LocalizedError, Equatable {
        case incompatibleCodec(format: MediaOutputFormat, codec: MediaCodec)

        public var errorDescription: String? {
            switch self {
            case .incompatibleCodec(let format, let codec):
                "\(codec.displayName) is not compatible with \(format.displayName)."
            }
        }
    }

    public static func arguments(
        input: URL,
        output: URL,
        settings: MediaConversionSettings
    ) throws -> [String] {
        guard settings.format.compatibleCodecs.contains(settings.codec) else {
            throw BuilderError.incompatibleCodec(format: settings.format, codec: settings.codec)
        }

        var arguments = [
            "-hide_banner", "-nostdin", "-y",
            "-i", input.path,
            "-map_metadata", "0"
        ]

        switch settings.format.kind {
        case .audio:
            arguments += ["-map", "0:a:0?", "-vn"]
            arguments += audioCodecArguments(settings.codec, quality: settings.quality)
        case .animatedImage:
            arguments += gifArguments(settings)
        case .video:
            arguments += ["-map", "0:v:0?", "-map", "0:a:0?"]
            arguments += videoCodecArguments(settings.codec, settings: settings)
            if let filter = scaleFilter(settings.resolution) {
                arguments += ["-vf", filter]
            }
            if let frameRate = settings.frameRate.value {
                arguments += ["-r", String(frameRate)]
            }
            if settings.includeAudio {
                arguments += containerAudioArguments(settings.format, quality: settings.quality)
            } else {
                arguments += ["-an"]
            }
            if [.mp4, .mov, .m4v].contains(settings.format) {
                arguments += ["-movflags", "+faststart"]
            }
        }

        arguments += ["-progress", "pipe:1", "-nostats", output.path]
        return arguments
    }

    private static func videoCodecArguments(
        _ codec: MediaCodec,
        settings: MediaConversionSettings
    ) -> [String] {
        switch codec {
        case .h264:
            let bitrate = videoBitrate(settings, hevc: false)
            return [
                "-c:v", codec.requiredEncoder, "-allow_sw", "1", "-pix_fmt", "yuv420p",
                "-b:v", bitrate, "-maxrate", bitrate, "-bufsize", doubledBitrate(bitrate)
            ]
        case .hevc:
            let bitrate = videoBitrate(settings, hevc: true)
            var arguments = [
                "-c:v", codec.requiredEncoder, "-allow_sw", "1", "-pix_fmt", "yuv420p",
                "-b:v", bitrate, "-maxrate", bitrate, "-bufsize", doubledBitrate(bitrate)
            ]
            if [.mp4, .mov, .m4v].contains(settings.format) {
                arguments += ["-tag:v", "hvc1"]
            }
            return arguments
        case .proRes:
            return ["-c:v", codec.requiredEncoder, "-profile:v", "3", "-pix_fmt", "yuv422p10le"]
        case .vp9:
            return [
                "-c:v", codec.requiredEncoder,
                "-crf", crf(settings.quality, high: 20, balanced: 28, compact: 36),
                "-b:v", "0", "-row-mt", "1"
            ]
        case .av1:
            return [
                "-c:v", codec.requiredEncoder,
                "-crf", crf(settings.quality, high: 24, balanced: 31, compact: 38),
                "-preset", settings.quality == .high ? "6" : "8"
            ]
        case .mpeg4, .wmv2, .flv:
            return [
                "-c:v", codec.requiredEncoder,
                "-q:v", crf(settings.quality, high: 2, balanced: 5, compact: 9)
            ]
        default:
            return []
        }
    }

    private static func audioCodecArguments(_ codec: MediaCodec, quality: ConversionQuality) -> [String] {
        switch codec {
        case .aac:
            return ["-c:a", codec.requiredEncoder, "-b:a", audioBitrate(quality)]
        case .mp3:
            return ["-c:a", codec.requiredEncoder, "-b:a", audioBitrate(quality)]
        case .pcm:
            return ["-c:a", codec.requiredEncoder]
        case .flac:
            return ["-c:a", codec.requiredEncoder, "-compression_level", quality == .compact ? "12" : "8"]
        case .opus:
            return ["-c:a", codec.requiredEncoder, "-b:a", audioBitrate(quality)]
        default:
            return []
        }
    }

    private static func containerAudioArguments(
        _ format: MediaOutputFormat,
        quality: ConversionQuality
    ) -> [String] {
        switch format {
        case .webm:
            return ["-c:a", "libopus", "-b:a", audioBitrate(quality)]
        case .avi:
            return ["-c:a", "libmp3lame", "-b:a", audioBitrate(quality)]
        case .wmv:
            return ["-c:a", "wmav1", "-b:a", audioBitrate(quality)]
        default:
            return ["-c:a", "aac", "-b:a", audioBitrate(quality)]
        }
    }

    private static func gifArguments(_ settings: MediaConversionSettings) -> [String] {
        let frameRate = min(settings.frameRate.value ?? 15, 30)
        let scale = scaleFilter(settings.resolution) ?? "scale=iw:ih:flags=lanczos"
        let colors = switch settings.quality {
        case .high: 256
        case .balanced: 192
        case .compact: 128
        }
        let filter = "[0:v:0]fps=\(frameRate),\(scale),split[s0][s1];[s0]palettegen=max_colors=\(colors)[p];[s1][p]paletteuse=dither=sierra2_4a[v]"
        return ["-filter_complex", filter, "-map", "[v]", "-an", "-loop", "0"]
    }

    private static func scaleFilter(_ resolution: ConversionResolution) -> String? {
        guard let dimensions = resolution.dimensions else { return nil }
        return "scale=w=\(dimensions.width):h=\(dimensions.height):force_original_aspect_ratio=decrease:force_divisible_by=2:flags=lanczos"
    }

    private static func videoBitrate(_ settings: MediaConversionSettings, hevc: Bool) -> String {
        let base: Int = switch settings.resolution {
        case .uhd2160: 35
        case .fullHD1080, .source: 12
        case .hd720: 7
        case .sd480: 3
        }
        let qualityMultiplier: Double = switch settings.quality {
        case .high: 1.4
        case .balanced: 1
        case .compact: 0.58
        }
        let codecMultiplier = hevc ? 0.7 : 1
        return "\(max(1, Int(Double(base) * qualityMultiplier * codecMultiplier)))M"
    }

    private static func doubledBitrate(_ bitrate: String) -> String {
        let value = Int(bitrate.dropLast()) ?? 1
        return "\(value * 2)M"
    }

    private static func audioBitrate(_ quality: ConversionQuality) -> String {
        switch quality {
        case .high: "256k"
        case .balanced: "192k"
        case .compact: "96k"
        }
    }

    private static func crf(
        _ quality: ConversionQuality,
        high: Int,
        balanced: Int,
        compact: Int
    ) -> String {
        switch quality {
        case .high: String(high)
        case .balanced: String(balanced)
        case .compact: String(compact)
        }
    }
}
