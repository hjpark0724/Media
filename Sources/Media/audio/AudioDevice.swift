//
//  AudioDevice.swift
//
//
//  Created by HYEONJUN PARK on 2020/12/14.
//

import Foundation
import AudioToolbox
import AVFoundation
import Logging
import Atomics
public protocol AudioDeviceDelegate : AnyObject {
    func onDeliverRecordedData(data:Data)
}
public class AudioDevice : NSObject{
    var audioUnit : VoiceProcessingUnit?
    public weak var delegate: AudioDeviceDelegate?
    public private(set) var isInterrupted: Bool {
        get {
            let isInterrupted = isInterrupted_.load(ordering: .acquiring)
            return isInterrupted
        }
        set {
            _ = isInterrupted_.exchange(newValue, ordering: .releasing)
        }
    }
    
    public private(set) var isPlaying: Bool {
        get {
            let isPlaying = isPlaying_.load(ordering: .acquiring)
            return isPlaying
        }
        set {
            _ = isPlaying_.exchange(newValue, ordering: .releasing)
        }
    }
    
    public private(set) var isRecording: Bool {
        get {
            let isRecording = isRecording_.load(ordering: .acquiring)
            return isRecording
        }
        set {
            _ = isRecording_.exchange(newValue, ordering: .releasing)
        }
    }
    
    var isAudioInitialized: Bool {
        get {
            let isAudioInitialized = isAudioInitialized_.load(ordering: .acquiring)
            return isAudioInitialized
        }
        set {
            _ = isAudioInitialized_.exchange(newValue, ordering: .releasing)
        }
    }
    var hasConfiguredSession: Bool {
        get {
            let hasConfiguredSession = hasConfiguredSession_.load(ordering: .acquiring)
            return hasConfiguredSession
        }
        set {
            _ = hasConfiguredSession_.exchange(newValue, ordering: .releasing)
        }
    }
    
    var isInterrupted_ = UnsafeAtomic<Bool>.create(false)
    var isPlaying_ = UnsafeAtomic<Bool>.create(false)
    var isRecording_ = UnsafeAtomic<Bool>.create(false)
    
    var isAudioInitialized_ = UnsafeAtomic<Bool>.create(false)
    var hasConfiguredSession_ = UnsafeAtomic<Bool>.create(false)
    
    var previousTime: Double = 0
    var playoutParameters  = AudioParameters()
    var recordParameters = AudioParameters()
    var lastPlayoutTime : Int64 = 0
    let logger = Logger(label: "AudioDevice")
    var skipBytes : Int = 0
    public var playOutBuffer = CircularBuffer(initialCapacity: 32000)
    public init(delegate: AudioDeviceDelegate?) {
        self.delegate = delegate
    }
    
    public override convenience init() {
        self.init(delegate:nil)
    }
    
    public func initRecording() -> Bool {
        guard let audioUnit = self.audioUnit, isAudioInitialized else {
            if !initPlayOrRecord() {
                logger.error("initRecording : initPlayOrRecord fail")
                return false
            }
            return true
        }
        return true
    }
    
    public func initPlayout() -> Bool {
        guard let audioUnit = self.audioUnit, isAudioInitialized else {
            if !initPlayOrRecord() {
                logger.error("initPlayout : initPlayOrRecord fail")
                return false
            }
            return true
        }
        return true
    }
    
    public func initRecording(sampleRate: Float64) -> Bool {
        guard let audioUnit = self.audioUnit, isAudioInitialized else {
            if !initPlayOrRecord(sampleRate: sampleRate) {
                logger.error("initRecording : initPlayOrRecord fail")
                return false
            }
            return true
        }
        
        logger.info("audio unit update record samplerate: \(sampleRate)")
        if !audioUnit.setRecordSampleRate(sampleRate: sampleRate) {
            logger.error("record sample rate fail")
            return false
        }
        isAudioInitialized = true
        return true
    }
    
    public func initPlayout(sampleRate: Float64) -> Bool {
        guard let audioUnit = self.audioUnit, isAudioInitialized else {
            if !initPlayOrRecord(sampleRate: sampleRate) {
                logger.error("initPlayout : initPlayOrRecord fail")
                return false
            }
            return true
        }
        
        logger.info("audio unit update playout samplerate: \(sampleRate)")
        if !audioUnit.setPlayOutSampleRate(sampleRate: sampleRate) {
            logger.error("playout sample rate fail")
            return false
        }
        isAudioInitialized = true
        return true
    }
    
    public func write(data: Data) {
        //if !isPlaying { return }
        playOutBuffer.write(data.withUnsafeBytes{return $0})
    }
    
    public func startPlayout() -> Bool {
        guard let audioUnit = self.audioUnit else {
            return false
        }
        if isAudioInitialized == false {
            logger.error("startPlayout: AudioDevice not initialized")
            return false
        }
        
        if !isRecording && audioUnit.state == .initialized {
            if !audioUnit.start() {
                return false;
            }
        }
        self.isPlaying = true
        return true;
    }
    
    
    public func stopPlayout() {
        if !isAudioInitialized || !isPlaying {
            return
        }
        isPlaying = false
        //logger.info("stopPlaying")
        if !isRecording {
            shutdownPlayOrRecord()
            isAudioInitialized = false
        }
        playOutBuffer.reset()
    }
    
    
    public func startRecording() -> Bool {
        guard let audioUnit = self.audioUnit else {
            return false
        }
        if !isPlaying && audioUnit.state == .initialized {
            if !audioUnit.start() {
                return false
            }
        }
        self.isRecording = true
        return true
    }
    
    public func stopRecording() {
        if !isAudioInitialized || !isRecording {
            return
        }
        //logger.info("stopRecording")
        isRecording = false
        if !isPlaying {
            shutdownPlayOrRecord()
            isAudioInitialized = false
        }
    }
    
    public func shutdownPlayOrRecord() {
        guard let audioUnit = self.audioUnit else { return }
        _ = audioUnit.stop()
        _ = audioUnit.uninitilize()
        audioUnit.disposeAudioUnit()
        let session = AudioSession.shared
        session.removeDelegate(delegate: self)
        isAudioInitialized = false
        self.audioUnit = nil
    }
    
    
    func updateAudioUnit(can_play_or_record: Bool) {
        if(isInterrupted || !isAudioInitialized ) {
            return
        }
        guard let audioUnit = audioUnit else {
            return
        }
        var shouldInitalizeAudioUnit: Bool = false
        var shouldUninitilzeAudioUnit: Bool = false
        var shouldStartAudioUnit: Bool = false
        var shouldStopAudioUnit: Bool = false
        switch audioUnit.state {
        case .initRequired:
            logger.info("AudioDevice state: Init Required")
        case .uninitialized:
            logger.info("AudioDevice state: UnIntialized")
            shouldInitalizeAudioUnit = can_play_or_record
            shouldStartAudioUnit = shouldInitalizeAudioUnit && isPlaying || isRecording
        case .initialized:
            logger.info("AudioDevice state: Initialized")
            shouldStartAudioUnit = can_play_or_record && isPlaying || isRecording
            shouldUninitilzeAudioUnit = !can_play_or_record
        case .started:
            logger.info("AudioDevice sate: Started")
            shouldStopAudioUnit = !can_play_or_record
            shouldUninitilzeAudioUnit = shouldStopAudioUnit;
        }

        if shouldInitalizeAudioUnit {
            setupAudioBuffersForActiveAudioSession()
            logger.info("Should Initialize Audio Unit")
            if !audioUnit.initilize(sampleRate: AudioSession.shared.sampleRate) { return }
        }
        if shouldStartAudioUnit {
            if !audioUnit.start() { return }
        }
        
        if shouldStopAudioUnit {
            if !audioUnit.stop() { return }
        }

        if shouldUninitilzeAudioUnit {
            logger.info("Should uninitialize Audio Unit")
            _ = audioUnit.uninitilize()
        }
    }
    
    func setupAudioBuffersForActiveAudioSession() {
        let session = AudioSession.shared
        let sample_rate = session.preferredSampleRate
        let io_buf_duration = session.preferredIOBufferDuration
        playoutParameters.reset(sampleRate: sample_rate, channels: playoutParameters.channels, duration: io_buf_duration)
        recordParameters.reset(sampleRate: sample_rate, channels: recordParameters.channels, duration: io_buf_duration)
        //print("playoutParameters.framesPerBuffer: \(playoutParameters.framesPerBuffer)")
        //update audio buffer
    }
    
    public func initPlayOrRecord() -> Bool {
        let audioUnit = VoiceProcessingUnit(delegate: self)
        let session = AudioSession.shared
        session.addDelegate(delegate: self)
        isInterrupted = session.isInterrupted
        session.beginSession()
        setupAudioBuffersForActiveAudioSession()
        if !audioUnit.initilize(sampleRate: session.preferredSampleRate) {
            logger.error("fail to initialize VoiceProcessingUnit")
            self.audioUnit = nil
            return false
        }
        self.audioUnit = audioUnit
        isAudioInitialized = true
        return true
    }
    
    public func initPlayOrRecord(sampleRate: Float64) -> Bool {
        let audioUnit = VoiceProcessingUnit(delegate: self)
        let session = AudioSession.shared
        session.addDelegate(delegate: self)
        isInterrupted = session.isInterrupted
        session.beginSession()
        
        setupAudioBuffersForActiveAudioSession()
        //_ = audioUnit?.initilize(sampleRate: session.preferredSampleRate)\
        if !audioUnit.initilize(sampleRate: sampleRate) {
            logger.error("fail to initialize VoiceProcessingUnit")
            self.audioUnit = nil
            return false
        }
        self.audioUnit = audioUnit
        isAudioInitialized = true
        return true
    }
}


// MARK: VoiceProcessingUnitDelegate delegate - 오디오 I/O 송 수신 처리
extension AudioDevice : VoiceProcessingUnitDelegate {
    //마이크 에서 수신된 데이터 처리
    func onDeliverRecordedData(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        numberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let audioUnit = self.audioUnit else {
            return -1
        }
        if isRecording == false {
            return 0
        }
        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: numberFrames * 2,
                mData: nil))
        let status = audioUnit.render(flags: flags, timestatmp: timestamp, busNumber: busNumber, numberFrames: numberFrames, ioData: &bufferList)
        if status != noErr {
            print("render failed: \(status)")
            return status
        }
        let data = Data(bytes: bufferList.mBuffers.mData!, count: Int(bufferList.mBuffers.mDataByteSize))
        delegate?.onDeliverRecordedData(data: data)
        return 0;
    }
    
    func onGetPlayoutData(
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        numberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard var audio_buffer = ioData?.pointee.mBuffers else {
            return -1
        }
        var bufferSize: Int = Int(audio_buffer.mDataByteSize)
        if !self.isPlaying || playOutBuffer.count < bufferSize {
            var flags = flags.pointee
            flags.insert(.unitRenderAction_OutputIsSilence)
            memset(audio_buffer.mData, 0, bufferSize)
            /*
            if self.isPlaying && playOutBuffer.isEmpty {
                logger.warning("buffer pool is empty")
            }
            */
            return noErr
        }
        
        if bufferSize > playOutBuffer.count {
            logger.warning("buffer pool is late. write:\(bufferSize), buffer pool :\(playOutBuffer.count)")
        }
        
        bufferSize = playOutBuffer.count < bufferSize ? playOutBuffer.count : bufferSize
        //logger.warning("write:\(bufferSize), buffer pool :\(playOutBuffer.count)")
        audio_buffer.mDataByteSize = UInt32(bufferSize)
        if let data = playOutBuffer.read(count: bufferSize) {
            let ptr = data.withUnsafeBytes{return $0.baseAddress!}
            memcpy(audio_buffer.mData, ptr, data.count)
        }
        return noErr
    }
}

extension AudioDevice: AudioSessionDelegate {
    func didBeginInterruption(session: AudioSession) {
        guard let audioUnit = self.audioUnit else {
            return;
        }
        if audioUnit.state == .started {
            _ = audioUnit.stop()
        }
        isInterrupted = true
    }
    
    func didEndInterruption(session: AudioSession, shouldResumeSession: Bool) {
        isInterrupted = false
        updateAudioUnit(can_play_or_record: AudioSession.shared.canPlayOrRecord)
    }
    
    
    func didChangeRoute(session: AudioSession, reason: AVAudioSession.RouteChangeReason, previousRoute: AVAudioSessionRouteDescription) {
    }
    
    func mediaServerTerminated(session: AudioSession) {
    }
    
    func mediaServerReset(session: AudioSession) {
    }
    
    func didChangeCanPlayOrRecord(session: AudioSession, canPlayOrRecord: Bool) {
        //print("didChangeCanPlayOrRecord")
    }
    
    func didStartPlayOrRecord(session: AudioSession) {
        //print("didStartPlayOrRecord")
    }
    
    func didStopPlayOrRecord(session: AudioSession) {
        print("didStopPlayOrRecord")
    }
    
    func didChangeOutputVolume(session: AudioSession, outputVolume: Float) {
    }
    
    func didDetectPlayoutGlitch(session: AudioSession, totalNumberOfGlitches: Int64) {
    }
    
    func willSetActive(session: AudioSession, active: Bool) {
    }
    
    func didSetActive(session: AudioSession, active: Bool) {
    }
    
    func failedToSetActive(session: AudioSession, active: Bool, error: Error) {
    }
}

