import SwiftUI
import UniformTypeIdentifiers

struct DesignDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var design: Design
    init(design: Design) { self.design = design }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 100_000 else {
            throw StudioError.invalid("Choose a small iLedBike design JSON file.")
        }
        design = try JSONDecoder().decode(Design.self, from: data)
        try design.validate()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try design.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(design))
    }
}
