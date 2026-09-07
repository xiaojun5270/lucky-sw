import Foundation
import UniformTypeIdentifiers

/// A file the user picked, held in memory.
///
/// The original passes Expo's `DocumentPickerAsset` straight into a `FormData`, which streams the
/// file from disk. `URLSession` can stream a file too, but only as the *whole* body, and every
/// docker upload is multipart, so the bytes are read once at pick time instead.
struct DockerAsset: Sendable, Hashable {
    var name: String
    var mimeType: String
    var content: Data

    var size: Int { content.count }
}

/// `saveDockerBinary` / `availableDockerFile` / `safeDownloadName`, plus the multipart builder.
///
/// Android's `Directory.pickDirectoryAsync()` branch has no iOS counterpart and the web branch is
/// irrelevant, so every download lands in the app's Documents directory — the one
/// `UIFileSharingEnabled` exposes in the Files app.
enum DockerFile {
    /// `saveDockerBinary(payload, fallbackName)` — writes the blob and answers the receipt the
    /// detail viewer shows. A payload whose `data` is not binary is returned untouched, which is
    /// how a JSON error envelope from a `.blob` request still reaches the viewer as a record.
    static func save(_ payload: JSONValue, fallback: String) throws -> JSONValue {
        guard case .binary(let blob)? = payload["data"] else { return payload }
        let filename = safeDownloadName(payload["filename"], fallback)
        let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
        let target = available(directory, filename)
        do {
            try blob.write(to: target, options: .withoutOverwriting)
        } catch {
            // The original deletes the file it created before rethrowing; a truncated archive that
            // looks like a finished download is worse than no file at all.
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return .object([
            ("filename", .string(filename)),
            ("byteLength", .number(Double(blob.count))),
            ("saved", .bool(true)),
            ("path", .string(target.path(percentEncoded: false))),
        ])
    }

    /// `safeDownloadName(value, fallback)` — the header's filename, percent-decoded when it can be,
    /// with the nine Windows-reserved characters and every C0 control replaced by `_`.
    ///
    /// The set is Windows-hostile rather than POSIX-hostile on purpose: these names come from a
    /// `Content-Disposition` written by a server that may itself run on Windows.
    static func safeDownloadName(_ value: JSONValue?, _ fallback: String) -> String {
        let trimmed = (value?.stringValue ?? "").jsTrimmed
        let raw = trimmed.isEmpty ? fallback : trimmed
        // `decodeURIComponent` throws on a malformed escape; the original keeps the raw name then.
        let decoded = raw.removingPercentEncoding ?? raw
        let forbidden: Set<Character> = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
        let cleaned = String(decoded.map { character -> Character in
            if forbidden.contains(character) { return "_" }
            if let scalar = character.unicodeScalars.first,
               character.unicodeScalars.count == 1, scalar.value <= 0x1f {
                return "_"
            }
            return character
        })
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// `availableDockerFile` — the plain name, then ` (1)` … ` (999)`, then a millisecond stamp.
    ///
    /// The split is at the last dot and `dot > 0`, so `.env` keeps its whole name while
    /// `backup.tar.gz` becomes `backup.tar (1).gz`.
    static func available(_ directory: URL, _ filename: String) -> URL {
        let manager = FileManager.default
        var candidate = directory.appending(path: filename)
        if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) { return candidate }
        var base = filename
        var suffix = ""
        if let dot = filename.lastIndex(of: "."), dot != filename.startIndex {
            base = String(filename[filename.startIndex..<dot])
            suffix = String(filename[dot...])
        }
        for index in 1...999 {
            candidate = directory.appending(path: "\(base) (\(index))\(suffix)")
            if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return directory.appending(path: "\(base)-\(stamp)\(suffix)")
    }

    /// `dockerUploadFormData(asset, fields)` — the file part plus every scalar field.
    ///
    /// `file_uri` and `file_name` are the form's own bookkeeping and never reach the wire; a null
    /// or empty value is dropped so the daemon sees an absent field rather than a blank one; and a
    /// nested object is JSON-stringified, which is how `build_args` travels.
    static func uploadForm(_ asset: DockerAsset, _ fields: JSONObject) -> MultipartBody {
        var form = MultipartBody()
        form.append("file", filename: asset.name, mimeType: asset.mimeType, content: asset.content)
        for (key, value) in fields.pairs {
            guard !["file_uri", "file_name"].contains(key), !value.isNull else { continue }
            switch value {
            case .string(let text) where text.isEmpty: continue
            case .object, .array: form.append(key, value: JSONSerializer.stringify(value))
            default: form.append(key, value: value.asDisplayString)
            }
        }
        return form
    }

    /// The MIME type a picked URL implies, for the file part's `Content-Type`.
    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }

    /// `volume_name` derived from a backup archive: the compression suffix, then the
    /// `-backup-YYYYMMDD-HHMMSS` stamp Lucky's own backup writer appends.
    static func volumeName(from filename: String) -> String {
        var name = filename
        for suffix in [".tar.gz", ".tgz"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
            break
        }
        return withoutBackupStamp(name)
    }

    /// `/-backup-\d{8}-\d{6}$/i` — 22 trailing characters, checked digit by digit.
    private static func withoutBackupStamp(_ name: String) -> String {
        let marker = "-backup-"
        guard name.count >= marker.count + 15 else { return name }
        let tail = String(name.suffix(marker.count + 15))
        guard tail.lowercased().hasPrefix(marker) else { return name }
        let stamp = Array(tail.dropFirst(marker.count))
        let digits = Set(0..<8).union(9..<15)
        for (index, character) in stamp.enumerated() {
            if index == 8 {
                guard character == "-" else { return name }
            } else if digits.contains(index) {
                guard character.isASCII, character.isNumber else { return name }
            }
        }
        return String(name.dropLast(tail.count))
    }
}
