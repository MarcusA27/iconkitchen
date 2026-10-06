import SwiftUI
import Foundation

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--render"), idx + 1 < args.count {
            let url = URL(fileURLWithPath: args[idx + 1])
            do {
                try HeadlessRenderer.renderPNG(.newDefault(), size: 1024, to: url)
                print("Rendered \(url.path)")
            } catch {
                FileHandle.standardError.write(Data("Render failed: \(error)\n".utf8))
                exit(1)
            }
            return
        }
        // Debug: --render-svg <svg> <out.png> renders the base tile + an imported SVG.
        if let idx = args.firstIndex(of: "--render-svg"), idx + 2 < args.count {
            let svgURL = URL(fileURLWithPath: args[idx + 1])
            let outURL = URL(fileURLWithPath: args[idx + 2])
            do {
                let data = try Data(contentsOf: svgURL)
                var file = IconFile.newDefault()
                file.layers.append(.newImage(name: "Art", data: data))
                let appr = args.count > idx + 3 ? Appearance(rawValue: args[idx + 3]) ?? .default : .default
                try HeadlessRenderer.renderPNG(file, size: 1024, appearance: appr, to: outURL)
                print("Rendered \(outURL.path)")
            } catch {
                FileHandle.standardError.write(Data("Render failed: \(error)\n".utf8))
                exit(1)
            }
            return
        }
        IconKitchenApp.main()
    }
}

struct IconKitchenApp: App {
    @State private var store = IconStore()

    init() {
        // Ensure the SwiftPM executable activates as a regular windowed app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("IconKitchen") {
            ContentView()
                .environment(store)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    if store.selectedLayerID == nil {
                        store.selectedLayerID = store.file.layers.first?.id
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Open…") { open() }.keyboardShortcut("o")
                Button("Save…") { save() }.keyboardShortcut("s")
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Icon.iconkitchen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.encoded().write(to: url)
    }

    private func open() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        try? store.load(data)
    }
}
