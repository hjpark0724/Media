//
//  RTPPacketizerH264.swift
//  
//
//  Created by HYEONJUN PARK on 2021/03/08.

import Foundation
class RTPPacketizerH264: RtpPacketizer {
    static var kNalHeaderSize: Int = 1
    static var kFuAHeaderSize: Int = 2
    static var kLengthFieldSize: Int = 2

    // Bit masks for StapA indicators.
    enum NalDefs : UInt8 {
        case kFBit = 0x80
        case kNriMask = 0x60
        case kTypeMask = 0x1F
        
    }

    // Bit masks for FU (A and B) headers.
    enum FuDefs : UInt8 {
        case kSBit = 0x80
        case kEBit = 0x40
        case kRBit = 0x20
        
    }

    enum PacketizationMode : Int {
        case NonInterleaved
        case SingleNalUnit
    }
    
    struct PacketUnit {
        var fragment: Data
        var isFirst: Bool
        var isLast: Bool
        var isAggregated: Bool
        var header: UInt8
        init(fragment: Data, isFirst: Bool, isLast: Bool, isAggregated: Bool, header: UInt8) {
            self.fragment = fragment
            self.isFirst = isFirst
            self.isLast = isLast
            self.isAggregated = isAggregated
            self.header = header
        }
    }
    
    var inputFragments: [Data] = []
    var packets: [PacketUnit] = []
    var numOfPackets = 0
    let limits: PayloadSizeLimits
    
    init(payload: Data, limits: PayloadSizeLimits, mode: PacketizationMode) {
        self.limits = limits
        super.init()
        guard let buf = payload.withUnsafeBytes({ return $0 }).bindMemory(to: UInt8.self).baseAddress else { return }
        
        for nalu in findNaluIndices(buffer: buf, count: payload.count) {
            inputFragments.append(Data(bytes: buf + Int(nalu.payloadStartOffset), count: Int(nalu.payloadSize)))
        }
        if !self.generatePacket(mode: mode) {
            packets.removeAll()
        }
        inputFragments.removeAll()
    }
    
    func generatePacket(mode: PacketizationMode) -> Bool {
        var i = 0
        while i < inputFragments.count {
            switch mode {
            case .SingleNalUnit:
                if !packetizeSingleNalu(index: i) {
                    return false
                }
                i += 1
            case .NonInterleaved:
                let fragmentLen = inputFragments[i].count
                var singlePacketCapacity = limits.maxPayloadLength
                if inputFragments.count == 1 {
                    singlePacketCapacity -= limits.singlePacketReductionLength
                } else if i == 0 {
                    singlePacketCapacity -= limits.firstPacketReductionLength
                } else if i == inputFragments.count - 1 {
                    singlePacketCapacity -= limits.lastPacketReductionLength
                }
                if fragmentLen > singlePacketCapacity {
                    if !packetizeFuA(index: i) {
                        return false;
                    }
                    i += 1
                } else {
                    //i = packetizeStapA(index: i)
                    if !packetizeSingleNalu(index: i) {
                        return false
                    }
                    i += 1
                }
            }
        }
        return true
    }
    
    private func packetizeFuA(index: Int) -> Bool {
        //한 패킷으로 전달할 수 없는 크기의 fragment 여러 개의 패킷으로 쪼갬
        let fragment = inputFragments[index]
        var limits = self.limits
        limits.maxPayloadLength -= RTPPacketizerH264.kFuAHeaderSize;
        if inputFragments.count != 1 {
            if index == inputFragments.count - 1 { //last packet
                limits.singlePacketReductionLength = limits.lastPacketReductionLength
            } else if index == 0 {
                limits.singlePacketReductionLength = limits.firstPacketReductionLength
            } else {
                limits.singlePacketReductionLength = 0
            }
        }
        if index != 0 {
            limits.firstPacketReductionLength = 0
        }
        if index != inputFragments.count - 1 {
            limits.lastPacketReductionLength = 0
        }
        
        var payloadLeft = fragment.count - RTPPacketizerH264.kNalHeaderSize
        var offset = RTPPacketizerH264.kNalHeaderSize
        let payloadSizes = seperateEqually(payloadLength: payloadLeft, limits: limits)
        if payloadSizes.count == 0 { return false }
        
        for (i, size) in payloadSizes.enumerated() {
            guard let ptr = fragment.withUnsafeBytes({ return $0 }).bindMemory(to: UInt8.self).baseAddress else { return false }
            let partedFragment = Data(bytes: ptr + offset, count: size)
            packets.append(PacketUnit(fragment: partedFragment,
                                      isFirst: i == 0,
                                      isLast: i == payloadSizes.count - 1, isAggregated: false, header: fragment[0]))
            offset += size
            payloadLeft -= size
        }
        numOfPackets += payloadSizes.count
        return true
    }
    
    private func packetizeStapA(index: Int) -> Int {
        //fragment를 한 패킷으로 합침
        var fragmentIndex = index
        var payloadLeft = limits.maxPayloadLength
        if inputFragments.count == 1 {
            payloadLeft -= limits.singlePacketReductionLength
        } else if index == 0 {
            payloadLeft -= limits.firstPacketReductionLength
        } else if index == inputFragments.count - 1 {
            payloadLeft -= limits.lastPacketReductionLength
        }
        var aggregatedNums = 0
        var fragmentHeadersLen = 0
        var fragment = inputFragments[fragmentIndex]
        numOfPackets += 1
        
        let neededPayloadSize : () -> Int  = {
            let fragmentSize = fragment.count + fragmentHeadersLen
            if self.inputFragments.count == 1 {
                return fragmentSize
            }
            if fragmentIndex == self.inputFragments.count - 1 {
                return fragmentSize + self.limits.lastPacketReductionLength
            }
            return fragmentSize
        }
        
        
        while(payloadLeft >= neededPayloadSize()) {
            packets.append(PacketUnit(fragment: fragment, isFirst: aggregatedNums == 0, isLast: false, isAggregated: true, header: fragment[0]))
            payloadLeft -= fragment.count
            payloadLeft -= fragmentHeadersLen
            fragmentHeadersLen = RTPPacketizerH264.kLengthFieldSize
            
            if aggregatedNums == 0 {
                fragmentHeadersLen += RTPPacketizerH264.kNalHeaderSize + RTPPacketizerH264.kLengthFieldSize
            }
            aggregatedNums += 1
            fragmentIndex += 1
            if fragmentIndex == inputFragments.count {
                break;
            }
            fragment = inputFragments[fragmentIndex]
        }
        var packet = packets[packets.count - 1]
        packet.isLast = true
        packets[packets.count - 1 ] = packet
        return fragmentIndex
    }
    
    private func packetizeSingleNalu(index: Int) -> Bool {
        var payloadLeft = limits.maxPayloadLength
        if inputFragments.count == 1 {
            payloadLeft -= limits.singlePacketReductionLength
        } else if index == 0 {
            payloadLeft  -= limits.firstPacketReductionLength
        } else if index == inputFragments.count - 1 {
            payloadLeft -= limits.lastPacketReductionLength
        }
        let fragment = inputFragments[index]
        if payloadLeft < fragment.count {
            return false
        }
        packets.append(PacketUnit(fragment: fragment, isFirst: true, isLast: true, isAggregated: false, header: fragment[0]))
        numOfPackets += 1
        return true
    }
    
    override func nextPacket (rtpPacket: RTPPacket) -> Bool {
        if packets.isEmpty {
            return false
        }
        guard let packet = packets.first else { return false }
        if packet.isFirst && packet.isLast { //Single NalU
            nextSingleNaluPacket(rtpPacket: rtpPacket)
        } else if packet.isAggregated { //StapA
            nextAggregatePacket(rtpPacket: rtpPacket)
        } else { //FuA
            nextFragmentPacket(rtpPacket: rtpPacket)
        }
        rtpPacket.setMarker(marker: packets.isEmpty)
        return true
    }
    
    func nextSingleNaluPacket(rtpPacket: RTPPacket) {
        //print("nextSingleNaluPacket")
        let packet = packets.removeFirst()
        guard let buffer = rtpPacket.buffer else { return }
        buffer.append(data: packet.fragment)
        rtpPacket.payloadSize = packet.fragment.count
    }
    
    func nextAggregatePacket(rtpPacket: RTPPacket) {
        var packet = packets.removeFirst()
        guard let buffer = rtpPacket.buffer else { return }
        let firstByte = (packet.header & (NalDefs.kFBit.rawValue | NalDefs.kNriMask.rawValue)) | NaluType.kStapA.rawValue
        //print("nextAggregatePacket")
        //print("header: \(String(format: "%02x", packet.header))")
        //print("firstByte: \(String(format: "%02x", firstByte))")
        buffer.append(byte: firstByte)
        var index = RTPPacketizerH264.kNalHeaderSize
        var isLast = packet.isLast
        
        //현재 패킷이 aggregated 타입
        while(packet.isAggregated) {
            let fragment = packet.fragment
            //print("fragment: \(fragment.hexDescription)")
            //print("fragment: \(fragment.count)")
            buffer.append(bytes: UInt16(fragment.count))
            index += RTPPacketizerH264.kLengthFieldSize
            buffer.append(data: fragment)
            index += fragment.count
            if(isLast) {
                break;
            }
            //다음 패킷으로 변경
            packet = packets.removeFirst()
            isLast = packet.isLast
        }
        rtpPacket.payloadSize = index
    }
    
    func nextFragmentPacket(rtpPacket: RTPPacket) {
        let packet = packets.removeFirst()
        let fu_indicator = (packet.header & (NalDefs.kFBit.rawValue | NalDefs.kNriMask.rawValue)) | NaluType.kFuA.rawValue
        
        var fu_header: UInt8 = 0
        fu_header |= packet.isFirst ? FuDefs.kSBit.rawValue : 0
        fu_header |= packet.isLast ? FuDefs.kEBit.rawValue : 0
        let type = packet.header & NalDefs.kTypeMask.rawValue
        fu_header |= type
       // print("nextFragmentPacket")
        //print("fu_indicator:\(fu_indicator)")
        //print("fun_header:\(fu_header)")
        
        guard let buffer = rtpPacket.buffer else { return }
        buffer.append(byte: fu_indicator)
        buffer.append(byte: fu_header)
        buffer.append(data: packet.fragment)
        rtpPacket.payloadSize  = RTPPacketizerH264.kFuAHeaderSize + packet.fragment.count
    }
}
