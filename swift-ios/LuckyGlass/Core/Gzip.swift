import Compression
import Foundation

/// `pako.ungzip` — the live-status WebSocket sends gzip-wrapped protobuf frames.
///
/// Apple's `Compression` framework speaks raw DEFLATE (`COMPRESSION_ZLIB`), so the RFC 1952
/// container has to be unwrapped by hand. The stream API is used rather than
/// `compression_decode_buffer` because the uncompressed size is only known from the
/// trailer, which a truncated frame would misreport.
enum Gzip {
    static func inflate(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        // 10-byte header + 8-byte trailer, plus at least one byte of payload.
        guard bytes.count >= 19 else { throw LuckyError("状态数据解压失败") }
        guard bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else {
            throw LuckyError("状态数据解压失败")
        }

        let flags = bytes[3]
        var cursor = 10
        if flags & 0x04 != 0 {  // FEXTRA
            guard cursor + 2 <= bytes.count else { throw LuckyError("状态数据解压失败") }
            let length = Int(bytes[cursor]) | Int(bytes[cursor + 1]) << 8
            cursor += 2 + length
        }
        if flags & 0x08 != 0 { cursor = try skipCString(bytes, from: cursor) }   // FNAME
        if flags & 0x10 != 0 { cursor = try skipCString(bytes, from: cursor) }   // FCOMMENT
        if flags & 0x02 != 0 { cursor += 2 }                                     // FHCRC

        let end = bytes.count - 8
        guard cursor < end else { throw LuckyError("状态数据解压失败") }

        let output = try rawInflate(bytes[cursor..<end])

        // The trailer's ISIZE is the uncompressed length mod 2^32; a mismatch means the
        // frame was truncated, which is the one corruption worth refusing to chart.
        let isize = UInt32(bytes[end + 4]) | UInt32(bytes[end + 5]) << 8
            | UInt32(bytes[end + 6]) << 16 | UInt32(bytes[end + 7]) << 24
        guard UInt32(truncatingIfNeeded: output.count) == isize else {
            throw LuckyError("状态数据解压失败")
        }
        return output
    }

    private static func skipCString(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        guard index < bytes.count else { throw LuckyError("状态数据解压失败") }
        return index + 1
    }

    private static func rawInflate(_ deflated: ArraySlice<UInt8>) throws -> Data {
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: -1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: -1)!,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            == COMPRESSION_STATUS_OK else { throw LuckyError("状态数据解压失败") }
        defer { compression_stream_destroy(&stream) }

        let chunkSize = 64 * 1024
        var output = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        let source = Array(deflated)
        return try source.withUnsafeBufferPointer { input -> Data in
            stream.src_ptr = input.baseAddress!
            stream.src_size = input.count
            while true {
                stream.dst_ptr = buffer
                stream.dst_size = chunkSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = chunkSize - stream.dst_size
                if produced > 0 { output.append(buffer, count: produced) }
                switch status {
                case COMPRESSION_STATUS_OK:
                    // Output buffer full: keep going. A stalled stream means bad input.
                    if produced == 0 && stream.src_size == 0 { throw LuckyError("状态数据解压失败") }
                case COMPRESSION_STATUS_END:
                    return output
                default:
                    throw LuckyError("状态数据解压失败")
                }
            }
        }
    }
}
