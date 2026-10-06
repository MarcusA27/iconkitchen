import Foundation
import Observation

/// IconKitchen's own document format. Codable JSON, versioned so we can evolve
/// it without breaking older files. This is deliberately NOT Apple's `.icon`
/// schema — we own this and can add an Apple exporter later.
struct IconFile: Codable {
    var formatVersion = 1
    var canvasSize: Double = 1024
    var appearances: [Appearance] = [.default]
    var lightAngle: Double = -45
    var layers: [IconLayer]

    static func newDefault() -> IconFile {
        IconFile(layers: [.newGlassBase()])
    }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case `default`, dark, clear, tinted
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .default: "Default"
        case .dark: "Dark"
        case .clear: "Clear"
        case .tinted: "Tinted"
        }
    }
}

/// Fixed icon geometry that matches the platform, not user-tunable. The shape
/// is a straight-sided rounded rectangle; this value is the corner p-norm power
/// (2 == circular corner, higher == Apple's continuous-curvature corner).
enum IconMetrics {
    static let squircleExponent: Double = 5

    /// Canvas background gray behind the icon. Icon Composer's default canvas is
    /// RGB 128,128,128 (sampled with Digital Color Meter). Single source of truth
    /// for both the live and headless renderers.
    static let canvasGray: (r: Double, g: Double, b: Double) = (128.0 / 255, 128.0 / 255, 128.0 / 255)
}

struct RGBAColor: Codable, Equatable {
    var r, g, b, a: Double
    static let systemBlueTop = RGBAColor(r: 0.35, g: 0.68, b: 1.0, a: 1)
    static let systemBlueBottom = RGBAColor(r: 0.0, g: 0.48, b: 1.0, a: 1)
}

enum ElementKind: String, Codable {
    case glassBase   // the procedural glass tile
    case image       // imported artwork (SVG/PNG) rasterized to a texture
}

/// One element in the icon stack. Back-to-front, the stack composes the icon.
struct IconLayer: Codable, Identifiable {
    var id = UUID()
    var name: String
    var isVisible = true
    var kind: ElementKind = .glassBase

    // Transform within the tile. `scale` is the element half-extent as a fraction
    // of the canvas; offset is normalized (1 == half the canvas), rotation in deg.
    var scale: Double = 0.78
    var offsetX: Double = 0
    var offsetY: Double = 0
    var rotation: Double = 0

    // Glass-base material.
    var colorTop = RGBAColor.systemBlueTop
    var colorBottom = RGBAColor.systemBlueBottom
    var specular: Double = 0.6        // strength of the directional sheen
    var edgeGlow: Double = 0.5        // rim light intensity
    var depth: Double = 0.25          // drop-shadow / parallax offset between layers

    // Image element: raw source bytes (SVG or PNG). Rasterized to a texture,
    // cached by the renderer.
    var imageData: Data? = nil

    static func newGlassBase() -> IconLayer {
        IconLayer(name: "Glass")
    }

    static func newImage(name: String, data: Data) -> IconLayer {
        var layer = IconLayer(name: name)
        layer.kind = .image
        layer.imageData = data
        layer.scale = 0.5              // artwork sits smaller than the full tile
        return layer
    }
}

@Observable
final class IconStore {
    var file: IconFile = .newDefault()
    var selectedLayerID: UUID?

    // Canvas view state, shared by the renderer and the drag handler.
    var zoom: CGFloat = 1
    var pan: CGSize = .zero          // points
    var appearance: Appearance = .default

    var appearanceIndex: Float {
        Float(Appearance.allCases.firstIndex(of: appearance) ?? 0)
    }

    /// Topmost image element whose (rotated) square bounds contain canvas point c.
    func hitTestImage(atCanvas c: CGPoint) -> UUID? {
        for layer in file.layers.reversed() where layer.isVisible && layer.kind == .image {
            let dx = c.x - layer.offsetX
            let dy = c.y - layer.offsetY
            let a = -layer.rotation * .pi / 180
            let px = dx * cos(a) - dy * sin(a)
            let py = dx * sin(a) + dy * cos(a)
            if abs(px) <= layer.scale && abs(py) <= layer.scale { return layer.id }
        }
        return nil
    }

    func setOffset(_ id: UUID, x: Double, y: Double) {
        guard let idx = file.layers.firstIndex(where: { $0.id == id }) else { return }
        file.layers[idx].offsetX = x
        file.layers[idx].offsetY = y
    }

    func setScale(_ id: UUID, _ s: Double) {
        guard let idx = file.layers.firstIndex(where: { $0.id == id }) else { return }
        file.layers[idx].scale = min(max(s, 0.05), 1.0)
    }

    func setRotation(_ id: UUID, _ deg: Double) {
        guard let idx = file.layers.firstIndex(where: { $0.id == id }) else { return }
        file.layers[idx].rotation = deg
    }

    func layer(_ id: UUID) -> IconLayer? { file.layers.first { $0.id == id } }

    var selectedLayer: IconLayer? {
        get { file.layers.first { $0.id == selectedLayerID } }
        set {
            guard let newValue,
                  let idx = file.layers.firstIndex(where: { $0.id == newValue.id })
            else { return }
            file.layers[idx] = newValue
        }
    }

    func addLayer() {
        var layer = IconLayer.newGlassBase()
        layer.name = "Glass \(file.layers.count + 1)"
        file.layers.append(layer)
        selectedLayerID = layer.id
    }

    func importImage(name: String, data: Data) {
        let layer = IconLayer.newImage(name: name, data: data)
        file.layers.append(layer)
        selectedLayerID = layer.id
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    func load(_ data: Data) throws {
        file = try JSONDecoder().decode(IconFile.self, from: data)
        selectedLayerID = file.layers.first?.id
    }

    func removeSelected() {
        guard let id = selectedLayerID else { return }
        file.layers.removeAll { $0.id == id }
        selectedLayerID = file.layers.last?.id
    }
}
