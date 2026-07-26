import CoreGraphics

public enum CaptureRegionGeometry {
    public static func normalizedSourceRect(_ rect: CGRect, displaySize: CGSize) -> CGRect? {
        guard rect.coordinatesAreFinite,
              displaySize.width.isFinite,
              displaySize.height.isFinite,
              displaySize.width >= 2,
              displaySize.height >= 2
        else { return nil }

        let displayBounds = CGRect(origin: .zero, size: displaySize)
        let clipped = rect.standardized.integral.intersection(displayBounds)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2 else { return nil }
        return clipped
    }

    public static func outputSize(for sourceSize: CGSize, scale: CGFloat) -> CGSize {
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              scale.isFinite,
              scale > 0
        else { return .zero }

        let width = max(2, Int((sourceSize.width * scale).rounded(.down)) & ~1)
        let height = max(2, Int((sourceSize.height * scale).rounded(.down)) & ~1)
        return CGSize(width: width, height: height)
    }

    public static func sourceRect(_ selectionRect: CGRect, relativeTo targetFrame: CGRect) -> CGRect? {
        guard selectionRect.coordinatesAreFinite,
              targetFrame.coordinatesAreFinite,
              targetFrame.width >= 2,
              targetFrame.height >= 2
        else { return nil }

        let relative = selectionRect.standardized.offsetBy(
            dx: -targetFrame.minX,
            dy: -targetFrame.minY
        )
        return normalizedSourceRect(relative, displaySize: targetFrame.size)
    }

    public static func appKitScreenRect(sourceRect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + sourceRect.minX,
            y: screenFrame.minY + screenFrame.height - sourceRect.maxY,
            width: sourceRect.width,
            height: sourceRect.height
        )
    }
}

private extension CGRect {
    var coordinatesAreFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}
