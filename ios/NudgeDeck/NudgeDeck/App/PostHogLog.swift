import PostHog

enum PostHogLog {
    private static let logger = PostHogSDK.shared.logger

    static func info(_ message: String) {
        logger?.info(message)
    }

    static func error(_ message: String) {
        logger?.error(message)
    }
}
