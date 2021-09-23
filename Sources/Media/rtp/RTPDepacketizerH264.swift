//
//  File.swift
//  
//
//  Created by HYEONJUN PARK on 2021/03/10.
//

import Foundation


fileprivate let kNalHeaderSize = 1;
fileprivate let kFuAHeaderSize = 2;
fileprivate let kLengthFieldSize = 2;
fileprivate let kStapAHeaderSize = kNalHeaderSize + kLengthFieldSize;

// Bit masks for FU (A and B) indicators.
fileprivate enum NalDefs : UInt8 {
    case kFBit = 0x80
    case kNriMask = 0x60
    case kTypeMask = 0x1F
    
}

// Bit masks for FU (A and B) headers.
fileprivate enum FuDefs : UInt8 {
    case kSBit = 0x80
    case kEBit = 0x40
    case kRBit = 0x20
}

struct NaluInfo {
    var type: UInt8 = 0
    var offset: Int = 0
    var size: Int = 0
}


struct ParsedPayload {
    enum PacketizationType {
        case kH264StapA
        case kH264SingleNalU
        case kH264FuA
    }
    
    var type: NaluType = .kSlice
    var isFirstPacketInFrame: Bool = false
    var packetizationType: PacketizationType = .kH264SingleNalU
    var payload: Data
    
    init(payload: Data) {
        self.payload = payload
    }
}

extension ParsedPayload : CustomStringConvertible {
    var description: String {
        return "[payload] type: \(type), packetization_mode: \(packetizationType) fisrt: \(isFirstPacketInFrame) size:\(payload.count)"
    }
}

class RTPDepacketizerH264 {
    func parse(_ payload : UnsafePointer<UInt8>, count: Int) -> [ParsedPayload] {
        let naltype = payload[0] & NalDefs.kTypeMask.rawValue
        if naltype == NaluType.kFuA.rawValue {
            return parseFuaNalu(payload, count: count)
        } else  {
            return processStapAOrSingleNalu(payload, count: count)
        }
    }
    
    func parseFuaNalu(_ payload: UnsafePointer<UInt8>, count: Int) -> [ParsedPayload]{
        var parsedPayloads:[ParsedPayload] = []
        if count < kFuAHeaderSize {
            return parsedPayloads
        }
        let fnri = payload[0] & (NalDefs.kFBit.rawValue | NalDefs.kNriMask.rawValue) // 상위 3비트
        guard let nalType = NaluType(rawValue: payload[1] & NalDefs.kTypeMask.rawValue) else { // 하위 5 비트
            return parsedPayloads
        }
        
        let firstFragment = ((payload[1] & FuDefs.kSBit.rawValue) > 0)
        //var parsedPayload = ParsedPayload(payload: Data(bytes: payload + kFuAHeaderSize, count: count - kFuAHeaderSize)
        
       // print(String(format: "first: 0x%02x", data[0]))
        var parsedPayload: ParsedPayload
        if firstFragment {
            let original_nal_header = fnri | nalType.rawValue //nal header
            var data = Data(capacity: count - kNalHeaderSize)
            data.append(original_nal_header)
            data.append(payload + kFuAHeaderSize, count: count - kFuAHeaderSize)
            parsedPayload = ParsedPayload(payload: data)
            parsedPayload.isFirstPacketInFrame = true
        } else {
            let data = Data(bytes: payload + kFuAHeaderSize, count: count - kFuAHeaderSize)
            parsedPayload = ParsedPayload(payload: data)
            parsedPayload.isFirstPacketInFrame = false
        }
        parsedPayload.packetizationType = .kH264FuA
        parsedPayload.type = nalType
        parsedPayloads.append(parsedPayload)
        return parsedPayloads
    }
    
    func processStapAOrSingleNalu(_ payload: UnsafePointer<UInt8>, count: Int) -> [ParsedPayload]{
        let nalu_start = payload + kNalHeaderSize
        let nalu_length = count - kNalHeaderSize
        var nal_type = NaluType(rawValue: payload[0] & NalDefs.kTypeMask.rawValue)
        var nalu_start_offsets: [Int] = []
        var parsedPayloads: [ParsedPayload] = []
        if nal_type == nil { return parsedPayloads}
        var packetize_mode = ParsedPayload.PacketizationType.kH264StapA
        if nal_type == NaluType.kStapA {
            if count <= kStapAHeaderSize {
                return parsedPayloads
            }
            if !parseStapAStartOffsets(nalu_start, count: nalu_length, offsets: &nalu_start_offsets) {
                return parsedPayloads
            }
            nal_type = NaluType(rawValue: payload[kStapAHeaderSize] & NalDefs.kTypeMask.rawValue)
            if nal_type == nil { return parsedPayloads}
        } else {
            packetize_mode = .kH264SingleNalU
            nalu_start_offsets.append(0)
        }
        
        nalu_start_offsets.append(count + kLengthFieldSize)
        for index in 0..<nalu_start_offsets.count - 1 {
            let start_offset = nalu_start_offsets[index]
            let end_offset = nalu_start_offsets[index + 1] - kLengthFieldSize
            guard let nal_type = NaluType(rawValue: payload[start_offset] & NalDefs.kTypeMask.rawValue) else { return parsedPayloads }
            switch nal_type {
            case .kSps: fallthrough
            case .kPps: fallthrough
            case .kIdr: fallthrough
            case .kSlice:
                var parsedPayload = ParsedPayload(payload: Data(bytes: payload + start_offset, count: end_offset - start_offset))
                parsedPayload.packetizationType = packetize_mode
                parsedPayload.isFirstPacketInFrame = true
                parsedPayload.type = nal_type
                parsedPayloads.append(parsedPayload)
            default:
                break
            }
        }
        return parsedPayloads
    }
    
    func parseStapAStartOffsets(_ payload: UnsafePointer<UInt8>, count: Int, offsets: inout [Int]) -> Bool {
        var remaingLength = count
        var offset: Int = 0
        var nalu_ptr = payload
        while remaingLength > 0 {
            if remaingLength < 2 {
                return false
            }
            var nalu_size: UInt16 = get(loc: nalu_ptr)
            nalu_size = nalu_size.bigEndian
            nalu_ptr += 2
            remaingLength -= 2
            if nalu_size > remaingLength {
                return false
            }
            nalu_ptr += Int(nalu_size)
            remaingLength -= Int(nalu_size)
            offsets.append(offset + kStapAHeaderSize)
            offset += kLengthFieldSize + Int(nalu_size)
        }
        return true
    }
    
    private func get<Element: UnsignedInteger>(loc: UnsafePointer<UInt8>) -> Element {
        return loc.withMemoryRebound(to: Element.self, capacity: 1){$0.pointee}
    }
}
