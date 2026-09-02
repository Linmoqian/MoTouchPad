import Foundation

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

public enum TouchProtocol {
    public static let port: UInt16 = 47651
    public static let magic: UInt32 = 0x3150_544D // "MTP1"
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
        precondition(frame.sensitivityPercent == 0 ||
                     (50...200).contains(frame.sensitivityPercent))
        let sensitivity = frame.sensitivityPercent == 0 ? 100 : frame.sensitivityPercent
        frame.contacts.forEach(assertValid)

        var data = Data(capacity: TouchProtocol.headerSize +
                        frame.contacts.count * TouchProtocol.contactSize)
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
        guard data.count >= TouchProtocol.headerSize else { throw TouchProtocolError.truncated }
        guard try readUInt32(from: data, at: 0) == TouchProtocol.magic else {
            throw TouchProtocolError.invalidMagic
        }
        let version = data[4]
        guard version == TouchProtocol.version else {
            throw TouchProtocolError.unsupportedVersion(version)
        }
        let typeRaw = data[5]
        guard let type = TouchFrameType(rawValue: typeRaw) else {
            throw TouchProtocolError.unsupportedType(typeRaw)
        }
        let flags = try readUInt16(from: data, at: 6)
        guard flags == 0 else { throw TouchProtocolError.invalidLength(data.count) }
        let sequence = try readUInt32(from: data, at: 8)
        let timestamp = Int64(bitPattern: try readUInt64(from: data, at: 12))
        let count = Int(data[20])
        guard count <= TouchProtocol.maxContacts else {
            throw TouchProtocolError.invalidContactCount(count)
        }
        let sensitivityRaw = Int(data[22])
        guard sensitivityRaw == 0 || (50...200).contains(sensitivityRaw) else {
            throw TouchProtocolError.invalidSensitivity(sensitivityRaw)
        }
        let expectedLength = TouchProtocol.headerSize + count * TouchProtocol.contactSize
        guard data.count == expectedLength else {
            throw TouchProtocolError.invalidLength(data.count)
        }
        guard type != .hello || count == 0 else { throw TouchProtocolError.invalidHello }

        var contacts: [TouchContact] = []
        contacts.reserveCapacity(count)
        for index in 0..<count {
            let offset = TouchProtocol.headerSize + index * TouchProtocol.contactSize
            let reserved = try readUInt16(from: data, at: offset + 2)
            guard reserved == 0 else {
                throw TouchProtocolError.invalidLength(data.count)
            }
            let contact = TouchContact(
                id: data[offset],
                touching: try readContactState(from: data, at: offset + 1),
                x: Float(bitPattern: try readUInt32(from: data, at: offset + 4)),
                y: Float(bitPattern: try readUInt32(from: data, at: offset + 8)),
                pressure: Float(bitPattern: try readUInt32(from: data, at: offset + 12)),
                major: Float(bitPattern: try readUInt32(from: data, at: offset + 16)),
                minor: Float(bitPattern: try readUInt32(from: data, at: offset + 20)))
            try validate(contact)
            contacts.append(contact)
        }

        return TouchFrame(
            type: type,
            sequence: sequence,
            timestampNanos: timestamp,
            buttons: data[21],
            sensitivityPercent: sensitivityRaw == 0 ? 100 : sensitivityRaw,
            naturalScrolling: try readSettingsFlags(from: data),
            contacts: contacts)
    }

    public static func parse(_ buffer: Data) throws -> (frame: TouchFrame, byteCount: Int)? {
        guard buffer.count >= TouchProtocol.headerSize else { return nil }
        guard buffer[0] == 0x4D, buffer[1] == 0x54,
              buffer[2] == 0x50, buffer[3] == 0x31 else {
            throw TouchProtocolError.invalidMagic
        }
        let count = Int(buffer[20])
        guard count <= TouchProtocol.maxContacts else {
            throw TouchProtocolError.invalidContactCount(count)
        }
        let totalSize = TouchProtocol.headerSize + count * TouchProtocol.contactSize
        guard buffer.count >= totalSize else { return nil }
        let frameData = Data(buffer.prefix(totalSize))
        let frame = try decode(frameData)
        return (frame, totalSize)
    }

    private static func assertValid(_ contact: TouchContact) {
        precondition(contactValuesAreValid(contact))
    }

    private static func validate(_ contact: TouchContact) throws {
        guard contactValuesAreValid(contact) else {
            throw TouchProtocolError.invalidContactValue
        }
    }

    private static func contactValuesAreValid(_ contact: TouchContact) -> Bool {
        [contact.x, contact.y, contact.pressure, contact.major, contact.minor]
            .allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var value = value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var value = value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
    }

    private static func append(_ value: UInt64, to data: inout Data) {
        var value = value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
    }

    private static func readUInt32(from data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else {
            throw TouchProtocolError.truncated
        }
        return UInt32(data[offset]) |
            UInt32(data[offset + 1]) << 8 |
            UInt32(data[offset + 2]) << 16 |
            UInt32(data[offset + 3]) << 24
    }

    private static func readUInt16(from data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else {
            throw TouchProtocolError.truncated
        }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readContactState(from data: Data, at offset: Int) throws -> Bool {
        let state = data[offset]
        guard state == 0 || state == 1 else {
            throw TouchProtocolError.invalidLength(data.count)
        }
        return state == 1
    }

    private static func readSettingsFlags(from data: Data) throws -> Bool {
        let flags = data[23]
        guard flags & 0xFE == 0 else {
            throw TouchProtocolError.invalidLength(data.count)
        }
        return flags & 0x01 != 0
    }

    private static func readUInt64(from data: Data, at offset: Int) throws -> UInt64 {
        guard offset >= 0, offset + 8 <= data.count else {
            throw TouchProtocolError.truncated
        }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        return value
    }
}
