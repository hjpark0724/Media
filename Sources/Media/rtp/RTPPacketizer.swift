//
//  RTPPacketizer.swift
//  Media
//
//  Created by HYEONJUN PARK on 2021/03/08.
//

import Foundation

class RtpPacketizer {

    struct PayloadSizeLimits {
        var maxPayloadLength = 1200
        var firstPacketReductionLength = 0
        var lastPacketReductionLength = 0
        var singlePacketReductionLength = 0
    }
    
    func seperateEqually(payloadLength: Int, limits: PayloadSizeLimits) -> [Int] {
        var result: [Int] = []
        //해당 페이로드가 최대 가능 페이로드 보다 작은 경우 1개의 패킷으로 전송가능
        if limits.maxPayloadLength >= limits.singlePacketReductionLength + payloadLength {
            result.append(payloadLength)
            return result
        }
        // 수용 가능한 바이트가 1바이트보다 작은 경우 결과는 empty
        if limits.maxPayloadLength - limits.firstPacketReductionLength < 1 ||
            limits.maxPayloadLength - limits.lastPacketReductionLength < 1 {
            return result
        }
        // 실제 총 바이트 =  페이로드 + fist, last 패킷 감소 길이
        let totalBytes = payloadLength + limits.firstPacketReductionLength + limits.lastPacketReductionLength
        
        var leftPackets = (totalBytes + limits.maxPayloadLength - 1) / limits.maxPayloadLength
        
        if leftPackets == 1 {
            leftPackets = 2
        }
        
        if payloadLength < leftPackets {
            return result
        }
        //패킷 당 바이트 수
        var bytesPerPacket = totalBytes / leftPackets
        let num_larger_packets = totalBytes % leftPackets;
        var remainingData = payloadLength
        
        result.reserveCapacity(leftPackets)
        var firstPacket = true
        while remainingData > 0 {
            if leftPackets == num_larger_packets {
                bytesPerPacket += 1
            }
            var currentPacketBytes = bytesPerPacket
            
            if firstPacket {
                if currentPacketBytes > limits.firstPacketReductionLength + 1 {
                    currentPacketBytes -= limits.firstPacketReductionLength;
                } else {
                    currentPacketBytes = 1
                }
            }
            if currentPacketBytes > remainingData {
                currentPacketBytes = remainingData
            }
            if(leftPackets == 2 && currentPacketBytes == remainingData) {
                currentPacketBytes -= 1
            }
            result.append(currentPacketBytes)
            remainingData -= currentPacketBytes
            leftPackets -= 1
            firstPacket = false
        }
        return result
    }
    
    open func nextPacket(rtpPacket: RTPPacket) -> Bool {
        return false 
    }
}

class BaseRtpPacketizer : RtpPacketizer {
    let payload: Data
    init(payload: Data) {
        self.payload = payload
    }
    
    override func nextPacket (rtpPacket: RTPPacket) -> Bool {
        guard let buffer = rtpPacket.buffer else { return false }
        if payload.isEmpty {
            return false
        }
        buffer.append(data: payload)
        rtpPacket.payloadSize = payload.count
        return true
    }
}
