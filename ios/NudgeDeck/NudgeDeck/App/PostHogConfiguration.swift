import Foundation
import PostHog

enum PostHogConfiguration {
    static func setup() {
        guard let projectToken = value(for: "POSTHOG_PROJECT_TOKEN") else {
            reportMissingConfiguration("POSTHOG_PROJECT_TOKEN")
            return
        }

        guard let host = value(for: "POSTHOG_HOST") else {
            reportMissingConfiguration("POSTHOG_HOST")
            return
        }

        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.errorTrackingConfig.autoCapture = true
        PostHogSDK.shared.setup(config)
        PostHogLog.info("application_launch_completed")
    }

    private static func value(for key: String) -> String? {
        let value = ProcessInfo.processInfo.environment[key]
            ?? Bundle.main.object(forInfoDictionaryKey: key) as? String

        guard let value, !value.isEmpty, !value.hasPrefix("$(") else {
            return nil
        }
        return value
    }

    private static func reportMissingConfiguration(_ key: String) {
        #if DEBUG
        assertionFailure("\(key) variable required by PostHog is missing or un-configured, this causes events to be silently missed. This error stops appearing once \(key) is configured")
        #endif
    }
}
