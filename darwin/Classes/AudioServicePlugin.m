#import "AudioServicePlugin.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

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
        // TODO: Handle multiple clients.
        // As no separate isolate is used on macOS, add both handlers to the one registrar.
#if TARGET_OS_IPHONE
        if (channel == nil) {
#endif
            AudioServicePlugin *instance = [[AudioServicePlugin alloc] init:registrar];
            channel = [FlutterMethodChannel
                methodChannelWithName:@"ryanheise.com/audioService"
                      binaryMessenger:[registrar messenger]];
            [registrar addMethodCallDelegate:instance channel:channel];
#if TARGET_OS_IPHONE
        } else {
            AudioServicePlugin *instance = [[AudioServicePlugin alloc] init:registrar];
#endif
            backgroundChannel = [FlutterMethodChannel
                methodChannelWithName:@"ryanheise.com/audioServiceBackground"
                      binaryMessenger:[registrar messenger]];
            [registrar addMethodCallDelegate:instance channel:backgroundChannel];
#if TARGET_OS_IPHONE
        }
#endif
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

#if TARGET_OS_IPHONE
        [AVAudioSession sharedInstance];
#endif

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
        if (@available(iOS 9.0, macOS 10.12.2, *)) {
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

#if TARGET_OS_OSX
        // No isolate can be used for macOS until https://github.com/flutter/flutter/issues/65222 is resolved.
        // We send a result here, and then the Dart code continues in the main isolate.
        result(@YES);
#endif
    } else if ([@"ready" isEqualToString:call.method]) {
        NSMutableDictionary *startParams = [NSMutableDictionary new];
        startParams[@"fastForwardInterval"] = fastForwardInterval;
        startParams[@"rewindInterval"] = rewindInterval;
        startParams[@"params"] = params;
        result(startParams);
    } else if ([@"started" isEqualToString:call.method]) {
#if TARGET_OS_IPHONE
        if (startResult) {
            startResult(@YES);
            startResult = nil;
        }
#endif
        result(@YES);
    } else if ([@"stopped" isEqualToString:call.method]) {
        _running = NO;
        [channel invokeMethod:@"onStopped" arguments:nil];
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
#if TARGET_OS_IPHONE
                UIImage* artImage = [UIImage imageWithContentsOfFile:artCacheFilePath];
#else
                NSImage* artImage = [[NSImage alloc] initWithContentsOfFile:artCacheFilePath];
#endif
                if (artImage != nil) {
#if TARGET_OS_IPHONE
                    artwork = [[MPMediaItemArtwork alloc] initWithImage: artImage];
#else
                    artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artImage.size requestHandler:^NSImage* _Nonnull(CGSize aSize) {
                        return artImage;
                    }];
#endif
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
        if (@available(iOS 3.0, macOS 10.13.2, *)) {
            if (artwork) {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
            }
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
    // Shift the actionBits right until the least significant bit is the tested action bit, and AND that with a 1 at the same position.
    // All bytes become 0, other than the tested action bit, which will be 0 or 1 according to its status in the actionBits long.
    BOOL enable = ((actionBits >> action) & 1);
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
                    int rewindIntervalInSeconds = [rewindInterval intValue]/1000;
                    NSNumber *rewindIntervalInSec = [NSNumber numberWithInt: rewindIntervalInSeconds];
                    commandCenter.skipBackwardCommand.preferredIntervals = @[rewindIntervalInSec];
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
                    int fastForwardIntervalInSeconds = [fastForwardInterval intValue]/1000;
                    NSNumber *fastForwardIntervalInSec = [NSNumber numberWithInt: fastForwardIntervalInSeconds];
                    commandCenter.skipForwardCommand.preferredIntervals = @[fastForwardIntervalInSec];
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
            if (@available(iOS 9.1, macOS 10.12.2, *)) {
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
