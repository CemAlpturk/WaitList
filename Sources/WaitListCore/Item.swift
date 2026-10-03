import Foundation

/// The final answer for an item: the user bought it, or decided not to.
public enum Outcome: String, Codable, Sendable, CaseIterable {
    case bought
    case skipped
}

/// What state an item is in right now.
public enum Phase: Hashable, Sendable {
    /// The waiting period has not ended yet.
    case waiting
    /// The waiting period has ended and the user has not decided yet.
    case due
    /// The user has decided.
    case decided(Outcome)
}

/// Something the user wants to buy, plus everything we know about the wait.
public struct Item: Identifiable, Codable, Hashable, Sendable {
    /// Stable identifier. Also used as the notification identifier.
    public let id: UUID
    /// What the user wants to buy.
    public var name: String
    /// The price, or nil if the user did not enter one.
    public var price: Decimal?
    /// Free text or a URL.
    public var note: String?
    /// When the item was added.
    public var createdAt: Date
    /// The instant the waiting period ends.
    public var decideAt: Date
    /// The decision, or nil if the user has not decided yet.
    public var outcome: Outcome?
    /// When the decision was made, or nil if not decided.
    public var decidedAt: Date?
    /// How many times "wait longer" was used.
    public var extensionCount: Int

    /// Creates an item. Usually you call `ItemStore.add` instead, which fills in the dates for you.
    public init(id: UUID = UUID(), name: String, price: Decimal? = nil, note: String? = nil,
                createdAt: Date, decideAt: Date, outcome: Outcome? = nil, decidedAt: Date? = nil,
                extensionCount: Int = 0) {
        self.id = id
        self.name = name
        self.price = price
        self.note = note
        self.createdAt = createdAt
        self.decideAt = decideAt
        self.outcome = outcome
        self.decidedAt = decidedAt
        self.extensionCount = extensionCount
    }

    /// True once the user has marked the item bought or skipped.
    public var isDecided: Bool {
        outcome != nil
    }

    /// The item's state at `now`: decided if it has an outcome, otherwise due once `decideAt` has been reached, otherwise waiting.
    public func phase(at now: Date) -> Phase {
        if let outcome {
            return .decided(outcome)
        }
        return decideAt <= now ? .due : .waiting
    }

    /// True if the waiting period is over and the user has not decided yet.
    public func isDue(at now: Date) -> Bool {
        phase(at: now) == .due
    }

    /// True if the waiting period is still running (and the user has not decided early).
    public func isWaiting(at now: Date) -> Bool {
        phase(at: now) == .waiting
    }

    /// Whole calendar days from the start of `now`'s day to the start of `decideAt`'s day, never negative.
    public func daysLeft(at now: Date, calendar: Calendar = .current) -> Int {
        Self.calendarDays(from: now, to: decideAt, calendar: calendar)
    }

    /// Whole calendar days between createdAt and (decidedAt ?? now), never negative.
    public func daysWaited(at now: Date, calendar: Calendar = .current) -> Int {
        Self.calendarDays(from: createdAt, to: decidedAt ?? now, calendar: calendar)
    }

    /// `note` parsed as an http(s) URL, if it is one (trimmed; scheme required).
    public var noteURL: URL? {
        guard let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// Number of midnights between the two dates' days, clamped to zero.
    private static func calendarDays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(0, days)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, price, note, createdAt, decideAt, outcome, decidedAt, extensionCount
    }

    /// Decodes an item. Optional fields and `extensionCount` may be missing (older files).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        price = try container.decodeIfPresent(Decimal.self, forKey: .price)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        decideAt = try container.decode(Date.self, forKey: .decideAt)
        outcome = try container.decodeIfPresent(Outcome.self, forKey: .outcome)
        decidedAt = try container.decodeIfPresent(Date.self, forKey: .decidedAt)
        extensionCount = try container.decodeIfPresent(Int.self, forKey: .extensionCount) ?? 0
    }
}
