import Foundation

/// Somewhere items can be saved to and loaded from.
public protocol ItemPersistence {
    /// All saved items, or [] if nothing has been saved yet.
    func load() throws -> [Item]
    /// Replaces everything saved with `items`.
    func save(_ items: [Item]) throws
}

/// Problems reading the items file.
public enum PersistenceError: Error, Equatable {
    /// The file could not be read. It was moved to the given backup URL so nothing is lost.
    case corruptFile(URL)
    /// The file was written by a newer WaitList (it has this format version). The file was left untouched.
    case unsupportedVersion(Int)
    /// The file could not be read, and moving it aside also failed. It was left untouched at the given URL.
    case corruptFileNotMoved(URL)
}

extension PersistenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .corruptFile(let backupURL):
            return "The WaitList data file could not be read. It was moved to \(backupURL.path)."
        case .unsupportedVersion(let version):
            return "The WaitList data file was saved by a newer version of WaitList (format \(version)). Please update WaitList."
        case .corruptFileNotMoved(let fileURL):
            return "The WaitList data file at \(fileURL.path) could not be read and was left untouched."
        }
    }
}

/// Saves items as a JSON file: `{"version": 1, "items": [...]}`.
public struct FileItemPersistence: ItemPersistence {
    /// The file format version this code reads and writes.
    public static let currentVersion = 1

    /// Where the items are stored.
    public let fileURL: URL

    /// Uses the file at `fileURL`. Nothing is read or written until `load` or `save` is called.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// ~/Library/Application Support/WaitList/items.json (directory created if needed).
    public static func defaultFileURL() throws -> URL {
        let fileManager = FileManager.default
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
        let fileURL = fileURL(inApplicationSupport: support)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return fileURL
    }

    /// `<support>/WaitList/items.json`. Only builds the path; nothing is created.
    static func fileURL(inApplicationSupport support: URL) -> URL {
        support.appendingPathComponent("WaitList", isDirectory: true)
            .appendingPathComponent("items.json", isDirectory: false)
    }

    /// Reads the file. A missing file means no items yet.
    /// A damaged file is moved aside and `PersistenceError.corruptFile(backupURL)` is thrown.
    /// A file from a newer version throws `PersistenceError.unsupportedVersion` and is not touched.
    public func load() throws -> [Item] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        // A read failure (e.g. permissions) is passed on as is; the file is not moved.
        let data = try Data(contentsOf: fileURL)

        let decoder = Self.makeDecoder()
        let probe: VersionProbe
        do {
            probe = try decoder.decode(VersionProbe.self, from: data)
        } catch {
            throw moveCorruptFileAside()
        }
        guard probe.version == Self.currentVersion else {
            throw PersistenceError.unsupportedVersion(probe.version)
        }
        do {
            return try decoder.decode(FileContents.self, from: data).items
        } catch {
            throw moveCorruptFileAside()
        }
    }

    /// Writes all items, replacing the file atomically (a crash mid-write never leaves a half-written file).
    public func save(_ items: [Item]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(FileContents(version: Self.currentVersion, items: items))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// A decoder for the file format. Dates are ISO 8601 as written by `save` ("2026-10-17T07:00:00Z"); fractional
    /// seconds ("2026-10-17T07:00:00.250Z") and offsets ("+02:00") are accepted too, so a hand-edited file still loads.
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let parser = LenientISO8601Parser()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parser.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "Expected an ISO 8601 date, found \(text)")
            }
            return date
        }
        return decoder
    }

    // MARK: Private

    private struct VersionProbe: Decodable {
        let version: Int
    }

    private struct FileContents: Codable {
        let version: Int
        let items: [Item]
    }

    /// Renames the unreadable file to `items.corrupt-<yyyyMMdd-HHmmss>.json` in the same folder
    /// and returns the error to throw.
    private func moveCorruptFileAside() -> PersistenceError {
        let fileManager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        // Add -1, -2, ... if a backup with the same name already exists (two failures in one second).
        for attempt in 0..<100 {
            var name = "\(baseName).corrupt-\(stamp)"
            if attempt > 0 { name += "-\(attempt)" }
            if !fileExtension.isEmpty { name += ".\(fileExtension)" }
            let backupURL = directory.appendingPathComponent(name, isDirectory: false)
            if fileManager.fileExists(atPath: backupURL.path) { continue }
            do {
                try fileManager.moveItem(at: fileURL, to: backupURL)
                return .corruptFile(backupURL)
            } catch {
                return .corruptFileNotMoved(fileURL)
            }
        }
        return .corruptFileNotMoved(fileURL)
    }
}

/// ISO 8601 with whole seconds, then with fractional seconds (`ISO8601DateFormatter` accepts exactly one
/// of the two per configuration).
private final class LenientISO8601Parser: @unchecked Sendable {
    // ISO8601DateFormatter is thread-safe (Formatter subclasses are, since macOS 10.9); these are never mutated.
    private let wholeSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private let fractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func date(from text: String) -> Date? {
        wholeSeconds.date(from: text) ?? fractionalSeconds.date(from: text)
    }
}

/// Keeps items in memory only. For tests and SwiftUI previews.
public final class InMemoryItemPersistence: ItemPersistence {
    /// What has been "saved".
    public var items: [Item]
    /// Test hook: if set, the next save throws it and clears it.
    public var failNextSave: Error?

    /// Starts with `items` already "saved".
    public init(items: [Item] = []) {
        self.items = items
    }

    /// Returns `items`.
    public func load() throws -> [Item] {
        items
    }

    /// Stores `items`, or throws `failNextSave` once if it is set.
    public func save(_ items: [Item]) throws {
        if let error = failNextSave {
            failNextSave = nil
            throw error
        }
        self.items = items
    }
}
