//
//  File.swift
//  
//
//  Created by HYEONJUN PARK on 2021/03/26.
//

import Foundation
import AVFoundation
public protocol VideoStreamer : AnyObject {
    func onFrame(frame: VideoPacket)
}

public protocol VideoStreamerDelegate : AnyObject {
    func onReceive(frame: VideoFrame)
}
public class RTPH264VideoStreamer : VideoStreamer {
    //public var videoView : MTLVideoView? = nil
    private var size: CGSize = .zero
    public weak var delegate: VideoStreamerDelegate? = nil
    private var decoder: H264VideoDecoder = H264VideoDecoder()
    public init() {
        decoder.delegate = self
    }
    
    deinit {
        //print("RTPH264VideoStreamer deinit")
    }
    
    public func onFrame(frame: VideoPacket) {
        decoder.decode(inputImage: frame)
    }
}

extension RTPH264VideoStreamer : H264VideoDecoderDelegate {
    public func wasDecoded(with: H264VideoDecoder, frame: VideoFrame) {
        //print("decode frame:\(frame.width) x \(frame.height)")
        delegate?.onReceive(frame: frame)
    }
}

