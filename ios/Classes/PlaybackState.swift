//
//  PlaybackState.swift
//  audio_service
//
//  Created by Mohamed Abdallah on 3/29/20.
//

import Foundation

class PlaybackState {
    var controls =  [RemoteCommand]()
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
        let controls = arguments[0] as? [[String:Any]] ?? []
        let systemActions = arguments[1] as? [Int] ?? []
        state = BasicPlaybackState(rawValue: arguments[2] as? Int ?? 0) ?? .none
        position =  arguments[3] as? Int ?? 0
        speed =  arguments[4] as? Double ?? 1.0
        updateTime = arguments[5] as? UInt64 ?? UInt64(Date().timeIntervalSince1970 * 1000)
        appendRemoteCommands(controls.compactMap({$0["action"] as? Int}))
        appendRemoteCommands(systemActions)
    }
    
    func toArguments() -> NSArray {
        return [state.rawValue,0,position,speed,updateTime]
    }
    
    private func appendRemoteCommands(_ commands: [Int]) {
        commands.forEach({
            if let mediaAction = mediaActionToRemoteCommand(MediaAction(rawValue: $0)) {
                controls.append(mediaAction)
            }
        })
    }
    
    private func mediaActionToRemoteCommand(_ mediaAction: MediaAction?) -> RemoteCommand? {
        switch mediaAction {
        case .stop:
            return .stop
        case .pause:
            return .pause
        case .play:
            return .play
        case .rewind:
            //TODO add preferredIntervals
            return .skipBackward(preferredIntervals: [30])
        case .skipToPrevious:
            return .previous
        case .skipToNext:
            return .next
        case .fastForward:
            return .skipForward(preferredIntervals: [30])
        case .setRating:
            return nil
        case .seekTo:
            return .changePlaybackPosition
        case .playPause:
            return .togglePlayPause
        case .playFromMediaId:
            return nil
        case .playFromSearch:
            return nil
        case .skipToQueueItem:
            return nil
        case .playFromUri:
            return nil
        case .none:
            return nil
        }
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

/// The actons associated with playing audio.
public enum MediaAction: Int {
    
    case stop
    
    case pause
    
    case play
    
    case rewind
    
    case skipToPrevious
    
    case skipToNext
    
    case fastForward
    
    case setRating
    
    case seekTo
    
    case playPause
    
    case playFromMediaId
    
    case playFromSearch
    
    case skipToQueueItem
    
    case playFromUri
    
}
