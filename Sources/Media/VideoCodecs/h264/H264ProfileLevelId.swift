//
//  H264ProfileLevelId.swift
//  
//
//  Created by HYEONJUN PARK on 2021/03/17.
//

import Foundation

let kProfileLevelId = "profile-level-id"
let kConstraintSet3Flag: UInt8 = 0x10



public enum Profile {
    case kProfileConstrainedBaseline
    case kProfileBaseline
    case kProfileMain
    case kProfileConstrainedHigh
    case kProfileHigh
}

public enum Level : Int {
  case kLevel1_b = 0
  case kLevel1 = 10
  case kLevel1_1 = 11
  case kLevel1_2 = 12
  case kLevel1_3 = 13
  case kLevel2 = 20
  case kLevel2_1 = 21
  case kLevel2_2 = 22
  case kLevel3 = 30
  case kLevel3_1 = 31
  case kLevel3_2 = 32
  case kLevel4 = 40
  case kLevel4_1 = 41
  case kLevel4_2 = 42
  case kLevel5 = 50
  case kLevel5_1 = 51
  case kLevel5_2 = 52
};

func byteMaskString(c: Character, str: String) -> UInt8 {
    var mask: UInt8 = 0
    for i in 0..<8 {
        if str[str.index(str.startIndex, offsetBy: i)] == c {
            mask = mask | (1 << (7 - UInt8(i)))
        }
    }
    return mask
}

public struct BittPattern {
    let mask: UInt8
    let masked_value: UInt8
    public init(str: String) {
        self.mask = ~byteMaskString(c: "x", str: str)
        self.masked_value = byteMaskString(c: "1", str: str)
    }
    func isMatch(value: UInt8) -> Bool { return masked_value == (value & mask) }
}


public struct ProfilePattern {
    let profile_idc: UInt8
    let profile_iop: BittPattern
    let profile: Profile
}

public struct ProfileLevelId {
    public let profile: Profile;
    public let level: Level;
};

extension ProfileLevelId : CustomStringConvertible {
    public var description: String {
        if level == .kLevel1_b {
            switch profile {
            case .kProfileConstrainedBaseline:
                return "42f00b"
            case .kProfileBaseline:
                return "42100b"
            case .kProfileMain:
                return "4d100b"
            default:
                return ""
            }
        }
        var idc_iop: String = ""
        switch profile {
        case .kProfileConstrainedBaseline:
            idc_iop = "42e0"
        case .kProfileBaseline:
            idc_iop = "4200"
        case .kProfileMain:
            idc_iop = "4d00"
        case .kProfileConstrainedHigh:
            idc_iop = "640c"
        case .kProfileHigh:
            idc_iop = "6400"
        }
        return String(format: "%s%02x", idc_iop, level.rawValue)
    }
}

let kProfilePatterns:[ProfilePattern] = [
    ProfilePattern(profile_idc: 0x42, profile_iop: BittPattern(str: "x1xx0000"), profile: .kProfileConstrainedBaseline),
    ProfilePattern(profile_idc: 0x4D, profile_iop: BittPattern(str: "1xxx0000"), profile: .kProfileConstrainedBaseline),
    ProfilePattern(profile_idc: 0x58, profile_iop: BittPattern(str: "11xx0000"), profile: .kProfileConstrainedBaseline),
    ProfilePattern(profile_idc: 0x42, profile_iop: BittPattern(str: "x0xx0000"), profile: .kProfileBaseline),
    ProfilePattern(profile_idc: 0x58, profile_iop: BittPattern(str: "10xx0000"), profile: .kProfileBaseline),
    ProfilePattern(profile_idc: 0x4D, profile_iop: BittPattern(str: "0x0x0000"), profile: .kProfileMain),
    ProfilePattern(profile_idc: 0x64, profile_iop: BittPattern(str: "00000000"), profile: .kProfileMain),
    ProfilePattern(profile_idc: 0x64, profile_iop: BittPattern(str: "00001100"), profile: .kProfileConstrainedHigh)
]

struct LevelConstraint {
    let maxMacroBlockPerSecond: Int
    let maxMacroBlockFrameSize: Int
    let level: Level
}

let kLevelConstraints: [LevelConstraint] = [
    LevelConstraint(maxMacroBlockPerSecond: 1485, maxMacroBlockFrameSize: 99, level: .kLevel1),
    LevelConstraint(maxMacroBlockPerSecond: 1485, maxMacroBlockFrameSize: 99, level: .kLevel1_b),
    LevelConstraint(maxMacroBlockPerSecond: 3000, maxMacroBlockFrameSize: 396, level: .kLevel1_1),
    LevelConstraint(maxMacroBlockPerSecond: 6000, maxMacroBlockFrameSize: 396, level: .kLevel1_2),
    LevelConstraint(maxMacroBlockPerSecond: 11880, maxMacroBlockFrameSize: 396, level: .kLevel1_3),
    LevelConstraint(maxMacroBlockPerSecond: 11880, maxMacroBlockFrameSize: 396, level: .kLevel2),
    LevelConstraint(maxMacroBlockPerSecond: 19800, maxMacroBlockFrameSize: 792, level: .kLevel2_1),
    LevelConstraint(maxMacroBlockPerSecond: 20250, maxMacroBlockFrameSize: 1620, level: .kLevel2_2),
    LevelConstraint(maxMacroBlockPerSecond: 40500, maxMacroBlockFrameSize: 1620, level: .kLevel3),
    LevelConstraint(maxMacroBlockPerSecond: 108000, maxMacroBlockFrameSize: 3600, level: .kLevel3_1),
    LevelConstraint(maxMacroBlockPerSecond: 216000, maxMacroBlockFrameSize: 5120, level: .kLevel3_2),
    LevelConstraint(maxMacroBlockPerSecond: 245760, maxMacroBlockFrameSize: 8192, level: .kLevel4),
    LevelConstraint(maxMacroBlockPerSecond: 245760, maxMacroBlockFrameSize: 8192, level: .kLevel4_1),
    LevelConstraint(maxMacroBlockPerSecond: 522240, maxMacroBlockFrameSize: 8704, level: .kLevel4_2),
    LevelConstraint(maxMacroBlockPerSecond: 589824, maxMacroBlockFrameSize: 22080, level: .kLevel5),
    LevelConstraint(maxMacroBlockPerSecond: 983040, maxMacroBlockFrameSize: 36864, level: .kLevel5_1),
    LevelConstraint(maxMacroBlockPerSecond: 2073600, maxMacroBlockFrameSize: 36864, level: .kLevel5_2)
]

public func parseProfileLevelId(level: String) -> ProfileLevelId? {
    guard let numeric = Int(level, radix: 16) else { return nil }
    let level_idc = UInt8(numeric & 0xFF)
    let profile_iop = UInt8((numeric >> 8) & 0xFF)
    let profile_idc = UInt8((numeric >> 16) & 0xFf)
    
    guard var level: Level = Level(rawValue: Int(level_idc)) else { return nil }
    if level == .kLevel1_1 {
        level = profile_iop & kConstraintSet3Flag != 0 ? .kLevel1_b : .kLevel1_1
    }
    guard let pattern = kProfilePatterns.first (
            where: { $0.profile_idc == profile_idc && $0.profile_iop.isMatch(value: profile_iop)}
    ) else { return nil }
    return ProfileLevelId(profile: pattern.profile, level: level)
}




