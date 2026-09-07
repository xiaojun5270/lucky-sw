import UIKit

/// `expo-clipboard`, as the two calls the original actually makes.
///
/// `Clipboard.setStringAsync` / `getStringAsync` are `async` because the JS bridge is; `UIPasteboard`
/// is synchronous, so the `await`s at the call sites disappear. Both are `@MainActor` because
/// `UIPasteboard` is not `Sendable` and reading it off the main actor is a data race.
@MainActor
enum LuckyClipboard {
    /// `Clipboard.setStringAsync(text)`. The original follows every copy with an `Alert.alert`; the
    /// callers here follow it with a `LuckyToast` instead.
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    /// `Clipboard.getStringAsync()`. An empty pasteboard answers `''` in the original and `""` here
    /// — the Docker screen's 粘贴 button tests the result for emptiness either way.
    static func paste() -> String {
        UIPasteboard.general.string ?? ""
    }
}
