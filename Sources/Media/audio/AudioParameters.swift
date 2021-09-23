//
//  File.swift
//  
//
//  Created by HYEONJUN PARK on 2020/12/15.
//

import Foundation

public class AudioParameters {
    public static let kBitsPerSample: UInt32 = 16
    
    public var sampleRate: Double = 0
    public var channels: UInt32 = 0
    public var framesPerBuffer: UInt32 = 0
    public var framesPer10msBuffer: UInt32 = 0
    public init() {
        self.sampleRate = 0
        self.channels = 0
        self.framesPerBuffer = 0
        self.framesPer10msBuffer = 0
    }
    public init(sampleRate: Double, channels: UInt32, framesPerBuffer: UInt32) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.framesPerBuffer = framesPerBuffer
        self.framesPer10msBuffer = UInt32(sampleRate / 100)
    }
    
    public func reset(sampleRate: Double, channels: UInt32, framesPerBuffer: UInt32) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.framesPerBuffer = framesPerBuffer
        self.framesPer10msBuffer = UInt32(sampleRate / 100)
    }
    
    public func reset(sampleRate: Double, channels: UInt32, duration: Double) {
        let frames_per_buffer : UInt32 = UInt32(Double(sampleRate) * duration + 0.5)
        self.reset(sampleRate: sampleRate, channels: channels, framesPerBuffer: frames_per_buffer)
    }
    
    public func getBytesPerFrame() -> UInt32 {
        return (channels * AudioParameters.kBitsPerSample) / 8
    }
    
    public func getBytePerBuffer() -> UInt32 {
        return framesPerBuffer * getBytesPerFrame()
    }
    
    public var isValid:Bool { sampleRate > 0 && framesPerBuffer > 0 }
    
    public func getBufferSizeInMilliseconds() -> Double {
        if sampleRate == 0 { return 0.0 }
        return Double(framesPerBuffer) / (sampleRate/1000.0)
    }
    
    public func getBufferSizeInSeconds() -> Double {
        if sampleRate == 0 { return 0.0 }
        return Double(framesPerBuffer) / sampleRate
    }
}
