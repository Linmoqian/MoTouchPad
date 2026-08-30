import Foundation

/// MoTouchPad protocol v1 常量与触控快照编码。
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
}

struct TouchContact {
    var id: UInt8
    var touching: Bool
    /// 归一化 0...1
    var x: Float
    var y: Float
    var pressure: Float
    var major: Float
    var minor: Float
}

struct TouchFrame {
    var type: UInt8
    var sequence: UInt32
    /// 单调时钟纳秒时间戳
    var timestampNanos: Int64
    var contacts: [TouchContact]
    /// 指针灵敏度百分比 50...200
    var sensitivityPercent: Int
    var naturalScrolling: Bool

    func encoded() -> Data {
        var data = Data(capacity: TouchProtocol.headerSize + contacts.count * TouchProtocol.contactSize)
        var magic = TouchProtocol.magic.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &magic) { Data($0) })
        data.append(TouchProtocol.version)
        data.append(type)
        data.append(contentsOf: [0, 0]) // Flags（保留）
        var sequence = sequence.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &sequence) { Data($0) })
        var timestamp = timestampNanos.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &timestamp) { Data($0) })
        data.append(UInt8(contacts.count))
        data.append(0) // Physical buttons（保留）
        data.append(UInt8(clamping: sensitivityPercent))
        data.append(naturalScrolling ? 1 : 0)

        for contact in contacts {
            data.append(contact.id)
            data.append(contact.touching ? 1 : 0)
            data.append(contentsOf: [0, 0]) // Reserved
            for value in [contact.x, contact.y, contact.pressure, contact.major, contact.minor] {
                var bits = value.bitPattern.littleEndian
                data.append(contentsOf: withUnsafeBytes(of: &bits) { Data($0) })
            }
        }
        return data
    }
}

/// 每帧一个完整快照；发送队列满时丢弃最旧快照。
final class TouchFrameSequencer {
    private var sequence: UInt32 = 0

    func makeSnapshot(contacts: [TouchContact],
                      sensitivityPercent: Int,
                      naturalScrolling: Bool) -> TouchFrame {
        sequence &+= 1
        return TouchFrame(
            type: TouchProtocol.typeTouch,
            sequence: sequence,
            timestampNanos: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000),
            contacts: Array(contacts.prefix(TouchProtocol.maxContacts)),
            sensitivityPercent: min(max(sensitivityPercent, 50), 200),
            naturalScrolling: naturalScrolling)
    }
}
