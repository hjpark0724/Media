//
//  EncodedImage.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/08.
//

import Foundation
public struct EncodedImage {
    var width: Int = 0
    var height: Int = 0
    var isKeyFrame: Bool = false
    var presntationTimestamp: Double = 0
    var rotation: VideoRotation = .rotation_0
    var buffer: Data //AnnexB type
    public init(buffer: Data) {
        self.buffer = buffer
    }
}
