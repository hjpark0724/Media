//
//  H264Common.swift
//  VideoCapturer
//
//  Created by HYEONJUN PARK on 2021/01/08.
//

import Foundation
import AVFoundation
import VideoToolbox

public let kNaluLongStartSequenceSize = 4
public let kNaluShortStartSequenceSize = 3
public let kNaluTypeSize = 1
public let kNaluTypeMask:UInt8 = 0x1f

public enum NaluType : UInt8 { //5bit
    case kSlice = 1
    case kIdr = 5
    case kSei = 6
    case kSps = 7
    case kPps = 8
    case kAud = 9
    case kEndOfSequence = 10
    case kEndOfStream = 11
    case kFiller = 12
    case kStapA = 24
    case kFuA = 28 //1 1100
}

public enum SliceType : UInt8 {
    case kP = 0
    case kB = 1
    case kI = 2
    case kSp = 3
    case kSi = 4
    
}

public class NaluIndex {
    public var startOffset: Int32 = 0
    public var payloadStartOffset: Int32 = 0
    public var payloadSize: Int32 = 0
    public init(startOffset: Int32, payloadStartOffset: Int32) {
        self.startOffset = startOffset
        self.payloadStartOffset = payloadStartOffset
        self.payloadSize = 0
    }
}

/*
 * 입력된 AnnexBuffer에서 각각의 NalUnit에 대한 정보 위치 파싱
 */
public func findNaluIndices(buffer: UnsafePointer<UInt8>, count: Int) -> [NaluIndex] {
    let end = count - kNaluShortStartSequenceSize // start bit는 0001,001 둘다 가능
    var indices: [NaluIndex] = []
    var i : Int = 0
    while (i < end ) {
        if buffer[i + 2] > 1 {
            i += 3
        } else if buffer[i + 2] == 1 {
            if buffer[i + 1] == 0 && buffer[i] == 0 { // StartBit 를 찾은 경우 '001'
                let index =
                    NaluIndex(startOffset: Int32(i), payloadStartOffset: Int32(i + 3))
                if index.startOffset > 0 && buffer[Int(index.startOffset - 1)] == 0 { // 0001 인 경우 처리
                    index.startOffset -= 1
                }
                //이 전 저장된 NalUnit의 정보가 있는 경우 이전 NalUnit의 크기는 이전 유닛의 페이로드 시작 위치에서 현재 startbit의 시작점 까지
                if let last = indices.last {
                    last.payloadSize = index.startOffset - last.payloadStartOffset //
                }
                indices.append(index)
            }
            i += 3;
        } else {
            i += 1
        }
    }
    // 마지막 NalUnit의 페이로드 데이터 크기 계산
    if let last = indices.last {
        last.payloadSize = Int32(count) - last.payloadStartOffset
    }
    return indices
}


public func parseNaluType(byte: UInt8) -> NaluType? {
    return NaluType(rawValue: (byte & kNaluTypeMask))
}

