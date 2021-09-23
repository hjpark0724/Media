//
//  AnnexBBuferReader.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/11.
//

import Foundation
import AVFoundation
import VideoToolbox

class AnnexBBufferReader : NSObject {
    var data : UnsafePointer<UInt8>
    var length: Int
    var indices: [NaluIndex]
    var index: Int = 0
    init(data: UnsafePointer<UInt8>, count: Int) {
        self.data = data
        self.length = count
        self.indices = findNaluIndices(buffer: self.data, count: self.length)
        super.init()
    }
    
    func resetStart() {
        self.index = 0
    }
    
    func readNalUnit(buffer: inout UnsafePointer<UInt8>?, count: inout Int32) -> Bool {
        if index > indices.count {
            return false
        }
        let nalUType = indices[index]
        count = nalUType.payloadSize
        buffer = data + Int(nalUType.payloadStartOffset)
        index += 1
        return true
    }
    
    func remainBytes() -> Int {
        if index >= indices.count {
            return 0
        }
        return length - Int(indices[index].startOffset)
    }
    
    func seekToNaluOfType(type: NaluType) -> Bool {
        for naluIndex in indices {
            //각 페이로드의 첫번째 바이트를 통해서 해당 NalUnitType 확인
            if let nal_type = parseNaluType(byte: data[Int(naluIndex.payloadStartOffset)]) {
                if nal_type == type {
                    return true
                }
            }
        }
        return false
    }
}

let kHeaderBytesSize: Int = 4
class AvccBufferWriter : NSObject {
    var start: UnsafeMutablePointer<UInt8>
    var length: Int = 0
    var offset: Int = 0
    
    init(buffer: UnsafeMutablePointer<UInt8>, count: Int) {
        self.start = buffer
        self.length = count
    }
    
    func writeNalu(data: UnsafePointer<UInt8>, count: Int) -> Bool {
        if count + kHeaderBytesSize > remainBytes() { return false }
        var bigEndian = UInt32(count).bigEndian
        let length_size = MemoryLayout<UInt32>.size
        let bytePtr = withUnsafePointer(to: &bigEndian) {
            $0.withMemoryRebound(to: UInt8.self, capacity: length_size) {
                return $0
            }
        }
        memcpy(start + offset, bytePtr, length_size)
        //print(Data(bytes: start + offset, count: length_size).hexDescription)
        offset += length_size
        memcpy(start + offset, data, count)
        //print(Data(bytes: start + offset, count: count).hexDescription)
        offset += count
        return true
    }
    
    func remainBytes() -> Int {
        return length - offset
    }
}
