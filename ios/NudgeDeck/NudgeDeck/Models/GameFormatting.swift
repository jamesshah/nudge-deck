import Foundation

/// Quiet hours in minutes after local midnight. May wrap past midnight (e.g. 22:00 to 07:00).
struct QuietHours: Equatable {
    let startMinutes: Int
    let endMinutes: Int

    static let minutesPerDay = 24 * 60

    func contains(minuteOfDay m: Int) -> Bool {
        if startMinutes == endMinutes { return false }
        if startMinutes < endMinutes { return m >= startMinutes && m < endMinutes }
        return m >= startMinutes || m < endMinutes
    }

    /// Mirrors the backend's rule: uses the player's stored UTC offset.
    func contains(date: Date, utcOffsetMinutes: Double) -> Bool {
        contains(minuteOfDay: GameFormatting.minuteOfDay(date: date, utcOffsetMinutes: utcOffsetMinutes))
    }
}

enum GameFormatting {
    /// Matches backend `MAX_PROOF_BYTES` in `lib/rules.ts`.
    static let maxProofBytes = 3 * 1024 * 1024

    static func proofFileTooLargeMessage(for type: ProofType) -> String {
        switch type {
        case .photo: return "Photos must be under 3 MB. Try a smaller one."
        case .audio: return "Voice notes must be under 3 MB. Try a shorter recording."
        case .text: return "Keep photo and voice note proofs under 3 MB."
        }
    }

    static func isProofFileWithinLimit(_ data: Data) -> Bool {
        data.count <= maxProofBytes
    }

    static func minuteOfDay(date: Date, utcOffsetMinutes: Double) -> Int {
        let totalMinutes = Int(floor(date.timeIntervalSince1970 / 60)) + Int(utcOffsetMinutes)
        let day = QuietHours.minutesPerDay
        return ((totalMinutes % day) + day) % day
    }

    static func timeZone(identifier: String, utcOffsetMinutes: Double) -> TimeZone {
        TimeZone(identifier: identifier)
            ?? TimeZone(secondsFromGMT: Int(utcOffsetMinutes) * 60)
            ?? .current
    }

    /// "9:41 PM" in the given player's time zone.
    static func clockTime(_ date: Date, timeZone: TimeZone, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "10:00 PM" for 1320 minutes after midnight.
    static func timeOfDay(minutes: Int, locale: Locale = .current) -> String {
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
        return clockTime(date, timeZone: calendar.timeZone, locale: locale)
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current, reference: Date = Date()) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: reference) ?? reference
    }

    /// Fraction of the season elapsed, clamped to 0...1.
    static func seasonProgress(startedAt: Double?, endsAt: Double?, now: Date) -> Double {
        guard let start = startedAt, let end = endsAt, end > start else { return 0 }
        let nowMs = now.timeIntervalSince1970 * 1000
        return min(1, max(0, (nowMs - start) / (end - start)))
    }

    static func daysLeft(endsAt: Double?, now: Date) -> Int {
        guard let end = endsAt else { return 0 }
        let remaining = end / 1000 - now.timeIntervalSince1970
        return max(0, Int(ceil(remaining / 86_400)))
    }

    static func timeframeLabel(days: Int) -> String {
        switch days {
        case 7: return "1 week"
        case 30: return "1 month"
        case 90: return "3 months"
        case 180: return "6 months"
        default: return "\(days) days"
        }
    }

    static func stateLabel(_ state: PlayState) -> String {
        switch state {
        case .pending: return "Your Nudge is waiting… 👀"
        case .proofSubmitted: return "Proof sent"
        case .completed: return "Nudge complete 🫡"
        case .refused: return "Passed"
        case .countered: return "Blocked"
        }
    }

    static func stateSymbol(_ state: PlayState) -> String {
        switch state {
        case .pending: return "hourglass"
        case .proofSubmitted: return "paperplane.fill"
        case .completed: return "checkmark.seal.fill"
        case .refused: return "hand.raised.fill"
        case .countered: return "shield.lefthalf.filled"
        }
    }

    /// Convex sends a thrown `ConvexError("message")` as JSON-encoded data, e.g. `"\"message\""`.
    static func convexErrorMessage(fromData data: String) -> String {
        if let json = data.data(using: .utf8),
           let message = try? JSONDecoder().decode(String.self, from: json) {
            return message
        }
        return data
    }

    static func normalizedInviteCode(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
