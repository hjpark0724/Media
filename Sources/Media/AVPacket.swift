//
//  AVPacket.swift
//  
//
//  Created by HYEONJUN PARK on 2021/04/05.
//

import Foundation
public enum PacketType {
    case video
    case audio
}

public protocol AVPacket {
    var type: PacketType { get }
    var presentationTimestamp: Int { get }
    var data: Data { get }
}

public enum VideoRotation : Int {
    case rotation_0 = 0
    case rotation_90 = 90
    case rotation_180 = 180
    case rotation_270 = 270
}

public struct AudioPacket : AVPacket {
    public var type: PacketType
    public var presentationTimestamp: Int
    public var data: Data
    public init(timestamp: Int, data: Data) {
        self.type = .audio
        self.presentationTimestamp = timestamp
        self.data = data
    }
}

public struct VideoPacket : AVPacket {
    public var type: PacketType
    public var presentationTimestamp: Int
    public var data: Data
    public var rotation: VideoRotation = .rotation_0
    public init(timestamp: Int, data: Data) {
        self.type = .video
        self.presentationTimestamp = timestamp
        self.data = data
    }
}
