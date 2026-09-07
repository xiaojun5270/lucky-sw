import Foundation

/// Minimal protobuf wire-format reader, replacing `protobufjs/light`.
///
/// Only what the two status messages need: varint, fixed32, fixed64 and
/// length-delimited. Unknown fields are skipped rather than rejected, which is what
/// `Type.decode` does and what lets the port keep working against newer Lucky builds.
struct ProtobufReader {
    enum WireType: Int {
        case varint = 0, fixed64 = 1, lengthDelimited = 2, startGroup = 3, endGroup = 4, fixed32 = 5
    }

    private let bytes: [UInt8]
    private var index: Int
    private let end: Int

    init(_ data: Data) {
        bytes = [UInt8](data)
        index = 0
        end = bytes.count
    }

    private init(bytes: [UInt8], range: Range<Int>) {
        self.bytes = bytes
        index = range.lowerBound
        end = range.upperBound
    }

    var isAtEnd: Bool { index >= end }

    mutating func nextField() throws -> (number: Int, wire: WireType) {
        let tag = try varint()
        guard let wire = WireType(rawValue: Int(tag & 0x07)), tag >> 3 > 0 else {
            throw LuckyError("状态数据解析失败")
        }
        return (Int(tag >> 3), wire)
    }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < end {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { throw LuckyError("状态数据解析失败") }
        }
        throw LuckyError("状态数据解析失败")
    }

    mutating func fixed32() throws -> UInt32 {
        guard index + 4 <= end else { throw LuckyError("状态数据解析失败") }
        var value: UInt32 = 0
        for offset in 0..<4 { value |= UInt32(bytes[index + offset]) << (8 * UInt32(offset)) }
        index += 4
        return value
    }

    mutating func fixed64() throws -> UInt64 {
        guard index + 8 <= end else { throw LuckyError("状态数据解析失败") }
        var value: UInt64 = 0
        for offset in 0..<8 { value |= UInt64(bytes[index + offset]) << (8 * UInt64(offset)) }
        index += 8
        return value
    }

    mutating func float() throws -> Double {
        Double(Float(bitPattern: try fixed32()))
    }

    mutating func bool() throws -> Bool {
        try varint() != 0
    }

    mutating func string() throws -> String {
        let range = try lengthDelimited()
        return String(decoding: bytes[range], as: UTF8.self)
    }

    /// A nested message, returned as its own reader over the same buffer.
    mutating func message() throws -> ProtobufReader {
        ProtobufReader(bytes: bytes, range: try lengthDelimited())
    }

    mutating func lengthDelimited() throws -> Range<Int> {
        let length = Int(try varint())
        guard length >= 0, index + length <= end else { throw LuckyError("状态数据解析失败") }
        let range = index..<(index + length)
        index += length
        return range
    }

    mutating func skip(_ wire: WireType) throws {
        switch wire {
        case .varint: _ = try varint()
        case .fixed64: _ = try fixed64()
        case .fixed32: _ = try fixed32()
        case .lengthDelimited: _ = try lengthDelimited()
        case .startGroup, .endGroup: throw LuckyError("状态数据解析失败")
        }
    }
}

extension LuckyLiveStatus {
    /// `statusType.decode(ungzip(bytes))` plus the `ok === false` guard.
    ///
    /// `ok` defaults to `false` exactly as the generated message prototype does, so a frame
    /// that omits the field is treated as an invalid connection — same as the original.
    static func decode(gzipped: Data) throws -> LuckyLiveStatus {
        try decode(protobuf: try Gzip.inflate(gzipped))
    }

    static func decode(protobuf: Data) throws -> LuckyLiveStatus {
        var reader = ProtobufReader(protobuf)
        var status = LuckyLiveStatus()
        var ok = false
        var error = ""

        while !reader.isAtEnd {
            let field = try reader.nextField()
            switch (field.number, field.wire) {
            case (1, .varint): ok = try reader.bool()
            case (2, .lengthDelimited): error = try reader.string()
            case (3, .varint): status.totalMem = Double(try reader.varint())
            case (4, .varint): status.usedMem = Double(try reader.varint())
            case (5, .fixed32): status.usedCpu = try reader.float()
            case (6, .fixed32): status.currentProcessUsedCpu = try reader.float()
            case (7, .varint): status.goroutine = Double(try reader.varint())
            case (8, .varint): status.processUsedMem = Double(try reader.varint())
            case (9, .varint): status.netIn = Double(try reader.varint())
            case (10, .varint): status.netOut = Double(try reader.varint())
            case (11, .varint): status.lastNetInSpeed = Double(try reader.varint())
            case (12, .varint): status.lastNetOutSpeed = Double(try reader.varint())
            case (13, .varint): status.handleCount = Double(try reader.varint())
            case (14, .varint): status.numGc = Double(try reader.varint())
            case (15, .varint): status.heapInuse = Double(try reader.varint())
            case (16, .lengthDelimited): status.runTime = try reader.string()
            case (17, .lengthDelimited): status.queryTime = try reader.string()
            case (50, .lengthDelimited):
                var nested = try reader.message()
                status.history.append(try LuckyStatusSample(reader: &nested))
            default: try reader.skip(field.wire)
            }
        }

        if !ok { throw LuckyError(error.isEmpty ? "状态连接无效" : error) }
        if status.history.count > LuckyStatusConstants.historyLimit {
            status.history = Array(status.history.suffix(LuckyStatusConstants.historyLimit))
        }
        return status
    }
}

extension LuckyStatusSample {
    /// `SystemSample` — `time` is an `int64`, the rest are `uint64` or `float`.
    fileprivate init(reader: inout ProtobufReader) throws {
        self.init()
        while !reader.isAtEnd {
            let field = try reader.nextField()
            switch (field.number, field.wire) {
            case (1, .varint): time = Double(Int64(bitPattern: try reader.varint()))
            case (2, .fixed32): systemCpuPercent = try reader.float()
            case (3, .fixed32): processCpuPercent = try reader.float()
            case (4, .varint): totalMem = Double(try reader.varint())
            case (5, .varint): usedMem = Double(try reader.varint())
            case (6, .varint): netInTransfer = Double(try reader.varint())
            case (7, .varint): netOutTransfer = Double(try reader.varint())
            case (8, .varint): netInSpeed = Double(try reader.varint())
            case (9, .varint): netOutSpeed = Double(try reader.varint())
            default: try reader.skip(field.wire)
            }
        }
    }
}
