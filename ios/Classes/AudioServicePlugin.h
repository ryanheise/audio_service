#import <Flutter/Flutter.h>

@interface AudioServicePlugin : NSObject<FlutterPlugin>
@end

enum AudioProcessingState {
    none,
    connecting,
    ready,
    buffering,
    fastForwarding,
    rewinding,
    skippingToPrevious,
    skippingToNext,
    skippingToQueueItem,
    completed,
    stopped,
    error
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
