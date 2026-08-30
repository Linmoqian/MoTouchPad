import Foundation

/// MoTouchPad protocol v1 帧解码。
/// 格式定义见 protocol/PROTOCOL.md，所有字段小端。
enum TouchProtocol {
    static let port: UInt16 = 47651
    static let magic: UInt32 = 0x3150_544D // "MTP1"
    static let version: UInt8 = 1
    static let typeHello: UInt8 = 1
    static let typeTouch: UInt8 = 2
    static let headerSize = 24
    static let contactSize = 24
    static let maxContacts = 5
    /// PC -> Android 传输层心跳字节。
    static let heartbeat: UInt8 = 0x7F
}

struct TouchContact {
    var id: UInt8
    var touching: Bool
    var x: Float
    var y: Float
    var pressure: Float
    var major: Float
    var minor: Float
}

struct TouchFrame {
    enum FrameType {
        case hello
        case touch
    }

    var type: FrameType
    var sequence: UInt32
    var timestampNanos: Int64
    /// 指针灵敏度百分比 50...200
    var sensitivityPercent: Int
    var naturalScrolling: Bool
    var contacts: [TouchContact]

    /// 从缓冲区头部解析一帧；数据不足时返回 nil 等待更多字节。
    /// 返回成功时给出消耗的字节数。
    static func parse(_ buffer: Data) -> (frame: TouchFrame, byteCount: Int)? {
        guard buffer.count >= TouchProtocol.headerSize else { return nil }
        let header = buffer.prefix(TouchProtocol.headerSize)
        let magic = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard magic == TouchProtocol.magic else { return nil }
        guard header[header.startIndex + 4] == TouchProtocol.version else { return nil }

        let count = Int(header[header.startIndex + 20])
        guard count <= TouchProtocol.maxContacts else { return nil }
        let totalSize = TouchProtocol.headerSize + count * TouchProtocol.contactSize
        guard buffer.count >= totalSize else { return nil }

        let sensitivityRaw = header[header.startIndex + 22]
        let settingsFlags = header[header.startIndex + 23]
        var contacts: [TouchContact] = []
        contacts.reserveCapacity(count)
        for index in 0..<count {
            let start = buffer.startIndex + TouchProtocol.headerSize + index * TouchProtocol.contactSize
            let record = buffer[start..<start + TouchProtocol.contactSize]
            func float(at offset: Int) -> Float {
                Float(bitPattern: record.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) })
            }
            contacts.append(TouchContact(
                id: record[record.startIndex],
                touching: record[record.startIndex + 1] != 0,
                x: float(at: 4),
                y: float(at: 8),
                pressure: float(at: 12),
                major: float(at: 16),
                minor: float(at: 20)))
        }

        let type: FrameType = header[header.startIndex + 5] == TouchProtocol.typeHello ? .hello : .touch
        let sequence = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) }
        let timestamp = header.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 12, as: Int64.self) }
        let frame = TouchFrame(
            type: type,
            sequence: sequence,
            timestampNanos: timestamp,
            sensitivityPercent: sensitivityRaw == 0 ? 100 : min(max(Int(sensitivityRaw), 50), 200),
            naturalScrolling: settingsFlags & 0x01 != 0,
            contacts: contacts)
        return (frame, totalSize)
    }
}
