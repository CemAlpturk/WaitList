import AppKit
import Foundation
import WaitListCore

/// Entry point. We drive the AppKit lifecycle directly instead of a SwiftUI `App`
/// because a menubar popover needs programmatic control (open from a notification,
/// badge the status item) that `MenuBarExtra` does not expose.
///
/// Command line (all optional, for development):
///   --snapshot <dir>                  Render every screen in light and dark mode as PNGs into <dir>, then exit.
///                                     Uses sample data only; never touches real data or notifications.
///   --debug-add-due-in <seconds> <name>
///                                     Developer only: before the app loads its data, append an item that becomes
///                                     due <seconds> from now to the data file. Lets you test notifications end to
///                                     end without waiting days. The app then launches normally.
///   --debug-dump-data                 Print the items in the data file as JSON and exit (no UI, no notifications).
/// Environment:
///   WAITLIST_DATA_FILE=<path>         Use this JSON file instead of
///                                     ~/Library/Application Support/WaitList/items.json.
///                                     Legacy (1.x) import is skipped in this mode.
///
/// Example: WAITLIST_DATA_FILE=build/test.json WaitList --debug-add-due-in 30 "Test" --debug-dump-data
@main
enum Main {
    @MainActor
    static func main() {
        let options: LaunchOptions
        do {
            options = try LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("WaitList: \(error.localizedDescription)\n", stderr)
            exit(64) // EX_USAGE
        }

        if let directory = options.snapshotDirectory {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited) // no Dock icon, never activates
            do {
                try Snapshotter.run(into: directory)
                exit(0)
            } catch {
                fputs("WaitList: snapshot failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        let location = DataLocation.resolve(environment: ProcessInfo.processInfo.environment)

        if let request = options.debugAdd {
            guard DebugCommands.addItem(named: request.name, dueIn: request.seconds, location: location) else {
                exit(1)
            }
        }
        if options.debugDump {
            exit(DebugCommands.dumpItems(location: location))
        }

        let app = NSApplication.shared
        let delegate = AppDelegate(dataLocation: location)
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menubar only, no Dock icon
        app.run()
    }
}

/// Parsed command line flags. Unknown arguments are ignored (Finder and Xcode pass their own).
struct LaunchOptions {
    var snapshotDirectory: URL?
    var debugAdd: (seconds: TimeInterval, name: String)?
    var debugDump = false

    struct UsageError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func parse(_ arguments: [String]) throws -> LaunchOptions {
        var options = LaunchOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--snapshot":
                guard index + 1 < arguments.count else {
                    throw UsageError("--snapshot needs an output directory")
                }
                let path = (arguments[index + 1] as NSString).expandingTildeInPath
                options.snapshotDirectory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
                index += 2
            case "--debug-add-due-in":
                guard index + 2 < arguments.count,
                      let seconds = TimeInterval(arguments[index + 1]), seconds.isFinite else {
                    throw UsageError("usage: --debug-add-due-in <seconds> <name>")
                }
                let name = arguments[index + 2].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { throw UsageError("--debug-add-due-in needs a non-empty name") }
                options.debugAdd = (seconds, name)
                index += 3
            case "--debug-dump-data":
                options.debugDump = true
                index += 1
            default:
                index += 1
            }
        }
        return options
    }
}

/// Where the items file lives for this run.
enum DataLocation {
    /// ~/Library/Application Support/WaitList/items.json
    case standard(URL)
    /// WAITLIST_DATA_FILE: a developer-chosen file. Legacy import is skipped.
    case override(URL)
    /// The Application Support folder could not be created; the app runs in memory only.
    case unavailable(reason: String)

    static let environmentKey = "WAITLIST_DATA_FILE"

    var fileURL: URL? {
        switch self {
        case .standard(let url), .override(let url): return url
        case .unavailable: return nil
        }
    }

    static func resolve(environment: [String: String]) -> DataLocation {
        if let path = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            return .override(URL(fileURLWithPath: expanded, isDirectory: false).standardizedFileURL)
        }
        do {
            return .standard(try FileItemPersistence.defaultFileURL())
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }
}

/// The developer-only `--debug-*` commands. They work on the data file directly, before any store exists.
enum DebugCommands {
    /// Appends an item due `seconds` from now. Returns false (and prints why) on failure.
    static func addItem(named name: String, dueIn seconds: TimeInterval, location: DataLocation) -> Bool {
        guard let url = location.fileURL else {
            fputs("WaitList: no data file available, nothing added.\n", stderr)
            return false
        }
        let persistence = FileItemPersistence(fileURL: url)
        do {
            let now = Date()
            let item = Item(name: name, createdAt: now, decideAt: now.addingTimeInterval(seconds))
            try persistence.save(try persistence.load() + [item])
            let when = item.decideAt.formatted(date: .abbreviated, time: .standard)
            print("Added “\(name)”, due \(when), to \(url.path)")
            return true
        } catch {
            fputs("WaitList: could not add debug item: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    /// Prints the items as pretty JSON. Returns the process exit code.
    static func dumpItems(location: DataLocation) -> Int32 {
        guard let url = location.fileURL else {
            fputs("WaitList: no data file available.\n", stderr)
            return 1
        }
        do {
            let items = try FileItemPersistence(fileURL: url).load()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(items), as: UTF8.self))
            return 0
        } catch {
            fputs("WaitList: could not read \(url.path): \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}
