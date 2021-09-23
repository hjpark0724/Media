//
//  VideoFrame.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/04.
//

import Foundation
import VideoToolbox
import libyuv

let kNV12PixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
let kI420PixelFormat = kCVPixelFormatType_420YpCbCr8PlanarFullRange
public class VideoFrame {
    //인코딩되지 않은 영상 데이터 버퍼
    public var pixelBuffer: CVPixelBuffer!
    public var cropX: Int = 0
    public var cropY: Int = 0
    public var width: Int = 0
    public var height: Int = 0
    public var bufferWidth: Int = 0
    public var bufferHeight: Int = 0
    public var cropWidth: Int = 0
    public var cropHeight: Int = 0
    public var presentationTime: Double
    public var rotation: VideoRotation = .rotation_0
    
    public convenience init(pixelBuffer: CVPixelBuffer, presentationTime: Double) {
        self.init(pixelBuffer: pixelBuffer,
        adpatedWidth: CVPixelBufferGetWidth(pixelBuffer),
        adpatedHeight: CVPixelBufferGetHeight(pixelBuffer),
        cropWidth: CVPixelBufferGetWidth(pixelBuffer),
        cropHeight: CVPixelBufferGetHeight(pixelBuffer),
        cropX: 0,
        cropY: 0,
        presentationTime: presentationTime)
    }
    
    public init(pixelBuffer: CVPixelBuffer,
         adpatedWidth: Int, adpatedHeight: Int,
         cropWidth: Int, cropHeight: Int,
         cropX: Int, cropY: Int, presentationTime: Double) {
        self.width = adpatedWidth
        self.height = adpatedHeight
        self.pixelBuffer = pixelBuffer
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.cropX = cropX & ~1
        self.cropY = cropY & ~1
        self.presentationTime = presentationTime
    }
    
    public func rotate(rotation: VideoRotation) -> VideoFrame? {
        guard let frameBuffer = toI420(rotation: rotation) else { return nil }
        var outPixelBuffer: CVPixelBuffer? = nil
        let attributes : [NSObject:NSNumber] = [
            kCVPixelBufferIOSurfaceOpenGLESFBOCompatibilityKey : true,
            kCVPixelBufferIOSurfaceOpenGLESTextureCompatibilityKey : true,
            kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, frameBuffer.width, frameBuffer.height,
                            kNV12PixelFormat, attributes as CFDictionary, &outPixelBuffer)
        
        guard var outBuffer = outPixelBuffer else {
            return nil
        }
        
        let ret = copyI420ToNV12PixelBuffer(frameBuffer: frameBuffer, pixelBuffer: &outBuffer)
        if ret == false {
            return nil
        }
        let videoFrame = VideoFrame(pixelBuffer: outBuffer, presentationTime: self.presentationTime)
        return videoFrame
    }
    
    private func toI420(rotation: VideoRotation) -> I420Buffer? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        guard let srcY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self),
              let srcUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)?.assumingMemoryBound(to: UInt8.self) else {
            return nil
            
        }
       
        let srcYStride = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
        let srcUVStride = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))
        var bufferWidth: Int
        var bufferHeight: Int
        
        if rotation == .rotation_90 || rotation == .rotation_270 {
            bufferWidth = height
            bufferHeight = width
        } else {
            bufferWidth = width
            bufferHeight = height
        }
        var rotationMode: RotationMode
        switch rotation {
        case .rotation_0:
            rotationMode = RotationMode(rawValue: 0)
        case .rotation_90:
            rotationMode = RotationMode(rawValue: 90)
        case .rotation_180:
            rotationMode = RotationMode(rawValue: 180)
        case .rotation_270:
            rotationMode = RotationMode(rawValue: 270)
        }
        
        let frameBuffer = I420Buffer(width: bufferWidth, height: bufferHeight)
        NV12ToI420Rotate(srcY, srcYStride,
                   srcUV, srcUVStride,
                   &frameBuffer.dataY, frameBuffer.strideY,
                   &frameBuffer.dataU, frameBuffer.strideU,
                   &frameBuffer.dataV, frameBuffer.strideV,
                   Int32(width), Int32(height), rotationMode)
        
        return frameBuffer
    }
}


func copyI420ToNV12PixelBuffer(frameBuffer: I420Buffer, pixelBuffer: inout CVPixelBuffer) -> Bool {
    let cvRet = CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    if cvRet != kCVReturnSuccess {
        return false
    }
    
    guard let dstY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self),
          let dstUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)?.assumingMemoryBound(to: UInt8.self) else {
        return false
    }
    let dstStrideY = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
    let dstStrideUV = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))
    
    let ret = I420ToNV12(&frameBuffer.dataY, frameBuffer.strideY,
                         &frameBuffer.dataU, frameBuffer.strideU,
                         &frameBuffer.dataV, frameBuffer.strideV,
                         dstY, dstStrideY, dstUV, dstStrideUV, Int32(frameBuffer.width), Int32(frameBuffer.height))
    CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    if ret != 0 {
        return false
    }
    return true
}


public class I420Buffer {
    var dataY: [UInt8]
    var dataU: [UInt8]
    var dataV: [UInt8]
    let strideY: Int32
    let strideU: Int32
    let strideV: Int32
    let width: Int
    let height: Int
    init(width: Int, height: Int) {
        self.strideY = Int32(width)
        self.strideU = strideY / 2
        self.strideV = strideU
        self.width = width
        self.height = height
        self.dataY = [UInt8](repeating: 0, count: width * height)
        let uvSize = (width + 1) / 2 * (height + 1) / 2
        self.dataU = [UInt8](repeating: 0, count: uvSize)
        self.dataV = [UInt8](repeating: 0, count: uvSize)
    }
}
