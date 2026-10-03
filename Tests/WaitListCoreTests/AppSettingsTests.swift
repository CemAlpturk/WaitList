import XCTest
@testable import WaitListCore

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaults() throws {
        let settings = AppSettings(defaults: try makeTestDefaults())

        XCTAssertEqual(settings.defaultWaitDays, 14)
        XCTAssertEqual(settings.notificationHour, 9)
        XCTAssertEqual(settings.notificationMinute, 0)
        XCTAssertEqual(settings.currencyCode, AppSettings.defaultCurrencyCode)
        XCTAssertEqual(settings.currencyCode.count, 3)
        XCTAssertFalse(settings.hasMigratedLegacyItems)
    }

    func testNotificationTime() throws {
        let settings = AppSettings(defaults: try makeTestDefaults())
        XCTAssertEqual(settings.notificationTime, DateComponents(hour: 9, minute: 0))

        settings.notificationHour = 20
        settings.notificationMinute = 15
        XCTAssertEqual(settings.notificationTime, DateComponents(hour: 20, minute: 15))
    }

    func testClampingOnSet() throws {
        let defaults = try makeTestDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.defaultWaitDays = 0
        XCTAssertEqual(settings.defaultWaitDays, 1)
        settings.defaultWaitDays = 1_000
        XCTAssertEqual(settings.defaultWaitDays, 365)

        settings.notificationHour = 24
        XCTAssertEqual(settings.notificationHour, 23)
        settings.notificationHour = -1
        XCTAssertEqual(settings.notificationHour, 0)

        settings.notificationMinute = 60
        XCTAssertEqual(settings.notificationMinute, 59)
        settings.notificationMinute = -10
        XCTAssertEqual(settings.notificationMinute, 0)

        // The stored values are the clamped ones.
        XCTAssertEqual(defaults.integer(forKey: "settings.defaultWaitDays"), 365)
        XCTAssertEqual(defaults.integer(forKey: "settings.notificationHour"), 0)
        XCTAssertEqual(defaults.integer(forKey: "settings.notificationMinute"), 0)
    }

    func testCurrencyCodeIsUppercasedOrFallsBack() throws {
        let settings = AppSettings(defaults: try makeTestDefaults())

        settings.currencyCode = "sek"
        XCTAssertEqual(settings.currencyCode, "SEK")
        settings.currencyCode = " eur "
        XCTAssertEqual(settings.currencyCode, "EUR")

        for invalid in ["", "EURO", "US", "12A", "€€€"] {
            settings.currencyCode = invalid
            XCTAssertEqual(settings.currencyCode, AppSettings.defaultCurrencyCode, "input: \(invalid)")
        }
    }

    func testValuesPersistToTheSuite() throws {
        let defaults = try makeTestDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.defaultWaitDays = 30
        settings.notificationHour = 18
        settings.notificationMinute = 45
        settings.currencyCode = "SEK"
        settings.hasMigratedLegacyItems = true

        XCTAssertEqual(defaults.integer(forKey: "settings.defaultWaitDays"), 30)
        XCTAssertEqual(defaults.string(forKey: "settings.currencyCode"), "SEK")
        XCTAssertTrue(defaults.bool(forKey: "settings.hasMigratedLegacyItems"))

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.defaultWaitDays, 30)
        XCTAssertEqual(reloaded.notificationHour, 18)
        XCTAssertEqual(reloaded.notificationMinute, 45)
        XCTAssertEqual(reloaded.currencyCode, "SEK")
        XCTAssertTrue(reloaded.hasMigratedLegacyItems)
    }

    func testInvalidStoredValuesAreCorrectedOnLoad() throws {
        let defaults = try makeTestDefaults()
        defaults.set(999, forKey: "settings.defaultWaitDays")
        defaults.set(31, forKey: "settings.notificationHour")
        defaults.set("not a number", forKey: "settings.notificationMinute")
        defaults.set("xx", forKey: "settings.currencyCode")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.defaultWaitDays, 365)
        XCTAssertEqual(settings.notificationHour, 23)
        XCTAssertEqual(settings.notificationMinute, 0)
        XCTAssertEqual(settings.currencyCode, AppSettings.defaultCurrencyCode)
    }
}
