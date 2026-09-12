import Foundation

enum StoreLoadResult: Sendable {
    case loaded(StoredState)
    case missing
    case unreadable(String)
}

actor JSONStore {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.fileURL = support
                .appendingPathComponent("KeyTally", isDirectory: true)
                .appendingPathComponent("counts.json", isDirectory: false)
        }
    }

    func load() -> StoreLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try JSONDecoder().decode(StoredState.self, from: data)
            guard state.version == 1 else {
                return .unreadable("Unsupported data version \(state.version). The original file was not changed.")
            }
            return .loaded(state)
        } catch {
            return .unreadable("Could not read counts.json: \(error.localizedDescription). The original file was not changed.")
        }
    }

    func save(_ state: StoredState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
