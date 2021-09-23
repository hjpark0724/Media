//
//  AudioEngine.swift
//  
//
//  Created by HYEONJUN PARK on 2021/04/06.
//

import Foundation
import AVFoundation
class AudioEngine {
    private var audioEngine = AVAudioEngine()
    var isRecorded: Bool = false
    func setup() {
        let input = audioEngine.inputNode
        /*
        if #available(iOS 13.0, *) {
            do {
                try input.setVoiceProcessingEnabled(true)
            } catch {
                print("Could not enable voice processing \(error)")
                return
            }
        }
        */
        let voiceFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)
        
        input.installTap(onBus: 0, bufferSize: 640, format: voiceFormat) { buffer, when in
            if buffer.int16ChannelData != nil {
               // let audioBuffer = buffer.audioBufferList.pointee.mBuffers
                //print("buffer")
            }
        }
        audioEngine.prepare()
    }
    
    func start() -> Bool {
        do {
            try audioEngine.start()
            isRecorded = true
            return true
        } catch {
            return false;
        }
    }
}
