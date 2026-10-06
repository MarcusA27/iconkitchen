import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Liquid Glass on macOS 26, with a material fallback on older systems.
    @ViewBuilder
    func liquidGlass(_ shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}

struct ContentView: View {
    @Environment(IconStore.self) private var store

    var body: some View {
        ZStack {
            CanvasView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            SelectionOverlay()

            VStack(spacing: 0) {
                TopBar()
                Spacer()
                BottomBar()
            }
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Environment(IconStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack {
            Text("Untitled").font(.headline)
            Spacer()
            Picker("", selection: $store.appearance) {
                ForEach(Appearance.allCases) { a in Text(a.displayName).tag(a) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()
            Spacer()
            Button(action: export) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
        }
        // Leading pad clears the window traffic lights.
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .liquidGlass(.rect)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "icon.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? HeadlessRenderer.renderPNG(store.file, size: 1024, to: url)
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    @Environment(IconStore.self) private var store
    @State private var showLayers = false
    @State private var showColor = false

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 12) {
            Spacer()
            Button { showLayers.toggle() } label: {
                Image(systemName: "square.stack.3d.up")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showLayers, arrowEdge: .bottom) { LayersPopover() }

            Button(action: importArtwork) {
                Image(systemName: "photo.badge.plus")
            }
            .buttonStyle(.borderless)

            Divider().frame(height: 22)

            Button { showColor.toggle() } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(swatchGradient)
                    .frame(width: 26, height: 26)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showColor, arrowEdge: .bottom) { ColorPopover() }

            Divider().frame(height: 22)

            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                Slider(value: $store.file.lightAngle, in: -180...180)
                    .frame(width: 160)
                Text("\(Int(store.file.lightAngle))°")
                    .font(.callout.monospacedDigit())
                    .frame(width: 42, alignment: .trailing)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .liquidGlass(.rect)
    }

    private var swatchGradient: LinearGradient {
        let layer = store.file.layers.first ?? .newGlassBase()
        return LinearGradient(colors: [layer.colorTop.color, layer.colorBottom.color],
                              startPoint: .top, endPoint: .bottom)
    }

    private func importArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.svg, .png]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        store.importImage(name: url.deletingPathExtension().lastPathComponent, data: data)
    }
}

// MARK: - Popovers

private struct ColorPopover: View {
    @Environment(IconStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let binding = baseLayerBinding {
                ColorPicker("Top", selection: colorBinding(binding.colorTop))
                ColorPicker("Bottom", selection: colorBinding(binding.colorBottom))
            }
        }
        .padding(16)
        .frame(width: 200)
    }

    private var baseLayerBinding: Binding<IconLayer>? {
        guard let idx = store.file.layers.indices.first else { return nil }
        return Binding(get: { store.file.layers[idx] },
                       set: { store.file.layers[idx] = $0 })
    }

    private func colorBinding(_ rgba: Binding<RGBAColor>) -> Binding<Color> {
        Binding(
            get: { rgba.wrappedValue.color },
            set: { newColor in
                let c = NSColor(newColor).usingColorSpace(.sRGB) ?? .black
                rgba.wrappedValue = RGBAColor(r: Double(c.redComponent),
                                              g: Double(c.greenComponent),
                                              b: Double(c.blueComponent),
                                              a: Double(c.alphaComponent))
            })
    }
}

private struct LayersPopover: View {
    @Environment(IconStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            List(selection: $store.selectedLayerID) {
                ForEach(store.file.layers.reversed()) { layer in
                    Label(layer.name, systemImage: layer.kind == .image ? "photo" : "square.fill")
                        .tag(layer.id)
                }
            }
            .frame(height: 130)

            Divider()
            HStack {
                Button { store.addLayer() } label: { Image(systemName: "plus") }
                Button { store.removeSelected() } label: { Image(systemName: "minus") }
                    .disabled(store.selectedLayerID == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)

            // Transform controls for a selected image element.
            if let binding = selectedImageBinding {
                Divider()
                VStack(spacing: 8) {
                    labeledSlider("Size", binding.scale, 0.1...0.95)
                    labeledSlider("Depth", binding.depth, 0...1)
                }
                .padding(10)
            }
        }
        .frame(width: 220)
    }

    private var selectedImageBinding: Binding<IconLayer>? {
        guard let id = store.selectedLayerID,
              let idx = store.file.layers.firstIndex(where: { $0.id == id }),
              store.file.layers[idx].kind == .image
        else { return nil }
        return Binding(get: { store.file.layers[idx] },
                       set: { store.file.layers[idx] = $0 })
    }

    private func labeledSlider(_ title: String, _ value: Binding<Double>,
                               _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
        }
    }
}

extension RGBAColor {
    var color: Color { Color(red: r, green: g, blue: b) }
}
