//
//  VideoPixelBuffer.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/04.
//

import Foundation
import AVFoundation
import libyuv
class CapturedFrame : NSObject {
    let width: Int
    let height: Int
    var bufferWidth: Int = 0
    var bufferHeight: Int = 0
    var cropWidth: Int = 0
    var cropHeight: Int = 0
    var sampleBuffer: CMSampleBuffer
    var cropX: Int = 0
    var cropY: Int = 0
    var timestampNs: Int64 = 0
    var rotation: VideoRotation = .rotation_0
    init(sampleBuffer: CMSampleBuffer,
         width:Int,
         height:Int,
         cropWidth:Int,
         cropHeight: Int,
         cropX: Int,
         cropY: Int) {
        self.width = width
        self.height = height
        self.sampleBuffer = sampleBuffer
        super.init()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        self.bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        self.bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.cropX = cropX & ~1
        self.cropY = cropY & ~1
        
    }
    
    convenience init(sampleBuffer: CMSampleBuffer) {
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            self.init(sampleBuffer: sampleBuffer,
                      width: CVPixelBufferGetWidth(pixelBuffer),
                      height: CVPixelBufferGetHeight(pixelBuffer),
                      cropWidth: CVPixelBufferGetWidth(pixelBuffer),
                      cropHeight: CVPixelBufferGetHeight(pixelBuffer),
                      cropX: 0,
                      cropY: 0)
        } else {
            self.init(sampleBuffer: sampleBuffer, width:0, height:0, cropWidth:0, cropHeight:0, cropX: 0, cropY: 0)
        }
    }
    
    func requireCropping() -> Bool {
        return cropWidth != bufferWidth || cropHeight != bufferHeight
    }
    
    func requireScaling(width:Int, height:Int) -> Bool {
        return cropWidth != width || cropHeight != height
    }
    
    func bufferSizeForCropAndScale(width: Int, height: Int) -> Int {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return 0 }
        let srcPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        switch srcPixelFormat {
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            fallthrough
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            let srcChromaWidth = (cropWidth + 1) / 2
            let srcChromaHeight = (cropHeight + 1) / 2
            let dstChromaWidth  = (width + 1) / 2
            let dstChromaHeight = (height + 1) / 2
            return srcChromaWidth * srcChromaHeight * 2 + dstChromaWidth * dstChromaHeight * 2
        default:
            return 0
        }
    }
    
    func cropAndScaleTo(output: CVPixelBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let src_pixel_format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        //let dst_pixel_format = CVPixelBufferGetPixelFormatType(output)
        switch src_pixel_format {
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:
            fallthrough
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            cropAndScaleNV12To(output: output)
        case kCVPixelFormatType_32BGRA:
            fallthrough
        case kCVPixelFormatType_32ARGB:
            cropAndScaleARGBTo(output: output)
        default:
            print("not supported pixel format")
        }
    }
    
    
    
    // MARK: private functions
    
    private func cropAndScaleNV12To(output: CVPixelBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ret = CVPixelBufferLockBaseAddress(output, CVPixelBufferLockFlags(rawValue: 0))
        if ret != kCVReturnSuccess {
            print("Failed to lock base address:\(ret)")
        }
        let dst_width = CVPixelBufferGetWidth(output)
        let dst_height = CVPixelBufferGetHeight(output)
        
        guard let dst_y = CVPixelBufferGetBaseAddressOfPlane(output, 0)?.assumingMemoryBound(to: UInt8.self),
              let dst_uv = CVPixelBufferGetBaseAddressOfPlane(output, 1)?.assumingMemoryBound(to: UInt8.self) else {
            return
        }
        let dst_y_stride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
        let dst_uv_stride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard var src_y = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self),
              var src_uv = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)?.assumingMemoryBound(to: UInt8.self) else {
            return
        }
        
        let src_y_stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let src_uv_stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        src_y += src_y_stride * cropY + cropX
        src_uv += src_uv_stride * (cropY / 2) + cropX
        NV12Scale(src_y, Int32(src_y_stride),
                  src_uv, Int32(src_uv_stride),
                  Int32(cropWidth), Int32(cropHeight),
                  dst_y, Int32(dst_y_stride),
                  dst_uv, Int32(dst_uv_stride),
                  Int32(dst_width), Int32(dst_height), kFilterBox)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferUnlockBaseAddress(output, CVPixelBufferLockFlags(rawValue: 0))
    }
    
    private func cropAndScaleARGBTo(output: CVPixelBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ret = CVPixelBufferLockBaseAddress(output, CVPixelBufferLockFlags(rawValue: 0))
        if ret != kCVReturnSuccess {
            print("Failed to lock base address:\(ret)")
        }
        
        let dst_width = CVPixelBufferGetWidth(output)
        let dst_height = CVPixelBufferGetHeight(output)
        guard let dst = CVPixelBufferGetBaseAddress(output)?.assumingMemoryBound(to: UInt8.self) else {
            return
        }
        let dst_stride = CVPixelBufferGetBytesPerRow(output)
        
        guard var src = CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self) else {
            return
        }
        let src_stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4
        src += src_stride * cropY + (cropX * bytesPerPixel)
        
        ARGBScale(src, Int32(src_stride), Int32(cropWidth), Int32(cropHeight),
                  dst, Int32(dst_stride), Int32(dst_width), Int32(dst_height), kFilterBox)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferUnlockBaseAddress(output, CVPixelBufferLockFlags(rawValue: 0))
    }
}
