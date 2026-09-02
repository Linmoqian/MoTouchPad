import Foundation

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

final class TouchFrameSequencer {
    private var sequence: UInt32 = 0

    func makeSnapshot(contacts: [TouchContact],
                      sensitivityPercent: Int,
                      naturalScrolling: Bool) -> TouchFrame {
        sequence &+= 1
        return TouchFrame(
            type: .touch,
            sequence: sequence,
            timestampNanos: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000),
            buttons: 0,
            contacts: Array(contacts.prefix(TouchProtocol.maxContacts)),
            sensitivityPercent: min(max(sensitivityPercent, 50), 200),
            naturalScrolling: naturalScrolling)
    }
}
