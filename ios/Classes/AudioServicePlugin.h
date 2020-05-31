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
	pause,
	temporaryPause,
	temporaryDuck,
	unknownPause
};
