import Foundation

// Created on 2026-09-02; updated 2026-10-13.
// @author: https://github.com/Linmoqian

public enum TouchProtocol {
    public static let port: UInt16 = 47651
    public static let magic: UInt32 = 0x3150_544D
    public static let version: UInt8 = 1
    public static let headerSize = 24
    public static let contactSize = 24
    public static let maxContacts = 5
    public static let maxFrameSize = headerSize + maxContacts * contactSize
    public static let heartbeat: UInt8 = 0x7F
}

public enum TouchProtocolError: Error, Equatable {
    case truncated
    case invalidMagic
    case unsupportedVersion(UInt8)
    case unsupportedType(UInt8)
    case invalidContactCount(Int)
    case invalidLength(Int)
    case invalidSensitivity(Int)
    case invalidHello
    case invalidContactValue
}

public enum TouchFrameCodec {
    public static func encode(_ frame: TouchFrame) -> Data {
        precondition(frame.contacts.count <= TouchProtocol.maxContacts)
        precondition(frame.type != .hello || frame.contacts.isEmpty)
        precondition(frame.sensitivityPercent == 0 || (50...200).contains(frame.sensitivityPercent))
        let sensitivity = frame.sensitivityPercent == 0 ? 100 : frame.sensitivityPercent
        var data = Data(capacity: TouchProtocol.headerSize + frame.contacts.count * TouchProtocol.contactSize)
        append(TouchProtocol.magic, to: &data)
        data.append(TouchProtocol.version)
        data.append(frame.type.rawValue)
        append(UInt16(0), to: &data)
        append(frame.sequence, to: &data)
        append(UInt64(bitPattern: frame.timestampNanos), to: &data)
        data.append(UInt8(frame.contacts.count))
        data.append(frame.buttons)
        data.append(UInt8(sensitivity))
        data.append(frame.naturalScrolling ? 1 : 0)
        for contact in frame.contacts {
            precondition(valid(contact))
            data.append(contact.id)
            data.append(contact.touching ? 1 : 0)
            append(UInt16(0), to: &data)
            append(contact.x.bitPattern, to: &data)
            append(contact.y.bitPattern, to: &data)
            append(contact.pressure.bitPattern, to: &data)
            append(contact.major.bitPattern, to: &data)
            append(contact.minor.bitPattern, to: &data)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> TouchFrame {
        try data.withUnsafeBytes { bytes in
            let size = try frameSize(bytes, at: 0)
            guard let size else { throw TouchProtocolError.truncated }
            guard size == bytes.count else { throw TouchProtocolError.invalidLength(bytes.count) }
            return try decode(bytes, at: 0)
        }
    }

    public static func parse(_ buffer: Data) throws -> (frame: TouchFrame, byteCount: Int)? {
        try buffer.withUnsafeBytes { bytes in
            guard let size = try frameSize(bytes, at: 0), bytes.count >= size else { return nil }
            return (try decode(bytes, at: 0), size)
        }
    }

    /// 在原缓冲内按偏移解码完整帧，避免逐帧复制帧和剩余 TCP 字节。
    static func parseBatch(_ data: Data) throws -> (frames: [TouchFrame], consumed: Int) {
        try data.withUnsafeBytes { bytes in
            var frames: [TouchFrame] = []
            var offset = 0
            while let size = try frameSize(bytes, at: offset), bytes.count - offset >= size {
                frames.append(try decode(bytes, at: offset))
                offset += size
            }
            return (frames, offset)
        }
    }

    private static func frameSize(_ bytes: UnsafeRawBufferPointer, at offset: Int) throws -> Int? {
        guard bytes.count - offset >= TouchProtocol.headerSize else { return nil }
        guard read(UInt32.self, bytes, offset) == TouchProtocol.magic else {
            throw TouchProtocolError.invalidMagic
        }
        guard bytes[offset + 4] == TouchProtocol.version else {
            throw TouchProtocolError.unsupportedVersion(bytes[offset + 4])
        }
        guard TouchFrameType(rawValue: bytes[offset + 5]) != nil else {
            throw TouchProtocolError.unsupportedType(bytes[offset + 5])
        }
        let count = Int(bytes[offset + 20])
        guard count <= TouchProtocol.maxContacts else { throw TouchProtocolError.invalidContactCount(count) }
        return TouchProtocol.headerSize + count * TouchProtocol.contactSize
    }

    // Caller validated the header and complete frame length before any load.
    private static func decode(_ bytes: UnsafeRawBufferPointer, at offset: Int) throws -> TouchFrame {
        let count = Int(bytes[offset + 20])
        let length = TouchProtocol.headerSize + count * TouchProtocol.contactSize
        let type = TouchFrameType(rawValue: bytes[offset + 5])!
        guard read(UInt16.self, bytes, offset + 6) == 0, bytes[offset + 23] & 0xFE == 0 else {
            throw TouchProtocolError.invalidLength(length)
        }
        let sensitivity = Int(bytes[offset + 22])
        guard sensitivity == 0 || (50...200).contains(sensitivity) else {
            throw TouchProtocolError.invalidSensitivity(sensitivity)
        }
        guard type != .hello || count == 0 else { throw TouchProtocolError.invalidHello }
        var contacts: [TouchContact] = []
        contacts.reserveCapacity(count)
        for index in 0..<count {
            let start = offset + TouchProtocol.headerSize + index * TouchProtocol.contactSize
            guard read(UInt16.self, bytes, start + 2) == 0, bytes[start + 1] <= 1 else {
                throw TouchProtocolError.invalidLength(length)
            }
            let contact = TouchContact(
                id: bytes[start], touching: bytes[start + 1] == 1,
                x: Float(bitPattern: read(UInt32.self, bytes, start + 4)),
                y: Float(bitPattern: read(UInt32.self, bytes, start + 8)),
                pressure: Float(bitPattern: read(UInt32.self, bytes, start + 12)),
                major: Float(bitPattern: read(UInt32.self, bytes, start + 16)),
                minor: Float(bitPattern: read(UInt32.self, bytes, start + 20)))
            guard valid(contact) else { throw TouchProtocolError.invalidContactValue }
            contacts.append(contact)
        }
        return TouchFrame(type: type, sequence: read(UInt32.self, bytes, offset + 8),
                          timestampNanos: Int64(bitPattern: read(UInt64.self, bytes, offset + 12)),
                          buttons: bytes[offset + 21], sensitivityPercent: sensitivity == 0 ? 100 : sensitivity,
                          naturalScrolling: bytes[offset + 23] & 1 != 0, contacts: contacts)
    }

    private static func valid(_ contact: TouchContact) -> Bool {
        valid(contact.x) && valid(contact.y) && valid(contact.pressure) &&
            valid(contact.major) && valid(contact.minor)
    }

    private static func valid(_ value: Float) -> Bool {
        value.isFinite && value >= 0 && value <= 1
    }

    private static func read<T: FixedWidthInteger>(_: T.Type, _ bytes: UnsafeRawBufferPointer,
                                                   _ offset: Int) -> T {
        T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: T.self))
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

/// Each append returns all complete frames, retaining at most one partial frame.
public struct TouchFrameStreamDecoder {
    private var buffer = Data()
    public var bufferedByteCount: Int { buffer.count }

    public init() {}

    public mutating func append(_ bytes: Data) throws -> [TouchFrame] {
        buffer.append(bytes)
        do {
            let parsed = try TouchFrameCodec.parseBatch(buffer)
            if parsed.consumed == buffer.count {
                buffer.removeAll(keepingCapacity: true)
            } else if parsed.consumed > 0 {
                buffer = Data(buffer.dropFirst(parsed.consumed))
            }
            return parsed.frames
        } catch {
            reset()
            throw error
        }
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}
