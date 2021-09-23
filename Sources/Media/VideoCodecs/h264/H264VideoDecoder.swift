//
//  H264VideoDecoder.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/07.
//

import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia
import Logging
public protocol H264VideoDecoderDelegate: AnyObject {
    func wasDecoded(with: H264VideoDecoder, frame: VideoFrame)
}

public class DecodeParams {
    let rotation: VideoRotation
    public init(rotation: VideoRotation) {
        self.rotation = rotation
    }
}

public class H264VideoDecoder : NSObject {
    var memoryPool: CMMemoryPool
    var decompressionSession: VTDecompressionSession? = nil
    var videoFromat: CMVideoFormatDescription? = nil
    let logger = Logger(label: "H264VideoDecoder")
    public weak var delegate: H264VideoDecoderDelegate? = nil
    
    public init(delegate: H264VideoDecoderDelegate) {
    
        self.delegate = delegate
        memoryPool = CMMemoryPoolCreate(options: nil)
        super.init()
    }
    
    public override init() {
        self.delegate = nil
        memoryPool = CMMemoryPoolCreate(options: nil)
        super.init()
    }
    
    public func decode(inputImage: VideoPacket) {
        if inputImage.data.isEmpty {
            //logger.error("image is empty")
            return
        }
        guard let annexBBuffer = inputImage.data.withUnsafeBytes({ $0.bindMemory(to: UInt8.self).baseAddress })  else { return }
        //VideoFormatDescription 생성 -> SPS, PPS 가 있는 경우
        if let inputFormat = createVideoForamtDescription(buffer: annexBBuffer, count: inputImage.data.count) {
            //해당 포맷이 이전 포맷과 동일하지 않다면 세션 리셋
            if !CMFormatDescriptionEqual(inputFormat, otherFormatDescription: videoFromat) {
                //logger.info("format: \(inputFormat)")
                videoFromat = inputFormat
                resetDecompressionSession()
            }
        }
        
        if videoFromat == nil {
            logger.error("missing video format. keyframe is required")
            return
        }
        let decodeParam = DecodeParams(rotation: inputImage.rotation)
        guard let session = decompressionSession else { return }
        var sampleBuffer: CMSampleBuffer? = nil
        //AnnexB 버퍼를 CMSampleBuffer 변환
        let presentaionTimestamp = Double(inputImage.presentationTimestamp) / 1000.0
        if !H264AnnexBBufferToCMSampleBuffer(buffer: inputImage.data,
                                             video_format: videoFromat!,
                                             presentationTime: presentaionTimestamp,
                                             out_sample_buffer: &sampleBuffer,
                                             memory_pool: memoryPool) {
            logger.error("fail to create H264AnnexBBufferToCMSampleBuffer")
            return
        }
        
        let frameFlags: VTDecodeFrameFlags = [
            ._EnableAsynchronousDecompression,
            ._EnableTemporalProcessing
        ]
        let frameRefcon = Unmanaged.passRetained(decodeParam)
        var infoFlags = VTDecodeInfoFlags(rawValue: 0)
        let status = VTDecompressionSessionDecodeFrame(session,
                                                       sampleBuffer: sampleBuffer!,
                                                       flags: frameFlags,
                                                       frameRefcon: frameRefcon.toOpaque(),
                                                       infoFlagsOut: &infoFlags)
        if status != noErr {
            logger.error("VTDecompressionSessionDecodeFrame fail: \(status)")
            _ = frameRefcon.takeRetainedValue()
            resetDecompressionSession()
        }
        /*
        if #available(iOS 13.0, *) {
            logger.info("\(videoFromat!.dimensions.width) x \(videoFromat!.dimensions.height)")
        }
        */
    }
    
    func resetDecompressionSession() {
        destroyDecompressionSession()
        guard let videoFormat = self.videoFromat else { return }
        let pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange //NV12
        //let pixelFormat = kCVPixelFormatType_32BGRA
        let attributes: [NSString: AnyObject] = [
            kCVPixelBufferPixelFormatTypeKey : NSNumber(value: pixelFormat),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as  AnyObject,
            kCVPixelBufferOpenGLESCompatibilityKey: NSNumber(booleanLiteral: true)
        ]
        
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: callback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                     formatDescription: videoFormat,
                                     decoderSpecification: nil,
                                     imageBufferAttributes: attributes as CFDictionary,
                                     outputCallback: &outputCallback,
                                     decompressionSessionOut: &decompressionSession)
        if status != noErr {
            logger.error("Failed to create decompression session: \(status)")
            return
        }
        
        if let session = decompressionSession {
            VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        }
        
    }
    
    func destroyDecompressionSession() {
        guard let session = decompressionSession  else {
            return
        }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        VTDecompressionSessionInvalidate(session)
        decompressionSession = nil
        videoFromat = nil 
    }
    
    private var callback: VTDecompressionOutputCallback = {(decompressionOutputRefCon: UnsafeMutableRawPointer?, param: UnsafeMutableRawPointer?, status: OSStatus, infoFlags: VTDecodeInfoFlags, imageBuffer: CVBuffer?, presentationTimeStamp: CMTime, duration: CMTime) in
        let decoder = Unmanaged<H264VideoDecoder>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
        let decodeParams = Unmanaged<DecodeParams>.fromOpaque(param!).takeRetainedValue()
        
        if status != noErr {
            //decoder.logger.error("Failed to decode frame. status: \(status)")
            return
        }
        //print("decode: \(presentationTimeStamp.seconds), duration: \(duration.seconds) infoFlags: \(infoFlags)")
        decoder.didOutputForSession(status, infoFlags: infoFlags, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, duration: duration, rotation: decodeParams.rotation)
    }
    
    
    func didOutputForSession(_ status: OSStatus, infoFlags: VTDecodeInfoFlags, imageBuffer: CVImageBuffer?, presentationTimeStamp: CMTime, duration: CMTime,
                             rotation: VideoRotation) {
        guard let imageBuffer = imageBuffer, status == noErr else { return }
        
        let videoFrame = VideoFrame(pixelBuffer: imageBuffer, presentationTime: presentationTimeStamp.seconds)
        videoFrame.rotation = rotation
        delegate?.wasDecoded(with: self, frame: videoFrame)
        //print("decode: \(videoFrame.presentationTime), duration: \(duration.seconds) infoFlags: \(infoFlags), formatType = \(formatType.string!)")
    }
}
