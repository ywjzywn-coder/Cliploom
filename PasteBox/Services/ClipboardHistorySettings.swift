import Foundation

enum ClipboardHistorySettings {
    static let maximumCountKey = "history.maximumCount"
    static let maximumAgeDaysKey = "history.maximumAgeDays"

    static let defaultMaximumCount = 500
    static let defaultMaximumAgeDays = 30

    static let countRange = 10...5000
    static let ageDaysRange = 1...3650

    static func maximumCount(defaults: UserDefaults = .standard) -> Int {
        clamped(
            defaults.object(forKey: maximumCountKey) as? Int ?? defaultMaximumCount,
            to: countRange
        )
    }

    static func maximumAgeDays(defaults: UserDefaults = .standard) -> Int {
        clamped(
            defaults.object(forKey: maximumAgeDaysKey) as? Int ?? defaultMaximumAgeDays,
            to: ageDaysRange
        )
    }

    static func saveMaximumCount(_ value: Int, defaults: UserDefaults = .standard) {
        defaults.set(clamped(value, to: countRange), forKey: maximumCountKey)
    }

    static func saveMaximumAgeDays(_ value: Int, defaults: UserDefaults = .standard) {
        defaults.set(clamped(value, to: ageDaysRange), forKey: maximumAgeDaysKey)
    }

    private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
