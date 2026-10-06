import MetalKit

/// MTKView with Icon Composer-style canvas navigation and element dragging:
/// two-finger scroll pans, pinch zooms, double-click resets, and click-drag
/// moves the image element under the pointer.
final class IconMTKView: MTKView {
    weak var store: IconStore?

    private var dragLayerID: UUID?
    private var dragStartC = CGPoint.zero
    private var dragStartOffset = CGPoint.zero

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        store?.pan.width += event.scrollingDeltaX
        store?.pan.height += event.scrollingDeltaY
    }

    override func magnify(with event: NSEvent) {
        guard let store else { return }
        store.zoom = min(max(store.zoom * (1 + event.magnification), 0.1), 8.0)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            store?.pan = .zero
            store?.zoom = 1
            return
        }
        let c = canvasCoord(convert(event.locationInWindow, from: nil))
        if let hit = store?.hitTestImage(atCanvas: c), let layer = store?.layer(hit) {
            dragLayerID = hit
            dragStartC = c
            dragStartOffset = CGPoint(x: layer.offsetX, y: layer.offsetY)
            store?.selectedLayerID = hit
        } else {
            dragLayerID = nil
            store?.selectedLayerID = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let id = dragLayerID else { return }
        let c = canvasCoord(convert(event.locationInWindow, from: nil))
        store?.setOffset(id,
                         x: dragStartOffset.x + (c.x - dragStartC.x),
                         y: dragStartOffset.y + (c.y - dragStartC.y))
    }

    override func mouseUp(with event: NSEvent) { dragLayerID = nil }

    /// AppKit view point (y-up, bottom-left) → canvas space where 1 == half the
    /// min dimension, y-down to match the shader.
    private func canvasCoord(_ p: CGPoint) -> CGPoint {
        let minDim = min(bounds.width, bounds.height)
        let zoom = store?.zoom ?? 1
        let pan = store?.pan ?? .zero
        let denom = 0.5 * minDim * zoom
        guard denom > 0 else { return .zero }
        let yDown = bounds.height - p.y
        return CGPoint(x: (p.x - (bounds.width / 2 + pan.width)) / denom,
                       y: (yDown - (bounds.height / 2 + pan.height)) / denom)
    }
}
