//
//  ByteBuffer.swift
//
//
//  Created by HYEONJUN PARK on 2021/03/10.
//

import Foundation

class BytesBuffer {
    var byteData: [UInt8]
    var capacity: Int
    var count: Int
    
     init(capacity: Int) {
        self.byteData = [UInt8].init(repeating: 0, count: capacity)
        self.capacity = capacity
        self.count = 0
    }
    
    public init(data: Data) {
        self.capacity = data.count.nextPowerOf2()
        self.byteData = [UInt8].init(repeating: 0, count: capacity)
        data.copyBytes(to: &self.byteData, count: data.count)
        self.count = data.count
    }
    
    public var data: Data? {
        if self.count == 0 { return nil }
        return Data(bytes: self.byteData, count: self.count)
    }
    
    subscript(index: Int) -> UInt8? {
        get {
            var byte: UInt8?
            guard self.byteData.startIndex..<self.count ~= index else { return nil }
            byte = self.byteData[index]
            return byte
        }
    }
    
    func setSize(count: Int) {
        self.count = count
    }
    
    func write(offset: Int, byte: UInt8) {
        byteData[offset] = byte
    }
    
    
    func write(offset: Int, bytes: UInt16) {
        let bytesArray = bytes.bigEndian.data.array
        for (i, byte) in bytesArray.enumerated() {
            byteData[offset + i] = byte
        }
    }
    
    /*
    func location(offset: Int) -> UnsafePointer<UInt8>? {
        guard let ptr = byteData.withUnsafeBytes({ return $0 }).bindMemory(to: UInt8.self).baseAddress else {
            return nil
        }
        return ptr + offset
    }
    */
    
    func location (offset: Int) -> UnsafeMutableRawPointer? {
        guard let ptr = byteData.withUnsafeMutableBytes({ return $0 }).baseAddress else {
            return nil
        }
        return ptr + offset
    }
    
    
    
    func write(offset: Int, bytes: UInt32) {
        let bytesArray = bytes.bigEndian.data.array
        for (i, byte) in bytesArray.enumerated() {
            byteData[offset + i] = byte
        }
    }
    
    func write(offset: Int, bytes: Data) {
        for (i, byte) in bytes.enumerated() {
            byteData[offset + i] = byte
        }
    }
    
    func writeZeroPadding(offset: Int, length: Int) {
        let bytesArray = [UInt8](repeating: 0, count: length)
        for (i, byte) in bytesArray.enumerated() {
            byteData[offset + i] = byte
        }
    }
    
    func append(byte: UInt8) {
        let index = self.count
        write(offset: index, byte: byte)
        self.count += 1
    }
    
    func append(bytes: UInt16) {
        let index = self.count
        write(offset: index, bytes: bytes)
        self.count += 2
    }
    
    func append(bytes: UInt32) {
        let index = self.count
        write(offset: index, bytes: bytes)
        self.count += 4
    }
    
    func append(data: Data) {
        guard let ptr = byteData.withUnsafeMutableBytes({return $0}).bindMemory(to: UInt8.self).baseAddress else { return }
        let dst = ptr + self.count
        data.copyBytes(to: dst, count: data.count)
        self.count += data.count
    }
    
    func get(offset: Int, count: Int) -> Data? {
        if offset + count > capacity { return nil }
        return Data(byteData[offset..<count])
    }
}

extension BytesBuffer : CustomStringConvertible {
    public var description: String {
        var desc = "[ "
        for index in 0..<self.count {
            if index == self.count - 1 {
                desc += String(format: "0x%02x", byteData[index])
            } else {
                desc += String(format: "0x%02x, ", byteData[index])
            }
        }
        desc += " ]"
        return desc
    }
}



