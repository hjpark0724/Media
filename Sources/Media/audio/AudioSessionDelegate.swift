//
//  AudioSessionDelegate.swift
//  
//
//  Created by HYEONJUN PARK on 2020/12/11.
//

import Foundation
import AVFoundation
protocol AudioSessionDelegate: NSObject {
    func didBeginInterruption(session: AudioSession)
    func didEndInterruption(session: AudioSession, shouldResumeSession: Bool)
    func didChangeRoute(session: AudioSession,
                                    reason: AVAudioSession.RouteChangeReason,
                                     previousRoute:AVAudioSessionRouteDescription)
    func mediaServerTerminated(session: AudioSession)
    func mediaServerReset(session: AudioSession)
    
    
    
    //func shouldConfigure(session: AudioSession)
    
    //func shouldUnconfigure(session: AudioSession)

    func didChangeCanPlayOrRecord(session: AudioSession, canPlayOrRecord:Bool)
    func didStartPlayOrRecord(session: AudioSession)
    func didStopPlayOrRecord(session: AudioSession)
    func didChangeOutputVolume(session: AudioSession, outputVolume: Float)
    func didDetectPlayoutGlitch(session: AudioSession, totalNumberOfGlitches: Int64)
    
    func willSetActive(session: AudioSession, active: Bool)
    func didSetActive(session: AudioSession, active: Bool)
    func failedToSetActive(session: AudioSession, active: Bool, error: Error)
}
