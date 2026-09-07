import Foundation

/// `LuckyRecord` / `LuckyListItem` / `LuckyModule` — all three are `Record<string, unknown>`
/// in the original. The UI reads fields by trying several spellings (`Key`/`key`/`id`,
/// `Enable`/`enable`, …) because Lucky's modules disagree with each other, so the port keeps
/// them dynamic instead of inventing structs the server would not honour.
typealias LuckyRecord = JSONValue
typealias LuckyListItem = JSONValue
typealias LuckyModule = JSONValue

/// The accessors the list screens use, gathered in one place. Each takes the first
/// **non-empty** spelling rather than the first present one, which is what the call sites
/// do with their `String(item.Key ?? item.key ?? …)` chains.
extension JSONValue {
    /// `item.Key ?? item.key ?? item.id`
    var luckyKey: String? {
        for field in ["Key", "key", "id"] {
            if let text = self[field]?.stringValue, !text.isEmpty { return text }
            // Some builds return numeric ids.
            if let number = self[field], number.isFiniteNumber { return number.asDisplayString }
        }
        return nil
    }

    /// `item.Name ?? item.name ?? item.TaskName`
    var luckyName: String? {
        for field in ["Name", "name", "TaskName"] {
            if let text = self[field]?.stringValue, !text.isEmpty { return text }
        }
        return nil
    }

    /// `item.Enable ?? item.enable` — `null` falls through, as `??` does.
    var luckyEnable: JSONValue? {
        if let value = self["Enable"], !value.isNull { return value }
        if let value = self["enable"], !value.isNull { return value }
        return nil
    }

    /// `item.Status ?? item.status`
    var luckyStatus: String? {
        for field in ["status", "Status"] {
            if let text = self[field]?.stringValue, !text.isEmpty { return text }
        }
        return nil
    }
}

struct LuckyLoginInput: Sendable, Equatable {
    var baseUrl: String = ""
    var account: String = ""
    var password: String = ""
    var twoFACode: String = ""
}

/// `getLuckyDashboard()` — `/api/status`, `/api/info` merged with `/version`, `/api/modules/list`.
struct LuckyDashboard: Sendable {
    var status: JSONValue = .object([])
    var info: JSONValue = .object([])
    var modules: [LuckyModule] = []
}

/// The four service kinds that share the list / detail / logs / actions screens.
enum LuckyServiceKind: String, Sendable, CaseIterable, Identifiable {
    case webservice, ddns, docker, ssl

    var id: String { rawValue }
}

enum LuckyHttpMethod: String, Sendable, CaseIterable, Identifiable, Comparable, Codable {
    case get = "GET", post = "POST", put = "PUT", delete = "DELETE", patch = "PATCH"

    var id: String { rawValue }

    /// Registry order, so the method chips never shuffle between renders.
    static func < (lhs: LuckyHttpMethod, rhs: LuckyHttpMethod) -> Bool {
        guard let left = allCases.firstIndex(of: lhs), let right = allCases.firstIndex(of: rhs)
        else { return false }
        return left < right
    }
}

/// One row of `LuckyEndpoints.json` — the 328-endpoint registry behind the debugger.
struct LuckyEndpointDefinition: Sendable, Hashable, Identifiable, Decodable {
    var id: String
    var path: String
    var methods: [LuckyHttpMethod]
    var module: String
    var source: String
    var notes: String
    var requiresSuffix: Bool
    var pathVariables: [String]

    private enum CodingKeys: String, CodingKey {
        case id, path, methods, module, source, notes, requiresSuffix, pathVariables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        // A method the port does not model is dropped rather than failing the whole
        // registry — a newer Lucky build must not blank out the debugger.
        methods = try container.decode([String].self, forKey: .methods)
            .compactMap(LuckyHttpMethod.init(rawValue:))
        module = try container.decode(String.self, forKey: .module)
        source = try container.decode(String.self, forKey: .source)
        notes = try container.decode(String.self, forKey: .notes)
        requiresSuffix = try container.decode(Bool.self, forKey: .requiresSuffix)
        pathVariables = try container.decode([String].self, forKey: .pathVariables)
    }
}

struct LuckyModuleDefinition: Sendable, Hashable, Identifiable, Decodable {
    var key: String
    var label: String
    var endpointCount: Int
    var methodCount: Int

    var id: String { key }
}

/// `callLuckyEndpoint(call)` — a debugger invocation. `query` is either a record or an
/// array of pairs, because the object-mode builder lets the user repeat a key.
struct LuckyEndpointCall: Sendable {
    var endpoint: LuckyEndpointDefinition
    var method: LuckyHttpMethod
    var pathValues: [String: String] = [:]
    var suffix: String = ""
    var query: JSONValue?
    var body: JSONValue?
    /// The `FormData` branch of `getBody`. It wins over `body` when both are set, because the
    /// original screen never fills in both and a multipart body cannot be expressed as JSON.
    var form: MultipartBody?
    var retryAuth: Bool = true
}
