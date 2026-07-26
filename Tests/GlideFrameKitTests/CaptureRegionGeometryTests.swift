import CoreGraphics
import XCTest
@testable import GlideFrameKit

final class CaptureRegionGeometryTests: XCTestCase {
    func testSourceRectIsStandardizedAndClippedToDisplay() throws {
        let rect = CGRect(x: 240, y: 180, width: -300, height: -220)

        let normalized = try XCTUnwrap(CaptureRegionGeometry.normalizedSourceRect(
            rect,
            displaySize: CGSize(width: 1_440, height: 900)
        ))

        XCTAssertEqual(normalized, CGRect(x: 0, y: 0, width: 240, height: 180))
    }

    func testInvalidAndTinyRegionsAreRejected() {
        XCTAssertNil(CaptureRegionGeometry.normalizedSourceRect(
            CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
            displaySize: CGSize(width: 1_440, height: 900)
        ))
        XCTAssertNil(CaptureRegionGeometry.normalizedSourceRect(
            CGRect(x: 1_500, y: 1_000, width: 100, height: 100),
            displaySize: CGSize(width: 1_440, height: 900)
        ))
    }

    func testOutputSizeUsesBackingScaleAndEvenPixelDimensions() {
        XCTAssertEqual(
            CaptureRegionGeometry.outputSize(
                for: CGSize(width: 501, height: 301),
                scale: 2
            ),
            CGSize(width: 1_002, height: 602)
        )
        XCTAssertEqual(
            CaptureRegionGeometry.outputSize(
                for: CGSize(width: 501, height: 301),
                scale: 1
            ),
            CGSize(width: 500, height: 300)
        )
    }

    func testSelectionRectConvertsToWindowRelativeSourceRect() throws {
        let result = try XCTUnwrap(CaptureRegionGeometry.sourceRect(
            CGRect(x: 420, y: 260, width: 640, height: 360),
            relativeTo: CGRect(x: 300, y: 180, width: 1_200, height: 800)
        ))

        XCTAssertEqual(result, CGRect(x: 120, y: 80, width: 640, height: 360))
    }

    func testWindowRelativeSourceRectClipsToWindowBounds() throws {
        let result = try XCTUnwrap(CaptureRegionGeometry.sourceRect(
            CGRect(x: 100, y: 100, width: 400, height: 300),
            relativeTo: CGRect(x: 300, y: 180, width: 1_200, height: 800)
        ))

        XCTAssertEqual(result, CGRect(x: 0, y: 0, width: 200, height: 220))
    }

    func testSourceCoordinatesConvertToAppKitScreenCoordinates() {
        let result = CaptureRegionGeometry.appKitScreenRect(
            sourceRect: CGRect(x: 20, y: 30, width: 600, height: 400),
            screenFrame: CGRect(x: 100, y: 200, width: 1_440, height: 900)
        )

        XCTAssertEqual(result, CGRect(x: 120, y: 670, width: 600, height: 400))
    }
}
