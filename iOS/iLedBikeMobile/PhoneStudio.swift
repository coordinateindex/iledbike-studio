import SwiftUI
import PhotosUI
import CoreBluetooth
import UIKit

private let bikeAccent = Color(red: 0.69, green: 0.96, blue: 0.36)
private let bikeBackground = Color(red: 0.045, green: 0.06, blue: 0.065)
let bikePalette = ["#FF0000", "#FF8A33", "#B0F55C", "#36D9FF", "#9C7CFF", "#FF62C6", "#FFFFFF"]
func phoneColor(_ hex: String) -> Color {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
}
func phoneHex(_ color: Color) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#FFFFFF" }
    return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
}

@main struct BikePhoneApp: App {
    var body: some Scene {
        WindowGroup { PhoneStudio().preferredColorScheme(.dark).tint(bikeAccent) }
    }
}

struct PhoneStudio: View {
    @StateObject private var store = LibraryStore()
    @StateObject private var connection = BikeConnection()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("replaceFlashingMode") private var replaceFlash = true
    @State private var tab = 0
    @State private var settingUp: String?
    @State private var verificationStart = 0
    @State private var physicalPanelConfirmed = false
    @State private var confirmConnectionMove = false
    @State private var error: String?
    @State private var notice = ""
    @State private var showingDrawing = false
    @State private var showingDetails = false
    @State private var importing = false
    @State private var exporting = false
    @State private var naming = false
    @State private var designName = ""
    @State private var photo: PhotosPickerItem?
    @State private var previewEpoch = Date()
    @State private var sentBikeName = ""
    @State private var importingPhoto = false
    @FocusState private var textFocused: Bool

    private var design: Binding<Design> { Binding(get: { store.design }, set: { store.updateDesign($0); notice = "" }) }
    private var matchesBike: Bool { connection.connected && connection.selectedIdentifier == store.bike.peripheralID && store.bike.peripheralID != nil }
    private var validProgram: Bool { (try? store.design.program()) != nil }
    private var canSend: Bool { matchesBike && connection.displayIsOn && !connection.busy && validProgram && !importingPhoto }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { bikesScreen }.tabItem { Label("Bikes", systemImage: "bicycle") }.tag(0)
            NavigationStack { editorScreen }.tabItem { Label("Studio", systemImage: "square.grid.3x3.fill") }.tag(1)
            NavigationStack { libraryScreen }.tabItem { Label("Designs", systemImage: "square.stack") }.tag(2)
        }
        .onAppear {
            connection.onUploaded = {
                notice = "Sent to \(sentBikeName). Your bike is ready."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            connection.onFailure = { message in notice = message }
            connection.onDisplayPowerChanged = { isOn in
                notice = "\(store.bike.name)’s display reports \(isOn ? "on" : "off")."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            connection.onSignalChanged = { signal in
                notice = "\(store.bike.name) reports \(signal.label.lowercased())."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        .onChange(of: connection.busy) { _, busy in UIApplication.shared.isIdleTimerDisabled = busy }
        .onChange(of: connection.selectedIdentifier) { _, _ in physicalPanelConfirmed = false }
        .onChange(of: settingUp) { _, _ in physicalPanelConfirmed = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.saveNow(); connection.pauseForBackground(); UIApplication.shared.isIdleTimerDisabled = false }
        }
        .onChange(of: store.design.text) { _, _ in previewEpoch = Date() }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            let targetBike = store.library.selectedBikeID
            importingPhoto = true
            Task { @MainActor in
                defer { importingPhoto = false; photo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), data.count <= 20_000_000 else {
                        throw StudioError.invalid("Choose a photo smaller than 20 MB.")
                    }
                    guard targetBike == store.library.selectedBikeID else { throw StudioError.invalid("Bike changed during import. Choose the photo again for this bike.") }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try data.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
                    var next = store.design; next.imagePixels = try Raster.importImage(url).pixels; next.kind = "image"
                    store.updateDesign(next)
                } catch { self.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showingDetails) {
            NavigationStack {
                ScrollView { Text(connection.events.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() }
                    .navigationTitle("Connection details").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingDetails = false } } }
            }
        }
        .fullScreenCover(isPresented: $showingDrawing) {
            TouchPixelEditor(pixels: Binding(get: { store.design.imagePixels ?? PixelDrawing.blank }, set: { pixels in
                var next = store.design; next.imagePixels = pixels; store.updateDesign(next)
            }))
        }
        .alert("Something needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .alert("Correct this panel’s saved name?", isPresented: $confirmConnectionMove) {
            Button("Cancel", role: .cancel) {}
            Button("Move connection") { saveConnection(moving: true) }
        } message: {
            Text("Move this connection from \(connectedOwner?.name ?? "the other bike") to \(store.bike.name)? The old bike will need setup again. Both bikes keep their own designs.")
        }
        .alert("Save design", isPresented: $naming) {
            TextField("Design name", text: $designName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                do { try store.saveDesign(name: designName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My design" : designName); notice = "Saved in your design library." }
                catch { self.error = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 100_000 else { throw StudioError.invalid("Choose an iLedBike design JSON file smaller than 100 KB.") }
                let imported = try JSONDecoder().decode(Design.self, from: Data(contentsOf: url)); try imported.validate()
                store.updateDesign(imported); notice = "Design imported. Nothing has been sent."; tab = 1
            } catch { self.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: DesignDocument(design: store.design), contentType: .json, defaultFilename: "Bike design.iledbike") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }

    private var bikesScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro("YOUR RIDES", title: "Pick a bike.", subtitle: "Two bikes. Your own designs. All local.")
                ForEach(store.library.bikes) { bike in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "bicycle").font(.title).foregroundStyle(bikeAccent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bike.name).font(.title3.bold())
                                Text(bike.id == store.bike.id && matchesBike ? (connection.displayIsOn ? "Connected · display on" : "Connected · display off") : bike.peripheralID == nil ? "Set up once to remember this bike" : "Saved on this iPhone")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if bike.id == store.bike.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(bikeAccent) }
                        }
                        Button {
                            textFocused = false
                            if connection.selectedIdentifier != bike.peripheralID || bike.peripheralID == nil { connection.disconnect() }
                            store.selectBike(bike.id); notice = ""
                            if let identifier = bike.peripheralID {
                                settingUp = nil
                                if !matchesBike { connection.reconnect(identifier) }
                                tab = 1
                            } else { settingUp = bike.id; connection.scan() }
                        } label: {
                            Text(bike.peripheralID == nil ? "Find \(bike.name)" : bike.id == store.bike.id && matchesBike ? "Open studio" : "Connect & edit")
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(connection.busy || importingPhoto)
                        if bike.peripheralID != nil {
                            Menu {
                                Button("Find this bike again") {
                                    connection.disconnect(); store.selectBike(bike.id); settingUp = bike.id; connection.scan()
                                }
                                Button("Forget connection", role: .destructive) {
                                    if bike.id == store.bike.id { connection.disconnect() }; store.forget(bike.id)
                                }
                            } label: { Label("Connection options", systemImage: "ellipsis.circle").font(.subheadline).frame(minHeight: 36) }
                            .disabled(connection.busy)
                        }
                    }.card()
                }
                if settingUp != nil { discovery }
                if !connection.status.isEmpty { Text(connection.status).font(.footnote).foregroundStyle(.secondary) }
                if let message = store.storageError { Text(message).foregroundStyle(.orange) }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Display off ≠ Bluetooth off", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                    Text("A bike can appear nearby while its LEDs are off. Turn the panel on before sending. The Mac app must disconnect before this phone connects.").font(.subheadline).foregroundStyle(.secondary)
                }.card()
                Button("Connection details") { showingDetails = true }.font(.subheadline).frame(minHeight: 44)
            }.padding(20)
        }.background(bikeBackground).navigationTitle("iLedBike Studio").navigationBarTitleDisplayMode(.inline)
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find \(store.bike.name)").font(.title3.bold())
            if !connection.connected {
                Text("Keep only \(store.bike.name) in Bluetooth range during setup. A remote can trigger both panels, so its reply alone cannot identify a bike.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(connection.devices, id: \.identifier) { device in
                    Button {
                        physicalPanelConfirmed = false
                        verificationStart = connection.remoteEventCount; connection.connect(device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Panel · \(device.identifier.uuidString.suffix(4))", systemImage: "antenna.radiowaves.left.and.right")
                                Text(store.owner(of: device.identifier).map { "Saved as \($0.name)" } ?? "Not assigned to a bike")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right")
                        }.frame(minHeight: 44)
                    }
                        .disabled(connection.busy)
                }
                if connection.scanning { ProgressView("Looking nearby…") }
                Button("Find nearby bikes") { connection.scan() }.disabled(connection.busy || connection.scanning).frame(minHeight: 44)
            } else {
                Text("Connected panel · \(connection.selectedIdentifier?.uuidString.suffix(4) ?? "")").font(.headline)
                if let owner = connectedOwner {
                    Text("Currently saved as \(owner.name).").font(.subheadline).foregroundStyle(owner.id == store.bike.id ? Color.secondary : Color.orange)
                }
                Text("With the other bike out of Bluetooth range, short-press RIGHT on \(store.bike.name)’s remote. Check the large LED panel, not the remote’s indicator light. Don’t hold the button.").font(.subheadline)
                let verified = connection.remoteEventCount > verificationStart && connection.lastRemoteMode == 3
                Label(verified ? "Right-button reply received" : "Waiting for a right-button reply", systemImage: verified ? "checkmark.circle.fill" : "hand.tap")
                    .foregroundStyle(verified ? bikeAccent : .secondary)
                Toggle("Only \(store.bike.name) is in range, and its LED panel showed the right arrow", isOn: $physicalPanelConfirmed)
                    .font(.subheadline).disabled(!verified || connection.busy)
                Button("Save as \(store.bike.name)") {
                    if let owner = connectedOwner, owner.id != store.bike.id { confirmConnectionMove = true }
                    else { saveConnection(moving: false) }
                }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!verified || !physicalPanelConfirmed || connection.busy)
                Button("Try another panel") { connection.disconnect(); verificationStart = connection.remoteEventCount; connection.scan() }.frame(minHeight: 44)
            }
        }.card()
    }

    private var connectedOwner: SavedBike? {
        connection.selectedIdentifier.flatMap { store.owner(of: $0) }
    }
    private func saveConnection(moving: Bool) {
        guard settingUp == store.bike.id, connection.connected, !connection.busy,
              physicalPanelConfirmed, connection.remoteEventCount > verificationStart,
              connection.lastRemoteMode == 3, let identifier = connection.selectedIdentifier else { return }
        do {
            if moving {
                guard let owner = connectedOwner else { return }
                try store.moveConnection(identifier, from: owner.id, to: store.bike.id)
            } else { try store.assign(identifier, to: store.bike.id) }
            store.saveNow(); settingUp = nil; tab = 1
        } catch { self.error = error.localizedDescription }
    }

    private var editorScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Button { tab = 0 } label: {
                    HStack {
                        Circle().fill(matchesBike && connection.displayIsOn ? bikeAccent : .orange).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 3) { Text(store.bike.name).font(.headline); Text(matchesBike ? connection.displayIsOn ? "Connected and ready" : "Display off · turn it on" : "Tap to connect or switch bikes").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.down")
                    }.foregroundStyle(.primary)
                }.card().disabled(connection.busy)
                if matchesBike { displayControls }
                Picker("Design type", selection: design.kind) { Text("Message").tag("message"); Text("Image").tag("image") }.pickerStyle(.segmented)
                    .onChange(of: store.design.kind) { _, kind in if kind == "image" && store.design.imagePixels == nil { var next = store.design; next.imagePixels = PixelDrawing.blank; store.updateDesign(next) } }
                    .disabled(connection.busy)
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(store.design.kind == "image" ? "YOUR PIXELS" : "LIVE PREVIEW").font(.caption.monospaced().bold()).tracking(1.5); Spacer(); Text("36 × 12").font(.caption.monospaced()).foregroundStyle(.secondary) }
                    TimelineView(.animation(minimumInterval: 0.08, paused: store.design.kind == "image" || !store.design.scrolling || scenePhase != .active)) { context in
                        let raster = try? store.design.raster()
                        let offset = store.design.kind == "message" && store.design.scrolling ? Int(max(0, context.date.timeIntervalSince(previewEpoch)) * (4 + Double(store.design.speed) / 15)) % ((raster?.width ?? 36) + 36) - 36 : 0
                        PixelPreview(raster: raster, offset: offset).aspectRatio(3, contentMode: .fit)
                    }
                    if store.design.kind == "image" {
                        Button { showingDrawing = true } label: { Label("Draw & edit pixels", systemImage: "hand.draw.fill").frame(maxWidth: .infinity, minHeight: 36) }.buttonStyle(.bordered).disabled(connection.busy)
                    }
                }.card()
                if store.design.kind == "message" { messageEditor } else { imageTools }
                Toggle(isOn: $replaceFlash) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Same design when cycling").font(.headline)
                        Text("Also replaces double-flash / hazard artwork. Turn signals and brake stay intact.").font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(connection.busy).card()
                if matchesBike && !connection.displayIsOn {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use Display on above, or turn it on with the remote and refresh.").font(.subheadline)
                        Button("Refresh panel status") { connection.queryInfo() }.frame(minHeight: 44).disabled(connection.busy)
                    }.card()
                }
                if !notice.isEmpty { Label(notice, systemImage: "info.circle").font(.subheadline).foregroundStyle(bikeAccent).accessibilityIdentifier("uploadNotice") }
                if !validProgram { Text(programError).font(.footnote).foregroundStyle(.orange) }
                if let message = store.storageError { Text(message).font(.footnote).foregroundStyle(.orange) }
                HStack {
                    Button { designName = store.design.kind == "image" ? "My pixel art" : store.design.text; naming = true } label: { Label("Save design", systemImage: "square.and.arrow.down") }.disabled(!validProgram)
                    Spacer()
                    Menu { Button("Export design file") { exporting = true }; Button("Import design file") { importing = true }; Button("Connection details") { showingDetails = true } } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                }.disabled(connection.busy)
            }.padding(20).padding(.bottom, 8)
        }
        .scrollDismissesKeyboard(.interactively).background(bikeBackground)
        .navigationTitle("Make it yours").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { textFocused = false } } }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if connection.busy { ProgressView(value: connection.progress).tint(bikeAccent); Text(connection.status).font(.caption) }
                Button {
                    textFocused = false
                    guard canSend else { return }
                    do {
                        let program = try store.design.program(); sentBikeName = store.bike.name; notice = ""
                        connection.upload(program: program, replaceFlashingMode: replaceFlash)
                    } catch { self.error = error.localizedDescription }
                } label: {
                    HStack { Image(systemName: "arrow.up.right"); Text(connection.busy ? "Working… Keep app open" : "Send to \(store.bike.name)").fontWeight(.bold) }.frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!canSend)
                if !connection.busy && !matchesBike { Button("Connect \(store.bike.name)") { if let identifier = store.bike.peripheralID { connection.reconnect(identifier) } else { tab = 0 } }.font(.subheadline).frame(minHeight: 32) }
            }.padding(.horizontal, 20).padding(.vertical, 10).background(.ultraThinMaterial)
        }
    }
    private var displayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(store.bike.name) display", systemImage: "power").font(.headline)
            HStack(spacing: 12) {
                Button {
                    guard matchesBike, let identifier = store.bike.peripheralID else { return }
                    notice = ""; connection.setDisplayPower(true, for: identifier)
                } label: {
                    Label("Display on", systemImage: "sun.max").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("displayOn")
                Button {
                    guard matchesBike, let identifier = store.bike.peripheralID else { return }
                    notice = ""; connection.setDisplayPower(false, for: identifier)
                } label: {
                    Label("Display off", systemImage: "moon").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("displayOff")
            }.buttonStyle(.bordered)
            Text("Off darkens the display. Bluetooth may stay awake; this does not turn off the handheld remote.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup {
                VStack(spacing: 10) {
                    signalButton(.forward, icon: "arrow.up")
                    HStack(spacing: 8) {
                        signalButton(.left, icon: "arrow.left")
                        signalButton(.artwork, icon: "square.grid.3x3")
                        signalButton(.right, icon: "arrow.right")
                    }
                    signalButton(.brake, icon: "arrow.down")
                    Text("Uses the panel’s existing signals. My design returns to its uploaded artwork.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12).disabled(!connection.displayIsOn)
            } label: { Label("Signals", systemImage: "arrow.up.and.down.and.arrow.left.and.right").font(.headline) }
        }.card().disabled(connection.busy)
    }
    private func signalButton(_ signal: BikeProtocol.Signal, icon: String) -> some View {
        Button {
            guard matchesBike, let identifier = store.bike.peripheralID else { return }
            notice = ""; connection.selectSignal(signal, for: identifier)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(signal.label).font(.caption.weight(.semibold))
            }.frame(maxWidth: .infinity, minHeight: 56)
        }.buttonStyle(.bordered)
            .accessibilityIdentifier("signal-\(signal.rawValue)")
    }
    private var programError: String { do { _ = try store.design.program(); return "" } catch { return error.localizedDescription } }
    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Something worth lighting up", text: design.text, axis: .vertical).font(.title2.bold()).lineLimit(1...3).focused($textFocused).textInputAutocapitalization(.characters)
                .onChange(of: store.design.text) { _, value in if value.count > 40 { var next = store.design; next.text = String(value.prefix(40)); store.updateDesign(next) } }
            HStack { Text("\(store.design.text.count)/40 characters").font(.caption).foregroundStyle(.secondary); Spacer(); ColorPicker("Color", selection: Binding(get: { phoneColor(store.design.color) }, set: { color in var next = store.design; next.color = phoneHex(color); store.updateDesign(next) }), supportsOpacity: false) }
            Toggle("Scroll message", isOn: design.scrolling)
            if store.design.scrolling { HStack { Image(systemName: "tortoise"); Slider(value: Binding(get: { Double(store.design.speed) }, set: { value in var next = store.design; next.speed = Int(value); store.updateDesign(next) }), in: 40...230); Image(systemName: "hare") }.accessibilityLabel("Scroll speed") }
        }.card().disabled(connection.busy)
    }
    private var imageTools: some View {
        HStack {
            PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) { Label("Import photo", systemImage: "photo") }.frame(minHeight: 44)
            Spacer()
            if importingPhoto { ProgressView() } else { Text("Draw or fit a photo").font(.caption).foregroundStyle(.secondary) }
        }.card().disabled(connection.busy || importingPhoto)
    }
    private var libraryScreen: some View {
        List {
            Section {
                Text("Load a design into \(store.bike.name)’s studio. Nothing sends until you tap Send.").font(.subheadline).foregroundStyle(.secondary)
                Button("Import from Files", systemImage: "folder") { importing = true }.frame(minHeight: 36).disabled(connection.busy)
            }
            Section {
                ForEach(HalloweenDesigns.all) { item in
                    Button {
                        store.updateDesign(item.design); tab = 1
                        notice = "Loaded \(item.name). Edit it or send when ready."
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.name).font(.headline).foregroundStyle(.primary)
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            PixelPreview(raster: try? item.design.raster(), offset: 0)
                                .aspectRatio(3, contentMode: .fit).frame(maxHeight: 90)
                            if item.design.kind == "message" {
                                Text(item.design.text).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }.disabled(connection.busy || importingPhoto)
                }
            } header: { Text("Halloween collection") }
              footer: { Text("Tap a design to load it into \(store.bike.name)’s Studio. Save your edits to keep a personal copy.") }
            if store.library.designs.isEmpty {
                ContentUnavailableView("Your collection starts here", systemImage: "square.stack", description: Text("Save a message or drawing from Studio, or import a design made on your Mac."))
            }
            ForEach(store.library.designs) { item in
                Button {
                    store.updateDesign(item.design); tab = 1; notice = "Loaded \(item.name). Ready when you are."
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.name).font(.headline).foregroundStyle(.primary)
                        PixelPreview(raster: try? item.design.raster(), offset: 0).aspectRatio(3, contentMode: .fit).frame(maxHeight: 90)
                    }.padding(.vertical, 8)
                }.disabled(connection.busy)
            }.onDelete { offsets in if !connection.busy { store.removeDesigns(at: offsets) } }
        }.navigationTitle("Saved designs").toolbar { EditButton().disabled(connection.busy) }
    }
    private func intro(_ eyebrow: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.caption.monospaced().bold()).tracking(2).foregroundStyle(bikeAccent)
            Text(title).font(.largeTitle.bold()); Text(subtitle).foregroundStyle(.secondary)
        }
    }
}

private extension View {
    func card() -> some View { padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.065))) }
}

struct TouchPixelEditor: View {
    @Binding var pixels: [UInt8]
    @Environment(\.dismiss) private var dismiss
    @State private var color = "#B0F55C"
    @State private var tool = "Paint"
    @State private var zoom = 2
    @State private var undo: [[UInt8]] = []
    @State private var redo: [[UInt8]] = []
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    Text(tool == "Move" ? "Drag to move around the canvas" : "Drag to paint. Switch to Move to pan.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("Zoom", selection: $zoom) { Text("1×").tag(1); Text("2×").tag(2); Text("4×").tag(4) }.pickerStyle(.segmented).frame(width: 144)
                }.padding(.horizontal)
                GeometryReader { geometry in
                    let width = max(288, geometry.size.width - 32) * CGFloat(zoom)
                    ScrollView([.horizontal, .vertical]) {
                        PixelDrawingCanvas(pixels: Binding(get: { pixels }, set: { pixels = $0 ?? PixelDrawing.blank }), color: tool == "Erase" ? "#000000" : color, beginStroke: remember)
                            .frame(width: width, height: width / 3).allowsHitTesting(tool != "Move").padding(16)
                    }.scrollDisabled(tool != "Move").background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                }
                Picker("Tool", selection: $tool) { Text("Paint").tag("Paint"); Text("Erase").tag("Erase"); Text("Move").tag("Move") }.pickerStyle(.segmented).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bikePalette, id: \.self) { hex in
                            Button { color = hex; tool = "Paint" } label: { Circle().fill(phoneColor(hex)).frame(width: 28, height: 28).padding(7).overlay(Circle().stroke(color == hex && tool == "Paint" ? .white : .clear, lineWidth: 2)) }.accessibilityLabel("Brush \(hex)")
                        }
                        ColorPicker("Custom", selection: Binding(get: { phoneColor(color) }, set: { color = phoneHex($0); tool = "Paint" }), supportsOpacity: false).labelsHidden().frame(width: 44, height: 44).accessibilityLabel("Custom brush color")
                    }.padding(.horizontal)
                }
                HStack {
                    Button { guard let previous = undo.popLast() else { return }; redo.append(pixels); pixels = previous } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(undo.isEmpty)
                    Button { guard let next = redo.popLast() else { return }; undo.append(pixels); pixels = next } label: { Label("Redo", systemImage: "arrow.uturn.forward") }.disabled(redo.isEmpty)
                    Spacer(); Button("Clear", role: .destructive) { confirmClear = true }
                }.buttonStyle(.bordered).controlSize(.large).padding(.horizontal).padding(.bottom, 8)
            }.background(bikeBackground).navigationTitle("Pixel studio").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.bold) } }
                .confirmationDialog("Clear the canvas? You can undo this.", isPresented: $confirmClear, titleVisibility: .visible) { Button("Clear pixels", role: .destructive) { remember(); pixels = PixelDrawing.blank } }
        }.tint(bikeAccent).preferredColorScheme(.dark)
    }
    private func remember() { undo.append(pixels); if undo.count > 100 { undo.removeFirst() }; redo = [] }
}
