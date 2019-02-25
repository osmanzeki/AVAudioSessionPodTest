//
//  Extensions.swift
//  AVAudioSessionPodTest
//
//  Created by r618 on 24/02/2019.
//  Copyright © 2019 Martin Cvengroš. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

// extension of OptionSet for iterating over an OptionSet members
// courtesy of https://stackoverflow.com/questions/32102936/how-do-you-enumerate-optionsettype-in-swift
extension OptionSet where RawValue: FixedWidthInteger {
    
    func elements() -> AnySequence<Self> {
        var remainingBits = rawValue
        var bitMask: RawValue = 1
        return AnySequence {
            return AnyIterator {
                while remainingBits != 0 {
                    defer { bitMask = bitMask &* 2 }
                    if remainingBits & bitMask != 0 {
                        remainingBits = remainingBits & ~bitMask
                        return Self(rawValue: bitMask)
                    }
                }
                return nil
            }
        }
    }
}

// https://medium.com/@cafielo/how-to-detect-notch-screen-in-swift-56271827625d
extension UIDevice {
    var hasNotch: Bool {
        if #available(iOS 11.0,  *) {
            let bottom = UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0
            return bottom > 0
        }
        
        return false
    }
}


// These are not extensions 'cause we can't have extensions!

// since OptionSet (AVAudioSession.CategoryOptions) description is useless for printing and reflection for static members in Swift currently doesn't work, we have to interate
// e.g. these return only AVAudioSession.CategoryOptions + rawValue
// String(reflecting: opt)
// String(describing: AVAudioSession.CategoryOptions(rawValue: opt.rawValue))
// String(describing: opt)

func AudioSessionCategoryOptionDescription(option: AVAudioSession.CategoryOptions) -> String
{
    var result = ""
    switch option
    {
    case .allowBluetooth:
        result = ".allowBluetooth"
    case .allowBluetoothA2DP:
        result = ".allowBluetoothA2DP"
    case .defaultToSpeaker:
        result = ".defaultToSpeaker"
    default:
        result = "this is unexpected"
    }
    
    return result
}

func AudioSessionReasonDescription(_ reason: AVAudioSession.RouteChangeReason) -> String {
    switch(reason) {
    case .unknown:
        return "unknown"
    case .newDeviceAvailable:
        return "newDeviceAvailable"
    case .oldDeviceUnavailable:
        return "oldDeviceUnavailable"
    case .categoryChange:
        return "categoryChange"
    case .override:
        return "override"
    case .wakeFromSleep:
        return "wakeFromSleep"
    case .noSuitableRouteForCategory:
        return "noSuitableRouteForCategory"
    case .routeConfigurationChange:
        return "routeConfigurationChange"
    }
}
