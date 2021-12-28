//
//  AudioSession.swift
//  AudioLibrary
//
//  Created by HYEONJUN PARK on 2020/12/09.
//

import Foundation
import AVFoundation
import UIKit
import Atomics
import Logging

import Utils
struct WeakReference<T> {
    weak var _reference: AnyObject?
    init(_ object:T) { _reference = object as AnyObject }
    var reference: T? { return _reference as? T }
}
    
public class AudioSession : NSObject {
    let logger = Logger(label: "AudioSession")
    private var _isAudioEnabled: Bool = false
    
    public var isAudioEnabled: Bool {
        get {
            return self._isAudioEnabled
        }
        set {
            if _isAudioEnabled == newValue {
                return
            }
            _isAudioEnabled = newValue
        }
    }
    
    public var canPlayOrRecord: Bool {
        get {
            return self._isAudioEnabled
        }
        set {
            if _isAudioEnabled == newValue { return }
            self.notifyDidChangeCanPlayOrRecord(canPlayOrRecord: isAudioEnabled)
        }
    }
    
    var isActive: Bool = false
    let activationCount = ManagedAtomic<Int>(0)
    let sessionCount = ManagedAtomic<Int>(0)
    var isInterrupted: Bool = false
   public let session: AVAudioSession
    let serialQueue = DispatchQueue(label: "com.RTCAudioSession")
    public static let shared = AudioSession()
    override convenience init() {
        self.init(with: AVAudioSession.sharedInstance())
    }
    
    var delegates = SynchronizedArray<WeakReference<AudioSessionDelegate>>()
    init(with session: AVAudioSession) {
        self.session = session
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(handleInterruptionNotification),
                           name:  AVAudioSession.interruptionNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(handleRouteChangeNotification),
                           name: AVAudioSession.routeChangeNotification,
                           object:nil)
        center.addObserver(self,
                           selector: #selector(handleMediaServicesWereLost),
                           name: AVAudioSession.mediaServicesWereLostNotification,
                           object:nil)
        center.addObserver(self,
                           selector: #selector(handleMediaServicesWereReset),
                           name:AVAudioSession.mediaServicesWereResetNotification,
                           object:nil);
        center.addObserver(self,
                           selector: #selector(handleSilenceSecondaryAudioHintNotification),
                           name:AVAudioSession.silenceSecondaryAudioHintNotification,
                           object:nil)
        center.addObserver(self,
                           selector: #selector(handleApplicationDidBecomeActive),
                           name:UIApplication.didBecomeActiveNotification,
                           object:nil);
        
    }
    
    func beginSession() {
        sessionCount.wrappingIncrement(ordering: .releasing)
        self.notifyDidStartPlayOrRecord()
    }
    
    func endSession() {
        sessionCount.wrappingDecrement(ordering: .releasing)
        self.notifyDidStopPlayOrRecord()
    }
    func addDelegate(delegate: AudioSessionDelegate) {
        delegates.append(WeakReference(delegate))
    }
    
    func removeDelegate(delegate: AudioSessionDelegate) {
        let index = delegates.firstIndex{ $0.reference! == delegate }
        if let index = index {
            delegates.remove(at: index)
        }
    }
    
    
    public func setActive(active: Bool) -> Bool {
        serialQueue.sync {
        self.notifyWillSetActive(active: active)
        let activationCount = self.activationCount.load(ordering: .acquiring)
        let shouldSetActive = active && !self.isActive || (!active && self.isActive && activationCount == 1)
        if (shouldSetActive) {
            let options = active ? AVAudioSession.SetActiveOptions(rawValue: 0) : AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation
            do {
                try self.session.setActive(active, options: options)
            } catch {
                logger.error("session setActive fail:\(error)")
                self.notifyFailedToSetActive(active: active, error: error)
                return false
            }
            self.isActive = active
            if active && self.isInterrupted {
                self.isInterrupted = false
                self.notifyDidEndInterruption(shouldResume: true)
            }
        }
        if active == true {
            self.activationCount.wrappingIncrement(ordering: .releasing)
        } else {
            self.activationCount.wrappingDecrement(ordering: .releasing)
        }
        self.notifyDidSetActive(active: active)
        return true
        }
    }
    
    
    func updateAudioSessionAfterEvent() {
        let shouldActivate = self.activationCount.load(ordering: .acquiring) > 0
        let options = shouldActivate ? AVAudioSession.SetActiveOptions(rawValue: 0) : AVAudioSession.SetActiveOptions.notifyOthersOnDeactivation
        do{
            try self.session.setActive(shouldActivate, options: options)
            self.isActive = shouldActivate
        } catch {
            logger.error("fail to set session active:\(error)")
        }
    }
    
    
    //MARK - AVAudioSession Proxy
    public func setCategory(category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) -> Bool {
        serialQueue.sync {
            do {
                try self.session.setCategory(category, mode: mode, options: options)
            } catch {
                logger.error("setCategory fail:\(error)")
                return false
            }
            return true
        }
    }
    
    func setInputGain(gain: Float) -> Bool {
        do {
            try self.session.setInputGain(gain)
        } catch {
            logger.error("setInputGain fail:\(error)")
            return false
        }
        return true
    }

    func setPreferredSampleRate(sampleRate: Double) -> Bool {
        do {
            try self.session.setPreferredSampleRate(sampleRate)
        } catch {
            logger.error("setPreferredSampleRate fail:\(error)")
            return false
        }
        return true
    }
    
    func setPreferredIOBufferDuration(duration: TimeInterval) -> Bool {
        do {
            try self.session.setPreferredIOBufferDuration(duration)
        } catch {
            logger.error("setPreferredIOBufferDuration fail:\(error)")
            return false
        }
        return true
    }
    
    func setPreferredInputNumberOfChannels(count: Int) -> Bool {
        do {
            try self.session.setPreferredInputNumberOfChannels(count)
        } catch {
            logger.error("setPreferredInputNumberOfChannels fail:\(error)")
            return false
        }
        return true
    }
    
    func setPreferredOutputNumberOfChannels(count: Int) -> Bool {
        do {
            try self.session.setPreferredOutputNumberOfChannels(count)
        } catch {
            logger.error("setPreferredOutputNumberOfChannels fail:\(error)")
            return false
        }
        return true
    }
    
    public func overrideOutputAudioPort(portOverride: AVAudioSession.PortOverride) -> Bool {
        do {
            try self.session.overrideOutputAudioPort(portOverride)
        } catch {
            logger.error("overrideOutputAudioPort fail:\(error)")
            return false
        }
        return true
    }
    
    func setPreferredInput(inPort: AVAudioSessionPortDescription) -> Bool {
        do {
            try self.session.setPreferredInput(inPort)
        } catch {
            logger.error("setPreferredInput fail:\(error)")
            return false
        }
        return true
    }
    
    func setInputDataSource(dataSource: AVAudioSessionDataSourceDescription) -> Bool {
        do {
            try self.session.setInputDataSource(dataSource)
        } catch {
            logger.error("setInputDataSource fail:\(error)")
            return false
        }
        return true
    }
    
    func setOutputDataSource(dataSource: AVAudioSessionDataSourceDescription) -> Bool {
        do {
            try self.session.setOutputDataSource(dataSource)
        } catch {
            logger.error("setOutDataSource fail:\(error)")
            return false
        }
        return true
    }
    
    var category :AVAudioSession.Category {
        return AVAudioSession.sharedInstance().category
    }
    var categoryOptions :AVAudioSession.CategoryOptions {
        return AVAudioSession.sharedInstance().categoryOptions
    }
    
    var secondaryAudioShouldBeSilencedHint: Bool {
        return AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }
    
    var mode: AVAudioSession.Mode {
        return AVAudioSession.sharedInstance().mode
    }
    
    var preferredSampleRate: Double {
        return AVAudioSession.sharedInstance().preferredSampleRate
    }
    
    var preferredIOBufferDuration: Double {
        return AVAudioSession.sharedInstance().preferredIOBufferDuration
    }
    
    var inputNumberOfChannels: Int {
        return AVAudioSession.sharedInstance().inputNumberOfChannels
    }
    
    var outputNumberOfChannels: Int {
        return AVAudioSession.sharedInstance().outputNumberOfChannels
    }
    
    var sampleRate: Double {
        return AVAudioSession.sharedInstance().sampleRate
    }
    
    
    @objc func handleInterruptionNotification(notification: NSNotification) {
        guard let interruptType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? AVAudioSession.InterruptionType else { return }
        switch interruptType {
        case .began:
            self.isActive = false
            self.isInterrupted = true
            self.notifyDidBeginInterruption()
            break
        case .ended:
            self.isInterrupted = false
            self.updateAudioSessionAfterEvent()
            guard let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? AVAudioSession.InterruptionOptions else { return }
            let shouldResume = (options == .shouldResume) ? true : false
            self.notifyDidEndInterruption(shouldResume:shouldResume)
            break
        @unknown default:
            break
        }
    }
    
    @objc func handleRouteChangeNotification(notification: NSNotification) {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? AVAudioSession.RouteChangeReason else { return }
        switch reason {
        case .unknown:
            logger.info("Audio route changed: ReasonUnknown")
            break;
        case .newDeviceAvailable:
            logger.info("Audio route changed: newDeviceAvailable")
            break;
        case .oldDeviceUnavailable:
            logger.info("Audio route changed: oldDeviceUnavailable")
            break;
        case .categoryChange:
            logger.info("Audio route changed: categoryChange")
            break;
        case .override:
            logger.info("Audio route changed: override")
            break;
        case .wakeFromSleep:
            logger.info("Audio route changed: wakeFromSleep")
            break;
        case .noSuitableRouteForCategory:
            logger.info("Audio route changed: noSuitableRouteForCategory")
            break;
        case .routeConfigurationChange:
            logger.info("Audio route changed: routeConfigurationChange")
            break;
        @unknown default:
            break;
        }
        
        guard let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
        logger.info("previous:\(previous)\n current route:\(self.session.currentRoute)")
        self.notifyDidChangeRoute(reason: reason, previousRoute: previous)
    }
    
    @objc func handleMediaServicesWereLost(notification: NSNotification) {
        self.updateAudioSessionAfterEvent()
        self.notifyMediaServiceWereLost()
    }
    
    @objc func handleMediaServicesWereReset(notification: NSNotification) {
        self.updateAudioSessionAfterEvent()
        self.notifyMediaServiceWereReset()
    }
    
    @objc func handleSilenceSecondaryAudioHintNotification(notification: NSNotification) {
    }
    
    @objc func handleApplicationDidBecomeActive(notification: NSNotification) {
        if self.isInterrupted {
            self.isInterrupted = false
            self.updateAudioSessionAfterEvent()
        }
        self.notifyDidEndInterruption(shouldResume:true)
    }
    
    func notifyDidBeginInterruption() {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didBeginInterruption(session: self)}
    }
    
    func notifyDidEndInterruption(shouldResume:Bool) {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didEndInterruption(session: self, shouldResumeSession: shouldResume)}
    }
    
    func notifyDidChangeRoute(reason: AVAudioSession.RouteChangeReason,
                              previousRoute:AVAudioSessionRouteDescription){
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didChangeRoute(session: self, reason: reason, previousRoute: previousRoute)}
    }
    
    func notifyMediaServiceWereLost() {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.mediaServerTerminated(session: self)}
    }
    
    func notifyMediaServiceWereReset() {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.mediaServerReset(session: self)}
    }
     
    func notifyDidChangeCanPlayOrRecord(canPlayOrRecord: Bool) {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didChangeCanPlayOrRecord(session: self, canPlayOrRecord: canPlayOrRecord)}
    }
    
    func notifyDidStartPlayOrRecord() {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didStartPlayOrRecord(session: self)}
    }
    
    func notifyDidStopPlayOrRecord() {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didStopPlayOrRecord(session: self)}
    }
    
    func notifyDidChangeOutputVolume(volume: Float) {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didChangeOutputVolume(session: self, outputVolume: volume)}
    }
    
    func notifyDidDetectPlayoutGlitch(numOfGlitch: Int64) {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didDetectPlayoutGlitch(session: self, totalNumberOfGlitches: numOfGlitch)}
    }
    
    func notifyWillSetActive(active: Bool) {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.willSetActive(session: self, active: active)}
    }
    
    func notifyDidSetActive(active: Bool) {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.didSetActive(session: self, active: active)}
    }
    
    func notifyFailedToSetActive(active: Bool, error: Error) {
        delegates.forEach {[weak self] in
            guard let `self` = self else { return }
            $0.reference?.failedToSetActive(session: self, active: active, error: error)}
    }
    
    
    func endAudioSession() {
        self.notifyDidStopPlayOrRecord()
    }
    
    public func setConfiguration(configuration: AudioSessionConfiguration, active:Bool, shouldSetActive: Bool = true) -> Bool {
        if self.category != configuration.category ||
            self.mode != configuration.mode ||
            self.categoryOptions != configuration.categoryOptions {
            if !self.setCategory(category: configuration.category, mode: configuration.mode, options: configuration.categoryOptions) {
                logger.error("setCategory fail\n")
                return false
            }
        }
        let sessionSampleRate = self.sampleRate
        let desiredSampleRate = configuration.sampleRate
        if sessionSampleRate != desiredSampleRate {
            if !self.setPreferredSampleRate(sampleRate: desiredSampleRate) {
                return false
            }
        }
        
        if self.preferredIOBufferDuration != configuration.ioBufferDuration {
            if !self.setPreferredIOBufferDuration(duration: configuration.ioBufferDuration) {
                return false
            }
        }
        
        if shouldSetActive {
            if !self.setActive(active: active) {
                return false
            }
        }
        
        if self.isActive && self.mode == .voiceChat {
            if self.inputNumberOfChannels != configuration.inputNumberOfChannels {
                if !self.setPreferredInputNumberOfChannels(count: Int(configuration.inputNumberOfChannels)) {
                    return false
                }
            }
            if self.outputNumberOfChannels != configuration.outputNumberOfChannels {
                if !self.setPreferredOutputNumberOfChannels(count: Int(configuration.outputNumberOfChannels)) {
                    return false
                }
            }
        }
        return true
    }
}
