//
//  PlaybackState.swift
//  audio_service
//
//  Created by Mohamed Abdallah on 3/29/20.
//

import Foundation

class PlaybackState {
    var state: BasicPlaybackState
    var position: Int
    var updateTime: UInt64
    var speed: Double
    
    init() {
        let msSinceEpoch = UInt64(Date().timeIntervalSince1970 * 1000)
        state = .none
        position = 0
        updateTime = msSinceEpoch
        speed = 1.0
    }
    
    init? (arguments: Any?) {
        guard let arguments = arguments as? NSArray else {return nil}
        state = BasicPlaybackState(rawValue: arguments[2] as? Int ?? 0) ?? .none
        position =  arguments[3] as? Int ?? 0
        speed =  arguments[4] as? Double ?? 1.0
        updateTime = arguments[5] as? UInt64 ?? UInt64(Date().timeIntervalSince1970 * 1000)
    }
    
    func toArguments() -> NSArray {
        return [state.rawValue,0,position,speed,updateTime]
    }
}


enum BasicPlaybackState:Int {
  case none
  case stopped
  case paused
  case playing
  case fastForwarding
  case rewinding
  case buffering
  case error
  case connecting
  case skippingToPrevious
  case skippingToNext
  case skippingToQueueItem
}
