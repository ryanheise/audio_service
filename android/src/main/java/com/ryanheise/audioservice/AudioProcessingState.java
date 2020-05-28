package com.ryanheise.audioservice;

public enum AudioProcessingState {
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
  error,
}
