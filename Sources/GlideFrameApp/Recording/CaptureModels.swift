import CoreGraphics
import Foundation

enum CaptureTargetKind: String, CaseIterable, Identifiable {
    case display, window, region
    var id: Self { self }
}

struct CaptureTargetDescriptor: Identifiable, Hashable {
    let id: String
    let kind: CaptureTargetKind
    let title: String
    let subtitle: String
    let nativeID: UInt32
    let selectionDisplayID: UInt32
    let selectionFrame: CGRect
    let bundleIdentifier: String?

    init(
        id: String,
        kind: CaptureTargetKind,
        title: String,
        subtitle: String,
        nativeID: UInt32,
        selectionDisplayID: UInt32,
        selectionFrame: CGRect,
        bundleIdentifier: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.nativeID = nativeID
        self.selectionDisplayID = selectionDisplayID
        self.selectionFrame = selectionFrame
        self.bundleIdentifier = bundleIdentifier
    }
}

struct RecordingOptions: Equatable {
    var targetID: String?
    var frameRate = 30
    var recordSystemAudio = true
    var recordMicrophone = true
    var recordCamera = false
    var countdown = 3
    var region: CGRect?
}

enum RecordingState: Equatable {
    case idle
    case preparing
    case countdown(Int)
    case recording(startedAt: Date)
    case paused
    case finalizing
    case failed(String)

    var isActive: Bool {
        switch self {
        case .preparing, .countdown, .recording, .paused, .finalizing: true
        case .idle, .failed: false
        }
    }
}
