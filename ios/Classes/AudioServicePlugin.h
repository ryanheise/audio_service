#import <Flutter/Flutter.h>

@interface AudioServicePlugin : NSObject<FlutterPlugin>

@property (readonly, nonatomic) FlutterMethodChannel *channel;

@end

enum AudioProcessingState {
    as_idle,
    as_loading,
    as_buffering,
    as_ready,
    as_completed,
    as_error
};

enum AudioInterruption {
    AIPause,
    AITemporaryPause,
    AITemporaryDuck,
    AIUnknownPause
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
    AUnused_2, // setCaptioningEnabled
    ASetShuffleMode,
    // Non-standard
    ASeekBackward,
    ASeekForward,
};
