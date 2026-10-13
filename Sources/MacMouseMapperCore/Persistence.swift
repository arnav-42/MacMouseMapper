import Foundation

public enum ConfigurationStoreError: Error, Equatable {
    case unableToCreateDirectory
}

/// Codable-backed configuration storage. A malformed file, unsupported version,
/// or invalid mapping is treated as a safe default rather than crashing startup.
public final class ConfigurationStore {
    public let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public convenience init(fileManager: FileManager = .default) {
        self.init(fileURL: Self.defaultURL(fileManager: fileManager), fileManager: fileManager)
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("MacMouseMapper", isDirectory: true)
            .appendingPathComponent("configuration.json", isDirectory: false)
    }

    public func load() -> AppConfiguration {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return .default
        }
        do {
            let persisted = try decoder.decode(PersistedConfiguration.self, from: data)
            guard persisted.version == PersistedConfiguration.currentVersion else {
                return .default
            }
            return persisted.configuration.sanitized()
        } catch {
            return .default
        }
    }

    public func save(_ configuration: AppConfiguration) throws {
        let parent = fileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw ConfigurationStoreError.unableToCreateDirectory
        }
        let persisted = PersistedConfiguration(configuration: configuration.sanitized())
        let data = try encoder.encode(persisted)
        try data.write(to: fileURL, options: .atomic)
    }
}
