#import "AudioServicePlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
//#import <Foundation/Foundation.h>

// NOTE: This is a barebones implementation of the iOS side.
//
// If you'd like to help, please see the TODO comments below, then open a
// GitHub issue to announce your intention to work on a particular feature, and
// submit a pull request. We have an open discussion over at issue #10 about
// all things iOS if you'd like to discuss approaches or ask for input. Thank
// you for your support!

@implementation AudioServicePlugin

static FlutterMethodChannel *channel = nil;
static FlutterMethodChannel *backgroundChannel = nil;
static BOOL _running = NO;
static FlutterResult startResult = nil;
static MPRemoteCommandCenter *commandCenter = nil;
static NSArray *queue = nil;
static NSMutableDictionary *mediaItem = nil;
static long actionBits;
static NSArray *commands;
static BOOL _controlsUpdated = NO;
static enum AudioProcessingState processingState = none;
static BOOL playing = NO;
static NSNumber *position = nil;
static NSNumber *bufferedPosition = nil;
static NSNumber *updateTime = nil;
static NSNumber *speed = nil;
static NSNumber *repeatMode = nil;
static NSNumber *shuffleMode = nil;
static NSNumber *fastForwardInterval = nil;
static NSNumber *rewindInterval = nil;
static NSMutableDictionary *params = nil;
static MPMediaItemArtwork* artwork = nil;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    @synchronized(self) {
        // TODO: Need a reliable way to detect whether this is the client
        // or background.
        if (channel == nil) {
            AudioServicePlugin *clientInstance = [[AudioServicePlugin alloc] init:registrar];
            channel = [FlutterMethodChannel
                methodChannelWithName:@"ryanheise.com/audioService"
                      binaryMessenger:[registrar messenger]];
            [registrar addMethodCallDelegate:clientInstance channel:channel];
        } else {
            AudioServicePlugin *backgroundInstance = [[AudioServicePlugin alloc] init:registrar];
            backgroundChannel = [FlutterMethodChannel
                methodChannelWithName:@"ryanheise.com/audioServiceBackground"
                      binaryMessenger:[registrar messenger]];
            [registrar addMethodCallDelegate:backgroundInstance channel:backgroundChannel];
        }
    }
}

- (instancetype)init:(NSObject<FlutterPluginRegistrar> *)registrar {
    self = [super init];
    NSAssert(self, @"super init cannot be nil");
    return self;
}

- (void)broadcastPlaybackState {
    [channel invokeMethod:@"onPlaybackStateChanged" arguments:@[
        // processingState
        @(processingState),
        // playing
        @(playing),
        // actions
        @(actionBits),
        // position
        position,
        // bufferedPosition
        bufferedPosition,
        // playback speed
        speed,
        // update time since epoch
        updateTime,
        // repeat mode
        repeatMode,
        // shuffle mode
        shuffleMode,
    ]];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    // TODO:
    // - Restructure this so that we have a separate method call delegate
    //     for the client instance and the background instance so that methods
    //     can't be called on the wrong instance.
    if ([@"connect" isEqualToString:call.method]) {
        long long msSinceEpoch = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        if (position == nil) {
            position = @(0);
            bufferedPosition = @(0);
            updateTime = [NSNumber numberWithLongLong: msSinceEpoch];
            speed = [NSNumber numberWithDouble: 1.0];
            repeatMode = @(0);
            shuffleMode = @(0);
        }
        // Notify client of state on subscribing.
        [self broadcastPlaybackState];
        [channel invokeMethod:@"onMediaChanged" arguments:@[mediaItem ? mediaItem : [NSNull null]]];
        [channel invokeMethod:@"onQueueChanged" arguments:@[queue ? queue : [NSNull null]]];

        result(nil);
    } else if ([@"disconnect" isEqualToString:call.method]) {
        result(nil);
    } else if ([@"start" isEqualToString:call.method]) {
        if (_running) {
            result(@NO);
            return;
        }
        _running = YES;
        // The result will be sent after the background task actually starts.
        // See the "ready" case below.
        startResult = result;

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioInterrupt:) name:AVAudioSessionInterruptionNotification object:nil];

        // Initialise AVAudioSession
        NSNumber *categoryIndex = [call.arguments objectForKey:@"iosAudioSessionCategory"];
        AVAudioSessionCategory category = nil;
        switch (categoryIndex.integerValue) {
            case 0: category = AVAudioSessionCategoryAmbient; break;
            case 1: category = AVAudioSessionCategorySoloAmbient; break;
            case 2: category = AVAudioSessionCategoryPlayback; break;
            case 3: category = AVAudioSessionCategoryRecord; break;
            case 4: category = AVAudioSessionCategoryPlayAndRecord; break;
            case 5: category = AVAudioSessionCategoryMultiRoute; break;
        }
        NSNumber *categoryOptions = [call.arguments objectForKey:@"iosAudioSessionCategoryOptions"];
        if (categoryOptions != [NSNull null]) {
            [[AVAudioSession sharedInstance] setCategory:category withOptions:[categoryOptions integerValue] error:nil];
        } else {
            [[AVAudioSession sharedInstance] setCategory:category error:nil];
        }
        [[AVAudioSession sharedInstance] setActive: YES error: nil];
        // Set callbacks on MPRemoteCommandCenter
        fastForwardInterval = [call.arguments objectForKey:@"fastForwardInterval"];
        rewindInterval = [call.arguments objectForKey:@"rewindInterval"];
        commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
        commands = @[
            commandCenter.stopCommand,
            commandCenter.pauseCommand,
            commandCenter.playCommand,
            commandCenter.skipBackwardCommand,
            commandCenter.previousTrackCommand,
            commandCenter.nextTrackCommand,
            commandCenter.skipForwardCommand,
            [NSNull null],
            commandCenter.changePlaybackPositionCommand,
            commandCenter.togglePlayPauseCommand,
            [NSNull null],
            [NSNull null],
            [NSNull null],
            [NSNull null],
            [NSNull null],
            [NSNull null],
            [NSNull null],
            [NSNull null],
            commandCenter.changeRepeatModeCommand,
            [NSNull null],
            [NSNull null],
            commandCenter.changeShuffleModeCommand,
            commandCenter.seekBackwardCommand,
            commandCenter.seekForwardCommand,
        ];
        [commandCenter.changePlaybackRateCommand setEnabled:YES];
        [commandCenter.togglePlayPauseCommand setEnabled:YES];
        [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(togglePlayPause:)];
        // TODO: enable more commands
        // Language options
        if (@available(iOS 9.0, *)) {
            [commandCenter.enableLanguageOptionCommand setEnabled:NO];
            [commandCenter.disableLanguageOptionCommand setEnabled:NO];
        }
        // Rating
        [commandCenter.ratingCommand setEnabled:NO];
        // Feedback
        [commandCenter.likeCommand setEnabled:NO];
        [commandCenter.dislikeCommand setEnabled:NO];
        [commandCenter.bookmarkCommand setEnabled:NO];
        [self updateControls];

        // Params
        params = [call.arguments objectForKey:@"params"];

    } else if ([@"ready" isEqualToString:call.method]) {
        NSMutableDictionary *startParams = [NSMutableDictionary new];
        startParams[@"fastForwardInterval"] = fastForwardInterval;
        startParams[@"rewindInterval"] = rewindInterval;
        startParams[@"params"] = params;
        result(startParams);
    } else if ([@"started" isEqualToString:call.method]) {
        if (startResult) {
            startResult(@YES);
            startResult = nil;
        }
        result(@YES);
    } else if ([@"stopped" isEqualToString:call.method]) {
        _running = NO;
        [channel invokeMethod:@"onStopped" arguments:nil];
        [[AVAudioSession sharedInstance] setActive: NO error: nil];
        [commandCenter.changePlaybackRateCommand setEnabled:NO];
        [commandCenter.togglePlayPauseCommand setEnabled:NO];
        [commandCenter.togglePlayPauseCommand removeTarget:nil];
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
        processingState = none;
        playing = NO;
        position = nil;
        bufferedPosition = nil;
        updateTime = nil;
        speed = nil;
        artwork = nil;
        mediaItem = nil;
        repeatMode = @(0);
        shuffleMode = @(0);
        actionBits = 0;
        [self updateControls];
        _controlsUpdated = NO;
        queue = nil;
        startResult = nil;
        fastForwardInterval = nil;
        rewindInterval = nil;
        params = nil;
        commandCenter = nil;
        result(@YES);
    } else if ([@"isRunning" isEqualToString:call.method]) {
        if (_running) {
            result(@YES);
        } else {
            result(@NO);
        }
    } else if ([@"setBrowseMediaParent" isEqualToString:call.method]) {
        result(@YES);
    } else if ([@"addQueueItem" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onAddQueueItem" arguments:@[call.arguments] result: result];
    } else if ([@"addQueueItemAt" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onAddQueueItemAt" arguments:call.arguments result: result];
    } else if ([@"removeQueueItem" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onRemoveQueueItem" arguments:@[call.arguments] result: result];
    } else if ([@"updateQueue" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onUpdateQueue" arguments:@[call.arguments] result: result];
    } else if ([@"updateMediaItem" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onUpdateMediaItem" arguments:@[call.arguments] result: result];
    } else if ([@"click" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onClick" arguments:@[call.arguments] result: result];
    } else if ([@"prepare" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onPrepare" arguments:nil result: result];
    } else if ([@"prepareFromMediaId" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onPrepareFromMediaId" arguments:@[call.arguments] result: result];
    } else if ([@"play" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onPlay" arguments:nil result: result];
    } else if ([@"playFromMediaId" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onPlayFromMediaId" arguments:@[call.arguments] result: result];
    } else if ([@"playMediaItem" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onPlayMediaItem" arguments:@[call.arguments] result: result];
    } else if ([@"skipToQueueItem" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSkipToQueueItem" arguments:@[call.arguments] result: result];
    } else if ([@"pause" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onPause" arguments:nil result: result];
    } else if ([@"stop" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onStop" arguments:nil result: result];
    } else if ([@"seekTo" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSeekTo" arguments:@[call.arguments] result: result];
    } else if ([@"skipToNext" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSkipToNext" arguments:nil result: result];
    } else if ([@"skipToPrevious" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSkipToPrevious" arguments:nil result: result];
    } else if ([@"fastForward" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onFastForward" arguments:nil result: result];
    } else if ([@"rewind" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onRewind" arguments:nil result: result];
    } else if ([@"setRepeatMode" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSetRepeatMode" arguments:@[call.arguments] result: result];
    } else if ([@"setShuffleMode" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSetShuffleMode" arguments:@[call.arguments] result: result];
    } else if ([@"setRating" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSetRating" arguments:@[call.arguments[@"rating"], call.arguments[@"extras"]] result: result];
    } else if ([@"setSpeed" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSetSpeed" arguments:@[call.arguments] result: result];
    } else if ([@"seekForward" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSeekForward" arguments:@[call.arguments] result: result];
    } else if ([@"seekBackward" isEqualToString:call.method]) {
        [backgroundChannel invokeMethod:@"onSeekBackward" arguments:@[call.arguments] result: result];
    } else if ([@"setState" isEqualToString:call.method]) {
        long long msSinceEpoch;
        if (call.arguments[7] != [NSNull null]) {
            msSinceEpoch = [call.arguments[7] longLongValue];
        } else {
            msSinceEpoch = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        }
        actionBits = 0;
        NSArray *controlsArray = call.arguments[0];
        for (int i = 0; i < controlsArray.count; i++) {
            NSDictionary *control = (NSDictionary *)controlsArray[i];
            NSNumber *actionIndex = (NSNumber *)control[@"action"];
            int actionCode = 1 << [actionIndex intValue];
            actionBits |= actionCode;
        }
        NSArray *systemActionsArray = call.arguments[1];
        for (int i = 0; i < systemActionsArray.count; i++) {
            NSNumber *actionIndex = (NSNumber *)systemActionsArray[i];
            int actionCode = 1 << [actionIndex intValue];
            actionBits |= actionCode;
        }
        processingState = [call.arguments[2] intValue];
        playing = [call.arguments[3] boolValue];
        position = call.arguments[4];
        bufferedPosition = call.arguments[5];
        speed = call.arguments[6];
        repeatMode = call.arguments[9];
        shuffleMode = call.arguments[10];
        updateTime = [NSNumber numberWithLongLong: msSinceEpoch];
        [self broadcastPlaybackState];
        [self updateControls];
        [self updateNowPlayingInfo];
        result(@(YES));
    } else if ([@"setQueue" isEqualToString:call.method]) {
        queue = call.arguments;
        [channel invokeMethod:@"onQueueChanged" arguments:@[queue]];
        result(@YES);
    } else if ([@"setMediaItem" isEqualToString:call.method]) {
        mediaItem = call.arguments;
        NSString* artUri = mediaItem[@"artUri"];
        artwork = nil;
        if (![artUri isEqual: [NSNull null]]) {
            NSString* artCacheFilePath = [NSNull null];
            NSDictionary* extras = mediaItem[@"extras"];
            if (![extras isEqual: [NSNull null]]) {
                artCacheFilePath = extras[@"artCacheFile"];
            }
            if (![artCacheFilePath isEqual: [NSNull null]]) {
                UIImage* artImage = [UIImage imageWithContentsOfFile:artCacheFilePath];
                if (artImage != nil) {
                    artwork = [[MPMediaItemArtwork alloc] initWithImage: artImage];
                }
            }
        }
        [self updateNowPlayingInfo];
        [channel invokeMethod:@"onMediaChanged" arguments:@[call.arguments]];
        result(@(YES));
    } else if ([@"notifyChildrenChanged" isEqualToString:call.method]) {
        result(@YES);
    } else if ([@"androidForceEnableMediaButtons" isEqualToString:call.method]) {
        result(@YES);
    } else {
        // TODO: Check if this implementation is correct.
        // Can I just pass on the result as the last argument?
        [backgroundChannel invokeMethod:call.method arguments:call.arguments result: result];
    }
}

- (MPRemoteCommandHandlerStatus) play: (MPRemoteCommandEvent *) event {
    NSLog(@"play");
    [backgroundChannel invokeMethod:@"onPlay" arguments:nil];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) pause: (MPRemoteCommandEvent *) event {
    NSLog(@"pause");
    [backgroundChannel invokeMethod:@"onPause" arguments:nil];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (void) updateNowPlayingInfo {
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary new];
    if (mediaItem) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = mediaItem[@"title"];
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = mediaItem[@"album"];
        if (mediaItem[@"artist"] != [NSNull null]) {
            nowPlayingInfo[MPMediaItemPropertyArtist] = mediaItem[@"artist"];
        }
        if (mediaItem[@"duration"] != [NSNull null]) {
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = [NSNumber numberWithLongLong: ([mediaItem[@"duration"] longLongValue] / 1000)];
        }
        if (artwork) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
        }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = [NSNumber numberWithInt:([position intValue] / 1000)];
    }
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = [NSNumber numberWithDouble: playing ? 1.0 : 0.0];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
}

- (void) updateControls {
    for (enum MediaAction action = AStop; action <= ASeekForward; action++) {
        [self updateControl:action];
    }
    _controlsUpdated = YES;
}

- (void) updateControl:(enum MediaAction)action {
    MPRemoteCommand *command = commands[action];
    if (command == [NSNull null]) return;
    int actionBit = 1 << action;
    BOOL enable = actionBits & actionBit;
    if (_controlsUpdated && enable == command.enabled) return;
    [command setEnabled:enable];
    switch (action) {
        case AStop:
            if (enable) {
                [commandCenter.stopCommand addTarget:self action:@selector(stop:)];
            } else {
                [commandCenter.stopCommand removeTarget:nil];
            }
            break;
        case APause:
            if (enable) {
                [commandCenter.pauseCommand addTarget:self action:@selector(pause:)];
            } else {
                [commandCenter.pauseCommand removeTarget:nil];
            }
            break;
        case APlay:
            if (enable) {
                [commandCenter.playCommand addTarget:self action:@selector(play:)];
            } else {
                [commandCenter.playCommand removeTarget:nil];
            }
            break;
        case ARewind:
            if (rewindInterval.integerValue > 0) {
                if (enable) {
                    [commandCenter.skipBackwardCommand addTarget: self action:@selector(skipBackward:)];
                    commandCenter.skipBackwardCommand.preferredIntervals = @[rewindInterval];
                } else {
                    [commandCenter.skipBackwardCommand removeTarget:nil];
                }
            }
            break;
        case ASkipToPrevious:
            if (enable) {
                [commandCenter.previousTrackCommand addTarget:self action:@selector(previousTrack:)];
            } else {
                [commandCenter.previousTrackCommand removeTarget:nil];
            }
            break;
        case ASkipToNext:
            if (enable) {
                [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrack:)];
            } else {
                [commandCenter.nextTrackCommand removeTarget:nil];
            }
            break;
        case AFastForward:
            if (fastForwardInterval.integerValue > 0) {
                if (enable) {
                    [commandCenter.skipForwardCommand addTarget: self action:@selector(skipForward:)];
                    commandCenter.skipForwardCommand.preferredIntervals = @[fastForwardInterval];
                } else {
                    [commandCenter.skipForwardCommand removeTarget:nil];
                }
            }
            break;
        case ASetRating:
            // TODO:
            // commandCenter.ratingCommand
            // commandCenter.dislikeCommand
            // commandCenter.bookmarkCommand
            break;
        case ASeekTo:
            if (@available(iOS 9.1, *)) {
                if (enable) {
                    [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(changePlaybackPosition:)];
                } else {
                    [commandCenter.changePlaybackPositionCommand removeTarget:nil];
                }
            }
        case APlayPause:
            // Automatically enabled.
            break;
        case ASetRepeatMode:
            if (enable) {
                [commandCenter.changeRepeatModeCommand addTarget:self action:@selector(changeRepeatMode:)];
            } else {
                [commandCenter.changeRepeatModeCommand removeTarget:nil];
            }
            break;
        case ASetShuffleMode:
            if (enable) {
                [commandCenter.changeShuffleModeCommand addTarget:self action:@selector(changeShuffleMode:)];
            } else {
                [commandCenter.changeShuffleModeCommand removeTarget:nil];
            }
            break;
        case ASeekBackward:
            if (enable) {
                [commandCenter.seekBackwardCommand addTarget:self action:@selector(seekBackward:)];
            } else {
                [commandCenter.seekBackwardCommand removeTarget:nil];
            }
            break;
        case ASeekForward:
            if (enable) {
                [commandCenter.seekForwardCommand addTarget:self action:@selector(seekForward:)];
            } else {
                [commandCenter.seekForwardCommand removeTarget:nil];
            }
            break;
    }
}

- (void) audioInterrupt:(NSNotification*)notification {
    NSNumber *interruptionType = (NSNumber*)[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey];
    switch ([interruptionType integerValue]) {
        case AVAudioSessionInterruptionTypeBegan:
        {
            enum AudioInterruption interruption = AIUnknownPause;
            [backgroundChannel invokeMethod:@"onAudioFocusLost" arguments:@[@(interruption)]];
            break;
        }
        case AVAudioSessionInterruptionTypeEnded:
        {
            if ([(NSNumber*)[notification.userInfo valueForKey:AVAudioSessionInterruptionOptionKey] intValue] == AVAudioSessionInterruptionOptionShouldResume) {
                enum AudioInterruption interruption = AITemporaryPause;
                [backgroundChannel invokeMethod:@"onAudioFocusGained" arguments:@[@(interruption)]];
            } else {
                enum AudioInterruption interruption = AIPause;
                [backgroundChannel invokeMethod:@"onAudioFocusGained" arguments:@[@(interruption)]];
            }
            break;
        }
        default:
            break;
    }
}

- (MPRemoteCommandHandlerStatus) togglePlayPause: (MPRemoteCommandEvent *) event {
    NSLog(@"togglePlayPause");
    [backgroundChannel invokeMethod:@"onClick" arguments:@[@(0)]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) stop: (MPRemoteCommandEvent *) event {
    NSLog(@"stop");
    [backgroundChannel invokeMethod:@"onStop" arguments:nil];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) nextTrack: (MPRemoteCommandEvent *) event {
    NSLog(@"nextTrack");
    [backgroundChannel invokeMethod:@"onSkipToNext" arguments:nil];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) previousTrack: (MPRemoteCommandEvent *) event {
    NSLog(@"previousTrack");
    [backgroundChannel invokeMethod:@"onSkipToPrevious" arguments:nil];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) changePlaybackPosition: (MPChangePlaybackPositionCommandEvent *) event {
    NSLog(@"changePlaybackPosition");
    [backgroundChannel invokeMethod:@"onSeekTo" arguments: @[@((long long) (event.positionTime * 1000))]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) skipForward: (MPRemoteCommandEvent *) event {
    NSLog(@"skipForward");
    [backgroundChannel invokeMethod:@"onFastForward" arguments:nil];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) skipBackward: (MPRemoteCommandEvent *) event {
    NSLog(@"skipBackward");
    [backgroundChannel invokeMethod:@"onRewind" arguments:nil];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) seekForward: (MPSeekCommandEvent *) event {
    NSLog(@"seekForward");
    BOOL begin = event.type == MPSeekCommandEventTypeBeginSeeking;
    [backgroundChannel invokeMethod:@"onSeekForward" arguments:@[@(begin)]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) seekBackward: (MPSeekCommandEvent *) event {
    NSLog(@"seekBackward");
    BOOL begin = event.type == MPSeekCommandEventTypeBeginSeeking;
    [backgroundChannel invokeMethod:@"onSeekBackward" arguments:@[@(begin)]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) changeRepeatMode: (MPChangeRepeatModeCommandEvent *) event {
    NSLog(@"changeRepeatMode");
    int modeIndex;
    switch (event.repeatType) {
        case MPRepeatTypeOff:
            modeIndex = 0;
            break;
        case MPRepeatTypeOne:
            modeIndex = 1;
            break;
        // MPRepeatTypeAll
        default:
            modeIndex = 2;
            break;
    }
    [backgroundChannel invokeMethod:@"onSetRepeatMode" arguments:@[@(modeIndex)]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) changeShuffleMode: (MPChangeShuffleModeCommandEvent *) event {
    NSLog(@"changeShuffleMode");
    int modeIndex;
    switch (event.shuffleType) {
        case MPShuffleTypeOff:
            modeIndex = 0;
            break;
        case MPShuffleTypeItems:
            modeIndex = 1;
            break;
        // MPShuffleTypeCollections
        default:
            modeIndex = 2;
            break;
    }
    [backgroundChannel invokeMethod:@"onSetShuffleMode" arguments:@[@(modeIndex)]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
