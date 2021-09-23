//
//  RTPPacketizerAmrWB.swift
//  
//
//  Created by HYEONJUN PARK on 2021/04/05.
//

import Foundation
import AudioCodecs
class RTPPacketizerAmrWB : RtpPacketizer {
    var payload: Data = Data()
    init(payload: Data) {
        self.payload = payload
    }
    
    override func nextPacket (rtpPacket: RTPPacket) -> Bool {
        guard let buffer = rtpPacket.buffer else { return false }
        if payload.isEmpty {
            return false
        }
        buffer.append(byte: 0xF0) //
        buffer.append(data: payload)
        rtpPacket.payloadSize = payload.count + 1
        return true
    }
}
