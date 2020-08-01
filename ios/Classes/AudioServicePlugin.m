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
static enum AudioProcessingState processingState = none;
static BOOL playing = NO;
static NSNumber *position = nil;
static NSNumber *bufferedPosition = nil;
static NSNumber *updateTime = nil;
static NSNumber *speed = nil;
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
  // Nothing here yet.
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  // TODO:
  // - Restructure this so that we have a separate method call delegate
  //   for the client instance and the background instance so that methods
  //   can't be called on the wrong instance.
  if ([@"connect" isEqualToString:call.method]) {
    long long msSinceEpoch = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    // Notify client of state on subscribing.
    if (position == nil) {
      position = @(0);
      bufferedPosition = @(0);
      updateTime = [NSNumber numberWithLongLong: msSinceEpoch];
      speed = [NSNumber numberWithDouble: 1.0];
    }
    [channel invokeMethod:@"onPlaybackStateChanged" arguments:@[
      // processingState
      @(processingState),
      // playing
      @(playing),
      // actions (TODO)
      @(0),
      // position
      position,
      // bufferedPosition
      bufferedPosition,
      // playback speed
      speed,
      // update time since epoch
      updateTime
    ]];
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
    commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.togglePlayPauseCommand setEnabled:YES];
    [commandCenter.playCommand setEnabled:YES];
    [commandCenter.pauseCommand setEnabled:YES];
    [commandCenter.stopCommand setEnabled:YES];
    [commandCenter.nextTrackCommand setEnabled:YES];
    [commandCenter.previousTrackCommand setEnabled:YES];
    [commandCenter.changePlaybackRateCommand setEnabled:YES];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(togglePlayPause:)];
    [commandCenter.playCommand addTarget:self action:@selector(play:)];
    [commandCenter.pauseCommand addTarget:self action:@selector(pause:)];
    [commandCenter.stopCommand addTarget:self action:@selector(stop:)];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrack:)];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(previousTrack:)];
    if (@available(iOS 9.1, *)) {
      [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(changePlaybackPosition:)];
    }
    // Skipping
    fastForwardInterval = [call.arguments objectForKey:@"fastForwardInterval"];
    rewindInterval = [call.arguments objectForKey:@"rewindInterval"];
    if (fastForwardInterval.integerValue > 0) {
      [commandCenter.skipForwardCommand setEnabled:YES];
      [commandCenter.skipForwardCommand addTarget: self action:@selector(skipForward:)];
      commandCenter.skipForwardCommand.preferredIntervals = @[fastForwardInterval];
    }
    if (rewindInterval.integerValue > 0) {
      [commandCenter.skipBackwardCommand setEnabled:YES];
      [commandCenter.skipBackwardCommand addTarget: self action:@selector(skipBackward:)];
      commandCenter.skipBackwardCommand.preferredIntervals = @[rewindInterval];
    }
    // Params
    params = [call.arguments objectForKey:@"params"];

    // TODO: enable more commands
    // Seeking
    [commandCenter.seekForwardCommand setEnabled:NO];
    [commandCenter.seekBackwardCommand setEnabled:NO];
    // Language options
    if (@available(iOS 9.0, *)) {
      [commandCenter.enableLanguageOptionCommand setEnabled:NO];
      [commandCenter.disableLanguageOptionCommand setEnabled:NO];
    }
    // Repeat/Shuffle
    [commandCenter.changeRepeatModeCommand setEnabled:NO];
    [commandCenter.changeShuffleModeCommand setEnabled:NO];
    // Rating
    [commandCenter.ratingCommand setEnabled:NO];
    // Feedback
    [commandCenter.likeCommand setEnabled:NO];
    [commandCenter.dislikeCommand setEnabled:NO];
    [commandCenter.bookmarkCommand setEnabled:NO];
  } else if ([@"ready" isEqualToString:call.method]) {
    NSMutableDictionary *startParams = [NSMutableDictionary new];
    startParams[@"fastForwardInterval"] = fastForwardInterval;
    startParams[@"rewindInterval"] = rewindInterval;
    startParams[@"params"] = params;
    result(startParams);
    if (startResult) {
      startResult(@YES);
      startResult = nil;
    }
  } else if ([@"stopped" isEqualToString:call.method]) {
    _running = NO;
    [channel invokeMethod:@"onStopped" arguments:nil];
    [[AVAudioSession sharedInstance] setActive: NO error: nil];
    [commandCenter.togglePlayPauseCommand setEnabled:NO];
    [commandCenter.playCommand setEnabled:NO];
    [commandCenter.pauseCommand setEnabled:NO];
    [commandCenter.stopCommand setEnabled:NO];
    [commandCenter.nextTrackCommand setEnabled:NO];
    [commandCenter.previousTrackCommand setEnabled:NO];
    [commandCenter.changePlaybackRateCommand setEnabled:NO];
    [commandCenter.togglePlayPauseCommand removeTarget:nil];
    [commandCenter.playCommand removeTarget:nil];
    [commandCenter.pauseCommand removeTarget:nil];
    [commandCenter.stopCommand removeTarget:nil];
    [commandCenter.nextTrackCommand removeTarget:nil];
    [commandCenter.previousTrackCommand removeTarget:nil];
    if (@available(iOS 9.1, *)) {
      [commandCenter.changePlaybackPositionCommand removeTarget:nil];
    }
    // Skipping
    [commandCenter.skipForwardCommand setEnabled:NO];
    [commandCenter.skipBackwardCommand setEnabled:NO];
    [commandCenter.skipForwardCommand removeTarget:nil];
    [commandCenter.skipBackwardCommand removeTarget:nil];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    processingState = none;
    playing = NO;
    position = nil;
    bufferedPosition = nil;
    updateTime = nil;
    speed = nil;
    artwork = nil;
    mediaItem = nil;
    queue = nil;
    startResult = nil;
    fastForwardInterval = nil;
    rewindInterval = nil;
    params = nil;
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
    [backgroundChannel invokeMethod:@"onAddQueueItem" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"addQueueItemAt" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onAddQueueItemAt" arguments:call.arguments];
    result(@YES);
  } else if ([@"removeQueueItem" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onRemoveQueueItem" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"updateQueue" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onUpdateQueue" arguments:@[call.arguments] result: result];
  } else if ([@"updateMediaItem" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onUpdateMediaItem" arguments:@[call.arguments] result: result];
  } else if ([@"click" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onClick" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"prepare" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPrepare" arguments:nil];
    result(@YES);
  } else if ([@"prepareFromMediaId" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPrepareFromMediaId" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"play" isEqualToString:call.method]) {
    [self play: nil];
    result(@YES);
  } else if ([@"playFromMediaId" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPlayFromMediaId" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"playMediaItem" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPlayMediaItem" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"skipToQueueItem" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onSkipToQueueItem" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"pause" isEqualToString:call.method]) {
    [self pause: nil];
    result(@YES);
  } else if ([@"stop" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onStop" arguments:nil];
    result(@YES);
  } else if ([@"seekTo" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onSeekTo" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"skipToNext" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onSkipToNext" arguments:nil];
    result(@YES);
  } else if ([@"skipToPrevious" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onSkipToPrevious" arguments:nil];
    result(@YES);
  } else if ([@"fastForward" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onFastForward" arguments:nil];
    result(@YES);
  } else if ([@"rewind" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onRewind" arguments:nil];
    result(@YES);
  } else if ([@"setRating" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onSetRating" arguments:@[call.arguments, [NSNull null]]];
    result(@YES);
  } else if ([@"setSpeed" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onSetSpeed" arguments:@[call.arguments]];
    result(@YES);
  } else if ([@"setState" isEqualToString:call.method]) {
    long long msSinceEpoch;
    if (call.arguments[7] != [NSNull null]) {
      msSinceEpoch = [call.arguments[7] longLongValue];
    } else {
      msSinceEpoch = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
    }
    processingState = [call.arguments[2] intValue];
    playing = [call.arguments[3] boolValue];
    position = call.arguments[4];
    bufferedPosition = call.arguments[5];
    speed = call.arguments[6];
    updateTime = [NSNumber numberWithLongLong: msSinceEpoch];
    [channel invokeMethod:@"onPlaybackStateChanged" arguments:@[
      // processingState
      @(processingState),
      // playing
      @(playing),
      // actions (TODO)
      @(0),
      // position
      position,
      // bufferedPosition
      bufferedPosition,
      // playback speed
      speed,
      // update time since epoch
      updateTime
    ]];
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

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
