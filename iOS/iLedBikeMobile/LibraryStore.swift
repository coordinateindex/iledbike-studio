import Foundation
import Combine

struct SavedBike: Codable, Identifiable {
    let id: String
    var name: String
    var peripheralID: UUID?
}
struct SavedDesign: Codable, Identifiable {
    var id = UUID()
    var name: String
    var design: Design
}
struct PhoneLibrary: Codable {
    var version = 2
    var bikes = [SavedBike(id: "bike-1", name: "Bike 1"), SavedBike(id: "bike-2", name: "Bike 2")]
    var selectedBikeID = "bike-1"
    var drafts: [String: Design] = [:]
    var designs: [SavedDesign] = []
    mutating func migrateIfNeeded() throws {
        guard version == 1 else { return }
        let previousIDs = bikes.map(\.id)
        guard previousIDs.count == 2, Set(previousIDs).count == 2,
              previousIDs.contains(selectedBikeID), Set(drafts.keys).isSubset(of: Set(previousIDs)) else {
            throw StudioError.invalid("This library has an unsupported format.")
        }
        let identifiers = ["bike-1", "bike-2"]
        let mapping = Dictionary(uniqueKeysWithValues: zip(previousIDs, identifiers))
        bikes = zip(bikes, identifiers).map { SavedBike(id: $0.1, name: $0.0.name, peripheralID: $0.0.peripheralID) }
        drafts = Dictionary(uniqueKeysWithValues: drafts.map { (mapping[$0.key]!, $0.value) })
        selectedBikeID = mapping[selectedBikeID]!
        version = 2
    }
    func validate() throws {
        guard version == 2, bikes.count == 2, Set(bikes.map(\.id)) == ["bike-1", "bike-2"],
              bikes.contains(where: { $0.id == selectedBikeID }),
              Set(drafts.keys).isSubset(of: Set(bikes.map(\.id))),
              Set(bikes.compactMap(\.peripheralID)).count == bikes.compactMap(\.peripheralID).count,
              designs.count <= 200 else { throw StudioError.invalid("This library has an unsupported format.") }
        for design in drafts.values { try design.validate() }
        for item in designs { try item.design.validate() }
    }
}

final class LibraryStore: ObservableObject {
    @Published private(set) var library: PhoneLibrary
    @Published private(set) var storageError: String?
    private let file: URL
    private var pendingSave: DispatchWorkItem?
    private var blocked = false
    var bike: SavedBike { library.bikes.first(where: { $0.id == library.selectedBikeID })! }
    var design: Design { library.drafts[library.selectedBikeID] ?? Design() }

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("BikeLibrary.json")
        var loaded = PhoneLibrary()
        do {
            if FileManager.default.fileExists(atPath: self.file.path) {
                let data = try Data(contentsOf: self.file)
                guard data.count <= 10_000_000 else { throw StudioError.invalid("The local library is too large.") }
                loaded = try JSONDecoder().decode(PhoneLibrary.self, from: data)
                try loaded.migrateIfNeeded()
                try loaded.validate()
            }
        } catch {
            storageError = "Could not open the saved library. Its file has been preserved. \(error.localizedDescription)"
            blocked = true
            loaded = PhoneLibrary()
        }
        library = loaded
    }
    func updateDesign(_ design: Design) {
        library.drafts[library.selectedBikeID] = design; scheduleSave()
    }
    func selectBike(_ id: String) {
        guard library.bikes.contains(where: { $0.id == id }) else { return }
        library.selectedBikeID = id; scheduleSave()
    }
    func assign(_ identifier: UUID, to id: String) throws {
        guard !library.bikes.contains(where: { $0.id != id && $0.peripheralID == identifier }) else {
            throw StudioError.invalid("That panel is already saved as the other bike. Connect to a different nearby panel.")
        }
        guard let index = library.bikes.firstIndex(where: { $0.id == id }) else { return }
        library.bikes[index].peripheralID = identifier; scheduleSave()
    }
    func owner(of identifier: UUID) -> SavedBike? {
        library.bikes.first { $0.peripheralID == identifier }
    }
    // Only used after explicit confirmation of the physical panel and its new name.
    // Move the connection alone: drafts and saved artwork belong to their profiles.
    func moveConnection(_ identifier: UUID, from sourceID: String, to targetID: String) throws {
        guard sourceID != targetID,
              let source = library.bikes.firstIndex(where: { $0.id == sourceID }),
              let target = library.bikes.firstIndex(where: { $0.id == targetID }),
              library.bikes[source].peripheralID == identifier,
              library.bikes[target].peripheralID == nil else {
            throw StudioError.invalid("The saved connections changed. Check both bike profiles before moving this connection.")
        }
        var next = library
        next.bikes[source].peripheralID = nil
        next.bikes[target].peripheralID = identifier
        try next.validate()
        library = next; scheduleSave()
    }
    func forget(_ id: String) {
        guard let index = library.bikes.firstIndex(where: { $0.id == id }) else { return }
        library.bikes[index].peripheralID = nil; scheduleSave()
    }
    func saveDesign(name: String) throws {
        try design.validate()
        guard library.designs.count < 200 else { throw StudioError.invalid("Your library is full. Export or remove a saved design first.") }
        library.designs.insert(SavedDesign(name: String(name.prefix(60)), design: design), at: 0); scheduleSave()
    }
    func removeDesigns(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) { library.designs.remove(at: index) }; scheduleSave()
    }
    private func scheduleSave() {
        pendingSave?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
    }
    func saveNow() {
        pendingSave?.cancel(); pendingSave = nil
        guard !blocked else { return }
        do {
            try library.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(library)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            storageError = nil
        } catch { storageError = "Could not save your changes: \(error.localizedDescription)" }
    }
}
