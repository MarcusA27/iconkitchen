# IconKitchen

An open-source, native macOS composer for layered **Liquid Glass** app icons —
a from-scratch alternative to Apple's Icon Composer, built on SwiftUI + Metal.

Icons are composed as a stack of glass slabs, each rendered by a Metal fragment
shader that models the material directly: a continuous-curvature squircle, a
vertical gradient fill, a directional edge light driven by a global light angle,
an omnidirectional fresnel rim, a broad specular sheen, and a depth-based drop
shadow. The same shader powers both the live canvas and headless PNG export.

## Status

Early. A working vertical slice: the app builds, launches, shows a three-pane
editor (layers · canvas · inspector), and renders the glass material live and to
disk. See the roadmap for what's missing.

## Requirements

- macOS 14+
- Swift 6 toolchain (ships with Xcode 16+)

## Build & run

```sh
swift run IconKitchen                 # launch the editor
swift run IconKitchen --render out.png  # headless render of the default icon
```

## Architecture

```
Sources/IconKitchen/
  App/         @main entry + CLI (--render) dispatch
  Model/       IconFile document format (our own JSON) + IconStore
  Views/       SwiftUI three-pane shell, Metal canvas bridge, inspector
  Rendering/   Metal shader source, live renderer, headless PNG renderer
```

The document format is deliberately **not** Apple's `.icon` schema — it's a
clean, versioned JSON we own. An Apple-compatible exporter can be layered on top
later.

## Roadmap

- [ ] Per-layer depth parallax and inter-layer shadows
- [ ] Appearance variants (Default / Dark / Clear / Tinted) with color remapping
- [ ] Image/SVG layer content, not just solid glass slabs
- [ ] True continuous-curvature squircle (iOS quintic) rather than a superellipse approximation
- [ ] Refraction / translucency sampling of layers beneath
- [ ] Save / open documents; export to `.iconset` and Apple `.icon`
- [ ] Direct manipulation on the canvas (drag, resize, reorder)

## License

MIT — see [LICENSE](LICENSE).
