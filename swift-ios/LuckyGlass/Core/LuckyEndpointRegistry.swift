import Foundation

/// `src/api/lucky-endpoints.generated.ts`, shipped as a bundled JSON resource instead of a
/// 4,450-line source file: 328 endpoints across 45 modules, with the Chinese module labels
/// and the pre-computed counts the browser screen displays.
enum LuckyEndpointRegistry {
    private struct Payload: Decodable {
        var endpoints: [LuckyEndpointDefinition]
        var modules: [LuckyModuleDefinition]
    }

    private static let payload: Payload = {
        guard let url = Bundle.main.url(forResource: "LuckyEndpoints", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return Payload(endpoints: [], modules: []) }
        return decoded
    }()

    /// `LUCKY_ENDPOINTS`
    static var endpoints: [LuckyEndpointDefinition] { payload.endpoints }

    /// `LUCKY_MODULES` — already ordered by the generator, which the module list relies on.
    static var modules: [LuckyModuleDefinition] { payload.modules }

    /// `getLuckyEndpoints(module)`
    static func endpoints(module: String?) -> [LuckyEndpointDefinition] {
        guard let module, !module.isEmpty else { return endpoints }
        return endpoints.filter { $0.module == module }
    }

    /// `getLuckyEndpoint(id)`
    static func endpoint(id: String) -> LuckyEndpointDefinition? {
        endpoints.first { $0.id == id }
    }

    /// The Chinese label for a module key, falling back to the key itself.
    static func label(for module: String) -> String {
        modules.first { $0.key == module }?.label ?? module
    }
}
