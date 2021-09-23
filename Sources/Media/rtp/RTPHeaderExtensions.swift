//
//  RTPHeaderExtensions.swift
//  
//
//  Created by HYEONJUN PARK on 2021/04/19.
//

import Foundation

public enum RTPExtensionType: Int {
    case kRTPExtensionNone
    case kRTPExtensionVideoRotation
    case kRTPExtensionNumberOfExtensions
}



func convertVideoRotationToCVOByte(rotation: VideoRotation) ->UInt8 {
  switch (rotation) {
  case .rotation_0:
      return 0
  case .rotation_90:
      return 1
  case .rotation_180:
      return 2
  case .rotation_270:
      return 3
  }
}

func convertCVOByteToVideoRotation(cvo_byte: UInt8) -> VideoRotation {
  // CVO byte: |0 0 0 0 C F R R|.
  let rotation_bits = cvo_byte & 0x3;
  switch (rotation_bits) {
    case 0:
        return .rotation_0;
    case 1:
        return .rotation_90;
    case 2:
        return .rotation_180;
    case 3:
        return .rotation_270;
  default:
    return .rotation_0
  }
}

public protocol ExtensionInfo {
    static var kId: RTPExtensionType { get }
    static var valueSizeBytes: Int { get }
    static var uri: String { get }
    static func write(data: UnsafeMutableRawPointer?, rotation: VideoRotation) -> Bool
    static func parse(data: UnsafeMutableRawPointer?, rotation: inout VideoRotation) -> Bool
}


class VideoOrientation : ExtensionInfo {
    static var kId: RTPExtensionType = .kRTPExtensionVideoRotation
    static var valueSizeBytes = 1
    static var uri = "urn:3gpp:video-orientation"
    @discardableResult
    static func write(data: UnsafeMutableRawPointer?, rotation: VideoRotation) -> Bool {
        guard let data = data else { return false }
        let cvo_byte = convertVideoRotationToCVOByte(rotation: rotation)
        data.storeBytes(of: cvo_byte, as: UInt8.self)
        return true
    }
    @discardableResult
    static func parse(data: UnsafeMutableRawPointer?, rotation: inout VideoRotation) -> Bool {
        guard let data = data else { return false }
        let rawValue = data.assumingMemoryBound(to: UInt8.self)
        rotation = convertCVOByteToVideoRotation(cvo_byte: rawValue.pointee)
        return true
    }
}

public class ExtensionHeaderMap {
    var map: [RTPExtensionType : ExtensionInfo.Type] = [:]
    public init() {
        map[VideoOrientation.kId] = (VideoOrientation.self as ExtensionInfo.Type)
    }
    
    public func findExtensinInfo(type: RTPExtensionType) -> ExtensionInfo.Type? {
        return map[type]
    }
}
