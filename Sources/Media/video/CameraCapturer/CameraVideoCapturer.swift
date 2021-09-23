//
//  CameraCapturer.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/03.
//

import UIKit
import AVFoundation
import Logging
var supportedPixelFormats :NSOrderedSet {
    return NSOrderedSet(objects: //kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange //420v
                        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange  // 420f

                 //kCVPixelFormatType_32BGRA, //BGRA
                 //kCVPixelFormatType_32ARGB
    )
}


public protocol CameraVideoCapturerDelegate: AnyObject {
    func didCpatureVideoFrame(capturer: CameraVideoCapturer, frame: VideoFrame);
}

let kNanosecondsPerSecond: Int64 = 1000000000

public class CameraVideoCapturer : NSObject {
    var orientation: UIDeviceOrientation = .portrait
    var videoDataOutput: AVCaptureVideoDataOutput? = nil
    public var captureSession: AVCaptureSession?  = nil
    var currentDevice: AVCaptureDevice? = nil
    weak var delegate : CameraVideoCapturerDelegate? = nil
    var preferredOutputPixelFormat : FourCharCode? = nil
    var outputPixelFormat: FourCharCode? = nil
    var rotation: VideoRotation = .rotation_0
    var isRunning: Bool = false
    let logger = Logger(label: "CameraVideoCapturer")

    lazy var capturerQueue: DispatchQueue = { [unowned self] in
        return DispatchQueue(label: "com.cybertel.CameraVideoCapturer")
       }()
    static var captureDevices : [AVCaptureDevice] {
        get {
            return AVCaptureDevice.DiscoverySession.init(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
        }
    }
    
    static func supportedFormatFor(device: AVCaptureDevice) -> [AVCaptureDevice.Format] {
        return device.formats
    }
    

    public init(delegate: CameraVideoCapturerDelegate?, captureSession: AVCaptureSession) {
        super.init()
        //logger.info("init CameraVideoCapturer")
        self.delegate = delegate
        self.captureSession = captureSession
        if !self.setupCaptureSession(captureSession: captureSession) {
            logger.error("fail to setupCaptureSession")
            return
        }
        
        let center = NotificationCenter.default
        // 디바이스 방향 전환
        center.addObserver(self,
                           selector: #selector(didChangeDeviceOrientation),
                           name: UIDevice.orientationDidChangeNotification,
                           object: nil)
        // 카메라 캡쳐 인터럽션
        center.addObserver(self,
                           selector: #selector(handleCaptureSessionInterruption),
                           name: NSNotification.Name.AVCaptureSessionWasInterrupted,
                           object: nil)
        // 카메라 캡채 인터럽션 종료
        center.addObserver(self,
                           selector: #selector(handleCaptureSessionInterruptionEnded),
                           name: NSNotification.Name.AVCaptureSessionInterruptionEnded,
                           object: nil)
        
        // 백그라운드에서 포그라운드로 전환
        center.addObserver(self,
                           selector: #selector(handleApplicationDidBecomeActive),
                           name: UIApplication.didBecomeActiveNotification,
                           object: UIApplication.shared)
        // 캡쳐 세션 에러
        center.addObserver(self,
                           selector:#selector(handleCaptureSessionRuntimeError),
                           name:NSNotification.Name.AVCaptureSessionRuntimeError,
                           object: captureSession)
        // 캡쳐 세션 시작
        center.addObserver(self,
                           selector:#selector(handleCaptureSessionDidStartRunning),
                           name:NSNotification.Name.AVCaptureSessionDidStartRunning,
                           object: captureSession)
        // 캡쳐 세션 종료
        center.addObserver(self,
                           selector:#selector(handleCaptureSessionDidStopRunning),
                           name:NSNotification.Name.AVCaptureSessionDidStopRunning,
                           object: captureSession);
    }
    
    public convenience init(delegate: CameraVideoCapturerDelegate?) {
        self.init(delegate: delegate, captureSession: AVCaptureSession())
    }
    
    public override convenience init() {
        self.init(delegate: nil, captureSession: AVCaptureSession())
    }
    /*
    deinit {
        logger.info("deinit")
    }
    */
    func setupCaptureSession(captureSession: AVCaptureSession) -> Bool {
        //캡쳐 세션 설정
        captureSession.sessionPreset = AVCaptureSession.Preset.inputPriority
        captureSession.usesApplicationAudioSession = false
        //비디오 출력 데이터 설정
        setupVideoDataOutput()
        //설정된 비디오 출력을 캡쳐 세션에 추가
        guard let output = videoDataOutput else { return false }
        if !captureSession.canAddOutput(output) {
            logger.error("fail to add output: can't not add output")
            return false
        }
        captureSession.addOutput(output)
        self.captureSession = captureSession
        return true
    }
    
    func startCapture(device: AVCaptureDevice, format: AVCaptureDevice.Format, fps: Int, completion: ((Error) -> Void)?) {
        do {
            DispatchQueue.main.async {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            }
            self.currentDevice = device;
            try self.currentDevice?.lockForConfiguration()
        } catch {
            logger.error("\(error)")
            completion?(error)
        }
        logger.info("start Camera Capture: \(Thread.current.threadName)")
        reconfigureCaptureSessionInput()
        updateOrientation()
        updateDeviceCaptureFormat(format: format, fps: fps)
        updateVideoDataOutputPixelFormat(format: format)
        captureSession?.startRunning()
        currentDevice?.unlockForConfiguration()
        isRunning = true
    }
    
    func stopCapture() {
        guard let session = captureSession else { return }
        logger.info("stop Camera Capture: \(Thread.current.threadName)")
        self.currentDevice = nil
        for old in session.inputs {
            session.removeInput(old)
        }
        session.stopRunning()
        
        DispatchQueue.main.async {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        self.isRunning = false
    }
    
    private func setupVideoDataOutput() {
        let videoDataOutput = AVCaptureVideoDataOutput()
        
        let availablePixelFormats = NSMutableOrderedSet(array: videoDataOutput.availableVideoPixelFormatTypes)
        availablePixelFormats.intersect(supportedPixelFormats)
        /*
        let avaialable = videoDataOutput.availableVideoPixelFormatTypes
        
        for format in avaialable {
            print(format.string!)
        }
        */
        if let pixelFormat = availablePixelFormats.firstObject {
            preferredOutputPixelFormat = pixelFormat as? OSType
            outputPixelFormat = preferredOutputPixelFormat
            // 카메라 출력 비디오 포맷 설정 (420v)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(pixelFormat as! OSType)]
            videoDataOutput.alwaysDiscardsLateVideoFrames = false
            videoDataOutput.setSampleBufferDelegate(self, queue: capturerQueue)
            self.videoDataOutput = videoDataOutput
        }
    }
    
    
    // MARK: AVCaptureSession notifications
    @objc func didChangeDeviceOrientation() {
        updateOrientation()
    }
    
    @objc func handleCaptureSessionInterruption(notification: NSNotification) {
        var reasonString: String? = nil
        guard let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? AVCaptureSession.InterruptionReason else { return }
        switch(reason) {
        case .videoDeviceNotAvailableInBackground:
            reasonString = "VideoDeviceNotAvailableInBackground"
        case .audioDeviceInUseByAnotherClient:
            reasonString = "AudioDeviceInUseByAnotherClient"
        case .videoDeviceInUseByAnotherClient:
            reasonString = "VideoDeviceInUseByAnotherClient"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            reasonString = "VideoDeviceNotAvailableWithMultipleForegroundApps"
        default:
            reasonString = "unknown"
        }
        logger.info("capture session interrupted: \(reasonString ?? "" )")
    }
    
    @objc func handleCaptureSessionInterruptionEnded(notification: NSNotification) {
        logger.info("capture session interrupt ended")
    }
    
    
    @objc func handleApplicationDidBecomeActive(notification: NSNotification) {
        if let session = self.captureSession {
            if self.isRunning && !session.isRunning {
                session.startRunning()
            }
        }
    }
    
    @objc func handleCaptureSessionRuntimeError() {
        
    }
    
    @objc func handleCaptureSessionDidStartRunning() {
        logger.info("capture session started")
    }
    
    @objc func handleCaptureSessionDidStopRunning() {
        logger.info("capture session stop")
    }
    
    
    // MARK: private method
    
    
    func updateDeviceCaptureFormat(format: AVCaptureDevice.Format, fps: Int) {
        if let device = currentDevice {
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
        }
    }
    
    func updateVideoDataOutputPixelFormat(format: AVCaptureDevice.Format) {
        var mediaSubType = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        if !supportedPixelFormats.contains(mediaSubType) {
            mediaSubType = preferredOutputPixelFormat!
        }
        if mediaSubType != outputPixelFormat {
            outputPixelFormat = mediaSubType
            print(mediaSubType)
            videoDataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(mediaSubType)]
        }
    }
    
    func reconfigureCaptureSessionInput() {
        guard let device = currentDevice,
              let session = captureSession else { return }
        
        do {
            let input = try AVCaptureDeviceInput.init(device: device)
            session.beginConfiguration()
            //세션에 이전 AVCaptureDeviceInput 제거
            for old in session.inputs {
                session.removeInput(old)
            }
            // 현재 디바이스에 대한 입력을 세션에 추가
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                logger.info("cannot add camera as an input to the session")
                return
            }
            session.commitConfiguration()
        } catch {
            logger.info("reconfigureCaptureSessionInput: \(error)")
        }
    }
    
    func updateOrientation() {
        let orientation = UIDevice.current.orientation
        switch orientation {
        case .portrait: fallthrough
        case .landscapeLeft: fallthrough
        case .landscapeRight: fallthrough
        case .portraitUpsideDown:
            self.orientation = orientation
        default:
            break
        }
    }
}

// MARK: AVCaptureVideoDataOutputSampleBufferDelegate - 비디오 출력 버퍼 delegate
extension CameraVideoCapturer : AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //샘플 버퍼 유효성 검사
        if CMSampleBufferGetNumSamples(sampleBuffer) != 1 ||
            !CMSampleBufferIsValid(sampleBuffer) ||
            !CMSampleBufferDataIsReady(sampleBuffer) {
            return
        }
        //샘플 버퍼에서 CVImageBuffer 가져오기 -> pixelBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let cameraPosition = currentDevice?.position
        var usingFrontCamera: Bool = false
        if cameraPosition != AVCaptureDevice.Position.unspecified {
            usingFrontCamera = AVCaptureDevice.Position.front == cameraPosition
        } else {
            let deviceInput = connection.inputPorts.first?.input as? AVCaptureDeviceInput
            usingFrontCamera = AVCaptureDevice.Position.front == deviceInput?.device.position
        }
        switch self.orientation {
        case .portrait:
            rotation = .rotation_90
        case .portraitUpsideDown:
            rotation = .rotation_270
        case .landscapeLeft:
            rotation = usingFrontCamera ? .rotation_180 : .rotation_0
        case .landscapeRight:
            rotation = usingFrontCamera ? .rotation_0 : .rotation_180
        default:
            rotation = .rotation_90
            break;
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        //print("capturer timestamp:\(timestamp.seconds)")
        let frame = VideoFrame(pixelBuffer: pixelBuffer, presentationTime: timestamp.seconds)
        frame.rotation = rotation
        delegate?.didCpatureVideoFrame(capturer: self, frame: frame)
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let dropReason = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil)
        logger.info("Dropped sample buffer: \(String(describing: dropReason!))")
    }
}
