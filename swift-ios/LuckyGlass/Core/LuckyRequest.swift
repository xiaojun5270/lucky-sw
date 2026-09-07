import Foundation

/// Request body variants, mirroring what the TypeScript client passes to `fetch`.
enum LuckyBody: Sendable {
    /// A JSON value that gets `JSON.stringify`d and sent with `Content-Type: application/json`.
    case json(JSONValue)
    /// A pre-built string body (the original sometimes passes the literal `'{}'`).
    case text(String)
    /// `FormData` — the boundary content type is applied by the multipart builder.
    case multipart(MultipartBody)
    /// `Blob` — sent as-is with no content type.
    case binary(Data)

    var data: Data {
        switch self {
        case .json(let value): return JSONSerializer.data(value)
        case .text(let text): return Data(text.utf8)
        case .multipart(let form): return form.data
        case .binary(let data): return data
        }
    }

    /// `application/json` is only added for plain bodies, exactly as in the original:
    /// FormData and Blob bodies must keep the content type the runtime chooses.
    var contentType: String? {
        switch self {
        case .json, .text: return "application/json"
        case .multipart(let form): return form.contentType
        case .binary: return nil
        }
    }
}

/// `multipart/form-data` builder. iOS has no `FormData`, so the body is assembled by hand;
/// the boundary header must be set explicitly here because there is no runtime to infer it.
struct MultipartBody: Sendable {
    struct Part: Sendable {
        var name: String
        var value: String?
        var filename: String?
        var mimeType: String?
        var content: Data?
    }

    let boundary: String
    private(set) var parts: [Part] = []

    init(boundary: String = "LuckyGlass-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func append(_ name: String, value: String) {
        parts.append(Part(name: name, value: value))
    }

    mutating func append(_ name: String, filename: String, mimeType: String?, content: Data) {
        parts.append(Part(name: name, filename: filename, mimeType: mimeType, content: content))
    }

    var data: Data {
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\n".utf8))
            if let filename = part.filename {
                body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"; filename=\"\(filename)\"\r\n".utf8))
                body.append(Data("Content-Type: \(part.mimeType ?? "application/octet-stream")\r\n\r\n".utf8))
                body.append(part.content ?? Data())
            } else {
                body.append(Data("Content-Disposition: form-data; name=\"\(part.name)\"\r\n\r\n".utf8))
                body.append(Data((part.value ?? "").utf8))
            }
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}

/// One HTTP call. Defaults match `luckyFetch`'s option defaults.
struct LuckyRequest: Sendable {
    enum ResponseKind: Sendable { case auto, json, text, blob }

    var path: String
    var method: String = "GET"
    var body: LuckyBody?
    var headers: [String: String] = [:]
    var baseUrl: String?
    var token: String?
    var timeout: TimeInterval = LuckyClientConstants.defaultTimeout
    var retryAuth: Bool = true
    var responseKind: ResponseKind = .auto

    init(_ path: String, method: String = "GET", body: LuckyBody? = nil) {
        self.path = path
        self.method = method
        self.body = body
    }
}

enum LuckyClientConstants {
    /// `DEFAULT_REQUEST_TIMEOUT_MS = 12000`
    static let defaultTimeout: TimeInterval = 12
    /// Blob download / multipart upload paths use a ten-minute budget.
    static let transferTimeout: TimeInterval = 600
}

extension JSONValue {
    /// `numericRet(payload.ret)` — `nil` when the field is missing or unparseable.
    /// The login paths distinguish "absent" from 0, so the optional form matters.
    var retValue: Int? {
        guard let value = self["ret"] else { return nil }
        switch value {
        case .number(let number): return number.isFinite ? Int(number) : nil
        case .string(let text):
            let trimmed = text.jsTrimmed
            guard !trimmed.isEmpty, let parsed = Double(trimmed), parsed.isFinite else { return nil }
            return Int(parsed)
        default: return nil
        }
    }

    /// `numericRet(payload.ret) ?? 0`
    var ret: Int { retValue ?? 0 }

    /// `payload.msg` when it is a string.
    var msg: String? { self["msg"]?.stringValue }

    /// `payload.data`
    var payloadData: JSONValue? { self["data"] }
}
