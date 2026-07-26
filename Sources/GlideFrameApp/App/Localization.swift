import Foundation

#if SWIFT_PACKAGE
private let localizationBundle = Bundle.module
#else
private let localizationBundle = Bundle.main
#endif

func tr(_ key: String) -> String {
    localizationBundle.localizedString(forKey: key, value: key, table: nil)
}
