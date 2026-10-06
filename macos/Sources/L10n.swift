import Foundation

/// UI language: Russian when it is the user's first preferred language, English otherwise.
/// `WOLFCLIP_LANG=ru` or `WOLFCLIP_LANG=en` overrides the detection (handy for screenshots).
enum L10n {
    static let isRussian: Bool = {
        switch ProcessInfo.processInfo.environment["WOLFCLIP_LANG"]?.lowercased() {
        case "ru": return true
        case "en": return false
        default: return Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") ?? false
        }
    }()
}

/// Picks the Russian or English variant of a user-visible string.
func tr(_ ru: String, _ en: String) -> String {
    L10n.isRussian ? ru : en
}
