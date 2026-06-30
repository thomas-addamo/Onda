import Foundation

/// Persistenza della configurazione su file JSON in Application Support.
/// Operazioni di I/O sincrone: usare SOLO fuori dai path hot (avvio, salvataggio
/// esplicito, cambio impostazioni), mai nel render/capture loop.
public struct ConfigurationStore {
    public enum StoreError: Error {
        case directoryUnavailable
    }

    private let fileURL: URL

    /// - Parameter fileName: nome del file di configurazione.
    public init(fileName: String = "configuration.json") throws {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.directoryUnavailable
        }
        let dir = support.appendingPathComponent("Onda", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(fileName)
    }

    /// Carica la configurazione; se il file non esiste restituisce `nil`.
    public func load() throws -> AppConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    /// Salva la configurazione (scrittura atomica).
    public func save(_ configuration: AppConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Carica la configurazione esistente oppure crea e salva la demo.
    public func loadOrCreateDemo() throws -> AppConfiguration {
        if let existing = try load() { return existing }
        let demo = AppConfiguration.demo
        try save(demo)
        return demo
    }

    public var path: String { fileURL.path }
}
