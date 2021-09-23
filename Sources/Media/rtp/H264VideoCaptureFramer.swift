//
//  H264VideoCaptureFramer.swift
//  
//
//  Created by HYEONJUN PARK on 2021/03/26.
//

import Foundation
/*
 * H264로 인코딩된 이미지를 받기 위해서는 onFrame() 클로져를 등록
 */
public class H264VideoCaptureFramer {
    var capturerController: CaptureController
    var encoder: H264VideoEncoder = H264VideoEncoder()
    var previousTime: Double = 0
    public var usingVideoRotation: Bool = false
    lazy var frameQueue: DispatchQueue = { [unowned self] in
        return DispatchQueue(label: "com.cybertel.H264VideoCaptureFramer")
       }(
    )
    public var onFrame: ((EncodedImage) -> ())? = nil
    
    public init(capturer: CameraVideoCapturer, usingFrontCamera: Bool) {
        self.capturerController = CaptureController(capturer: capturer, usingFrontCamera: usingFrontCamera)
        capturer.delegate = self
        self.encoder.delegate = self
    }
    
    deinit {
        //print("H264VideoCaptureFramer deinit")
    }
    
    public func start(width: Int, height: Int, kbps: Int, fps: Int) -> Bool {
        var encoderStarted: Bool = false
        if usingVideoRotation == true {
            encoderStarted = encoder.start(width: width, height: height, kbps: kbps, fps: fps)
        } else {
            encoderStarted = encoder.start(width: height, height: width, kbps: kbps, fps: fps)
        }
        if encoderStarted == false { return false }
        capturerController.startCapture(width: width, height: height, fps: fps)
        return true
    }
    
    public func stop() {
        capturerController.stopCapture()
        encoder.stop()
    }
}

extension H264VideoCaptureFramer : CameraVideoCapturerDelegate {
    
    /* 카메라에서 캡쳐된 이미지는 potrait 모드에서 가로로 누워 있어 이를 전송 후 영상을 MTKView 에서
       회전해야 하나 현재 안드로드는 이를 구현하고 있지 않기때문에 안드로이드 앱과 동일하게 해당 영상을
       90도 회전 후 인코딩해서 전송
    */
    public func didCpatureVideoFrame(capturer: CameraVideoCapturer, frame: VideoFrame) {
        // 카메라 캡쳐 와 프레임 회전 스레드를 분리
        frameQueue.async { [weak self] in
            guard let `self` = self else { return }
            if self.encoder.isStarted == false { return }
            if self.usingVideoRotation == true {
                self.encoder.encode(frame: frame)
            } else {
                if let rotate_frame = frame.rotate(rotation: .rotation_90) {
                    self.encoder.encode(frame: rotate_frame)
                }
            }
        }
    }
}


//MARK: H264VideoEncoderDelegate - 캡쳐된 이미지가 인코딩되면 등록된 onFrame 클로져 호출
extension H264VideoCaptureFramer : H264VideoEncoderDelegate {
    public func wasEncoded(with: H264VideoEncoder, frame: EncodedImage) {
        self.onFrame?(frame)
    }
}
