//
//  CameraPreviewView.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/05.
//

import UIKit
import AVKit
public class CameraPreviewView: UIView {
    let CONTEXT_XIB_NAME = "CameraPreviewView"
    @IBOutlet var contentView: UIView!
   
    private var captureSession_: AVCaptureSession? = nil
    public var currentOrientation: UIDeviceOrientation? = nil
    public var supportedRotation: Bool = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public var captureSession: AVCaptureSession? {
        get {
            return captureSession_
        }
        set {
            if captureSession_ == newValue {
                return
            }
            captureSession_ = newValue
            if let preview = self.previewLayer {
                preview.session = captureSession
                setCorrectVideoOrientation()
            }
        }
    }
    
    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        Bundle.module.loadNibNamed(CONTEXT_XIB_NAME, owner: self, options: nil)
        contentView.fixInView(self)
        self.previewLayer?.frame = self.layer.frame
        self.previewLayer?.videoGravity = .resizeAspectFill
        addOrientationObserver()
    }
    
    deinit {
        removeOrientationObserver()
    }
    
    public override final class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = self.layer.frame
        setCorrectVideoOrientation()
    }
    
    var previewLayer : AVCaptureVideoPreviewLayer? {
        return self.layer as? AVCaptureVideoPreviewLayer
    }
    
    private func addOrientationObserver() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(orientationChanged),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }
    
    private func removeOrientationObserver() {
        NotificationCenter.default.removeObserver(self,
                                                  name: UIDevice.orientationDidChangeNotification,
                                                  object: nil)
    }
    
    @objc func orientationChanged(notification: Notification) {
        setCorrectVideoOrientation()
    }
    
    func setCorrectVideoOrientation() {
        if !supportedRotation {
            return 
        }
        let orientation = UIDevice.current.orientation
        guard let layer = self.previewLayer,
              let connection = layer.connection else { return }
        connection.videoOrientation = AVCaptureVideoOrientation.landscapeLeft
        if orientation == currentOrientation {
            return
        }
        if connection.isVideoOrientationSupported {
            switch orientation {
            case .portraitUpsideDown:
                print("orientation: portraitUpsideDown")
                connection.videoOrientation = AVCaptureVideoOrientation.portraitUpsideDown
            case .landscapeRight:
                print("orientation: landscapeRight")
                connection.videoOrientation = AVCaptureVideoOrientation.landscapeLeft
            case .landscapeLeft:
                print("orientation: landscapeLeft")
                connection.videoOrientation = AVCaptureVideoOrientation.landscapeRight
            case .portrait:
                print("orientation: portrait")
                connection.videoOrientation = AVCaptureVideoOrientation.portrait
            default:
                return
            }
        }
        currentOrientation = orientation
    }
}

internal extension UIView {
    func fixInView(_ container: UIView!) -> Void {
        self.translatesAutoresizingMaskIntoConstraints = false;
        self.frame = container.frame;
        container.addSubview(self);
        NSLayoutConstraint(item: self, attribute: .leading, relatedBy: .equal, toItem: container, attribute: .leading, multiplier: 1.0, constant: 0).isActive = true
        NSLayoutConstraint(item: self, attribute: .trailing, relatedBy: .equal, toItem: container, attribute: .trailing, multiplier: 1.0, constant: 0).isActive = true
        NSLayoutConstraint(item: self, attribute: .top, relatedBy: .equal, toItem: container, attribute: .top, multiplier: 1.0, constant: 0).isActive = true
        NSLayoutConstraint(item: self, attribute: .bottom, relatedBy: .equal, toItem: container, attribute: .bottom, multiplier: 1.0, constant: 0).isActive = true
    }
}
