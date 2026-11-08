import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main struct StudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("iLedBike Studio") { StudioView().frame(minWidth: 920, minHeight: 640).preferredColorScheme(.dark) }
            .windowStyle(.hiddenTitleBar)
            .defaultSize(width: 1060, height: 740)
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct StudioView: View {
    @StateObject private var connection = BikeConnection()
    @State private var design = Design()
    @State private var notice = ""
    @State private var showDiagnostics = false
    @AppStorage("replaceFlashingMode") private var replaceFlashingMode = true
    @State private var previewEpoch = Date()
    @State private var brushColor = "#FF8A33"
    @State private var erasing = false
    @State private var imageUndo: [[UInt8]] = []
    @State private var imageRedo: [[UInt8]] = []
    private let accent = Color(red: 0.68, green: 0.96, blue: 0.36)
    private let palette = ["#FF8A33", "#FF0000", "#B0F55C", "#36D9FF", "#9C7CFF", "#FF62C6", "#FFFFFF"]
    private var raster: Raster? { try? design.raster() }
    private var designError: String? { do { _ = try design.program(); return nil } catch { return error.localizedDescription } }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("MAKE IT YOURS").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(accent)
                        Text(design.kind == "message" ? "A few bright words." : "Small canvas. Big character.").font(.system(size: 29, weight: .semibold, design: .rounded))
                    }
                    Spacer()
                    Text("36 × 12\n432 pixels").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                preview
                editor
                Spacer(minLength: 0)
                if let error = designError { Text(error).font(.callout).foregroundStyle(.orange) }
                if !notice.isEmpty { Text(notice).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Use this design in the double-flash slot, too", isOn: $replaceFlashingMode)
                        .toggleStyle(.checkbox).disabled(connection.busy)
                    Text("Replaces hazard/emergency artwork. Left, right, forward and brake stay unchanged.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(connection.status).font(.system(size: 13, weight: .medium))
                        Text(replaceFlashingMode ? "Updates ordinary display + double-flash slot." : "Updates the ordinary display program.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if connection.busy { ProgressView(value: connection.progress).frame(width: 80) }
                    Button(action: send) {
                        Label("Send to panel", systemImage: "arrow.up.right")
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .foregroundStyle(.black)
                            .background(accent, in: RoundedRectangle(cornerRadius: 9))
                            .opacity(!connection.connected || connection.busy || designError != nil ? 0.4 : 1)
                    }.buttonStyle(.plain)
                        .disabled(!connection.connected || connection.busy || designError != nil)
                }
            }.padding(32)
        }
        .background(Color(red: 0.055, green: 0.065, blue: 0.075))
        .onChange(of: design.text) { _, _ in previewEpoch = Date() }
        .onAppear { connection.onUploaded = { notice = "Upload acknowledged. The panel's reported settings are unchanged." } }
        .sheet(isPresented: $showDiagnostics) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connection details").font(.title2)
                Text("Device information, remote mode notifications and upload acknowledgements. Only ordinary content and optional double-flash slot 5 can be written; directional/brake slots, remote settings, reset and firmware are blocked.").foregroundStyle(.secondary)
                ScrollView { Text(connection.events.joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                Button("Done") { showDiagnostics = false }.keyboardShortcut(.defaultAction)
            }.padding(24).frame(width: 630, height: 420)
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 10) {
                Image(systemName: "bicycle").font(.system(size: 24)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) { Text("iLedBike").font(.system(size: 19, weight: .bold, design: .rounded)); Text("STUDIO").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(.secondary) }
            }.padding(.top, 8)
            VStack(spacing: 8) {
                toolButton("Message", icon: "textformat", kind: "message")
                toolButton("Image", icon: "photo", kind: "image")
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("YOUR DESIGNS").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                Button(action: saveDesign) { Label("Save design…", systemImage: "square.and.arrow.down") }.buttonStyle(.plain)
                Button(action: openDesign) { Label("Open design…", systemImage: "folder") }.buttonStyle(.plain)
                Button(action: exportPreview) { Label("Export pixels…", systemImage: "square.and.arrow.up") }.buttonStyle(.plain).disabled(raster == nil)
            }.font(.system(size: 12))
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Circle().fill(connection.connected ? accent : .gray).frame(width: 7, height: 7); Text(connection.connected ? "PANEL CONNECTED" : "PANEL CONNECTION").font(.system(size: 9, weight: .bold)).tracking(1) }
                if connection.connected || connection.busy {
                    Button("Disconnect") { connection.disconnect() }.buttonStyle(.bordered)
                } else {
                    Button("Find panel") { connection.scan() }.buttonStyle(.bordered)
                    ForEach(connection.devices, id: \.identifier) { device in
                        Button("Connect iLedBike · \(String(device.identifier.uuidString.suffix(4)))") { connection.connect(device) }.font(.caption)
                    }
                }
                Button("Connection details") { showDiagnostics = true }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            Text("LOCAL BY DESIGN\nNo account. No cloud.").font(.system(size: 9, design: .monospaced)).lineSpacing(4).foregroundStyle(.tertiary)
        }.padding(24).frame(width: 205).frame(maxHeight: .infinity).background(.white.opacity(0.025))
    }
    private func toolButton(_ title: String, icon: String, kind: String) -> some View {
        Button {
            design.kind = kind
            if kind == "image", design.imagePixels == nil { design.imagePixels = PixelDrawing.blank }
            notice = ""
        } label: {
            HStack { Image(systemName: icon).frame(width: 22); Text(title); Spacer() }
                .font(.system(size: 13, weight: .medium)).padding(12)
                .foregroundStyle(design.kind == kind ? accent : .secondary)
                .background(design.kind == kind ? accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(design.kind == "image" ? "PIXEL CANVAS" : "PANEL PREVIEW").tracking(1.6); Spacer(); Text(design.kind == "message" && design.scrolling ? "SCROLLING" : "36 × 12") }.font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            if design.kind == "image" {
                PixelDrawingCanvas(pixels: $design.imagePixels, color: erasing ? "#000000" : brushColor, beginStroke: rememberImage)
                    .aspectRatio(3, contentMode: .fit)
            } else {
                TimelineView(.animation(minimumInterval: 0.08, paused: !design.scrolling)) { timeline in
                    PixelPreview(raster: raster, offset: previewOffset(at: timeline.date))
                }.aspectRatio(3, contentMode: .fit)
            }
            HStack { Image(systemName: "checkmark.shield"); Text("Left, right, forward, brake and remote settings are protected.") }.font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(20).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.07)))
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            if design.kind == "message" {
                HStack { Text("Your message").font(.headline); Spacer(); Text("\(design.text.count) / 40").font(.caption).foregroundStyle(.secondary) }
                TextField("Something worth lighting up", text: $design.text).font(.system(size: 21, weight: .medium, design: .rounded)).textFieldStyle(.plain).padding(14).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 11) {
                    ForEach(palette, id: \.self) { hex in
                        Button { design.color = hex } label: {
                            Circle().fill(swiftColor(hex)).frame(width: 23, height: 23).padding(4)
                                .overlay(Circle().stroke(design.color == hex ? .white : .clear, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel("Color \(hex)")
                    }
                    ColorPicker("Custom color", selection: Binding(
                        get: { swiftColor(design.color) },
                        set: { design.color = colorHex($0) }
                    ), supportsOpacity: false).fixedSize().font(.caption)
                    Spacer()
                    Toggle("Scroll", isOn: $design.scrolling).toggleStyle(.switch).controlSize(.small)
                }
                if design.scrolling {
                    HStack { Text("Speed").foregroundStyle(.secondary); Slider(value: Binding(get: { Double(design.speed) }, set: { design.speed = Int($0) }), in: 40...230); Text("\(design.speed)").monospacedDigit().foregroundStyle(.secondary) }.font(.caption)
                }
            } else {
                Text("Draw something bright.").font(.headline)
                Text("Click or drag on the pixels above. Changes stay here until you send them.").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 11) {
                    ForEach(palette, id: \.self) { hex in
                        Button { brushColor = hex; erasing = false } label: {
                            Circle().fill(swiftColor(hex)).frame(width: 23, height: 23).padding(4)
                                .overlay(Circle().stroke(!erasing && brushColor == hex ? .white : .clear, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel("Brush \(hex)")
                    }
                    ColorPicker("Custom color", selection: Binding(
                        get: { swiftColor(brushColor) },
                        set: { brushColor = colorHex($0); erasing = false }
                    ), supportsOpacity: false).fixedSize().font(.caption)
                    Spacer()
                    Toggle(isOn: $erasing) { Label("Eraser", systemImage: "eraser") }.toggleStyle(.button)
                }
                HStack {
                    Button { undoImage() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(imageUndo.isEmpty)
                    Button { redoImage() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(imageRedo.isEmpty)
                    Button("Clear") { rememberImage(); design.imagePixels = PixelDrawing.blank }.disabled(!(design.imagePixels?.contains(where: { $0 != 0 }) ?? false))
                    Spacer()
                    Button(action: importImage) { Label("Import image…", systemImage: "photo.badge.plus") }
                }.buttonStyle(.bordered)
            }
        }
    }
    private func previewOffset(at date: Date) -> Int {
        guard design.kind == "message", design.scrolling, let raster else { return 0 }
        return Int(max(0, date.timeIntervalSince(previewEpoch)) * (4 + Double(design.speed) / 15)) % (raster.width + 36) - 36
    }
    private func swiftColor(_ hex: String) -> Color {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0xffffff
        return Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
    private func colorHex(_ color: Color) -> String {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }
    private func send() {
        do { let program = try design.program(); notice = ""; connection.upload(program: program, replaceFlashingMode: replaceFlashingMode) }
        catch { notice = error.localizedDescription }
    }
    private func rememberImage() {
        imageUndo.append(design.imagePixels ?? PixelDrawing.blank)
        if imageUndo.count > 100 { imageUndo.removeFirst() }
        imageRedo = []; notice = ""
    }
    private func undoImage() {
        guard let pixels = imageUndo.popLast() else { return }
        imageRedo.append(design.imagePixels ?? PixelDrawing.blank)
        design.imagePixels = pixels; notice = ""
    }
    private func redoImage() {
        guard let pixels = imageRedo.popLast() else { return }
        imageUndo.append(design.imagePixels ?? PixelDrawing.blank)
        design.imagePixels = pixels; notice = ""
    }
    private func importImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pixels = try Raster.importImage(url).pixels
            rememberImage(); design.imagePixels = pixels; design.kind = "image"
            notice = "Image fitted to the panel. Draw on it to make it yours."
        }
        catch { notice = error.localizedDescription }
    }
    private func saveDesign() {
        do {
            try design.validate()
            let panel = NSSavePanel(); panel.nameFieldStringValue = "My design.iledbike.json"; panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(design).write(to: url, options: .atomic); notice = "Design saved locally."
        } catch { notice = error.localizedDescription }
    }
    private func openDesign() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            guard size?.intValue ?? Int.max < 100_000 else { throw StudioError.invalid("Design file is too large.") }
            let loaded = try JSONDecoder().decode(Design.self, from: Data(contentsOf: url)); try loaded.validate()
            design = loaded; imageUndo = []; imageRedo = []; notice = "Design opened. Send when you're ready."
        } catch { notice = error.localizedDescription }
    }
    private func exportPreview() {
        guard let raster else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Panel pixels.png"; panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try raster.png().write(to: url, options: .atomic); notice = "Pixel artwork exported." } catch { notice = error.localizedDescription }
    }
}

