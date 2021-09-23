//
//  RTPPacket.swift
//
//
//  Created by HYEONJUN PARK on 2021/03/09.
//

import Foundation
import Utils

//  0                   1                   2                   3
//  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |V=2|P|X|  CC   |M|     PT      |       sequence number         |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                           timestamp                           |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |           synchronization source (SSRC) identifier            |
// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
// |            Contributing source (CSRC) identifiers             |
// |                             ....                              |
// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
// |  header eXtension profile id  |       length in 32bits        |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                          Extensions                           |
// |                             ....                              |
// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
// |                           Payload                             |
// |             ....              :  padding...                   |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |               padding         | Padding size  |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

fileprivate let kFixedHeaderSize = 12;
fileprivate let kRtpVersion: UInt8 = 2;
fileprivate let kOneByteExtensionProfileId: UInt16 = 0xBEDE;
fileprivate let kTwoByteExtensionProfileId: UInt16 = 0x1000;
fileprivate let kOneByteExtensionHeaderLength = 1;
fileprivate let kTwoByteExtensionHeaderLength = 2;
fileprivate let kDefaultPacketSize = 1500;



public class RTPPacket {
    public var marker: Bool = false
    public var payloadType: UInt8 = 0
    public var sequnceNumber: UInt16 = 0
    public var timestamp: UInt32 = 0
    public var ssrc: UInt32 = 0
    public var paddingSize : Int = 0
    public var payloadOffset: Int = 0
    public var payloadSize: Int = 0
    public var extensionSize: Int = 0
    public var extensionEntries: [ExtensionInfo] = []
    var buffer: BytesBuffer? = nil
    
    public struct ExtensionInfo {
        let id: UInt8;
        let length : UInt8;
        var offset: UInt16;
    }
    
    public init() {
    }
    
    public init(capacity: Int) {
        let buffer = BytesBuffer(capacity: capacity)
        payloadOffset = kFixedHeaderSize
        buffer.count = kFixedHeaderSize
        buffer.write(offset: 0, byte: kRtpVersion << 6);
        self.buffer = buffer
    }
    public var data : Data? {
        return buffer?.data
    }
    
    func setMarker(marker: Bool) {
        guard let buffer = self.buffer else { return }
        self.marker = marker
        if marker {
            write(offset: 1, byte: buffer[1]! | 0x80)
        }
    }
    
    func setPayloadType(payloadType: UInt8) {
        guard let buffer = self.buffer else { return }
        self.payloadType = payloadType
        write(offset: 1, byte: (buffer[1]! & 0x80) | payloadType)
    }
    
    func setSequenceNumber(seqNo: UInt16) {
        guard self.buffer != nil else { return }
        self.sequnceNumber = seqNo
        write(offset: 2, bytes: seqNo)
    }
    
    func setTimestamp(timestamp: UInt32) {
        guard self.buffer != nil else { return }
        self.timestamp = timestamp
        write(offset: 4, bytes: timestamp)
    }
    
    func setSsrc(ssrc: UInt32) {
        guard self.buffer != nil else { return }
        self.ssrc = ssrc
        write(offset: 8, bytes: ssrc)
    }
    
    func setCsrcs(csrcs: [UInt32]) {
        guard let buffer = self.buffer else { return }
        payloadOffset = kFixedHeaderSize + 4 * csrcs.count
        write(offset: 0, byte: buffer[0]! & 0xF0 | UInt8(csrcs.count))
        var offset = kFixedHeaderSize
        for csrc in csrcs {
            write(offset: offset, bytes: csrc)
            offset += 4
        }
        buffer.setSize(count: payloadOffset)
    }
    
    
    func AllocateExtension(id: Int , length: Int) -> UnsafeMutableRawPointer? {
        guard let buffer = self.buffer else { return nil}
        let num_csrc = buffer[0]! & 0x0F
        //csrc + extension_profile_id(2byte) + extension_length(2byte)
        let extensions_offset = kFixedHeaderSize + (Int(num_csrc) * 4) + 4
        //oneByteHeader의 경우 id는 [1:14] length: 2^4 = 16 일 때 사용 가능
        let required_two_byte_header = id > 14 || length > 16 || length == 0
        var profile_id: UInt16 = 0
        
        if(extensionSize > 0) {
            profile_id = get(offset: extensions_offset - 4)!
            //이전 까지 OneByteExtension Profile 로 작성 중 TwoByteExtension으로 변경이 필요한 경우
            if profile_id == kOneByteExtensionProfileId && required_two_byte_header {
                let expected_new_extension_size =  extensionSize + extensionEntries.count + kTwoByteExtensionHeaderLength + length
                if extensions_offset + expected_new_extension_size > buffer.capacity {
                    return nil
                }
                promoteToTwoByteHeaderExtension()
                profile_id = kTwoByteExtensionProfileId
            }
        } else {
            profile_id = required_two_byte_header ? kTwoByteExtensionProfileId : kOneByteExtensionProfileId
        }
        
        let extensions_header_size = profile_id == kOneByteExtensionProfileId ? 1 : 2
        let new_extension_size = extensionSize + extensions_header_size + length
        if extensions_offset + new_extension_size > buffer.capacity {
            return nil
        }
        
        if extensionSize == 0 {
            write(offset: 0, byte: buffer[0]! | 0x10) // set extension bit
            write(offset: extensions_offset - 4, bytes: profile_id)
        }
        
        if profile_id == kOneByteExtensionProfileId {
            var one_byte_header: UInt8 = UInt8(id << 4)
            one_byte_header = one_byte_header | UInt8(length - 1) // length - 1
            write(offset: extensions_offset + extensionSize, byte: one_byte_header)
        } else {
            let extension_id = UInt8(id)
            write(offset: extensions_offset + extensionSize, byte: extension_id)
            let extension_length = UInt8(length)
            write(offset: extensions_offset + extensionSize + 1, byte: extension_length)
        }
        let extension_id = UInt8(id)
        let extension_info_offset = UInt16(extensions_offset + extensionSize + extensions_header_size)
        let extension_length = UInt8(length)
        extensionEntries.append(ExtensionInfo(id: extension_id, length: extension_length, offset: extension_info_offset))
        extensionSize = new_extension_size
        let extension_size_padded = setExtensionLengthWithPadding(extensions_offset: UInt16(extensions_offset))
        payloadOffset = extensions_offset + Int(extension_size_padded)
        buffer.setSize(count: payloadOffset)
        return buffer.location(offset: Int(extension_info_offset))
    }
    
    
    func payloadLocation() -> UnsafeMutablePointer<UInt8>? {
            guard let buffer = self.buffer, payloadSize > 0 else { return nil }
            return buffer.location(offset: payloadOffset)?.assumingMemoryBound(to: UInt8.self)
    }
    
    func location(offset: Int) -> UnsafeMutableRawPointer? {
        guard let buffer = self.buffer else { return nil }
        return buffer.location(offset: offset)
    }
    
    /*
    func setPayload(data: Data) {
        guard let buffer = self.buffer else { return }
        let src = data.withUnsafeBytes { return $0 }.bindMemory(to: UInt8.self)
        payloadSize = src.count
        buffer.write(offset: payloadOffset, src: src)
    }
    */
    
    func promoteToTwoByteHeaderExtension() {
        guard let buffer = self.buffer else { return }
        let num_csrc = buffer[0]! & 0x0f
        let extensions_offset = kFixedHeaderSize + (Int(num_csrc) * 4) + 4
        
        let write_read_delta = extensionEntries.count
        for index in stride(from: extensionEntries.count - 1, to: 0, by: -1) {
            var entry = extensionEntries[index]
            let read_index = entry.offset
            var write_index = entry.offset + UInt16(write_read_delta)
            entry.offset = write_index
            guard let data = get(offset: Int(read_index), count: Int(entry.length)) else { return }
            write(offset: Int(write_index), bytes: data)
            write_index -= 1
            write(offset: Int(write_index), byte: entry.length)
            write_index -= 1
            write(offset: Int(write_index), byte: entry.id)
        }
        write(offset: extensions_offset - 4, bytes: kTwoByteExtensionProfileId)
        extensionSize += extensionEntries.count
        let extensions_size_padded = setExtensionLengthWithPadding(extensions_offset: UInt16(extensions_offset))
        payloadOffset = extensions_offset + Int(extensions_size_padded)
        buffer.setSize(count: payloadOffset)
    }
    
    func setExtensionLengthWithPadding(extensions_offset: UInt16) -> UInt16 {
        let extension_words = UInt16((extensionSize + 3) / 4)
        //extension header 전체 길이
        write(offset: Int(extensions_offset) - 2, bytes: extension_words)
        
        let extension_padding_size = Int(4 * extension_words) - extensionSize
        //print("location: \(Int(extensions_offset) + extensionSize)")
        //print("extension_padding_size: \(extension_padding_size)")
        writeZeroPadding(offset: Int(extensions_offset) + extensionSize, count: extension_padding_size)
        return 4 * extension_words
    }
    
    public func parse(data: Data) -> Bool {
        let buffer = data.withUnsafeBytes{return $0}.bindMemory(to: UInt8.self)
        if !parse(buffer: buffer) {
            return false
        }
        self.buffer = BytesBuffer(data: data)
        return true;
    }
    
    private func parse(buffer: UnsafeBufferPointer<UInt8>) -> Bool {
        //RTP Header 크기 체크
        if buffer.count < kFixedHeaderSize {
            return false
            
        }
        //RTP Version 체크
        let version: UInt8 = buffer[0] >> 6;
        if version != kRtpVersion {
            return false
        }
        let hasPadding = (buffer[0] & 0x20) != 0
        let hasExtension = (buffer[0] & 0x10) != 0
        let numbOfCsrc = buffer[0] & 0x0f
        marker = (buffer[1] & 0x80) != 0
        payloadType = buffer[1] & 0x7f
        
        sequnceNumber = get(buffer: buffer, offset: 2)
        sequnceNumber = sequnceNumber.bigEndian
        
        timestamp = get(buffer: buffer, offset: 4)
        timestamp = timestamp.bigEndian
        
        ssrc = get(buffer: buffer, offset: 8)
        ssrc = ssrc.bigEndian
        
        if buffer.count < kFixedHeaderSize + Int(numbOfCsrc) * 4 {
            return false
        }
        //CSRC 다음 위치
        payloadOffset = kFixedHeaderSize + Int(numbOfCsrc) * 4
        
        // rtp packet의 마지막 바이트는 패딩 크기
        if hasPadding {
            paddingSize = Int(buffer[buffer.count - 1]);
            if paddingSize == 0 {
                return false
            }
        }
        
        if hasExtension {
            extensionEntries.removeAll()
            let extension_offset = payloadOffset + 4
            if extension_offset > buffer.count {
                return false
            }
            //csrc 다음 2byte : extension profile id
            var profile: UInt16 = get(buffer: buffer, offset: payloadOffset)
            profile = profile.bigEndian
            // profile id 다음 2byte: capacity * 4
            var capacity: UInt16 = get(buffer: buffer, offset: payloadOffset + 2)
            //print("profile:\(String(format: "0x%02x", profile))")
            capacity = capacity.bigEndian
            capacity *= 4
            //print("capacity:\(capacity)")
            if extension_offset + Int(capacity) > buffer.count {
                return false
            }
            
            if profile != kOneByteExtensionProfileId &&
                profile != kTwoByteExtensionProfileId {
                print("unsupported rtp extension: \(profile)")
            } else {
                let extensionHeaderLen = profile == kOneByteExtensionProfileId ? kOneByteExtensionHeaderLength : kTwoByteExtensionHeaderLength
                let kPaddingByte = 0
                let kPaddingId = 0
                let kOneByteHeaderExtensionReservedId = 15
                while extensionSize + extensionHeaderLen < capacity {
                    if buffer[extension_offset + extensionSize] == kPaddingByte {
                        extensionSize += 1
                        continue
                    }
                    var id: UInt8 = 0
                    var length: UInt8 = 0
                    if profile == kOneByteExtensionProfileId {
                        // 상위 4비트 : ID [1:14] - 15는 reserved
                        id = buffer[extension_offset + extensionSize] >> 4
                        // 하위 4 비트 : 헤더 확장 요소의 길이 - 1 ,0 이면 1byte
                        length = 1 + (buffer[extension_offset + extensionSize] & 0xf)
                        // id 15는 reserved, id =0, length = 0
                        if (id == kOneByteHeaderExtensionReservedId || id == kPaddingId && length != 1) {
                            break;
                        }
                    } else {
                        id = buffer[extension_offset + extensionSize]
                        length = buffer[extension_offset + extensionSize + 1]
                    }
                    // RTPHeader Extension 길이 유효성 검사
                    if extensionSize + extensionHeaderLen + Int(length) > capacity {
                        break;
                    }
                    //현재 offset에서 헤더 길이를 더한 위치가 데이터 offset
                     let offset = extension_offset + extensionSize + extensionHeaderLen
                    extensionEntries.append(ExtensionInfo(id: id, length: length, offset: UInt16(offset)))
                    //다음 extenstion element 위치 조정
                    extensionSize += extensionHeaderLen + Int(length)
                }
            }
            payloadOffset = extension_offset + Int(capacity)
        }
        
        if payloadOffset + paddingSize > buffer.count {
            return false
        }
        
        payloadSize = buffer.count - payloadOffset - paddingSize
        return true;
    }
    
    
    
    private func get<Element: UnsignedInteger>(buffer: UnsafeBufferPointer<UInt8>, offset: Int) -> Element {
        return UnsafePointer(buffer.baseAddress! + offset).withMemoryRebound(to: Element.self, capacity: 1){$0.pointee}
    }
    
    private func get<Element: UnsignedInteger>(offset: Int) -> Element? {
        guard let buffer = self.buffer else { return nil }
        let pointer = buffer.byteData.withUnsafeBufferPointer { return $0 }
        return get(buffer: pointer, offset: offset)
    }
    
    private func get(offset: Int, count: Int) -> Data? {
        guard let buffer = self.buffer else { return nil }
        return buffer.get(offset: offset, count: count)
    }
    
    private func write(offset: Int, byte: UInt8) {
        guard let buffer = self.buffer else { return }
        buffer.write(offset: offset, byte: byte)
    }
    
    
    private func write(offset: Int, bytes: UInt16) {
        guard let buffer = self.buffer else { return }
        buffer.write(offset: offset, bytes: bytes)
    }
    
    private func write(offset: Int, bytes: UInt32) {
        guard let buffer = self.buffer else { return }
        buffer.write(offset: offset, bytes: bytes)
    }
    
    private func write(offset: Int, bytes: Data) {
        guard let buffer = self.buffer else { return }
        buffer.write(offset: offset, bytes: bytes)
    }
    
    private func writeZeroPadding(offset: Int, count: Int) {
        guard let buffer = self.buffer else { return }
        buffer.writeZeroPadding(offset: offset, length: count)
    }
}

extension RTPPacket: CustomStringConvertible {
    public var description: String {
        return """
rtp packet: [payload type: \(payloadType)], [marker: \(marker)], [seq: \(sequnceNumber)], [timestamp: \(timestamp)],
            [ssrc: \(ssrc)]
            [payload offset: \(payloadOffset)],
            [payload size: \(payloadSize)],
"""
    }
}


