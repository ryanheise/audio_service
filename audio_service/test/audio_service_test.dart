//import 'dart:async';
//
//import 'package:audio_service/audio_service.dart';
//import 'package:flutter/services.dart';
//import 'package:flutter_test/flutter_test.dart';

void main() {
  //TestWidgetsFlutterBinding.ensureInitialized();
  //final audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  //void expectDuration(Duration a, Duration b, {int epsilon = 200}) {
  //  expect((a - b).inMilliseconds.abs(), lessThanOrEqualTo(epsilon));
  //}

  //setUp(() {
  //  audioSessionChannel.setMockMethodCallHandler((MethodCall methodCall) async {
  //    return null;
  //  });
  //  MockAudioService.setup();
  //});

  //tearDown(() {
  //  MockAudioService.tearDown();
  //  audioSessionChannel.setMockMethodCallHandler(null);
  //});

  //test('init', () async {
  //  expect(AudioService.connected, equals(false));
  //  await AudioService.connect();
  //  expect(AudioService.connected, equals(true));
  //  expect(AudioService.running, equals(false));
  //  await AudioService.start(backgroundTaskEntrypoint: task1);
  //  expect(AudioService.running, equals(true));
  //  expect(AudioServiceBackground.state.playing, equals(false));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_singleItem.toString()));
  //  await Future.delayed(Duration.zero);
  //  expect(AudioService.playbackState?.playing, equals(false));
  //  expect(AudioService.currentMediaItem.toString(),
  //      equals(_singleItem.toString()));

  //  await AudioService.stop();
  //  expect(AudioServiceBackground.state.playing, equals(false));
  //  expect(AudioService.running, equals(false));
  //  expect(AudioService.connected, equals(true));
  //  await AudioService.disconnect();
  //  expect(AudioService.connected, equals(false));
  //});

  //test('options', () async {
  //  await AudioService.connect();
  //  expect(AudioService.running, equals(false));
  //  final params = <String, dynamic>{
  //    'param1': 'value1',
  //    'param2': 2,
  //    'param3': true,
  //    'param4': 4.5,
  //  };
  //  final fastForwardInterval = const Duration(seconds: 15);
  //  final rewindInterval = const Duration(seconds: 5);
  //  await AudioService.start(
  //    backgroundTaskEntrypoint: task1,
  //    params: params,
  //    fastForwardInterval: fastForwardInterval,
  //    rewindInterval: rewindInterval,
  //  );
  //  expect(
  //      (await AudioService.customAction('getParams')).cast<String, dynamic>(),
  //      equals(params));
  //  expect(await AudioService.customAction('getFastForwardInterval'),
  //      equals(fastForwardInterval.inMilliseconds));
  //  expect(await AudioService.customAction('getRewindInterval'),
  //      equals(rewindInterval.inMilliseconds));

  //  await AudioService.stop();
  //  await AudioService.disconnect();
  //});

  //test('queue-modify', () async {
  //  await AudioService.connect();
  //  await AudioService.start(backgroundTaskEntrypoint: task1);

  //  await AudioService.updateQueue(_multipleItems);
  //  expect(AudioServiceBackground.queue, equals(_multipleItems));
  //  expect(AudioService.queue, equals(_multipleItems));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.addQueueItem(_singleItem);
  //  expect(
  //      AudioServiceBackground.queue, equals(_multipleItems + [_singleItem]));
  //  expect(AudioService.queue, equals(_multipleItems + [_singleItem]));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.removeQueueItem(_singleItem);
  //  expect(AudioServiceBackground.queue, equals(_multipleItems));
  //  expect(AudioService.queue, equals(_multipleItems));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.addQueueItemAt(_singleItem, 0);
  //  expect(
  //      AudioServiceBackground.queue, equals([_singleItem] + _multipleItems));
  //  expect(AudioService.queue, equals([_singleItem] + _multipleItems));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_singleItem.toString()));

  //  await AudioService.removeQueueItem(_singleItem);
  //  expect(AudioServiceBackground.queue, equals(_multipleItems));
  //  expect(AudioService.queue, equals(_multipleItems));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.addQueueItems([_singleItem, _secondItem]);
  //  expect(AudioServiceBackground.queue,
  //      equals(_multipleItems + [_singleItem, _secondItem]));
  //  expect(AudioService.queue,
  //      equals(_multipleItems + [_singleItem, _secondItem]));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.removeQueueItem(_singleItem);
  //  await AudioService.removeQueueItem(_secondItem);
  //  expect(AudioServiceBackground.queue, equals(_multipleItems));
  //  expect(AudioService.queue, equals(_multipleItems));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  final modified = MediaItem(id: '1', title: 'New title', album: 'album');
  //  await AudioService.updateMediaItem(modified);
  //  expect(AudioServiceBackground.queue,
  //      equals([_multipleItems[0], modified, _multipleItems[2]]));
  //  expect(AudioService.queue,
  //      equals([_multipleItems[0], modified, _multipleItems[2]]));

  //  await AudioService.stop();
  //  expect(AudioServiceBackground.queue, equals([]));
  //  await AudioService.disconnect();
  //});

  //test('queue-skip', () async {
  //  await AudioService.connect();
  //  await AudioService.start(backgroundTaskEntrypoint: task1);

  //  await AudioService.updateQueue(_multipleItems);
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.skipToPrevious();
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.skipToNext();
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[1].toString()));

  //  await AudioService.skipToNext();
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[2].toString()));

  //  await AudioService.skipToNext();
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[2].toString()));

  //  await AudioService.skipToQueueItem(_multipleItems[1].id);
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[1].toString()));

  //  await AudioService.stop();
  //  expect(AudioServiceBackground.queue, equals([]));
  //  await AudioService.disconnect();
  //});

  //test('click', () async {
  //  await AudioService.connect();
  //  await AudioService.start(backgroundTaskEntrypoint: task1);

  //  await AudioService.updateQueue(_multipleItems);
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.click(MediaButton.next);
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[1].toString()));

  //  await AudioService.click(MediaButton.previous);
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));

  //  await AudioService.click(MediaButton.media);
  //  expect(AudioServiceBackground.state.playing, equals(true));

  //  await AudioService.click(MediaButton.media);
  //  expect(AudioServiceBackground.state.playing, equals(false));

  //  await AudioService.stop();
  //  await AudioService.disconnect();
  //});

  //test('play', () async {
  //  await AudioService.connect();
  //  await AudioService.start(backgroundTaskEntrypoint: task1);
  //  await AudioService.updateQueue(_multipleItems);
  //  expect(AudioServiceBackground.state.playing, equals(false));
  //  await Future.delayed(Duration.zero);
  //  expect(AudioService.playbackState.playing, equals(false));
  //  await AudioService.play();
  //  expect(AudioServiceBackground.state.playing, equals(true));
  //  await AudioService.pause();
  //  expect(AudioServiceBackground.state.playing, equals(false));
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[0].toString()));
  //  await AudioService.playFromMediaId(_multipleItems[2].id);
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_multipleItems[2].toString()));
  //  await AudioService.playMediaItem(_singleItem);
  //  expect(AudioServiceBackground.mediaItem.toString(),
  //      equals(_singleItem.toString()));

  //  await AudioService.stop();
  //  expect(AudioServiceBackground.state.playing, equals(false));
  //  await AudioService.disconnect();
  //});

  //test('shuffle', () async {
  //  await AudioService.connect();
  //  await AudioService.start(backgroundTaskEntrypoint: task1);
  //  expect(AudioServiceBackground.state.shuffleMode,
  //      equals(AudioServiceShuffleMode.none));
  //  expect(AudioService.playbackState.shuffleMode,
  //      equals(AudioServiceShuffleMode.none));

  //  await AudioService.setShuffleMode(AudioServiceShuffleMode.all);
  //  expect(AudioServiceBackground.state.shuffleMode,
  //      equals(AudioServiceShuffleMode.all));
  //  expect(AudioService.playbackState.shuffleMode,
  //      equals(AudioServiceShuffleMode.all));

  //  await AudioService.stop();
  //  expect(AudioServiceBackground.state.shuffleMode,
  //      equals(AudioServiceShuffleMode.none));
  //  await AudioService.disconnect();
  //});

  //test('repeat', () async {
  //  await AudioService.connect();
  //  await AudioService.start(backgroundTaskEntrypoint: task1);
  //  expect(AudioServiceBackground.state.repeatMode,
  //      equals(AudioServiceRepeatMode.none));
  //  expect(AudioService.playbackState.repeatMode,
  //      equals(AudioServiceRepeatMode.none));

  //  await AudioService.setRepeatMode(AudioServiceRepeatMode.all);
  //  expect(AudioServiceBackground.state.repeatMode,
  //      equals(AudioServiceRepeatMode.all));
  //  expect(AudioService.playbackState.repeatMode,
  //      equals(AudioServiceRepeatMode.all));

  //  await AudioService.stop();
  //  expect(AudioServiceBackground.state.repeatMode,
  //      equals(AudioServiceRepeatMode.none));
  //  await AudioService.disconnect();
  //});

  //test('MediaItem', () async {
  //  final item = MediaItem(
  //    id: 'id',
  //    album: 'album',
  //    title: 'title',
  //    artist: 'artist',
  //    genre: 'genre',
  //    duration: Duration.zero,
  //    artUri: 'https://foo.foo/foo.mp3',
  //    playable: true,
  //    displayTitle: 'displayTitle',
  //    displaySubtitle: 'displaySubtitle',
  //    displayDescription: 'displayDescription',
  //    rating: Rating.newHeartRating(true),
  //    extras: {'a': 'a', 'b': 2},
  //  );
  //  final expectedItem2 = MediaItem(
  //    id: 'id',
  //    album: 'album',
  //    title: 'title',
  //    artist: 'artist',
  //    genre: 'genre',
  //    duration: Duration(minutes: 1),
  //    artUri: 'https://foo.foo/foo.mp3',
  //    playable: true,
  //    displayTitle: 'displayTitle',
  //    displaySubtitle: 'displaySubtitle',
  //    displayDescription: 'displayDescription',
  //    rating: Rating.newHeartRating(true),
  //    extras: {'a': 'a', 'b': 2},
  //  );
  //  final expectedItem3 = MediaItem(
  //    id: 'id',
  //    album: 'album',
  //    title: 'new title',
  //    artist: 'artist',
  //    genre: 'genre',
  //    duration: Duration.zero,
  //    artUri: 'https://foo.foo/foo.mp3',
  //    playable: true,
  //    displayTitle: 'displayTitle',
  //    displaySubtitle: 'displaySubtitle',
  //    displayDescription: 'displayDescription',
  //    rating: Rating.newHeartRating(true),
  //    extras: {'a': 'a', 'b': 2},
  //  );
  //  final item2 = item.copyWith(duration: Duration(minutes: 1));
  //  expect(item2.toString(), equals(expectedItem2.toString()));
  //  final item3 = item.copyWith(title: 'new title');
  //  expect(item3.toString(), equals(expectedItem3.toString()));
  //});

  //test('rating', () async {
  //  for (var heart in [true, false]) {
  //    final rating = Rating.newHeartRating(heart);
  //    expect(rating.getRatingStyle(), equals(RatingStyle.heart));
  //    expect(rating.hasHeart(), equals(heart));
  //    expect(rating.isRated(), equals(true));
  //  }

  //  for (var maxStars = 3; maxStars <= 5; maxStars++) {
  //    final style = RatingStyle.values[maxStars];
  //    for (var stars = 0; stars <= maxStars; stars++) {
  //      final rating = Rating.newStarRating(style, stars);
  //      expect(rating.getRatingStyle(), equals(style));
  //      expect(rating.getStarRating(), equals(stars));
  //      expect(rating.isRated(), equals(true));
  //    }
  //    expect(() => Rating.newStarRating(style, -1), throwsArgumentError);
  //    expect(
  //        () => Rating.newStarRating(style, maxStars + 1), throwsArgumentError);
  //  }
  //  for (var style in [
  //    RatingStyle.none,
  //    RatingStyle.heart,
  //    RatingStyle.thumbUpDown,
  //    RatingStyle.percentage,
  //  ]) {
  //    expect(() => Rating.newStarRating(style, 3), throwsArgumentError);
  //  }

  //  for (var thumb in [true, false]) {
  //    final rating = Rating.newThumbRating(thumb);
  //    expect(rating.getRatingStyle(), equals(RatingStyle.thumbUpDown));
  //    expect(rating.isThumbUp(), equals(thumb));
  //    expect(rating.isRated(), equals(true));
  //  }

  //  for (var percent in [0.0, 45.5, 100.0]) {
  //    final rating = Rating.newPercentageRating(percent);
  //    expect(rating.getRatingStyle(), equals(RatingStyle.percentage));
  //    expect(rating.getPercentRating(), equals(percent));
  //    expect(rating.isRated(), equals(true));
  //  }
  //  expect(() => Rating.newPercentageRating(-1.0), throwsArgumentError);
  //  expect(() => Rating.newPercentageRating(100.1), throwsArgumentError);

  //  for (var style in RatingStyle.values) {
  //    final rating = Rating.newUnratedRating(style);
  //    expect(rating.getRatingStyle(), equals(style));
  //    expect(rating.isRated(), equals(false));
  //  }
  //});

  //test('positionStream', () async {
  //  final period = Duration(seconds: 3);
  //  final position1 = period;
  //  final position2 = position1 + period;
  //  final speed1 = 0.75;
  //  final speed2 = 1.5;
  //  final stepDuration = period ~/ 5;
  //  var target = stepDuration;
  //  await AudioService.connect();
  //  await AudioService.start(backgroundTaskEntrypoint: task1);
  //  await AudioService.setSpeed(speed1);
  //  AudioService.play();
  //  final stopwatch = Stopwatch();
  //  stopwatch.start();
  //  var completer = Completer();
  //  StreamSubscription subscription;
  //  subscription = AudioService.positionStream.listen((position) {
  //    if (position >= position1) {
  //      subscription.cancel();
  //      completer.complete();
  //    } else if (position >= target) {
  //      expectDuration(position, stopwatch.elapsed * speed1);
  //      target += stepDuration;
  //    }
  //  });
  //  await completer.future;
  //  await AudioService.setSpeed(speed2);
  //  stopwatch.reset();
  //  target = position1 + target;
  //  completer = Completer();
  //  subscription = AudioService.positionStream.listen((position) {
  //    if (position >= position2) {
  //      subscription.cancel();
  //      completer.complete();
  //    } else if (position >= target) {
  //      expectDuration(position, position1 + stopwatch.elapsed * speed2);
  //      target += stepDuration;
  //    }
  //  });
  //  await completer.future;
  //  await AudioService.stop();
  //  await AudioService.disconnect();
  //});

  //test('customEventStream', () async {
  //  await AudioService.connect();
  //  await AudioService.start(backgroundTaskEntrypoint: task1);
  //  Duration position;
  //  final subscription = AudioService.customEventStream.listen((event) {
  //    position = event;
  //  });
  //  for (var seconds in [47, 123]) {
  //    final testPosition = Duration(seconds: seconds);
  //    await AudioService.seekTo(testPosition);
  //    await Future.delayed(Duration(milliseconds: 100));
  //    expect(position, equals(testPosition));
  //  }
  //  await AudioService.stop();
  //  await AudioService.disconnect();
  //  subscription.cancel();
  //});
}

//final _singleItem = MediaItem(
//  id: 'single',
//  title: 'Single',
//  album: 'album',
//);
//final _secondItem = MediaItem(
//  id: 'second',
//  title: 'Second',
//  album: 'album',
//  duration: Duration(minutes: 2),
//);
//final _multipleItems = List.generate(
//    3, (i) => MediaItem(id: '$i', title: 'title $i', album: 'album'));
//
//void task1() => AudioServiceBackground.run(() => Task1());
//
//class Task1 extends BackgroundAudioTask {
//  final _queue = <MediaItem>[_singleItem];
//  var _index = 0;
//  Map _params;
//  MediaItem get mediaItem => _index < _queue.length ? _queue[_index] : null;
//
//  @override
//  Future<void> onStart(Map<String, dynamic> params) async {
//    _params = params;
//    await AudioServiceBackground.setQueue(_queue);
//    await AudioServiceBackground.setState(
//        processingState: AudioProcessingState.ready);
//    await AudioServiceBackground.setMediaItem(mediaItem);
//  }
//
//  @override
//  Future<void> onPause() async {
//    AudioServiceBackground.setState(playing: false);
//  }
//
//  @override
//  Future<void> onPrepare() async {}
//
//  @override
//  Future<void> onPrepareFromMediaId(String mediaId) async {}
//
//  @override
//  Future<void> onPlay() async {
//    await AudioServiceBackground.setState(playing: true);
//  }
//
//  @override
//  Future<void> onPlayFromMediaId(String mediaId) async {
//    _index = _queue.indexWhere((item) => item.id == mediaId);
//    await AudioServiceBackground.setState(playing: true);
//    await AudioServiceBackground.setMediaItem(mediaItem);
//  }
//
//  @override
//  Future<void> onPlayMediaItem(MediaItem mediaItem) async {
//    AudioServiceBackground.setState(playing: true);
//    await AudioServiceBackground.setMediaItem(mediaItem);
//  }
//
//  @override
//  Future<void> onAddQueueItem(MediaItem mediaItem) async {
//    _queue.add(mediaItem);
//    await AudioServiceBackground.setQueue(_queue);
//  }
//
//  @override
//  Future<void> onUpdateQueue(List<MediaItem> queue) async {
//    final oldMediaItem = mediaItem;
//    _queue.replaceRange(0, _queue.length, queue);
//    await AudioServiceBackground.setQueue(_queue);
//    if (mediaItem != oldMediaItem) {
//      await AudioServiceBackground.setMediaItem(mediaItem);
//    }
//  }
//
//  @override
//  Future<void> onUpdateMediaItem(MediaItem mediaItem) async {
//    final index = _queue.indexOf(mediaItem);
//    if (index != -1) {
//      _queue[index] = mediaItem;
//      await AudioServiceBackground.setQueue(_queue);
//    }
//  }
//
//  @override
//  Future<void> onAddQueueItemAt(MediaItem mediaItem, int index) async {
//    final oldMediaItem = this.mediaItem;
//    _queue.insert(index, mediaItem);
//    await AudioServiceBackground.setQueue(_queue);
//    if (this.mediaItem != oldMediaItem) {
//      await AudioServiceBackground.setMediaItem(this.mediaItem);
//    }
//  }
//
//  @override
//  Future<void> onRemoveQueueItem(MediaItem mediaItem) async {
//    final oldMediaItem = this.mediaItem;
//    _queue.remove(mediaItem);
//    await AudioServiceBackground.setQueue(_queue);
//    if (this.mediaItem != oldMediaItem) {
//      // Note: This is not a robust way to implement a queue, but our
//      // purpose is not to build a complete background task, rather it
//      // is to test the plugin proper.
//      await AudioServiceBackground.setMediaItem(this.mediaItem);
//    }
//  }
//
//  @override
//  Future<void> onFastForward() async {}
//
//  @override
//  Future<void> onRewind() async {}
//
//  @override
//  Future<void> onSkipToQueueItem(String mediaId) async {
//    final mediaItem = _queue.firstWhere((item) => item.id == mediaId);
//    await AudioServiceBackground.setMediaItem(mediaItem);
//  }
//
//  @override
//  Future<void> onSeekTo(Duration position) async {
//    await AudioServiceBackground.setState(position: position);
//    AudioServiceBackground.sendCustomEvent(position);
//  }
//
//  @override
//  Future<void> onSetRating(Rating rating, Map<dynamic, dynamic> extras) async {}
//
//  @override
//  Future<void> onSetRepeatMode(AudioServiceRepeatMode repeatMode) async {
//    await AudioServiceBackground.setState(repeatMode: repeatMode);
//  }
//
//  @override
//  Future<void> onSetShuffleMode(AudioServiceShuffleMode shuffleMode) async {
//    await AudioServiceBackground.setState(shuffleMode: shuffleMode);
//  }
//
//  @override
//  Future<void> onSeekBackward(bool begin) async {}
//
//  @override
//  Future<void> onSeekForward(bool begin) async {}
//
//  @override
//  Future<void> onSetSpeed(double speed) async {
//    await AudioServiceBackground.setState(speed: speed);
//  }
//
//  @override
//  Future<dynamic> onCustomAction(String name, dynamic arguments) async {
//    switch (name) {
//      case 'getParams':
//        return _params;
//      case 'getFastForwardInterval':
//        return fastForwardInterval.inMilliseconds;
//      case 'getRewindInterval':
//        return rewindInterval.inMilliseconds;
//      default:
//        return [name, arguments];
//    }
//  }
//
//  @override
//  Future<void> onTaskRemoved() async {
//    await onStop();
//  }
//}
//
//class MockAudioService {
//  static final channel = MethodChannel('ryanheise.com/audioService');
//  static final channelInverse =
//      MethodChannel('ryanheise.com/audioServiceInverse');
//  static final bgChannel =
//      MethodChannel('ryanheise.com/audioServiceBackground');
//  static final bgChannelInverse =
//      MethodChannel('ryanheise.com/audioServiceBackgroundInverse');
//
//  static var _connected = false;
//  static var _running = false;
//  static int _fastForwardInterval;
//  static int _rewindInterval;
//  static Map<String, dynamic> _params;
//  static Completer<bool> _stopCompleter;
//
//  static void setup() {
//    _connected = false;
//    _running = false;
//    _fastForwardInterval = null;
//    _rewindInterval = null;
//    _params = null;
//    _stopCompleter = null;
//    channel.setMockMethodCallHandler((call) async {
//      final onMethod =
//          'on' + call.method[0].toUpperCase() + call.method.substring(1);
//      final args = call.arguments;
//      switch (call.method) {
//        case 'isRunning':
//          return _running;
//        case 'start':
//          if (_running) return false;
//          _params = (args['params'] as Map)?.cast<String, dynamic>();
//          _fastForwardInterval = args['fastForwardInterval'];
//          _rewindInterval = args['rewindInterval'];
//          _running = true;
//          return true;
//        case 'connect':
//          if (_connected) return false;
//          _connected = true;
//          return true;
//        case 'disconnect':
//          _connected = false;
//          return true;
//        case 'setBrowseMediaParent':
//          return true;
//        case 'addQueueItem':
//        case 'removeQueueItem':
//        case 'updateQueue':
//        case 'updateMediaItem':
//        case 'playMediaItem':
//        case 'click':
//        case 'prepareFromMediaId':
//        case 'playFromMediaId':
//        case 'skipToQueueItem':
//        case 'seekTo':
//        case 'setRepeatMode':
//        case 'setShuffleMode':
//        case 'setSpeed':
//        case 'seekForward':
//        case 'seekBackward':
//          return bgChannelInverse.invokeMethod(onMethod, [args]);
//        case 'addQueueItemAt':
//        case 'prepare':
//        case 'play':
//        case 'pause':
//        case 'skipToNext':
//        case 'skipToPrevious':
//        case 'fastForward':
//        case 'rewind':
//          return bgChannelInverse.invokeMethod(onMethod, args);
//        case 'stop':
//          bgChannelInverse.invokeMethod(onMethod, args);
//          _stopCompleter = Completer();
//          return _stopCompleter.future;
//        case 'setRating':
//          return bgChannelInverse
//              .invokeMethod(onMethod, [args['rating'], args['extras']]);
//        default:
//          return bgChannelInverse.invokeMethod(call.method, args);
//      }
//    });
//    bgChannel.setMockMethodCallHandler((call) async {
//      final args = call.arguments;
//      switch (call.method) {
//        case 'ready':
//          return {
//            'fastForwardInterval': _fastForwardInterval,
//            'rewindInterval': _rewindInterval,
//            'params': _params,
//          };
//        case 'started':
//          return true;
//        case 'setMediaItem':
//          await channelInverse.invokeMethod('onMediaChanged', [args]);
//          return true;
//        case 'setQueue':
//          await channelInverse.invokeMethod('onQueueChanged', [args]);
//          return true;
//        case 'setState':
//          final rawControls = args[0];
//          final rawSystemActions = args[1];
//          var actionBits = 0;
//          for (var rawControl in rawControls) {
//            actionBits |= (1 << rawControl["action"]);
//          }
//          for (var rawSystemAction in rawSystemActions) {
//            actionBits |= 1 << rawSystemAction;
//          }
//          int updateTime = args[7];
//          if (updateTime == null) {
//            updateTime = DateTime.now().millisecondsSinceEpoch;
//          }
//          await channelInverse.invokeMethod('onPlaybackStateChanged', [
//            args[2], // processingState
//            args[3], // playing
//            actionBits,
//            args[4], // position
//            args[5], // bufferedPosition
//            args[6], // speed
//            updateTime,
//            args[9], // repeatMode
//            args[10], // shuffleMode
//          ]);
//          return true;
//        case 'stopped':
//          _running = false;
//          await channelInverse.invokeMethod('onStopped');
//          _stopCompleter.complete(true);
//          return true;
//        case 'notifyChildrenChanged':
//          return true;
//        case 'androidForceEnableMediaButtons':
//          return true;
//      }
//    });
//  }
//
//  static void tearDown() {
//    channel.setMockMethodCallHandler(null);
//    bgChannel.setMockMethodCallHandler(null);
//  }
//}
