import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BaseAudioHandler:', () {
    test('playbackState returns default PlaybackState()', () {
      final audioHandler = BaseAudioHandler();
      final expected = PlaybackState();
      final actual = audioHandler.playbackState.value;
      expect(actual.processingState, equals(expected.processingState));
      expect(actual.playing, equals(expected.playing));
      expect(actual.controls, equals(expected.controls));
      expect(actual.androidCompactActionIndices,
          equals(expected.androidCompactActionIndices));
      expect(actual.systemActions, equals(expected.systemActions));
      expect(actual.updatePosition, equals(expected.updatePosition));
      expect(actual.bufferedPosition, equals(expected.bufferedPosition));
      expect(actual.speed, equals(expected.speed));
      expect(actual.updateTime.millisecond,
          closeTo(expected.updateTime.millisecond, 1000));
      expect(actual.errorCode, equals(expected.errorCode));
      expect(actual.errorMessage, equals(expected.errorMessage));
      expect(actual.repeatMode, equals(expected.repeatMode));
      expect(actual.shuffleMode, equals(expected.shuffleMode));
      expect(actual.captioningEnabled, equals(expected.captioningEnabled));
      expect(actual.queueIndex, equals(expected.queueIndex));
    });

    test('queue returns empty media item list', () {
      final audioHandler = BaseAudioHandler();
      final queue = audioHandler.queue.value;
      expect(queue, equals(<MediaItem>[]));
    });

    test('queueTitle returns empty string', () {
      final audioHandler = BaseAudioHandler();
      final queueTitle = audioHandler.queueTitle.value;
      expect(queueTitle, equals(''));
    });

    test('mediaItem returns null', () {
      final audioHandler = BaseAudioHandler();
      final mediaItem = audioHandler.mediaItem.value;
      expect(mediaItem, isNull);
    });

    test('androidPlaybackInfo returns BehaviorSubject', () {
      final audioHandler = BaseAudioHandler();
      final androidPlaybackInfo = audioHandler.androidPlaybackInfo;
      expect(androidPlaybackInfo, isA<BehaviorSubject<AndroidPlaybackInfo>>());
    });

    test('ratingStyle is a BehaviorSubject', () {
      final audioHandler = BaseAudioHandler();
      final ratingStyle = audioHandler.ratingStyle;
      expect(ratingStyle, isA<BehaviorSubject<RatingStyle>>());
    });

    test('customEvent is a PublishSubject', () {
      final audioHandler = BaseAudioHandler();
      final customEvent = audioHandler.customEvent;
      expect(customEvent, isA<PublishSubject<dynamic>>());
    });

    test('customState is a PublishSubject', () {
      final audioHandler = BaseAudioHandler();
      final customState = audioHandler.customState;
      expect(customState, isA<BehaviorSubject<dynamic>>());
    });

    test('click() default logic works', () async {
      final audioHandler = TestableBaseAudioHandler();

      // was paused, MediaButton.media clicked
      await audioHandler.click();
      expect(audioHandler.playbackState.valueOrNull?.playing, false);
      expect(audioHandler.playCount, equals(1));
      expect(audioHandler.pauseCount, equals(0));
      expect(audioHandler.skipToNextCount, equals(0));
      expect(audioHandler.skipToPreviousCount, equals(0));

      // was playing, MediaButton.media clicked
      audioHandler.reset();
      audioHandler.playbackState.add(PlaybackState(playing: true));
      await audioHandler.click();
      expect(audioHandler.playCount, equals(0));
      expect(audioHandler.pauseCount, equals(1));
      expect(audioHandler.skipToNextCount, equals(0));
      expect(audioHandler.skipToPreviousCount, equals(0));

      // MediaButton.next
      audioHandler.reset();
      await audioHandler.click(MediaButton.next);
      expect(audioHandler.playCount, equals(0));
      expect(audioHandler.pauseCount, equals(0));
      expect(audioHandler.skipToNextCount, equals(1));
      expect(audioHandler.skipToPreviousCount, equals(0));

      // MediaButton.previous
      audioHandler.reset();
      await audioHandler.click(MediaButton.previous);
      expect(audioHandler.playCount, equals(0));
      expect(audioHandler.pauseCount, equals(0));
      expect(audioHandler.skipToNextCount, equals(0));
      expect(audioHandler.skipToPreviousCount, equals(1));
    });

    test('stop() default logic works', () async {
      final audioHandler = TestableBaseAudioHandler();
      await audioHandler.stop();
      expect(audioHandler.playbackState.value.processingState,
          AudioProcessingState.idle);
    });

    test('getChildren() returns empty media item list', () async {
      final audioHandler = BaseAudioHandler();
      final children = await audioHandler.getChildren('parentMediaId');
      expect(children, equals(<MediaItem>[]));
    });

    test('getMediaItem() returns null', () async {
      final audioHandler = BaseAudioHandler();
      final mediaItem = await audioHandler.getMediaItem('mediaId');
      expect(mediaItem, isNull);
    });

    test('search() returns empty list', () async {
      final audioHandler = BaseAudioHandler();
      final results = await audioHandler.search('query');
      expect(results, equals(<MediaItem>[]));
    });
  });
}

class TestableBaseAudioHandler extends BaseAudioHandler {
  var pauseCount = 0;
  var playCount = 0;
  var skipToNextCount = 0;
  var skipToPreviousCount = 0;

  void reset() {
    pauseCount = 0;
    playCount = 0;
    skipToNextCount = 0;
    skipToPreviousCount = 0;
  }

  @override
  Future<void> pause() {
    pauseCount++;
    return super.pause();
  }

  @override
  Future<void> play() {
    playCount++;
    return super.play();
  }

  @override
  Future<void> skipToNext() {
    skipToNextCount++;
    return super.skipToNext();
  }

  @override
  Future<void> skipToPrevious() {
    skipToPreviousCount++;
    return super.skipToPrevious();
  }
}
