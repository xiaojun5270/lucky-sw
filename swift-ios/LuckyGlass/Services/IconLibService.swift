import Foundation

/// Port of `src/services/iconlib.ts` — the icon library behind the rule icon picker.
enum IconLibService {
    /// `getIconLibraryIcons()` — the envelope, its `data` and its `result` are each checked for
    /// an `icons` array, and the first one found wins even if it is empty.
    static func icons() async throws -> [JSONValue] {
        let payload = try await LuckyClient.shared.fetch("/api/iconlib/icons")
        for source in [payload, payload["data"] ?? .null, payload["result"] ?? .null] {
            guard source.isRecord, case .array(let items)? = source["icons"] else { continue }
            return items.filter(\.isRecord)
        }
        return []
    }
}
