//
//  RTPDePacketizerAmrWB.swift
//  
//
//  Created by HYEONJUN PARK on 2021/04/05.
//

import Foundation
import AudioCodecs
import Utils
import AVFoundation
import Logging
public class RTPAudioPacketFramer {
    var prevSeq: UInt16 = 0
    var isFirst: Bool = true
    let depacketizer: RTPAudioDepacketizer
    let logger = Logger(label: "RTPAudioPacketFramer")
    public init(codecType: AudioCodecType) {
        switch codecType {
        case .amrwb:
            depacketizer = RTPDepacketizerAmrWB()
        case .g711:
            depacketizer = RTPDepacketizerG711()
        @unknown default:
            fatalError("UnSuppoted AudioCodec")
        }
    }
    public func reset() {
        isFirst = true
    }
    
    public func received(data: Data) -> AudioPacket? {
        let packet = RTPPacket(capacity: 1500)
        if !packet.parse(data: data) {
            logger.error("packet parse fail")
            return nil
        }
       
        if !isFirst {
            let diff = Int(packet.sequnceNumber) - Int(prevSeq)
            if diff == 0 {
                logger.warning("duplicate packet: prev:\(prevSeq) cur:\(packet.sequnceNumber)")
                return nil
            } else if diff > 1 {
                logger.warning("loss packet: [seq:\(prevSeq)]:\(packet.sequnceNumber - prevSeq)")
            } else if  prevSeq != 65535 && diff < 0 {
                logger.warning("late packet: \(prevSeq) cur:\(packet.sequnceNumber)")
            }
        }else {
            isFirst = false
        }
        
        prevSeq = packet.sequnceNumber
        let cmtime = CMTime(value: CMTimeValue(packet.timestamp), timescale: 16000)
        let timestamp: Int = Int(cmtime.seconds * 1000)
        if let data = depacketize(rtpPacket: packet) {
            return AudioPacket(timestamp: timestamp, data: data)
        } else {
            logger.error("fail to create audio packet")
        }
        return nil
    }
    
    private func depacketize(rtpPacket : RTPPacket) -> Data? {
        guard let payloadPtr = rtpPacket.payloadLocation(), rtpPacket.payloadSize > 0 else { return nil }
        let payload = Data(bytes: payloadPtr, count: rtpPacket.payloadSize)
        //print("payload size:\(payload.count) rtpPackt:\(rtpPacket.payloadSize)")
        return depacketizer.parse(payload: payload)
        //return nil
    }
}


public protocol RTPAudioDepacketizer {
    func parse(payload: Data) -> Data
}

public class RTPDepacketizerG711: RTPAudioDepacketizer {
    public func parse(payload: Data) -> Data {
        return payload
    }
}

public class RTPDepacketizerAmrWB : RTPAudioDepacketizer {
    public func parse(payload: Data) -> Data {
        var data = payload
        data.removeFirst()
        return data
    }
}


