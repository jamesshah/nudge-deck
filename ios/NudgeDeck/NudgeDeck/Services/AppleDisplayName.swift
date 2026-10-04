import Foundation

/// Apple only returns the user's name on the first Sign in with Apple authorization.
/// Persist whatever we get so later sign-ins (or a wiped backend) can still send it.
enum AppleDisplayName {
    private static let defaultsKey = "appleDisplayNames"

    static func from(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }

        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        let formatted = formatter.string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.isEmpty { return String(formatted.prefix(40)) }

        let parts = [components.givenName, components.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return String(parts.joined(separator: " ").prefix(40))
    }

    static func cached(forAppleUserId userId: String) -> String? {
        let map = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        let name = map[userId]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    static func cache(_ name: String, forAppleUserId userId: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !userId.isEmpty else { return }
        var map = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        map[userId] = String(trimmed.prefix(40))
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }
}
