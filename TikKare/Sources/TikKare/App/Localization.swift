import Foundation

/// Looks up a user-facing string. Keys are the English text; translations live in Resources/<lang>.lproj.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string, e.g. `L("Saved: %@", name)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}
