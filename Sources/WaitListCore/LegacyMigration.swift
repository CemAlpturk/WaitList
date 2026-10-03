import Foundation

/// Imports items saved by WaitList 1.x.
///
/// Version 1.x kept a JSON array of `{id, name, deadline}` in UserDefaults under the key "products",
/// with `deadline` as seconds since 2001-01-01 (JSONEncoder's default date format).
public enum LegacyMigration {
    /// UserDefaults key used by 1.x.
    public static let productsKey = "products"

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

    /// Looks in `defaults` (key "products") and then in `containerPlistURL` (PropertyListSerialization, key "products" holding Data). Returns [] if nothing found or anything fails to parse (migration must never block launch).
    public static func legacyItems(now: Date, time: DateComponents, defaults: UserDefaults = .standard,
                                   containerPlistURL: URL? = defaultContainerPlistURL,
                                   calendar: Calendar = .current) -> [Item] {
        if let data = defaults.data(forKey: productsKey),
           let items = try? decode(legacyData: data, now: now, time: time, calendar: calendar),
           !items.isEmpty {
            return items
        }
        if let containerPlistURL,
           let data = productsData(inPlistAt: containerPlistURL),
           let items = try? decode(legacyData: data, now: now, time: time, calendar: calendar) {
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

    /// The "products" Data value from a preferences plist file, or nil if the file is missing or unreadable.
    private static func productsData(inPlistAt url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path),
              let fileData = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: fileData, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }
        return dictionary[productsKey] as? Data
    }
}
