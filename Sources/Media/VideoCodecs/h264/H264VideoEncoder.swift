//
//  H264VideoEncoder.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/06.
//

import Foundation
import AVFoundation
import VideoToolbox
import Logging
let kNumMillisecsPerSec: Double = 1000
let kNumMicrosecsPerSec: Double = 1000000
let kNumNanosecsPerSec: Double = 1000000000

let kNumMicrosecsPerMillisec = kNumMicrosecsPerSec / kNumMillisecsPerSec
let kNumNanosecsPerMillisec = kNumNanosecsPerSec / kNumMillisecsPerSec
let kNumNanosecsPerMicrosec = kNumNanosecsPerSec / kNumMicrosecsPerSec;

public class EncodeParams {
    let width: Int32
    let height: Int32
    let timestamp: Double
    let rotation: VideoRotation
    
    public init(width: Int32, height: Int32, timestamp: Double, rotation: VideoRotation) {
        self.width = width
        self.height = height
        self.timestamp = timestamp
        self.rotation = rotation
    }
}


public protocol H264VideoEncoderDelegate: AnyObject {
    func wasEncoded(with: H264VideoEncoder, frame: EncodedImage)
}

open class H264VideoEncoder: NSObject {
    let kLimitToAverageBitrateFactor:Float = 1.5
    var compressSession: VTCompressionSession? = nil
    var targetBitrateBps: Int = 0
    var encoderFrameRate: Int = 0
    var width: Int32 = 0
    var height: Int32 = 0
    var logger = Logger(label: "H264VideoEncoder")
    var pixelBufferPool: CVPixelBufferPool? = nil
    public weak var delegate: H264VideoEncoderDelegate? = nil
    var isStarted: Bool = false
    public init(delegate: H264VideoEncoderDelegate? = nil) {
        self.delegate = delegate
    }
    
     deinit {
        //logger.info("deinit")
    }
    public func start(width: Int, height: Int, kbps: Int, fps: Int) -> Bool {
        self.width = Int32(width)
        self.height = Int32(height)
        self.targetBitrateBps = kbps * 1000;
        self.encoderFrameRate = fps
        
        //let status = resetCompresssionWithPixelFormat(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        let status = resetCompresssionWithPixelFormat(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        
        if status != noErr {
            return false
        }
        isStarted = true
        logger.info("start")
        return true
        
    }
    
    public func stop() {
        isStarted = false
        //destroyCompressionSession()
        //logger.info("stop")
    }
    
    public func encode(frame: VideoFrame) {
        if isStarted == false || delegate == nil { return }
        guard let pixelBuffer = frame.pixelBuffer,
              let session = compressSession else { return }
        
        var isKeyFrameRequired = false
        if resetCompressionIfNeedWithFrame(frame: frame) {
            isKeyFrameRequired = true
        }
        
        //키프레임 요청
        var properties: CFDictionary? = nil
        if isKeyFrameRequired {
            let attributes = [
                kVTEncodeFrameOptionKey_ForceKeyFrame as String : kCFBooleanTrue as CFBoolean
            ] as CFDictionary
            properties = attributes
        }
        
        let encodeParam = EncodeParams(width: self.width,
                                       height: self.height,
                                       timestamp: frame.presentationTime,
                                       rotation: frame.rotation)
        let timestamp = Int64(frame.presentationTime * kNumNanosecsPerSec)
        //print("encodedParams:\(encodeParam.width) x \(encodeParam.height)")
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let presentationTime = CMTimeMake(value: timestamp, timescale: Int32(kNumNanosecsPerSec))
        let sourceFrameRef = Unmanaged.passRetained(encodeParam)
        var status = VTCompressionSessionEncodeFrame(session,
                                                     imageBuffer: pixelBuffer,
                                                     presentationTimeStamp: presentationTime,
                                                     duration: CMTime.invalid,
                                                     frameProperties: properties,
                                                     sourceFrameRefcon: sourceFrameRef.toOpaque(),
                                                     infoFlagsOut: nil)
        
        if status == noErr {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
            return
        }
        _ = sourceFrameRef.takeRetainedValue()
        // 에러 처리
        if status == kVTInvalidSessionErr {
            logger.info("Invalid compression session, ressetting")
            status = resetCompresssionWithPixelFormat(pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer))
        } else if status == kVTVideoEncoderMalfunctionErr {
            logger.info("Encountered video encoder malfunction error. Resetting compression session.")
            status = resetCompresssionWithPixelFormat(pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer))
        } else if status != noErr {
            logger.info("Failed to encode frame with code: \(status)")
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        return
    }
    
    func setBitrateBps(bitrateBps: Int, framerate: Int) {
        if targetBitrateBps != bitrateBps || encoderFrameRate != framerate {
            setEncoderBitrateBps(bitrateBps: bitrateBps, framerate: framerate)
        }
    }
    
    private func destroyCompressionSession() {
        guard let session = compressSession else {
            return
        }
        VTCompressionSessionInvalidate(session)
        compressSession = nil
    }
    
    private func resetCompresssionWithPixelFormat(pixelFormat: OSType) -> OSStatus {
        destroyCompressionSession()
        //logger.info("resetCompresssionWithPixelFormat:\(pixelFormat.string!)")
        let sourceAttributes = [
            kCVPixelBufferOpenGLESCompatibilityKey as String : kCFBooleanTrue as CFBoolean,
            kCVPixelBufferIOSurfacePropertiesKey as String : [:] as CFDictionary,
            kCVPixelBufferPixelFormatTypeKey as String : Int64(pixelFormat),
        ] as CFDictionary
        
        
        //세션 생성
        
        let status = VTCompressionSessionCreate(allocator: nil,
                                                width: width,
                                                height: height,
                                                codecType: kCMVideoCodecType_H264,
                                                encoderSpecification: nil,
                                                imageBufferAttributes: sourceAttributes,
                                                compressedDataAllocator: nil,
                                                outputCallback: H264VideoEncoder.outputCallback,
                                                refcon: Unmanaged.passUnretained(self).toOpaque(),
                                                compressionSessionOut: &compressSession)
        
        if status != noErr {
            logger.info("fail to create compression sesssion: \(status)")
            return status
        }
        
        //인코더 설정
        guard let session = compressSession else { return kVTInvalidSessionErr }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: true as CFTypeRef)
        //Profile id level을 입력 받아 설정할 수 있도록 나중에 변경할 것
        /*
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        */
        
        //VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_3_0)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        //B-Frame 사용을 위한 프레임 재정렬 사용 안함
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: false as CFTypeRef)
        setEncoderBitrateBps(bitrateBps: targetBitrateBps, framerate: encoderFrameRate)
        // KeyFrame 30 frame 또는 1 분당
        VTSessionSetProperty(session, key:kVTCompressionPropertyKey_MaxKeyFrameInterval, value : 30 as CFTypeRef);
        /*
        VTSessionSetProperty(
            session, key:kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 60 as CFTypeRef);
        */
        pixelBufferPool = VTCompressionSessionGetPixelBufferPool(compressSession!)
        return noErr
    }
    
    
    private func setEncoderBitrateBps(bitrateBps: Int, framerate: Int) {
        guard let session = compressSession else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateBps as CFTypeRef);
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: framerate as CFTypeRef)
        
        let dataLimitBytesPerSecondValue: Int64 = Int64(Float(bitrateBps) * (kLimitToAverageBitrateFactor / 8 ))
        let onSecond: Int64 = 1
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [dataLimitBytesPerSecondValue, onSecond] as CFArray)
        targetBitrateBps = bitrateBps
        encoderFrameRate = framerate
    }
    
    

    
    private func resetCompressionIfNeedWithFrame(frame: VideoFrame) -> Bool {
        guard let pixelBuffer = frame.pixelBuffer else {
            return true
        }
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var resetCompression: Bool = false
        if compressSession != nil {
            var sessionPixelFormats: [OSType] = []
            if let attributes = CVPixelBufferPoolGetPixelBufferAttributes(pixelBufferPool!) {
                if let formats = (attributes as NSDictionary)[kCVPixelBufferPixelFormatTypeKey] as? Array<OSType> {
                    sessionPixelFormats.append(contentsOf: formats)
                }
            }
            if !sessionPixelFormats.contains(pixelFormat) {
                resetCompression = true
            }
        } else {
            resetCompression = true
        }
        
        if resetCompression {
            _ = resetCompresssionWithPixelFormat(pixelFormat: pixelFormat)
        }
        return resetCompression
    }
    
    private func createPixelBuffer() -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }
        var pixelBufferUnmanaged:CVPixelBuffer? = nil
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBufferUnmanaged)
        if status != kCVReturnSuccess {
            return nil
        }
        return pixelBufferUnmanaged
    }
    
    
    private static let outputCallback : VTCompressionOutputCallback = {
        (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
        
        if outputCallbackRefCon == nil || sourceFrameRefCon == nil {
            return
        }
        
        let encoder = unsafeBitCast(outputCallbackRefCon, to: H264VideoEncoder.self)
        let encodeParam = Unmanaged<EncodeParams>.fromOpaque(sourceFrameRefCon!).takeRetainedValue()
        encoder.frameWasEncoded(status: status,
                                infoFlags: infoFlags,
                                sampleBuffer: sampleBuffer,
                                width: encodeParam.width,
                                height: encodeParam.height,
                                timestamp: encodeParam.timestamp,
                                rotation: encodeParam.rotation)
        
    }
    
    private func frameWasEncoded(status: OSStatus,
                         infoFlags: VTEncodeInfoFlags,
                         sampleBuffer: CMSampleBuffer?,
                         width: Int32,
                         height: Int32,
                         timestamp: Double,
                         rotation: VideoRotation) {
        
        guard let delegate = self.delegate else { return }
        guard status == noErr else  {
            logger.info("error:\(status)")
            return
        }
        if infoFlags == .frameDropped {
            logger.info("frame dropped")
            return
        }
        guard let sampleBuffer = sampleBuffer else {
            logger.info("sample buffer is nil")
            return
        }
        if !CMSampleBufferDataIsReady(sampleBuffer) {
            logger.info("sample buffer data is not ready")
            return
        }
        //print("encoded frame")
        let isKeyframe = !CFDictionaryContainsKey(
            unsafeBitCast(CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true), 0), to: CFDictionary.self),
            unsafeBitCast(kCMSampleAttachmentKey_NotSync, to: UnsafeRawPointer.self)
        )
        /*
        if isKeyframe {
            print("Generated keyframe")
        }
        */
        guard let annexBBuffer = H264SampleBufferToAnnexBBuffer(sampleBuffer: sampleBuffer, isKeyFrame: isKeyframe) else { return }
        var encodedFrame = EncodedImage(buffer: annexBBuffer)
        encodedFrame.width  = Int(width)
        encodedFrame.height = Int(height)
        encodedFrame.presntationTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        encodedFrame.rotation = rotation
        encodedFrame.isKeyFrame = isKeyframe
        delegate.wasEncoded(with: self, frame: encodedFrame)
    }
}

