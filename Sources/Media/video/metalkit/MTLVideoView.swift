//
//  MTLVideoView.swift
//  Media
//
//  Created by HYEONJUN PARK on 2021/03/19.
//

import UIKit
import MetalKit
public class MTLVideoView: UIView {
    let CONTEXT_XIB_NAME = "MTLVideoView"
    @IBOutlet var contentView: UIView!
    @IBOutlet weak var metalView: MTKView!
    
    public var videoFrame: VideoFrame? = nil
    public var videoFrameSize: CGSize = .zero
    var lastFrameTime: Double = 0
    
    var renderer: MTLNV12Renderer? = nil
    
    public var isEnabled: Bool {
        get {
            return !self.metalView.isPaused
        }
        set {
            self.metalView.isPaused = !newValue
        }
    }
    
    public var videoContentMode: UIView.ContentMode {
        get {
            return metalView.contentMode
        }
        set {
            metalView.contentMode = newValue
        }
    }
    
    public override var isMultipleTouchEnabled: Bool {
        get {
            return self.metalView.isMultipleTouchEnabled
        }
        
        set {
            super.isMultipleTouchEnabled = newValue
            self.metalView.isMultipleTouchEnabled = newValue
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        if !self.videoFrameSize.equalTo(.zero) {
            self.metalView.drawableSize = self.drawableSize
        } else {
            self.metalView.drawableSize = self.bounds.size
        }
    }
    
    public var drawableSize: CGSize {
        //let frameSize = self.videoFrameSize
        //guard let frame = videFrame else { return .zero }
        //let landscape = frame.rotation == .rotation_0 || frame.rotation == .rotation_180
        return self.videoFrameSize
    }
    
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        Bundle.module.loadNibNamed(CONTEXT_XIB_NAME, owner: self, options: nil)
        contentView.fixInView(self)
        metalView.delegate =  self
        metalView.contentMode = .scaleAspectFit
    }
    
    public func renderFrame(frame: VideoFrame) {
        if !isEnabled {
            return
        }
        self.videoFrame = frame
    }
    
    
    public func setSize(size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            self.videoFrameSize = size
            let drawableSize = self.drawableSize
            self.metalView.drawableSize = drawableSize
            self.setNeedsLayout()
        }
    }
}

extension MTLVideoView : MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
    
    public func draw(in view: MTKView) {
        guard let frame = self.videoFrame,
              frame.presentationTime != lastFrameTime,
              !view.bounds.isEmpty else { return }
        let pixelFormat = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        if pixelFormat != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
            print("not supported pixel format:\(pixelFormat.string!)")
            return
        }
        
        if self.renderer == nil {
            let renderer = MTLNV12Renderer()
            _ = renderer.addRenderingDestination(view: self.metalView)
            self.renderer = renderer
        }
        renderer?.draw(frame: frame)
        lastFrameTime = frame.presentationTime
    }
    
    public func clear() {
        guard let renderer = self.renderer else { return }
        renderer.drawBlankAndWait()
    }
}
