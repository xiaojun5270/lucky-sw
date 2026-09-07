import Foundation

/// The query-string builders the service modules use.
///
/// There are four of them in the original and they are **not** interchangeable:
/// `services/lucky.ts` drops only `undefined`, `services/ddns.ts` and `services/ssl.ts`
/// also drop `null` and `''`, `services/tunnels.ts` goes through `URLSearchParams`,
/// which form-encodes (space → `+`) and keeps empty values, and `services/docker.ts`
/// drops the same three values as `compact` but `JSON.stringify`s anything that is not a
/// string. A rule whose remark is empty or whose key contains a space is enough to tell
/// the first three apart, and a `false` flag separates the last two, so each is ported as-is.
enum LuckyQuery {
    /// One query parameter. `nil` stands for `undefined`; `.null` for JSON `null`.
    typealias Parameter = (name: String, value: JSONValue?)

    /// `query()` in `services/lucky.ts` — keeps `null` and `''`, drops `undefined` only.
    static func loose(_ parameters: [Parameter]) -> String {
        let pairs = parameters.compactMap { parameter -> String? in
            guard let value = parameter.value else { return nil }
            return "\(JSCompat.encodeURIComponent(parameter.name))=\(JSCompat.encodeURIComponent(value.asDisplayString))"
        }
        return pairs.isEmpty ? "" : "?\(pairs.joined(separator: "&"))"
    }

    /// `query()` in `services/ddns.ts` and `services/ssl.ts` — also drops `null` and `''`.
    static func compact(_ parameters: [Parameter]) -> String {
        let pairs = parameters.compactMap { parameter -> String? in
            guard let value = parameter.value, !value.isNull else { return nil }
            let text = value.asDisplayString
            guard !text.isEmpty else { return nil }
            return "\(JSCompat.encodeURIComponent(parameter.name))=\(JSCompat.encodeURIComponent(text))"
        }
        return pairs.isEmpty ? "" : "?\(pairs.joined(separator: "&"))"
    }

    /// `query()` in `services/tunnels.ts` — `URLSearchParams`, **without** the leading `?`,
    /// because every call site writes the `?` itself.
    static func form(_ parameters: [Parameter]) -> String {
        JSCompat.formURLEncoded(parameters.map { ($0.name, $0.value?.asDisplayString ?? "undefined") })
    }

    /// `encodeQuery()` in `services/docker.ts` — drops `undefined`, `null` and `''` like
    /// `compact`, but everything that is not already a string goes through `JSON.stringify`
    /// instead of `String()`. For numbers and booleans the two agree; for a record or an
    /// array they do not, and `false` / `0` are kept because only the empty *string* is
    /// dropped.
    static func docker(_ parameters: [Parameter]) -> String {
        let pairs = parameters.compactMap { parameter -> String? in
            guard let value = parameter.value, !value.isNull else { return nil }
            let text: String
            if case .string(let raw) = value {
                guard !raw.isEmpty else { return nil }
                text = raw
            } else {
                text = JSONSerializer.stringify(value)
            }
            return "\(JSCompat.encodeURIComponent(parameter.name))=\(JSCompat.encodeURIComponent(text))"
        }
        return pairs.isEmpty ? "" : "?\(pairs.joined(separator: "&"))"
    }

    /// `encodeURIComponent(key)`
    static func escape(_ value: String) -> String { JSCompat.encodeURIComponent(value) }
}

extension LuckyBody {
    /// `body(value)` — `JSON.stringify(value)` with the JSON content type.
    static func value(_ value: JSONValue) -> LuckyBody { .json(value) }

    /// The literal `'{}'` body the logout call sends.
    static var emptyObject: LuckyBody { .text("{}") }
}
