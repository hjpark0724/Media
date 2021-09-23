//
//  AudioSessionConfiguration.swift
//
//
//  Created by HYEONJUN PARK on 2020/12/11.
//

import Foundation
import AVFoundation
let kAudioSessionPreferredNumberOfChannels: UInt32 = 1
//let kAudioSessionHighPerformanceSampleRate: Double = 48000.0
let kAudioSessionLowComplexitySampleRate: Double = 16000.0
let kAudioSessionHighPerformanceIOBufferDuration: Double = 0.02
let kAudioSessionLowComplexityIOBufferDuration: Double = 0.08;

public class AudioSessionConfiguration {
    public var category: AVAudioSession.Category
    public var categoryOptions: AVAudioSession.CategoryOptions
    public var mode : AVAudioSession.Mode
    public var sampleRate: Double
    public var ioBufferDuration: TimeInterval
    public var inputNumberOfChannels: UInt32
    public var outputNumberOfChannels: UInt32
    public init() {
        category = .playAndRecord
        categoryOptions = [.allowBluetooth, .duckOthers, .defaultToSpeaker]
        mode = .default
        //sampleRate = kAudioSessionHighPerformanceSampleRate
        sampleRate = 16000.0
        ioBufferDuration = kAudioSessionLowComplexityIOBufferDuration
        //ioBufferDuration = kAudioSessionHighPerformanceIOBufferDuration
        inputNumberOfChannels = kAudioSessionPreferredNumberOfChannels
        outputNumberOfChannels = kAudioSessionPreferredNumberOfChannels
    }
}

