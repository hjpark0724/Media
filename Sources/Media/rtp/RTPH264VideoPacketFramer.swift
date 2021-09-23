//
//  RTPVideoReceiver.swift
//  
//
//  Created by HYEONJUN PARK on 2021/03/16.
//

import Foundation
import AVFoundation
import Logging

public class RTPH264VideoPacketFramer {
    let depacketizer = RTPDepacketizerH264()
    var packets: [RTPPacket] = []
    var sps: Data? = nil
    var pps: Data? = nil
    var frame: Data = Data()
    var prevSeq: UInt16 = 0
    var isFirst: Bool = true
    var isPacketLoss: Bool = false
    let kStartBytes: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    let logger = Logger(label: "RTPH264VideoPacketFramer")
    let extensionHeaderMap = ExtensionHeaderMap()
    public var onPacket: ((VideoPacket) -> ())? = nil
    public init() {
    }
    public func reset() {
        sps = nil
        pps = nil
        frame.removeAll()
        prevSeq = 0
        isFirst = true
        packets.removeAll()
    }
    
    public func received(data: Data) {
        let packet = RTPPacket()
        if !packet.parse(data: data) {
            logger.error("rtppacket parse failed")
            return
        }
        
        if !packets.contains(where: {$0.sequnceNumber == packet.sequnceNumber}) {
            insert(of: packet)
            if packet.marker == true {
                let frames = packets.filter{ $0.sequnceNumber <= packet.sequnceNumber}
                if !hasPacketLoss(packets: frames) {
                    frames.forEach {received(rtpPacket:$0)}
                } else {
                    logger.warning("occur packet loss")
                }
                packets.removeSubrange(0..<frames.count)
            }
        }
    }
    
    public func received(rtpPacket: RTPPacket) {
        guard let payload = rtpPacket.payloadLocation(), rtpPacket.payloadSize > 0 else { return }
        let parsedPayloads = depacketizer.parse(payload, count: rtpPacket.payloadSize)
        if parsedPayloads.count == 0 {
            logger.info("fail to depacketize:\n \(rtpPacket)\n \(rtpPacket.data!.hexDescription)")
            return 
        }
        for parsedPayload in parsedPayloads {
            if parsedPayload.type == .kSps {
                if sps != parsedPayload.payload {
                    //logger.info("sps:\(parsedPayload.payload.hexDescription)")
                    sps = parsedPayload.payload
                }
            } else if parsedPayload.type == .kPps {
                if pps != parsedPayload.payload {
                    //logger.info("pps:\(parsedPayload.payload.hexDescription)")
                    pps = parsedPayload.payload
                }
            } else if parsedPayload.type == .kIdr {
                guard let sps = self.sps, let pps = self.pps else {
                    //키 프레임 수신 시 이전 sps, pps 가 없는 경우 NullFrame 전달
                    //logger.info("required spp and pps")
                    if rtpPacket.marker == true {
                        let cmtime = CMTime(value: CMTimeValue(rtpPacket.timestamp), timescale: 90000)
                        let timestamp: Int = Int(cmtime.seconds * 1000)
                        let packet = VideoPacket(timestamp: timestamp, data: Data())
                        onPacket?(packet)
                    }
                    return
                }
                //키 프레임의 첫 번째 payload 인 경우 sps 와 pps 를 추가
                if parsedPayload.isFirstPacketInFrame {
                    frame.removeAll()
                    frame.append(kStartBytes, count: kStartBytes.count)
                    frame.append(sps)
                    frame.append(contentsOf: kStartBytes)
                    frame.append(pps)
                    frame.append(contentsOf: kStartBytes)
                }
                
                frame.append(parsedPayload.payload)
                if rtpPacket.marker == true {
                    if frame.isEmpty { return }
                    let packet = makePacket(rtpPacket: rtpPacket, frame: frame)
                    onPacket?(packet)
                }
            } else if parsedPayload.type == .kSlice {
                if  self.sps == nil ||  self.pps == nil {
                    //키 프레임 수신 시 이전 sps, pps 가 없는 경우 NullFrame 전달
                    if rtpPacket.marker == true {
                        let cmtime = CMTime(value: CMTimeValue(rtpPacket.timestamp), timescale: 90000)
                        let timestamp: Int = Int(cmtime.seconds * 1000)
                        let packet = VideoPacket(timestamp: timestamp, data: Data())
                        onPacket?(packet)
                    }
                    return
                }
                if parsedPayload.isFirstPacketInFrame {
                    frame.removeAll()
                    frame.append(kStartBytes, count: kStartBytes.count)
                }
                frame.append(parsedPayload.payload)
                if rtpPacket.marker == true {
                    if frame.isEmpty { return }
                    let packet = makePacket(rtpPacket: rtpPacket, frame: frame)
                    onPacket?(packet)
                }
            } else {
                logger.error("unknwon type")
            }
        }
    }
    
    private func makePacket(rtpPacket: RTPPacket, frame: Data) -> VideoPacket {
        let cmtime = CMTime(value: CMTimeValue(rtpPacket.timestamp), timescale: 90000)
        //print("presentationTimestamp: \(cmtime.seconds)")
        let timestamp: Int = Int(cmtime.seconds * 1000)
        var packet = VideoPacket(timestamp: timestamp, data: frame)
        var rotation: VideoRotation = .rotation_0
        for extensionInfo in rtpPacket.extensionEntries {
            if let kId = RTPExtensionType(rawValue: Int(extensionInfo.id)) {
                if kId == .kRTPExtensionVideoRotation {
                    VideoOrientation.parse(data: rtpPacket.location(offset: Int(extensionInfo.offset)), rotation: &rotation)
                    packet.rotation = rotation
                }
            }
        }
        return packet
    }
    
    private func hasPacketLoss(packets: [RTPPacket]) -> Bool {
        let isConsecutive = zip(packets, packets.dropFirst()).allSatisfy{ $1.sequnceNumber == $0.sequnceNumber &+ 1 }
        return !isConsecutive
    }
    
    private func insert(of packet: RTPPacket) {
        guard let pos = packets.firstIndex(where:{ abs(Int($0.sequnceNumber) - Int(packet.sequnceNumber)) < 30 && Int($0.sequnceNumber) > packet.sequnceNumber}) else {
            packets.append(packet)
            return
        }
        packets.insert(packet, at: pos)
    }
}
