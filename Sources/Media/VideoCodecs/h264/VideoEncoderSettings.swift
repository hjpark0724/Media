//
//  VideoEncoderSettings.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/06.
//

import Foundation

public struct VideoEncoderSettings {
    public let name: String
    public let width: Int32
    public let height: Int32
    public let startBitrate: Int
    public let maxBitrate: UInt32
    public let minBitrate: UInt32
    public let maxFramerate: Int
    public let qpMax: UInt32
    public init(name: String, width: Int32, height: Int32, startBitrate: Int, maxBitrate: UInt32, minBitrate: UInt32, maxFramerate: Int, qpMax: UInt32) {
        self.name = name
        self.width = width
        self.height = height
        self.startBitrate = startBitrate
        self.maxBitrate = maxBitrate
        self.minBitrate = minBitrate
        self.maxFramerate = maxFramerate
        self.qpMax = qpMax
    }
}
