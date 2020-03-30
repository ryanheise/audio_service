//
//  RemoteCommandController.swift
//  audio_service
//
//  Created by Jørgen Henrichsen on 20/03/2018.
//  Modified by Mohamed Abdallah on 3/29/2020.
//

import Foundation
import MediaPlayer

public protocol RemoteCommandable {
    func getCommands() ->  [RemoteCommand]
}


public class RemoteCommandController {
    
    private let center: MPRemoteCommandCenter
    
    var playerActions: PlayerActions?
    
    var commandTargetPointers: [String: Any] = [:]
    
    init(remoteCommandCenter: MPRemoteCommandCenter = MPRemoteCommandCenter.shared(), playerActions: PlayerActions? = nil) {
        self.center = remoteCommandCenter
        self.playerActions = playerActions
    }
    
    func enable(commands: [RemoteCommand]) {
        self.disable(commands: RemoteCommand.all())
        commands.forEach { (command) in
            self.enable(command: command)
        }
    }
    
    func disable(commands: [RemoteCommand]) {
        commands.forEach { (command) in
            self.disable(command: command)
        }
    }
    
    private func enableCommand<Command: RemoteCommandProtocol>(_ command: Command) {
        center[keyPath: command.commandKeyPath].isEnabled = true
        commandTargetPointers[command.id] = center[keyPath: command.commandKeyPath].addTarget(handler: self[keyPath: command.handlerKeyPath])
    }
    
    private func disableCommand<Command: RemoteCommandProtocol>(_ command: Command) {
        center[keyPath: command.commandKeyPath].isEnabled = false
        center[keyPath: command.commandKeyPath].removeTarget(commandTargetPointers[command.id])
        commandTargetPointers.removeValue(forKey: command.id)
    }
    
    private func enable(command: RemoteCommand) {
        switch command {
        case .play: self.enableCommand(PlayBackCommand.play)
        case .pause: self.enableCommand(PlayBackCommand.pause)
        case .stop: self.enableCommand(PlayBackCommand.stop)
        case .togglePlayPause: self.enableCommand(PlayBackCommand.togglePlayPause)
        case .next: self.enableCommand(PlayBackCommand.nextTrack)
        case .previous: self.enableCommand(PlayBackCommand.previousTrack)
        case .changePlaybackPosition:
            if #available(iOS 9.1, *) {
                self.enableCommand(ChangePlaybackPositionCommand.changePlaybackPosition)
            } else {
                break
            }
        case .skipForward(let preferredIntervals): self.enableCommand(SkipIntervalCommand.skipForward.set(preferredIntervals: preferredIntervals))
        case .skipBackward(let preferredIntervals): self.enableCommand(SkipIntervalCommand.skipBackward.set(preferredIntervals: preferredIntervals))
        case .like(let isActive, let localizedTitle, let localizedShortTitle):
            self.enableCommand(FeedbackCommand.like.set(isActive: isActive, localizedTitle: localizedTitle, localizedShortTitle: localizedShortTitle))
        case .dislike(let isActive, let localizedTitle, let localizedShortTitle):
            self.enableCommand(FeedbackCommand.dislike.set(isActive: isActive, localizedTitle: localizedTitle, localizedShortTitle: localizedShortTitle))
        case .bookmark(let isActive, let localizedTitle, let localizedShortTitle):
            self.enableCommand(FeedbackCommand.bookmark.set(isActive: isActive, localizedTitle: localizedTitle, localizedShortTitle: localizedShortTitle))
        }
    }
    
    private func disable(command: RemoteCommand) {
        switch command {
        case .play: self.disableCommand(PlayBackCommand.play)
        case .pause: self.disableCommand(PlayBackCommand.pause)
        case .stop: self.disableCommand(PlayBackCommand.stop)
        case .togglePlayPause: self.disableCommand(PlayBackCommand.togglePlayPause)
        case .next: self.disableCommand(PlayBackCommand.nextTrack)
        case .previous: self.disableCommand(PlayBackCommand.previousTrack)
        case .changePlaybackPosition: if #available(iOS 9.1, *) {
            self.disableCommand(ChangePlaybackPositionCommand.changePlaybackPosition)
        } else {
            break
            }
        case .skipForward(_): self.disableCommand(SkipIntervalCommand.skipForward)
        case .skipBackward(_): self.disableCommand(SkipIntervalCommand.skipBackward)
        case .like(_, _, _): self.disableCommand(FeedbackCommand.like)
        case .dislike(_, _, _): self.disableCommand(FeedbackCommand.dislike)
        case .bookmark(_, _, _): self.disableCommand(FeedbackCommand.bookmark)
        }
    }
    // MARK: - Handlers
    
    public lazy var handlePlayCommand: RemoteCommandHandler = self.handlePlayCommandDefault
    public lazy var handlePauseCommand: RemoteCommandHandler = self.handlePauseCommandDefault
    public lazy var handleStopCommand: RemoteCommandHandler = self.handleStopCommandDefault
    public lazy var handleTogglePlayPauseCommand: RemoteCommandHandler = self.handleTogglePlayPauseCommandDefault
    public lazy var handleSkipForwardCommand: RemoteCommandHandler  = self.handleSkipForwardCommandDefault
    public lazy var handleSkipBackwardCommand: RemoteCommandHandler = self.handleSkipBackwardDefault
    public lazy var handleChangePlaybackPositionCommand: RemoteCommandHandler  = self.handleChangePlaybackPositionCommandDefault
    public lazy var handleNextTrackCommand: RemoteCommandHandler = self.handleNextTrackCommandDefault
    public lazy var handlePreviousTrackCommand: RemoteCommandHandler = self.handlePreviousTrackCommandDefault
    public lazy var handleLikeCommand: RemoteCommandHandler = self.handleLikeCommandDefault
    public lazy var handleDislikeCommand: RemoteCommandHandler = self.handleDislikeCommandDefault
    public lazy var handleBookmarkCommand: RemoteCommandHandler = self.handleBookmarkCommandDefault
    
    private func handlePlayCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let playerActions = self.playerActions {
            playerActions.play()
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handlePauseCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let playerActions = self.playerActions {
            playerActions.pause()
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleStopCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let playerActions = self.playerActions {
            playerActions.stop()
            return .success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleTogglePlayPauseCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let playerActions = self.playerActions {
            playerActions.togglePlaying()
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleSkipForwardCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let command = event.command as? MPSkipIntervalCommand,
            let interval = command.preferredIntervals.first,
            let playerActions = self.playerActions {
            playerActions.skipForward(interval: Double(truncating: interval))
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleSkipBackwardDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let command = event.command as? MPSkipIntervalCommand,
            let interval = command.preferredIntervals.first,
            let playerActions = self.playerActions {
            playerActions.skipBackward(interval: Double(truncating: interval))
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleChangePlaybackPositionCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let event = event as? MPChangePlaybackPositionCommandEvent,
            let playerActions = self.playerActions {
            playerActions.seek(to: event.positionTime * 1000)
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleNextTrackCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let playerActions = self.playerActions {
            playerActions.nextTrack()
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handlePreviousTrackCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let playerActions = self.playerActions {
            playerActions.previousTrack()
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleLikeCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        return MPRemoteCommandHandlerStatus.success
    }
    
    private func handleDislikeCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        return MPRemoteCommandHandlerStatus.success
    }
    
    private func handleBookmarkCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        return MPRemoteCommandHandlerStatus.success
    }
    
    private func getRemoteCommandHandlerStatus(forError error: Error) -> MPRemoteCommandHandlerStatus {
        //TODO handle errors
        //invalidSourceUrl, QueueError
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
}
