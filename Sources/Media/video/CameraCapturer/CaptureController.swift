//
//  CaptureController.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/04.
//

import Foundation
import AVKit
import Logging
public class CaptureController : NSObject {
    var capturer: CameraVideoCapturer
    let logger = Logger(label: "CaptureController")
    public var usingFrontCamera : Bool {
        get {
            return usingFrontCamera_
        }
    }
    
    private var usingFrontCamera_: Bool
    let kFramerateLimit: Float64 = 30.0;
    var width: Int = 0
    var height: Int = 0
    var fps: Int = 0
    
    public init(capturer: CameraVideoCapturer, usingFrontCamera: Bool) {
        self.capturer = capturer
        self.usingFrontCamera_ = usingFrontCamera
        super.init()
    }
    
    public convenience init(capturer: CameraVideoCapturer) {
        self.init(capturer: capturer, usingFrontCamera: true)
    }
    
    public var captureSession: AVCaptureSession? {
        get {
            return capturer.captureSession
        }
    }

    public func startCapture(width: Int, height: Int, fps: Int) {
        startCapture(width: width, height: height, fps: fps, completion: nil)
    }
    
    public func startCapture() {
        startCapture(width: self.width, height: self.height, fps: self.fps)
    }
    public func startCapture(width: Int, height: Int, fps: Int, completion: ((Error) -> Void)?) {
        let position = usingFrontCamera_ ? AVCaptureDevice.Position.front : AVCaptureDevice.Position.back
        let device = findDevice(position: position)
        guard let format = selectFormat(device: device, width: width, height: height) else {
            print("no valid format for device: \(device.debugDescription)")
            return
        }
        //let fps = selectFps(format: format)
        self.width = width
        self.height = height
        self.fps = fps
        capturer.startCapture(device: device, format: format, fps: self.fps, completion: completion)
    }
    
    public func stopCapture() {
        capturer.stopCapture()
    }
    
    public func switchCamera() {
        switchCamera(completion: nil)
    }
    
    public func switchCamera(completion:((Error) -> Void)?) {
        usingFrontCamera_ = !usingFrontCamera_
        startCapture(width: self.width, height: self.height, fps: self.fps, completion: completion)
    }
    
    private func findDevice(position: (AVCaptureDevice.Position)) -> AVCaptureDevice {
        let devices = CameraVideoCapturer.captureDevices
        if let device = devices.first(where: { $0.position == position }) {
            return device
        }
        return devices[0]
    }
    
    private func selectFormat(device: AVCaptureDevice, width: Int ,height: Int) -> AVCaptureDevice.Format? {
        let formats = CameraVideoCapturer.supportedFormatFor(device: device)
        let targetWidth: Int32 = Int32(width)
        let targetHeight: Int32 = Int32(height)
        var currentDiff = Int32.max
        var selectedFormat: AVCaptureDevice.Format?  = nil
        for format in formats {
            let dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            //print("dimension:\(dimension.width) * \(dimension.height)")
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let diff = abs(targetWidth - dimension.width) + abs(targetHeight - dimension.height)
            if diff < currentDiff {
                selectedFormat = format
                currentDiff = diff
            } else if (diff == currentDiff && pixelFormat == capturer.preferredOutputPixelFormat) {
                selectedFormat = format
            }
        }
        if let format  = selectedFormat {
            let dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            logger.info("selectedFormat:\(pixelFormat.string!) (\(dimension.width) * \(dimension.height))")
        }
        return selectedFormat
    }
    
    func selectFps(format: AVCaptureDevice.Format) -> Int {
        var maxSupportedFrameRate: Float64 = 0
        for fps_range in format.videoSupportedFrameRateRanges {
            maxSupportedFrameRate = fmax(maxSupportedFrameRate, fps_range.maxFrameRate)
        }
        return Int(fmin(maxSupportedFrameRate, kFramerateLimit))
    }
}
