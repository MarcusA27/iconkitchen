import SwiftUI
import MetalKit

/// Bridges the MTKView + renderer into SwiftUI and keeps them fed with the
/// current document.
struct CanvasView: NSViewRepresentable {
    @Environment(IconStore.self) private var store

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MTKView {
        // Non-zero initial frame so the view has a drawable on the first frame,
        // instead of waiting for SwiftUI layout (which can leave it blank).
        let view = IconMTKView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: IconMetrics.canvasGray.r,
                                        green: IconMetrics.canvasGray.g,
                                        blue: IconMetrics.canvasGray.b, alpha: 1)
        view.autoResizeDrawable = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60

        view.store = store
        let renderer = MetalRenderer(mtkView: view)
        renderer?.store = store
        view.delegate = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.store = store
    }

    final class Coordinator {
        var renderer: MetalRenderer?
    }
}
