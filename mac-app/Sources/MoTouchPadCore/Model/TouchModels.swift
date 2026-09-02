import Foundation

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

public enum TouchFrameType: UInt8, Equatable {
    case hello = 1
    case touch = 2
}

public struct TouchContact: Equatable {
    public var id: UInt8
    public var touching: Bool
    public var x: Float
    public var y: Float
    public var pressure: Float
    public var major: Float
    public var minor: Float

    public init(id: UInt8, touching: Bool, x: Float, y: Float,
                pressure: Float, major: Float, minor: Float) {
        self.id = id
        self.touching = touching
        self.x = x
        self.y = y
        self.pressure = pressure
        self.major = major
        self.minor = minor
    }
}

public struct TouchFrame: Equatable {
    public var type: TouchFrameType
    public var sequence: UInt32
    public var timestampNanos: Int64
    public var buttons: UInt8
    public var sensitivityPercent: Int
    public var naturalScrolling: Bool
    public var contacts: [TouchContact]

    public init(type: TouchFrameType, sequence: UInt32, timestampNanos: Int64,
                buttons: UInt8 = 0, sensitivityPercent: Int,
                naturalScrolling: Bool, contacts: [TouchContact]) {
        self.type = type
        self.sequence = sequence
        self.timestampNanos = timestampNanos
        self.buttons = buttons
        self.sensitivityPercent = sensitivityPercent
        self.naturalScrolling = naturalScrolling
        self.contacts = contacts
    }
}
