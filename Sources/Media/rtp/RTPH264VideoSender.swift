//
//  RTPH264VideoSender.swift
//  
//
//  Created by HYEONJUN PARK on 2021/03/12.
//

import Foundation
import Utils
fileprivate let kVideoPayloadTypeFrequency: UInt32 = 90000;
fileprivate let kMsToVideoTimestamp = kVideoPayloadTypeFrequency / 1000;


/*
public protocol RTPVideoSender : class {
    var timestamp: UInt32 { get  }
    var ssrc: UInt32 { get }
    var payloadType: UInt8 { get}
    var sequenceNumber: UInt16 { get }
    var onCreated:((Data) -> ())? { get }
    
    func start() -> Bool
    func stop()
}
*/

public class RTPH264VideoSender {
    let limit = RtpPacketizer.PayloadSizeLimits()
    var timestamp: UInt32 = 0
    var ssrc: UInt32
    var payloadType: UInt8 = 100
    var sequenceNumber: UInt16 = 0
    let packetizationMode : RTPPacketizerH264.PacketizationMode = .NonInterleaved
    var previousTime: Double = 0
    var framer: H264VideoCaptureFramer
    let usingVideoRotation: Bool
    public var captureController : CaptureController {
        get {
            return framer.capturerController
        }
    }
    
    //onFrame 내부에서 RTPPacket을 생성 후 호출됨
    public var onCreated:((Data) -> ())? = nil
    
    public init(framer: H264VideoCaptureFramer, usingVideoRotation: Bool) {
        self.framer = framer
        self.usingVideoRotation = usingVideoRotation
        self.ssrc = SSRCGenerator.shared.generate()
        self.framer.usingVideoRotation = usingVideoRotation
    }
    
    deinit {
        //print("RTPH264VideoSender deinit")
        SSRCGenerator.shared.release(ssrc: self.ssrc)
    }
    
    //H264VideoCaptureFramer의 start를 호출해 카메라 캡쳐를 시작하고, 인코딩된 영상을 받기 위해
    // onFrame closure 등록 
    public func start(width: Int, height: Int, kbps: Int, fps: Int) -> Bool {
        //인코딩된 이미지가 생성되면 framer에서 호출
        self.framer.onFrame = { [weak self] frame  in
            guard let `self` = self else { return }
            //print("Encoded Frame: \(frame.buffer.count)")
            guard let onCreated = self.onCreated else { return }
            let packetizer = RTPPacketizerH264(payload: frame.buffer, limits: self.limit, mode: self.packetizationMode)
            let numOfPackets = packetizer.numOfPackets
            if self.previousTime != 0 {
                let diff = UInt32((frame.presntationTimestamp - self.previousTime) * 1000)
                self.timestamp &+= (diff * kMsToVideoTimestamp)
            }
            self.previousTime = frame.presntationTimestamp
            for _ in 0..<numOfPackets {
                let rtpPacket = RTPPacket(capacity: 1500)
                rtpPacket.setSsrc(ssrc: self.ssrc)
                rtpPacket.setSequenceNumber(seqNo: self.sequenceNumber)
                rtpPacket.setPayloadType(payloadType: self.payloadType)
                rtpPacket.setTimestamp(timestamp: self.timestamp)
                
                if self.usingVideoRotation {
                    let ptr = rtpPacket.AllocateExtension(id: VideoOrientation.kId.rawValue, length: VideoOrientation.valueSizeBytes)
                    _ = VideoOrientation.write(data: ptr, rotation: frame.rotation)
                }
                
                if !packetizer.nextPacket(rtpPacket: rtpPacket) {
                    return
                }
                self.sequenceNumber &+= 1
                guard let data = rtpPacket.data else { return }
                onCreated(data)
            }
        }
        
        return self.framer.start(width: width, height: height, kbps: kbps , fps: fps)
    }
    
    public func stop() {
        self.framer.onFrame = nil
        self.framer.stop()
    }
}
