import Foundation

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

enum TouchFrameType: UInt8, Equatable {
    case hello = 1
    case touch = 2
}

struct TouchContact: Equatable {
    var id: UInt8
    var touching: Bool
    /// 归一化 0...1。
    var x: Float
    var y: Float
    var pressure: Float
    var major: Float
    var minor: Float
}

struct TouchFrame: Equatable {
    var type: TouchFrameType
    var sequence: UInt32
    /// 触控端单调时钟纳秒时间戳。
    var timestampNanos: Int64
    var buttons: UInt8
    var contacts: [TouchContact]
    /// 指针灵敏度百分比 50...200。
    var sensitivityPercent: Int
    var naturalScrolling: Bool
}

struct TouchpadSettings: Equatable {
    var sensitivityPercent = 100
    var naturalScrolling = false
}
