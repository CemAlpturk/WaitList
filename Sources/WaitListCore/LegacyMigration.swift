import Foundation
import os

/// Imports items saved by WaitList 1.x.
///
/// Version 1.x kept a JSON array of `{id, name, deadline}` in UserDefaults under the key "products",
/// with `deadline` as seconds since 2001-01-01 (JSONEncoder's default date format).
public enum LegacyMigration {
    /// UserDefaults key used by 1.x.
    public static let productsKey = "products"

    /// What looking for 1.x data found.
    public enum Result: Equatable, Sendable {
        /// No 1.x data, or only data that can never be imported (damaged). Nothing to retry.
        case none
        /// 1.x items to import.
        case items([Item])
        /// 1.x data exists but could not be read right now (for example the user denied macOS's
        /// "access data from other apps" prompt). Try again on a later launch.
        case unreadable
    }

    private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "LegacyMigration")

    /// Where the sandboxed 1.x app kept its preferences:
    /// ~/Library/Containers/com.cemalpturk.WaitList/Data/Library/Preferences/com.cemalpturk.WaitList.plist
    public static var defaultContainerPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(AppInfo.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(AppInfo.bundleIdentifier).plist", isDirectory: false)
    }

    /// Decodes 1.x JSON into Items: id and name preserved, decideAt = Scheduling.retimed(deadline, to: time), createdAt = now, everything else default.
    public static func decode(legacyData: Data, now: Date, time: DateComponents, calendar: Calendar = .current) throws -> [Item] {
        let products = try JSONDecoder().decode([LegacyProduct].self, from: legacyData)
        return products.map { product in
            Item(id: product.id,
                 name: product.name,
                 createdAt: now,
                 decideAt: Scheduling.retimed(product.deadline, to: time, calendar: calendar))
        }
    }

    /// Looks in `defaults` (key "products") and then in `containerPlistURL` (a preferences plist whose
    /// "products" key holds the JSON as Data). Damaged data counts as nothing to import, so it never blocks
    /// launch; a plist that exists but cannot be read is `.unreadable`, so the import is tried again later.
    public static func find(now: Date, time: DateComponents, defaults: UserDefaults = .standard,
                            containerPlistURL: URL? = defaultContainerPlistURL,
                            calendar: Calendar = .current) -> Result {
        if let data = defaults.data(forKey: productsKey),
           let items = try? decode(legacyData: data, now: now, time: time, calendar: calendar),
           !items.isEmpty {
            return .items(items)
        }
        guard let containerPlistURL else { return .none }
        switch productsData(inPlistAt: containerPlistURL) {
        case .missing:
            return .none
        case .unreadable:
            return .unreadable
        case .found(let data):
            guard let items = try? decode(legacyData: data, now: now, time: time, calendar: calendar),
                  !items.isEmpty else {
                log.notice("1.x data in \(containerPlistURL.path, privacy: .public) could not be decoded; nothing imported")
                return .none
            }
            return .items(items)
        }
    }

    /// The items `find` returns, or [] when there is nothing to import right now (for either reason).
    public static func legacyItems(now: Date, time: DateComponents, defaults: UserDefaults = .standard,
                                   containerPlistURL: URL? = defaultContainerPlistURL,
                                   calendar: Calendar = .current) -> [Item] {
        if case .items(let items) = find(now: now, time: time, defaults: defaults,
                                         containerPlistURL: containerPlistURL, calendar: calendar) {
            return items
        }
        return []
    }

    // MARK: Private

    /// The 1.x model, exactly as it was encoded.
    private struct LegacyProduct: Decodable {
        let id: UUID
        let name: String
        let deadline: Date
    }

    private enum PlistLookup {
        case missing
        case unreadable
        case found(Data)
    }

    /// The "products" Data value from a preferences plist file. A missing file, a damaged plist or a missing
    /// key is `.missing`; a file that exists but cannot be read (permissions, privacy prompt denied) is
    /// `.unreadable`.
    private static func productsData(inPlistAt url: URL) -> PlistLookup {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .missing
        } catch {
            log.error("Could not read 1.x data at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public). Will try again next launch.")
            return .unreadable
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: fileData, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let data = dictionary[productsKey] as? Data else {
            return .missing
        }
        return .found(data)
    }
}
