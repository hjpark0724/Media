//
//  VoidProcessingUnit.swift
//  AudioLibrary
//
//  Created by HYEONJUN PARK on 2020/12/10.
//

import Foundation
import AudioToolbox
import Logging
protocol VoiceProcessingUnitDelegate : AnyObject {
    func onDeliverRecordedData(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        numberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
    
    func onGetPlayoutData(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        numberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus
}


class VoiceProcessingUnit {
    enum State {
        case initRequired
        case uninitialized
        case initialized
        case started
    }
    let kOutputBus : AudioUnitElement = 0 //스피커
    let kInputBus : AudioUnitElement = 1 //마이크
    let numberOfChannel: UInt32 = 1
    let bytesPerSample: UInt32 = 2
    let kMaxNumberOfAudioUnitInitializeAttempts : Int = 5
    
    var audioUnit : AudioUnit? = nil
    var state: State  = .initRequired
    weak var delegate: VoiceProcessingUnitDelegate?
    
    let logger = Logger(label: "VoiceProcessingUnit")
    public convenience init() {
        self.init(delegate: nil)
    }
    
    public init(delegate: VoiceProcessingUnitDelegate?) {
        self.delegate = delegate
    }
    
    deinit {
        //logger.info("deinit")
        disposeAudioUnit()
    }
    //오디오 유닛 초기화
    func initilize(sampleRate: Float64) -> Bool {
        var result: OSStatus
        var description = AudioComponentDescription()
        description.componentType = kAudioUnitType_Output
        //description.componentSubType = kAudioUnitSubType_VoiceProcessingIO
        description.componentSubType = kAudioUnitSubType_RemoteIO
        description.componentManufacturer = kAudioUnitManufacturer_Apple
        description.componentFlags = 0
        description.componentFlagsMask = 0
        //logger.info("initialize sample rate: \(sampleRate)")
        guard let audioComponent = AudioComponentFindNext(nil, &description)  else {
            logger.error("fail to AudioComponentFindNext")
            return false
        }
        //오디오 컴포넌트 생성
        result = AudioComponentInstanceNew(audioComponent, &audioUnit)
        if (result != noErr) {
            audioUnit = nil
            logger.error("AudioComponentInstanceNew failed.\(result)")
            return false;
        }
        
        var flag:UInt32 = 1
        var size: UInt32 = UInt32(MemoryLayout<UInt32>.size)
        //입력 버스(마이크) 초기화
        result = AudioUnitSetProperty(
            audioUnit!,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            kInputBus,
            &flag,
            size)
        
        if(result != noErr) {
            logger.error("AudioUnitSetProperty kAudioUnitScope_Input failed.\(result)")
            self.disposeAudioUnit()
            return false
        }
        
        //출력 버스 활성화
        result = AudioUnitSetProperty(
            audioUnit!,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            kOutputBus,
            &flag,
            size)
        
        if(result != noErr) {
            logger.error("AudioUnitSetProperty kAudioUnitScope_Output failed.\(result)")
            self.disposeAudioUnit()
            return false
        }
        
        
        //오디오 포맷 설정
        var format:AudioStreamBasicDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked),
            mBytesPerPacket: numberOfChannel * bytesPerSample, // (16bits * channel) 2bytes
            mFramesPerPacket: 1, // 패킷 당 프레임 수
            mBytesPerFrame: numberOfChannel * bytesPerSample,
            mChannelsPerFrame:  numberOfChannel,
            mBitsPerChannel: 8 * bytesPerSample, //16 bits
            mReserved: 0
        )
        logger.info("input sample rate: \(sampleRate)")
        // 입력버스(마이크의 출력 설정)
        result = AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            kInputBus,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        
        if(result != noErr) {
            logger.error("kAudioUnitProperty_StreamFormat: kInputBus setting failed.\(result)")
            return false
        }
        
        // 출력 버스 (스피커 출력 설정)
        logger.info("output sample rate: \(sampleRate)")
        result = AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            kOutputBus,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        
        if(result != noErr) {
            logger.error("kAudioUnitProperty_StreamFormat: kOutputBus setting failed.\(result)")
            return false
        }
        
        //입력 콜백 설정
        var inputCallback = AURenderCallbackStruct(
            inputProc: onDeliverRecordedData,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        size = UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        result = AudioUnitSetProperty(
            audioUnit!,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            kInputBus,
            &inputCallback,
            size)
        
        if (result != noErr) {
            self.disposeAudioUnit()
            logger.error("kAudioOutputUnitProperty_SetInputCallback failed.\(result)")
            return false
        }
        
        var renderCallback = AURenderCallbackStruct(
            inputProc: onGetPlayoutData,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        
        //출력(스피커) 에 전달 될 오디오 데이터 콜백(출력) 설정
        result = AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Global,
            kOutputBus,
            &renderCallback,
            size)
        
        if(result != noErr) {
            self.disposeAudioUnit()
            logger.error("kAudioUnitProperty_SetRenderCallback failed.\(result)")
            return false
        }
        
        //마이크 출력용 내부 버퍼 사용 버퍼 사용
        flag = 1
        size = UInt32(MemoryLayout<UInt32>.size)
        result = AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_ShouldAllocateBuffer,
            kAudioUnitScope_Output,
            kInputBus,
            &flag,
            size);
        
        if (result != noErr) {
            self.disposeAudioUnit()
            logger.error("kAudioUnitProperty_ShouldAllocateBuffer failed. \(result)")
            return false
        }
        
        
        var failed_initalize_attempts: Int = 0
        result = AudioUnitInitialize(audioUnit!)
        while result != noErr {
            failed_initalize_attempts += 1
            logger.error("attempts to : \(failed_initalize_attempts)")
            if failed_initalize_attempts == kMaxNumberOfAudioUnitInitializeAttempts {
                logger.error("AudioUnitInitialize fail")
                return false
            }
            Thread.sleep(forTimeInterval: 0.1)
            result = AudioUnitInitialize(audioUnit!)
        }
        /*
        var isEnabledAgc: UInt32 = 0
        result = getAGCState(enabled: &isEnabledAgc)
        if result != noErr  {
            logger.info("get audio gain control failed")
        } else if isEnabledAgc == 0 {
            var enable_agc: UInt32 = 1;
            let size = UInt32(MemoryLayout<UInt32>.size)
            result = AudioUnitSetProperty(audioUnit!,
                                          kAUVoiceIOProperty_VoiceProcessingEnableAGC,
                                          kAudioUnitScope_Global, kInputBus, &enable_agc,
                                          size);
            if(result != noErr) {
                logger.error("Fail to enable the built-in AGC.:\(result)")
            }
            result = getAGCState(enabled: &isEnabledAgc)
            if(result != noErr) {
                logger.error("Fail to get AGC state: \(result)")
            }
        }
        */
        logger.info("AudioUnitInitialize")
        state = .initialized
        return true
    }
    
    //오디오 유닛 시작
    func start() -> Bool {
        guard let audioUnit = self.audioUnit else { return false }
        let result = AudioOutputUnitStart(audioUnit)
        if result != noErr {
            logger.error("Fail to start audio unit. Error=\(result)")
            disposeAudioUnit()
            return false
        }
        //logger.info("AudioOuputUnitStarted")
        state = .started
        return true
    }
    
    //오디오 유닛 종료
    func stop() -> Bool {
        guard let audioUnit = self.audioUnit else { return false }
        let result = AudioOutputUnitStop(audioUnit)
        if result != noErr {
            logger.error("Fail to stop audio unit. Error=\(result)")
            return false
        }
        //logger.info("AudioOutputUnitStop")
        state = .initialized
        return true
    }
    
    //오디오 유닛  uninitilize
    func uninitilize() -> Bool {
        guard let audioUnit = self.audioUnit else { return false }
        let result = AudioUnitUninitialize(audioUnit)
        if result != noErr {
            logger.error("Fail to uninitilize audio unit. Error=\(result)")
            return false
        }
        logger.info("AudioUnitUninitialize")
        state = .uninitialized
        return true
    }
    
    func setRecordSampleRate(sampleRate: Float64) -> Bool {
        var format:AudioStreamBasicDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked),
            mBytesPerPacket: numberOfChannel * bytesPerSample, // (16bits * channel) 2bytes
            mFramesPerPacket: 1, // 패킷 당 프레임 수
            mBytesPerFrame: numberOfChannel * bytesPerSample,
            mChannelsPerFrame:  numberOfChannel,
            mBitsPerChannel: 8 * bytesPerSample, //16 bits
            mReserved: 0
        )
        var curSampleRate: Float64 = 0
        var size: UInt32 = 0
        var result = AudioUnitGetProperty(audioUnit!, kAudioUnitProperty_SampleRate, kAudioUnitScope_Output, kInputBus, &curSampleRate, &size)
        if result != noErr {
            logger.error("get sample rate: kInputBus setting failed.\(result)")
        } else {
            logger.info("curSampleRate:\(curSampleRate)")
        }
        
         result = AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            kInputBus,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        if(result != noErr) {
            logger.error("kAudioUnitProperty_StreamFormat: kInputBus setting failed.\(result)")
            return false
        }
        return true
    }
    
    func setPlayOutSampleRate(sampleRate: Float64) -> Bool {
        var format:AudioStreamBasicDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked),
            mBytesPerPacket: numberOfChannel * bytesPerSample, // (16bits * channel) 2bytes
            mFramesPerPacket: 1, // 패킷 당 프레임 수
            mBytesPerFrame: numberOfChannel * bytesPerSample,
            mChannelsPerFrame:  numberOfChannel,
            mBitsPerChannel: 8 * bytesPerSample, //16 bits
            mReserved: 0
        )
        // 출력 버스 (스피커 출력 설정)
        let result = AudioUnitSetProperty(
            audioUnit!,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            kOutputBus,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        
        if(result != noErr) {
            logger.error("kAudioUnitProperty_StreamFormat: kOutputBus setting failed.\(result)")
            return false
        }
        return true
    }
    
    func disposeAudioUnit() {
        guard let audioUnit = self.audioUnit else { return }
        switch(state) {
        case .started:
            _ = stop();
            fallthrough
        case .initialized:
            _ = uninitilize();
            fallthrough
        default:
            break;
        }
        let result = AudioComponentInstanceDispose(audioUnit)
        if result != noErr {
            logger.error("AudioComponentInstanceDispose faild:\(result)")
        }
        self.audioUnit = nil
    }
        
    func getAGCState(enabled: inout UInt32) -> OSStatus {
        guard let audioUnit = self.audioUnit else { return -50 }
        var size = UInt32(MemoryLayout<UInt32>.size)
        let result = AudioUnitGetProperty(audioUnit,
                                          kAUVoiceIOProperty_VoiceProcessingEnableAGC,
                                          kAudioUnitScope_Global,
                                          kInputBus,
                                          &enabled,
                                          &size);
        return result;
    }
    
    func getInputSampleRate(sampleRate: inout Float64) -> OSStatus {
        guard let audioUnit = self.audioUnit else { return -50 }
        var size = UInt32(MemoryLayout<Float64>.size)
        let result = AudioUnitGetProperty(audioUnit,
                                          kAudioUnitProperty_SampleRate,
                                          kAudioUnitScope_Input,
                                          0,
                                          &sampleRate,
                                          &size)
        return result
    }
    
    func getOutputSampleRate(sampleRate: inout Float64) -> OSStatus {
        guard let audioUnit = self.audioUnit else { return -50 }
        var size = UInt32(MemoryLayout<Float64>.size)
        let result = AudioUnitGetProperty(audioUnit,
                                          kAudioUnitProperty_SampleRate,
                                          kAudioUnitScope_Output,
                                          0,
                                          &sampleRate,
                                          &size)
        return result
    }
    
    func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                timestatmp: UnsafePointer<AudioTimeStamp>,
                busNumber: UInt32,
                numberFrames: UInt32,
                ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        guard let audioUnit = self.audioUnit else { return -1 }
        let result = AudioUnitRender(audioUnit, flags, timestatmp, busNumber, numberFrames, ioData)
        if(result != noErr) {
            logger.error("AudioUnitRender failed. \(result)")
        }
        return result
    }
    
    func notifyGetPlayoutData(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        numberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let delegate = delegate else { return 0; }
        return delegate.onGetPlayoutData(flags: flags, timestamp: timestamp, busNumber: busNumber, numberFrames: numberFrames, ioData: ioData)
    }
    
    func notifyDeliverRecordedData(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        numberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let delegate = delegate else { return 0; }
        return delegate.onDeliverRecordedData(flags: flags, timestamp: timestamp, busNumber: busNumber, numberFrames: numberFrames, ioData: ioData)
    }
}
//출력 콜백
func onGetPlayoutData (
    inRefCon: UnsafeMutableRawPointer,
    flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    timestamp: UnsafePointer<AudioTimeStamp>,
    busNumber: UInt32,
    numberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    let audio_unit =  unsafeBitCast(inRefCon, to: VoiceProcessingUnit.self)
    return audio_unit.notifyGetPlayoutData (
        flags: flags,
        timestamp: timestamp,
        busNumber: busNumber,
        numberFrames: numberFrames,
        ioData: ioData);
}

//입력 콜백
func onDeliverRecordedData (
    inRefCon: UnsafeMutableRawPointer,
    flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    timestamp: UnsafePointer<AudioTimeStamp>,
    busNumber: UInt32,
    numberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    
    let audio_unit =  unsafeBitCast(inRefCon, to: VoiceProcessingUnit.self)
    return audio_unit.notifyDeliverRecordedData(
        flags: flags,
        timestamp: timestamp,
        busNumber: busNumber,
        numberFrames: numberFrames,
        ioData: ioData);
}




