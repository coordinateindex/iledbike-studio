import XCTest
@testable import iLedBikeMobile

final class MobileTests: XCTestCase {
    func testLegacyLibraryMigrationPreservesProfilesDraftsAndSelection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var original = PhoneLibrary()
        original.version = 1
        let firstID = UUID(), secondID = UUID()
        original.bikes = [SavedBike(id: "legacy-primary", name: "Custom first", peripheralID: firstID),
                          SavedBike(id: "legacy-secondary", name: "Custom second", peripheralID: secondID)]
        original.selectedBikeID = "legacy-secondary"
        var first = Design(); first.text = "FIRST"
        var second = Design(); second.text = "SECOND"
        original.drafts = ["legacy-primary": first, "legacy-secondary": second]
        original.designs = [SavedDesign(name: "Keep artwork", design: first)]
        let bytes = try JSONEncoder().encode(original)
        try bytes.write(to: url)
        let store = LibraryStore(file: url)
        XCTAssertNil(store.storageError)
        XCTAssertEqual(store.library.version, 2)
        XCTAssertEqual(store.bike.id, "bike-2")
        XCTAssertEqual(store.bike.name, "Custom second")
        XCTAssertEqual(store.bike.peripheralID, secondID)
        XCTAssertEqual(store.design.text, "SECOND")
        XCTAssertEqual(try Data(contentsOf: url), bytes, "Loading alone must not overwrite the original")
        store.selectBike("bike-1"); store.saveNow()
        let reloaded = LibraryStore(file: url)
        XCTAssertEqual(reloaded.bike.name, "Custom first")
        XCTAssertEqual(reloaded.bike.peripheralID, firstID)
        XCTAssertEqual(reloaded.design.text, "FIRST")
        XCTAssertEqual(reloaded.library.designs.first?.name, "Keep artwork")
        XCTAssertEqual(reloaded.library.drafts["bike-2"]?.text, "SECOND")
    }
    func testAmbiguousLegacyLibraryIsPreservedWithoutMigration() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var original = PhoneLibrary(); original.version = 1
        original.bikes = [SavedBike(id: "duplicate", name: "First"), SavedBike(id: "duplicate", name: "Second")]
        original.selectedBikeID = "duplicate"
        let bytes = try JSONEncoder().encode(original); try bytes.write(to: url)
        let store = LibraryStore(file: url); store.saveNow()
        XCTAssertNotNil(store.storageError)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    func testSignalSelectionIsScopedAndRequiresExactModeReadback() throws {
        XCTAssertEqual(BikeProtocol.envelope(BikeProtocol.Signal.left.payload), Data([1, 0, 2, 6, 0x1b, 2, 6, 3]))
        XCTAssertThrowsError(try BikeProtocol.validate([0x1c]))
        XCTAssertNil(BikeProtocol.Signal(rawValue: 5), "Hazard is not an exposed signal button")
        for signal in BikeProtocol.Signal.allCases {
            try BikeProtocol.validate(signal.payload, signal: signal)
            try BikeProtocol.validate([0x1c], signal: signal)
            try signal.verifyMode([0x1c, signal.rawValue])
            XCTAssertThrowsError(try BikeProtocol.validate(signal.payload))
            XCTAssertThrowsError(try signal.verifyMode([0x1e, signal.rawValue]))
            XCTAssertThrowsError(try signal.verifyMode([0x1c]))
            for state in 0...255 where state != Int(signal.rawValue) {
                XCTAssertThrowsError(try BikeProtocol.validate([0x1b, UInt8(state)], signal: signal))
                XCTAssertThrowsError(try signal.verifyMode([0x1c, UInt8(state)]))
            }
            for body: [UInt8] in [[0x1c, 1], [0x1b], [0x1b, signal.rawValue, 0], [0x1e, signal.rawValue], [5, 0], [0xfe, 0]] {
                XCTAssertThrowsError(try BikeProtocol.validate(body, signal: signal))
            }
            let program = try BikeProtocol.imageProgram(pixels: Array(repeating: 0, count: 1296))
            var decoder = FrameDecoder()
            let slotWrite = decoder.feed(try BikeProtocol.upload(program, target: .flashingMode)[0])[0]
            XCTAssertThrowsError(try BikeProtocol.validate(slotWrite, signal: signal), "Selecting a signal cannot grant artwork-slot writes")
        }
    }
    func testDisplayPowerRequiresExplicitScopeAndOnlyExpectedSettingChange() throws {
        for on in [false, true] {
            let baseline: [UInt8] = [0x1f, on ? 0 : 1, 255, 0, 0, 0, 0]
            let change = try DisplayPowerChange(isOn: on, baseline: baseline)
            var decoder = FrameDecoder()
            XCTAssertEqual(decoder.feed(BikeProtocol.envelope(change.payload)), [[5, on ? 1 : 0]])
            XCTAssertThrowsError(try BikeProtocol.validate(change.payload))
            XCTAssertThrowsError(try BikeProtocol.validate(change.payload, displayPower: !on))
            try BikeProtocol.validate(change.payload, displayPower: on)
            var expected = baseline; expected[1] = on ? 1 : 0
            try change.verify(expected)
            XCTAssertThrowsError(try change.verify(baseline))
            XCTAssertThrowsError(try change.verify(Array(expected.dropLast())))
            for index in 2..<expected.count {
                var changed = expected; changed[index] ^= 1
                XCTAssertThrowsError(try change.verify(changed))
            }
        }
        for body: [UInt8] in [[5], [5, 2], [5, 0, 0], [0x1e, 2], [0x1c, 2], [0xfe, 0]] {
            XCTAssertThrowsError(try BikeProtocol.validate(body, displayPower: false))
        }
        XCTAssertThrowsError(try DisplayPowerChange(isOn: false, baseline: []))
        XCTAssertThrowsError(try DisplayPowerChange(isOn: false, baseline: [0x1f, 2, 255, 0, 0, 0, 0]))
    }
    func testConnectionCorrectionPreservesBothDraftsAndSurvivesReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(file: url)
        var first = Design(); first.text = "FIRST"; store.updateDesign(first)
        let identifier = UUID(); try store.assign(identifier, to: "bike-1")
        store.selectBike("bike-2")
        var second = Design(); second.text = "SECOND"; store.updateDesign(second)
        try store.saveDesign(name: "Keep me")
        XCTAssertThrowsError(try store.assign(identifier, to: "bike-2"))
        XCTAssertThrowsError(try store.moveConnection(UUID(), from: "bike-1", to: "bike-2"))
        XCTAssertEqual(store.owner(of: identifier)?.id, "bike-1")
        try store.moveConnection(identifier, from: "bike-1", to: "bike-2")
        store.saveNow()
        let restored = LibraryStore(file: url)
        XCTAssertEqual(restored.owner(of: identifier)?.id, "bike-2")
        XCTAssertEqual(restored.design.text, "SECOND")
        restored.selectBike("bike-1")
        XCTAssertNil(restored.bike.peripheralID)
        XCTAssertEqual(restored.design.text, "FIRST")
        XCTAssertEqual(restored.library.designs.first?.name, "Keep me")
    }
    func testConnectionCorrectionCannotOverwriteAnotherSavedPanel() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(file: url)
        let first = UUID(), second = UUID()
        try store.assign(first, to: "bike-1"); try store.assign(second, to: "bike-2")
        XCTAssertThrowsError(try store.moveConnection(first, from: "bike-1", to: "bike-2"))
        XCTAssertEqual(store.owner(of: first)?.id, "bike-1")
        XCTAssertEqual(store.owner(of: second)?.id, "bike-2")
    }
    func testSlotsRemainProtected() throws {
        let program = try BikeProtocol.imageProgram(pixels: Array(repeating: 0, count: 1296))
        var decoder = FrameDecoder()
        let announce = decoder.feed(try BikeProtocol.upload(program, target: .flashingMode)[0])[0]
        XCTAssertEqual(announce.count, 10); XCTAssertEqual(announce[9], 5)
        XCTAssertThrowsError(try BikeProtocol.validate(announce))
        try BikeProtocol.validate(announce, target: .flashingMode)
        for state in 0...255 where state != 5 {
            var altered = announce; altered[9] = UInt8(state)
            XCTAssertThrowsError(try BikeProtocol.validate(altered, target: .flashingMode))
        }
    }
    func testBikeDraftsAndIdentitySurviveReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = LibraryStore(file: url)
        var first = Design(); first.text = "FIRST"; store.updateDesign(first)
        let identifier = UUID(); try store.assign(identifier, to: "bike-1")
        XCTAssertThrowsError(try store.assign(identifier, to: "bike-2"))
        store.selectBike("bike-2"); var other = Design(); other.text = "SECOND"; store.updateDesign(other)
        try store.saveDesign(name: "Second message"); store.saveNow()
        XCTAssertNil(store.storageError)
        let restored = LibraryStore(file: url)
        XCTAssertEqual(restored.design.text, "SECOND")
        restored.selectBike("bike-1"); XCTAssertEqual(restored.design.text, "FIRST")
        XCTAssertEqual(restored.bike.peripheralID, identifier)
        XCTAssertEqual(restored.library.designs.first?.design.text, "SECOND")
    }
    func testInvalidLibraryIsNotOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("invalid".utf8); try original.write(to: url)
        let store = LibraryStore(file: url); store.updateDesign(Design()); store.saveNow()
        XCTAssertNotNil(store.storageError); XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testTextReadsUpright() throws {
        let raster = try Raster.text("F", rgb: [255, 255, 255], scrolling: false)
        let rows = (0..<12).map { y in (0..<36).filter { x in raster.pixels[(y * 36 + x) * 3] > 0 }.count }.filter { $0 > 0 }
        XCTAssertGreaterThan(rows.first ?? 0, rows.last ?? 0, "F must have its long horizontal bar at the top")
    }
    func testInvalidDecodedLibraryUsesSafeDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var malformed = PhoneLibrary(); malformed.bikes = []
        let original = try JSONEncoder().encode(malformed); try original.write(to: url)
        let store = LibraryStore(file: url)
        XCTAssertEqual(store.bike.id, "bike-1"); XCTAssertNotNil(store.storageError)
        store.saveNow(); XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testPhoneTextAndImageRoundTrip() throws {
        var design = Design(); design.text = "HELLO BIKE"; design.color = "#00FF00"
        let raster = try design.raster(); XCTAssertEqual(raster.height, 12)
        XCTAssertTrue(raster.pixels.contains(255))
        let program = try design.program(); XCTAssertEqual(program[8], 1); XCTAssertEqual(program[14], 2)
        XCTAssertEqual(program.count, 38 + raster.width * 24)
        var pixels = PixelDrawing.blank
        PixelDrawing.line(&pixels, from: (0, 0), to: (35, 11), rgb: [255, 0, 0])
        XCTAssertEqual(Array(pixels[0..<3]), [255, 0, 0])
        XCTAssertEqual(Array(pixels.suffix(3)), [255, 0, 0])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Raster(width: 36, height: 12, pixels: pixels).png().write(to: url)
        let imported = try Raster.importImage(url)
        XCTAssertEqual(imported.pixels, pixels, "Image export/import must not flip the drawing")
    }
}
