#import <Flutter/Flutter.h>

@interface AudioServicePlugin : NSObject<FlutterPlugin>

@property (readonly, nonatomic) FlutterMethodChannel *channel;

@end

enum AudioProcessingState {
    ApsIdle,
    ApsLoading,
    ApsBuffering,
    ApsReady,
    ApsCompleted,
    ApsError
};

enum MediaAction {
    AStop,
    APause,
    APlay,
    ARewind,
    ASkipToPrevious,
    ASkipToNext,
    AFastForward,
    ASetRating,
    ASeekTo,
    APlayPause,
    APlayFromMediaId,
    APlayFromSearch,
    ASkipToQueueItem,
    APlayFromUri,
    APrepare,
    APrepareFromMediaId,
    APrepareFromSearch,
    APrepareFromUri,
    ASetRepeatMode,
    AUnused_1, // deprecated (setShuffleModeEnabled)
    ASetCaptioningEnabled,
    ASetShuffleMode,
    ASetSpeed,
    ASeekBackward,
    ASeekForward,
};
