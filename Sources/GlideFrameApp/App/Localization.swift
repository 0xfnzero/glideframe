import Foundation

#if SWIFT_PACKAGE
private let localizationBundle = Bundle.module
#else
private let localizationBundle = Bundle.main
#endif

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayNameKey: String {
        switch self {
        case .english:
            "language_english"
        case .simplifiedChinese:
            "language_simplified_chinese"
        }
    }

    static func normalized(_ rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .english
    }
}

func tr(_ key: String) -> String {
    tr(key, language: UserDefaults.standard.string(forKey: "app.language"))
}

func tr(_ key: String, language rawLanguage: String?) -> String {
    let language = AppLanguage.normalized(rawLanguage ?? AppLanguage.english.rawValue)
    if let bundlePath = localizationBundle.path(forResource: language.rawValue, ofType: "lproj"),
       let bundle = Bundle(path: bundlePath) {
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    if language != .english,
       let fallbackPath = localizationBundle.path(forResource: AppLanguage.english.rawValue, ofType: "lproj"),
       let fallbackBundle = Bundle(path: fallbackPath) {
        return fallbackBundle.localizedString(forKey: key, value: key, table: nil)
    }
    return localizationBundle.localizedString(forKey: key, value: key, table: nil)
}
