import CoreMedia
import XCTest
@testable import GlideFrameKit

final class CaptureTimelineTests: XCTestCase {
    func testPausedSamplesDoNotExtendTheRecording() throws {
        var timeline = CaptureTimeline(frameRate: 30)
        let time: (Int64) -> CMTime = { CMTime(value: $0, timescale: 30) }
        XCTAssertNil(timeline.presentationTime(for: time(0), isVideo: false))
        XCTAssertEqual(timeline.presentationTime(for: time(0), isVideo: true), .zero)
        XCTAssertEqual(timeline.presentationTime(for: time(30), isVideo: true), time(30))
        timeline.pause()
        XCTAssertNil(timeline.presentationTime(for: time(60), isVideo: true))
        XCTAssertNil(timeline.presentationTime(for: time(270), isVideo: false))
        timeline.resume()
        XCTAssertEqual(timeline.presentationTime(for: time(300), isVideo: true), time(31))
        XCTAssertEqual(timeline.presentationTime(for: time(330), isVideo: true), time(61))
        timeline.resume() // A duplicate resume must not remove unpaused footage.
        XCTAssertEqual(timeline.presentationTime(for: time(360), isVideo: true), time(91))
    }
}
