import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BaseAudioHandler:', () {
    test('Constructor sets correct default parameter values', () {
      final audioHandler = BaseAudioHandler();

      final actual = audioHandler.playbackState.nvalue!;
      final expected = PlaybackState(updateTime: actual.updateTime);
      expect(actual, equals(expected));
      final timeNow = DateTime.now().millisecond;
      expect(actual.updateTime.millisecond, closeTo(timeNow, 1000));

      final queue = audioHandler.queue.nvalue;
      expect(queue, equals(<MediaItem>[]));

      final queueTitle = audioHandler.queueTitle.nvalue;
      expect(queueTitle, equals(''));

      final mediaItem = audioHandler.mediaItem.nvalue;
      expect(mediaItem, isNull);

      final androidPlaybackInfo = audioHandler.androidPlaybackInfo;
      expect(androidPlaybackInfo, isA<BehaviorSubject<AndroidPlaybackInfo>>());

      final ratingStyle = audioHandler.ratingStyle;
      expect(ratingStyle, isA<BehaviorSubject<RatingStyle>>());

      final customEvent = audioHandler.customEvent;
      expect(customEvent, isA<PublishSubject<dynamic>>());

      final customState = audioHandler.customState;
      expect(customState, isA<BehaviorSubject<dynamic>>());
    });

    test('click() default logic works', () async {
      final audioHandler = TestableBaseAudioHandler();

      // was paused, MediaButton.media clicked
      await audioHandler.click();
      expect(audioHandler.playbackState.nvalue!.playing, false);
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

    test('other methods return expected default values', () async {
      final audioHandler = BaseAudioHandler();

      await audioHandler.stop();
      expect(audioHandler.playbackState.nvalue!.processingState,
          AudioProcessingState.idle);

      final children = await audioHandler.getChildren('parentMediaId');
      expect(children, equals(<MediaItem>[]));

      final mediaItem = await audioHandler.getMediaItem('mediaId');
      expect(mediaItem, isNull);

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

/// Backwards compatible extensions on rxdart's ValueStream
extension _ValueStreamExtension<T> on ValueStream<T> {
  /// Backwards compatible version of valueOrNull.
  T? get nvalue => hasValue ? value : null;
}
