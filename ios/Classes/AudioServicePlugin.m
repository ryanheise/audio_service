#import "AudioServicePlugin.h"

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
    result(nil);
  } else if ([@"disconnect" isEqualToString:call.method]) {
    result(nil);
  } else if ([@"start" isEqualToString:call.method]) {
    if (_running) {
      result(@NO);
    }
    _running = YES;
    // The result will be sent after the background task actually starts.
    // See the "ready" case below.
    startResult = result;
    // Initialise AVAudioSession
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive: YES error: nil];
    // Set callbacks on MPRemoteCommandCenter
    commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(togglePlayPause)];
    [commandCenter.playCommand addTarget:self action:@selector(togglePlayPause)];
    [commandCenter.pauseCommand addTarget:self action:@selector(togglePlayPause)];
    [commandCenter.stopCommand addTarget:self action:@selector(stop)];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrack)];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(previousTrack)];
    [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(changePlaybackPosition)];
    // TODO: enable more commands
    // Skipping
    commandCenter.skipForwardCommand.isEnabled = false;
    commandCenter.skipBackwardCommand.isEnabled = false;
    // Seeking
    commandCenter.seekForwardCommand.isEnabled = false;
    commandCenter.seekBackwardCommand.isEnabled = false;
    // Language options
    commandCenter.enableLanguageOptionCommand.isEnabled = false;
    commandCenter.disableLanguageOptionCommand.isEnabled = false;
    // Repeat/Shuffle
    commandCenter.changeRepeatModeCommand.isEnabled = false;
    commandCenter.changeShuffleModeCommand.isEnabled = false;
    // Rating
    commandCenter.ratingCommand.isEnabled = false;
    // Feedback
    commandCenter.likeCommand.isEnabled = false;
    commandCenter.dislikeCommand.isEnabled = false;
    commandCenter.bookmarkCommand.isEnabled = false;
  } else if ([@"ready" isEqualToString:call.method]) {
    result(@YES);
    startResult(@YES);
    startResult = nil;
  } else if ([@"stopped" isEqualToString:call.method]) {
    _running = NO;
    [channel invokeMethod:@"onStopped" arguments:nil];
    // TODO: (maybe)
    // Do we need to stop the AVAudioSession?
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
    [backgroundChannel invokeMethod:@"onAddQueueItem" arguments:call.arguments];
    result(@YES);
  } else if ([@"addQueueItemAt" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onAddQueueItemAt" arguments:call.arguments];
    result(@YES);
  } else if ([@"removeQueueItem" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onRemoveQueueItem" arguments:call.arguments];
    result(@YES);
  } else if ([@"click" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onClick" arguments:call.arguments];
    result(@YES);
  } else if ([@"prepare" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPrepare" arguments:nil];
    result(@YES);
  } else if ([@"prepareFromMediaId" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPrepareFromMediaId" arguments:call.arguments];
    result(@YES);
  } else if ([@"play" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPlay" arguments:nil];
    result(@YES);
  } else if ([@"playFromMediaId" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPlayFromMediaId" arguments:call.arguments];
    result(@YES);
  } else if ([@"skipToQueueItem" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onSkipToQueueItem" arguments:call.arguments];
    result(@YES);
  } else if ([@"pause" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onPause" arguments:nil];
    result(@YES);
  } else if ([@"stop" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onStop" arguments:nil];
    result(@YES);
  } else if ([@"seekTo" isEqualToString:call.method]) {
    [backgroundChannel invokeMethod:@"onSeekTo" arguments:call.arguments];
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
    [backgroundChannel invokeMethod:@"onSetRating" arguments:call.arguments];
    result(@YES);
  } else if ([@"setState" isEqualToString:call.method]) {
    [channel invokeMethod:@"onPlaybackStateChanged" arguments:@[
      // state
      call.arguments[1],
      // actions (TODO)
      @(0),
      // position
      call.arguments[2],
      // playback speed
      call.arguments[3],
      // update time since epoch (TODO!)
      @(0)
    ]];
    result(@(YES));
  } else if ([@"setQueue" isEqualToString:call.method]) {
    // TODO: pass through to onSetQueue
    result(@YES);
  } else if ([@"setMediaItem" isEqualToString:call.method]) {
    // TODO:
    // - Update MPNowPlayingInfoCenter (nowPlayingInfo)
    [channel invokeMethod:@"onMediaChanged" arguments:call.arguments];
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
- (void) togglePlayPause {
  [backgroundChannel invokeMethod:@"onTogglePlayPause" arguments:nil];
}
- (void) stop {
  [backgroundChannel invokeMethod:@"onStop" arguments:nil];
}
- (void) nextTrack {
  [backgroundChannel invokeMethod:@"onSkipToNext" arguments:nil];
}
- (void) previousTrack {
  [backgroundChannel invokeMethod:@"onSkipToPrevious" arguments:nil];
}
- (void) changePlaybackPosition: (MPChangePlaybackPositionCommandEvent) event {
  [backgroundChannel invokeMethod:@"onSeekTo" arguments: @[event.positionTime]];
}

@end
