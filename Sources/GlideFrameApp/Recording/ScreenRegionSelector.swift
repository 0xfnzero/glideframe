import AppKit
import CoreGraphics

@MainActor
final class ScreenRegionSelector {
    private struct WindowPresentation {
        let window: NSWindow
        let alphaValue: CGFloat
        let ignoresMouseEvents: Bool
    }

    private var continuation: CheckedContinuation<CGRect?, Never>?
    private var window: NSWindow?
    private var concealedWindows: [WindowPresentation] = []
    private weak var previousKeyWindow: NSWindow?

    func selectRegion(on displayID: CGDirectDisplayID, constrainedTo targetFrame: CGRect) async -> CGRect? {
        guard continuation == nil, let screen = Self.screen(for: displayID) else { return nil }
        let screenBounds = CGRect(origin: .zero, size: screen.frame.size)
        let selectableBounds = targetFrame.standardized.intersection(screenBounds)
        guard !selectableBounds.isNull,
              selectableBounds.width >= 32,
              selectableBounds.height >= 32
        else { return nil }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            concealApplicationWindows()

            let selectionView = RegionSelectionView(frame: screenBounds, selectableBounds: selectableBounds)
            selectionView.onComplete = { [weak self] rect in self?.finish(with: rect) }
            selectionView.onCancel = { [weak self] in self?.finish(with: nil) }

            let window = RegionSelectionWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = selectionView
            window.setFrame(screen.frame, display: true)
            self.window = window

            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(selectionView)
        }
    }

    func cancel() {
        finish(with: nil)
    }

    private func finish(with rect: CGRect?) {
        guard let continuation else { return }
        self.continuation = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        restoreApplicationWindows()
        continuation.resume(returning: rect)
    }

    private func concealApplicationWindows() {
        previousKeyWindow = NSApplication.shared.keyWindow
        concealedWindows = NSApplication.shared.windows
            .filter(\.isVisible)
            .map { window in
                let presentation = WindowPresentation(
                    window: window,
                    alphaValue: window.alphaValue,
                    ignoresMouseEvents: window.ignoresMouseEvents
                )
                window.alphaValue = 0
                window.ignoresMouseEvents = true
                return presentation
            }
    }

    private func restoreApplicationWindows() {
        for presentation in concealedWindows {
            presentation.window.alphaValue = presentation.alphaValue
            presentation.window.ignoresMouseEvents = presentation.ignoresMouseEvents
        }
        concealedWindows = []

        NSApplication.shared.activate(ignoringOtherApps: true)
        previousKeyWindow?.makeKeyAndOrderFront(nil)
        previousKeyWindow = nil
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == displayID
        }
    }
}

private final class RegionSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class RegionSelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let minimumSelectionSize: CGFloat = 32
    private let selectableBounds: CGRect
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    private lazy var cancelButton: NSButton = {
        let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: tr("cancel")) ?? NSImage()
        let button = NSButton(image: image, target: self, action: #selector(cancelSelection))
        button.bezelStyle = .circular
        button.isBordered = false
        button.contentTintColor = .white
        button.toolTip = tr("cancel")
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        button.layer?.cornerRadius = 16
        return button
    }()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame frameRect: NSRect, selectableBounds: CGRect) {
        self.selectableBounds = selectableBounds
        super.init(frame: frameRect)
        addSubview(cancelButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        cancelButton.frame = CGRect(x: 20, y: 20, width: 32, height: 32)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard selectableBounds.contains(point) else { return }
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clipped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil else { return }
        currentPoint = clipped(convert(event.locationInWindow, from: nil))
        guard let selectionRect,
              selectionRect.width >= minimumSelectionSize,
              selectionRect.height >= minimumSelectionSize
        else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            NSSound.beep()
            return
        }
        onComplete?(selectionRect.integral)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.46).setFill()
        bounds.fill()

        if selectableBounds != bounds {
            let targetOutline = NSBezierPath(rect: selectableBounds.insetBy(dx: 0.5, dy: 0.5))
            targetOutline.lineWidth = 1
            NSColor.white.withAlphaComponent(0.72).setStroke()
            targetOutline.stroke()
        }

        guard let selectionRect else { return }
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        selectionRect.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        let outline = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 2
        NSColor.white.setStroke()
        outline.stroke()
        drawSizeLabel(for: selectionRect)
    }

    @objc private func cancelSelection() {
        onCancel?()
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func clipped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, selectableBounds.minX), selectableBounds.maxX),
            y: min(max(point.y, selectableBounds.minY), selectableBounds.maxY)
        )
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) x \(Int(rect.height.rounded()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let label = NSAttributedString(string: text, attributes: attributes)
        let labelSize = label.size()
        let backgroundSize = CGSize(width: labelSize.width + 16, height: labelSize.height + 10)
        let preferredY = rect.maxY + 8
        let y = preferredY + backgroundSize.height <= bounds.maxY
            ? preferredY
            : max(bounds.minY + 8, rect.minY - backgroundSize.height - 8)
        let x = min(max(rect.minX, bounds.minX + 8), bounds.maxX - backgroundSize.width - 8)
        let backgroundRect = CGRect(origin: CGPoint(x: x, y: y), size: backgroundSize)

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: 5, yRadius: 5).fill()
        label.draw(at: CGPoint(x: backgroundRect.minX + 8, y: backgroundRect.minY + 5))
    }
}
