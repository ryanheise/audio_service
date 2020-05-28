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
