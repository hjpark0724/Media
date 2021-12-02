//
//  RTPAudioSender.swift
//  
//
//  Created by HYEONJUN PARK on 2021/04/05.
//

import Foundation
import AudioCodecs
import Utils
import Logging

/*
 * 마이크에서 수신된 음성을 RTP 패킷으로 전달하기 위한 패킷타이저 생성
 * Encoder 타입에 따라 RTPPacketizerAmrWB, 또는 BaseRtpPacketizer 생성 후
 * 해당 패킷타이저로 오디오 코덱의 규격에 맞는 RTP Packet 생성
 */
public class RTPAudioPacketGenerator {
    var timestamp: UInt32 = 0
    let ssrc: UInt32
    let payloadType: UInt8
    var sequenceNumber: UInt16 = 0
    var previoustime: Double = 0
    var buffer = CircularBuffer(initialCapacity: 3048)
    public var onCreate: ((Data) ->())? = nil
    let codec: RTPAudioCodec
    let logger = Logger(label: "RTPAudioPacketGenerator")
    let sendBytes: Int
    let timestampUnit: UInt32
    lazy var encodeQueue: DispatchQueue = { [unowned self] in
        return DispatchQueue(label: "com.encodeQueue.\(self)"/*, qos: .userInteractive*/)
    }()
    
    public init(codec: RTPAudioCodec, payloadType: UInt8) {
        self.codec = codec
        self.sendBytes = codec.codecType == .amrwb ? 640 : 320
        self.timestampUnit = UInt32(self.sendBytes / 2)
        self.ssrc = SSRCGenerator.shared.generate()
        self.payloadType = payloadType
        self.timestamp = 0
        self.sequenceNumber = 0
        
        self.buffer.reset()
    }
    
    public func reset() {
        self.timestamp = 0
        self.sequenceNumber = 0
        self.buffer.reset()
    }
}


extension RTPAudioPacketGenerator : AudioDeviceDelegate {
    public func onDeliverRecordedData(data: Data) {
        buffer.write(data.withUnsafeBytes{return $0})
        encodeQueue.async { [weak self] in
            guard let `self` = self else { return }
            while (self.buffer.count > self.sendBytes) {
                if let data = self.buffer.read(count: self.sendBytes) {
                    if data.count != self.sendBytes {
                        print("unexpected error");
                    }
                    if let encodedData = self.codec.encode(data) {
                        var packetizer : RtpPacketizer? = nil
                        if self.codec.codecType == .amrwb {
                            packetizer = RTPPacketizerAmrWB(payload: encodedData)
                        } else {
                            packetizer = BaseRtpPacketizer(payload: encodedData)
                        }
                        guard let packetizer = packetizer else { return }
                        let rtpPacket = RTPPacket(capacity: 1500)
                        if packetizer.nextPacket(rtpPacket: rtpPacket) {
                            rtpPacket.setSsrc(ssrc: self.ssrc)
                            rtpPacket.setSequenceNumber(seqNo: self.sequenceNumber)
                            rtpPacket.setPayloadType(payloadType: self.payloadType)
                            rtpPacket.setTimestamp(timestamp: self.timestamp)
                            self.sequenceNumber &+= 1
                            self.timestamp &+= self.timestampUnit
                            //print(rtpPacket)
                            if let data = rtpPacket.data {
                                self.onCreate?(data)
                            }
                            
                        }
                    }
                }
            }
        }
    }
}

