//
//  CircularBuffer.swift
//  
//
//  Created by HYEONJUN PARK on 2020/12/17.
//

import Foundation
import Utils
public class CircularBuffer : CustomStringConvertible {
    enum CircularBufferError: Error {
        case overflow
    }
    var buffer: ContiguousArray<UInt8>
    var tailIndex: Int = 0 //유효한 데이터의 마지막 위치
    var headIndex: Int = 0 //유효한 데이터의 시작 위치
    var mask: Int {
        return self.buffer.count &- 1
    }
    var isFull: Bool = false
    var overflow: Bool = false
    //동기화를 위한 큐
    private let queue = DispatchQueue(label: "com.CircularBuffer")
    
    public init(initialCapacity: Int) {
        self.headIndex = 0
        self.tailIndex = 0
        let capacity = Int(UInt32(initialCapacity).nextPowerOf2())
        self.buffer = ContiguousArray<UInt8>(repeating: 0, count: capacity)
    }
    
    public func reset() {
            self.headIndex = 0
            self.tailIndex = 0
    }
    
    public var isEmpty: Bool {
        return self.headIndex == self.tailIndex
    }
    
    //버퍼내 유효한 데이터의 크기
    public var count: Int {
        if self.tailIndex >= self.headIndex {
            return self.tailIndex &- self.headIndex
        } else {
            return self.buffer.count &- (self.headIndex &- self.tailIndex)
        }
    }
    
    var capacity: Int { self.buffer.count }
    
    private func increaseCapacity() {
        var newBuffer: ContiguousArray<UInt8> = []
        let newCapacity = self.buffer.count << 1 // Double the storage.
        let numOfBytes = self.count
        newBuffer.reserveCapacity(newCapacity)
        newBuffer.append(contentsOf: self.buffer[self.headIndex..<self.buffer.count])
        if self.headIndex > 0 {
            newBuffer.append(contentsOf: self.buffer[0..<self.headIndex])
        }
        print("CircularBuffer increase capacity: \(newBuffer.count)")
        let repeatitionCount = newCapacity &- newBuffer.count
        newBuffer.append(contentsOf: repeatElement(0, count: repeatitionCount))
        self.headIndex = 0
        self.tailIndex = numOfBytes
        self.buffer = newBuffer
    }
    
    private func indexAdvanced(index: Int, by: Int) -> Int {
        return (index &+ by) & self.mask
    }
    
    private func advanceHeadIdx(by: Int) {
        self.headIndex = indexAdvanced(index: self.headIndex, by: by)
    }

    
    private func advanceTailIdx(by: Int) {
        self.tailIndex = indexAdvanced(index: self.tailIndex, by: by)
    }
    
    public func write(_ bytes: UnsafeRawBufferPointer) {
        queue.sync {
            let data = bytes.bindMemory(to: UInt8.self)
            let writingBytes = data.count
            //버퍼에 용량이 부족할 경우 이전 버퍼의 두배로 버퍼 크기를 조정
            //tailIndex 가 headIndex를 넘어갈 순 없음
            if self.capacity - self.count <= writingBytes {
                increaseCapacity()
            }
            let writableBytes = (self.tailIndex + bytes.count > capacity) ? capacity - self.tailIndex : bytes.count
            memcpy(&self.buffer[self.tailIndex], data.baseAddress, writableBytes)
            let remainBytes = bytes.count - writableBytes
            if remainBytes > 0 {
                memcpy(&self.buffer[0], data.baseAddress! + writableBytes, remainBytes)
            }
            self.advanceTailIdx(by: writingBytes)
        }

    }
    
    
    /*
    public func write(_ bytes: UnsafeRawBufferPointer) throws {
        if self.capacity < count {
           throw CircularBufferError.overflow
       }
        queue.sync {
            var current = self.tail
            let ptr = bytes.bindMemory(to: UInt8.self)
            let writableBytes = self.tail + bytes.count > capacity ? capacity - self.tail : bytes.count
            memcpy(&buffer[current], bytes.baseAddress, writableBytes)
            let remainBytes = bytes.count - writableBytes
            if remainBytes > 0 {
                memcpy(&buffer[0], ptr.baseAddress! + writableBytes, remainBytes)
            }
            //버퍼에 쓰고 난 후 위치
            current += bytes.count
            current %= capacity
            //이전 프레임의 위치보다 쓰고 난 이 후 위치가 작거나 같은 경우 overflow 가 발생
            if current <= tail {
                overflow = true
            }
            
            if overflow && head == current {
                //buffer 가 가득 찬 경우와 크기가 0인 경우를 구분하기 위해 isFull 플래그를 설정
                isFull = true
            }
            else if (head > tail && head < current) || (overflow && head < current) {
                //head의 위치가 덮어쓰여진 경우 전체 버퍼를 무효화 하고 현재 쓴 버퍼의 위치로 헤드 이동
                print("buffer invalidate");
                self.head = self.tail
            }
            if overflow == true {
                overflow = false
            }
            self.tail = current
        }
    }
    */
    public func write(bytes: UnsafeRawPointer, count: Int) {
        let bptr = bytes.bindMemory(to: UInt8.self, capacity: MemoryLayout<UInt8>.size)
        let ptr = UnsafeRawBufferPointer(start: bptr, count: count)
        write(ptr)
    }
    
    public func read(count: Int) -> Data? {
        var data: Data? = nil
        let size = self.count
        if isEmpty { return nil }
        queue.sync {
            //유효성 검사 - 버퍼가 비어있거나 요청한 데이터보다 적은 경우 nil 반환
            if size < count { return }
            //tail == head && isFull == false 인 경우는 위에서 걸러짐
            
            //복사할 배열 생성
            var dest :[UInt8] = [UInt8](repeating: 0, count: count)
            let readablBytes = (headIndex + count) <= capacity ? count : capacity - headIndex
            let ptr = buffer.withUnsafeBytes{return $0 }
            memcpy(&dest[0], ptr.baseAddress! + headIndex, readablBytes)
            let remainBytes = count - readablBytes
            if remainBytes > 0 {
                memcpy(&dest[readablBytes], ptr.baseAddress, remainBytes)
            }
            self.headIndex += count
            self.headIndex %= capacity
            data = Data(dest)
            if isEmpty {
                self.reset()
            }
        }
      
        return data
    }
    
    public func skip(count : Int) {
        if isEmpty { return }
        queue.sync {
            self.headIndex += count
            self.headIndex %= capacity
            if isEmpty { self.reset() }
        }
    }
    
    public var description: String {
        var desc = "[ "
        desc += "head:\(self.headIndex) "
        desc += "tail:\(self.tailIndex) "
        /**
        for byte in self.buffer.enumerated() {
            if byte.0 == self.headIndex {
                desc += "<"
            } else if byte.0 == self.tailIndex {
                desc += ">"
            }
            desc += String(format: "%02x ", byte.1)
        }
        
        desc += "]"
        */
        desc += " (bufferCapacity: \(self.capacity), ringLength: \(self.count))"
        return desc
    }
}

