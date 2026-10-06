import SwiftUI

/// Draws a selection box with corner resize handles and a rotate handle over the
/// selected image element. Coordinates mirror the renderer's canvas transform.
struct SelectionOverlay: View {
    @Environment(IconStore.self) private var store

    var body: some View {
        GeometryReader { geo in
            if let layer = selectedImage {
                let w = geo.size.width, h = geo.size.height
                let denom = 0.5 * min(w, h) * store.zoom
                let cx = w / 2 + store.pan.width + layer.offsetX * denom
                let cy = h / 2 + store.pan.height + layer.offsetY * denom
                let half = layer.scale * denom

                ZStack {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 1)
                        .frame(width: half * 2, height: half * 2)
                        .allowsHitTesting(false)

                    ForEach(Corner.all, id: \.self) { corner in
                        handle
                            .offset(x: corner.dx * half, y: corner.dy * half)
                            .gesture(resizeDrag(layer: layer, geo: geo.size))
                    }

                    // Rotate handle above the box.
                    handle
                        .offset(y: -half - 22)
                        .gesture(rotateDrag(layer: layer, geo: geo.size))
                }
                .rotationEffect(.degrees(layer.rotation))
                .position(x: cx, y: cy)
            }
        }
        .coordinateSpace(name: Self.space)
    }

    private static let space = "canvas"

    private var handle: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 12, height: 12)
    }

    private var selectedImage: IconLayer? {
        guard let id = store.selectedLayerID, let l = store.layer(id), l.kind == .image
        else { return nil }
        return l
    }

    // Drag a corner: set the half-extent to the pointer's distance from center
    // (in the element's own rotated frame), keeping it square.
    private func resizeDrag(layer: IconLayer, geo: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.space))
            .onChanged { value in
                let c = canvasPoint(value.location, geo)
                let dx = c.x - layer.offsetX, dy = c.y - layer.offsetY
                let a = -layer.rotation * .pi / 180
                let lx = dx * cos(a) - dy * sin(a)
                let ly = dx * sin(a) + dy * cos(a)
                store.setScale(layer.id, max(abs(lx), abs(ly)))
            }
    }

    private func rotateDrag(layer: IconLayer, geo: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.space))
            .onChanged { value in
                let c = canvasPoint(value.location, geo)
                let ang = atan2(c.y - layer.offsetY, c.x - layer.offsetX)
                store.setRotation(layer.id, ang * 180 / .pi + 90)
            }
    }

    /// Named-space point (points, y-down) → canvas coords (1 == half min dim).
    private func canvasPoint(_ p: CGPoint, _ geo: CGSize) -> CGPoint {
        let denom = 0.5 * min(geo.width, geo.height) * store.zoom
        guard denom > 0 else { return .zero }
        return CGPoint(x: (p.x - (geo.width / 2 + store.pan.width)) / denom,
                       y: (p.y - (geo.height / 2 + store.pan.height)) / denom)
    }

    private enum Corner: Hashable {
        case tl, tr, bl, br
        static let all: [Corner] = [.tl, .tr, .bl, .br]
        var dx: CGFloat { self == .tl || self == .bl ? -1 : 1 }
        var dy: CGFloat { self == .tl || self == .tr ? -1 : 1 }
    }
}
