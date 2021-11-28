import 'dart:isolate';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import 'stubs.dart';

Isolate? isolate;

void main() {
  late AudioHandler proxy;

  late bool spawningIsolate;

  setUp(() async {
    if (spawningIsolate) {
      await runIsolateHandler();
    } else {
      IsolatedAudioHandler(_MockAudioHandler());
    }
    proxy = await IsolatedAudioHandler.lookup();
  });

  tearDown(() async {
    await proxy.unregister();
    if (spawningIsolate) {
      await killIsolate();
    }
  });

  // We need to run the tests not only in different isolates but also in the
  // same isolate since coverage is only collected by the main isolate:
  // https://github.com/dart-lang/test/issues/1108
  for (var differentIsolate in [true, false]) {
    spawningIsolate = differentIsolate;
    final isolateLabel =
        differentIsolate ? '(different isolate)' : '(same isolate)';

    test('$isolateLabel init', () async {
      //expect(await proxy.playbackState.first, PlaybackState());
      expect(await proxy.queue.first, const <MediaItem>[]);
      expect(await proxy.queueTitle.first, '');
      expect(await proxy.mediaItem.first, null);
      expect(proxy.ratingStyle.hasValue, false);
      expect(proxy.androidPlaybackInfo.hasValue, false);
      expect(proxy.customState.hasValue, false);
    });

    group('$isolateLabel method invocations $asciiSquare', () {
      void testMethod(
        String method,
        dynamic Function() function, {
        List<Object?> expectedArguments = const [],
        dynamic expectedResult,
      }) {
        test('$method', () async {
          final startCaptured = await proxy.captured(method);
          final dynamic result = await function();
          final captured = await proxy.captured(method);
          expect(captured.count, startCaptured.count + 1);
          expect(captured.invocation, isNotNull);

          final positionalArguments = captured.invocation!.positionalArguments;
          final namedArguments = captured.invocation!.namedArguments;
          if (expectedArguments.isEmpty) {
            expect(positionalArguments, <dynamic>[]);
            expect(namedArguments, <dynamic, dynamic>{});
          } else {
            for (var i = 0; i < expectedArguments.length; i++) {
              // Expect positional or named arguments had such argument.
              if (i < positionalArguments.length) {
                expect(
                  positionalArguments[i],
                  equals(expectedArguments[i]),
                );
              } else {
                expect(
                  namedArguments.values,
                  contains(expectedArguments[i]),
                  reason:
                      "There's no such argument in invocation, or the order is incorrect",
                );
              }
            }
          }

          expect(result, expectedResult);
        });
      }

      testMethod('prepare', () => proxy.prepare());
      testMethod(
        'prepareFromMediaId',
        () => proxy.prepareFromMediaId('1', Data.extras),
        expectedArguments: ['1', Data.extras],
      );
      testMethod(
        'prepareFromSearch',
        () => proxy.prepareFromSearch(Data.query, Data.extras),
        expectedArguments: [Data.query, Data.extras],
      );
      testMethod(
        'prepareFromUri',
        () => proxy.prepareFromUri(Data.uri, Data.extras),
        expectedArguments: [Data.uri, Data.extras],
      );
      testMethod('play', () => proxy.play());
      testMethod(
        'playFromMediaId',
        () => proxy.playFromMediaId(Data.mediaId, Data.extras),
        expectedArguments: [Data.mediaId, Data.extras],
      );
      testMethod(
        'playFromSearch',
        () => proxy.playFromSearch(Data.query, Data.extras),
        expectedArguments: [Data.query, Data.extras],
      );
      testMethod(
        'playFromUri',
        () => proxy.playFromUri(Data.uri, Data.extras),
        expectedArguments: [Data.uri, Data.extras],
      );
      testMethod(
        'playMediaItem',
        () => proxy.playMediaItem(Data.mediaItem),
        expectedArguments: [Data.mediaItem],
      );
      testMethod('pause', () => proxy.pause());
      testMethod(
        'click',
        () => proxy.click(),
        expectedArguments: [MediaButton.media],
      );
      testMethod('stop', () => proxy.stop());
      testMethod(
        'addQueueItem',
        () => proxy.addQueueItem(Data.mediaItem),
        expectedArguments: [Data.mediaItem],
      );
      testMethod(
        'addQueueItems',
        () => proxy.addQueueItems(Data.mediaItems),
        expectedArguments: [Data.mediaItems],
      );
      testMethod(
        'insertQueueItem',
        () => proxy.insertQueueItem(0, Data.mediaItem),
        expectedArguments: [0, Data.mediaItem],
      );
      testMethod(
        'updateQueue',
        () => proxy.updateQueue(Data.mediaItems),
        expectedArguments: [Data.mediaItems],
      );
      testMethod(
        'updateMediaItem',
        () => proxy.updateMediaItem(Data.mediaItem),
        expectedArguments: [Data.mediaItem],
      );
      testMethod(
        'removeQueueItem',
        () => proxy.removeQueueItem(Data.mediaItem),
        expectedArguments: [Data.mediaItem],
      );
      testMethod(
        'removeQueueItemAt',
        () => proxy.removeQueueItemAt(0),
        expectedArguments: [0],
      );
      testMethod('skipToNext', () => proxy.skipToNext());
      testMethod('skipToPrevious', () => proxy.skipToPrevious());
      testMethod('fastForward', () => proxy.fastForward());
      testMethod('rewind', () => proxy.rewind());
      testMethod(
        'skipToQueueItem',
        () => proxy.skipToQueueItem(0),
        expectedArguments: [0],
      );
      testMethod(
        'seek',
        () => proxy.seek(Duration.zero),
        expectedArguments: [Duration.zero],
      );
      testMethod(
        'setRating',
        () => proxy.setRating(const Rating.newHeartRating(true), Data.extras),
        expectedArguments: [const Rating.newHeartRating(true), Data.extras],
      );
      testMethod(
        'setCaptioningEnabled',
        () => proxy.setCaptioningEnabled(true),
        expectedArguments: [true],
      );
      testMethod(
        'setRepeatMode',
        () => proxy.setRepeatMode(AudioServiceRepeatMode.all),
        expectedArguments: [AudioServiceRepeatMode.all],
      );
      testMethod(
        'setShuffleMode',
        () => proxy.setShuffleMode(AudioServiceShuffleMode.all),
        expectedArguments: [AudioServiceShuffleMode.all],
      );
      testMethod(
        'seekBackward',
        () => proxy.seekBackward(true),
        expectedArguments: [true],
      );
      testMethod(
        'seekForward',
        () => proxy.seekForward(true),
        expectedArguments: [true],
      );
      testMethod(
        'setSpeed',
        () => proxy.setSpeed(1.5),
        expectedArguments: [1.5],
      );
      testMethod('onTaskRemoved', () => proxy.onTaskRemoved());
      testMethod('onNotificationDeleted', () => proxy.onNotificationDeleted());
      testMethod(
        'getChildren',
        () => proxy.getChildren(Data.mediaId, Data.extras),
        expectedArguments: [Data.mediaId, Data.extras],
        expectedResult: Data.mediaItems,
      );
      testMethod(
        'subscribeToChildren',
        () => proxy.subscribeToChildren(Data.mediaId),
        expectedArguments: [Data.mediaId],
        expectedResult: isA<BehaviorSubject<Map<String, dynamic>>>(),
      );
      testMethod(
        'getMediaItem',
        () => proxy.getMediaItem(Data.mediaId),
        expectedArguments: [Data.mediaId],
        expectedResult: Data.mediaItem,
      );
      testMethod(
        'search',
        () => proxy.search(Data.query, Data.extras),
        expectedArguments: [Data.query, Data.extras],
        expectedResult: Data.mediaItems,
      );
      testMethod(
        'androidSetRemoteVolume',
        () => proxy.androidSetRemoteVolume(3),
        expectedArguments: [3],
      );
      testMethod(
        'androidAdjustRemoteVolume',
        () => proxy.androidAdjustRemoteVolume(AndroidVolumeDirection.raise),
        expectedArguments: [AndroidVolumeDirection.raise],
      );
      testMethod(
        'customAction',
        () => proxy.echo('foo'),
        expectedArguments: [
          'echo',
          const {'arg': 'foo'},
        ],
        expectedResult: 'foo',
      );
    });

    test('$isolateLabel stream values', () async {
      Future<void> testStream<T>(
          String name, ValueStream<T> stream, T value) async {
        await proxy.add(name, value);
        expect(stream.nvalue, value);
      }

      await testStream(
          'playbackState', proxy.playbackState, Data.playbackState);
      await testStream('queue', proxy.queue, Data.mediaItems);
      await testStream('queueTitle', proxy.queueTitle, 'Queue');
      await testStream('androidPlaybackInfo', proxy.androidPlaybackInfo,
          Data.remotePlaybackInfo);
      await testStream('ratingStyle', proxy.ratingStyle, RatingStyle.heart);
      await testStream<dynamic>('customState', proxy.customState, 'foo');
    });

    test('$isolateLabel streams', () async {
      Future<void> testStream<T>(
          String name, Stream<T> stream, bool skipFirst, List<T> values) async {
        final actualValues = <T>[];
        final subscription =
            stream.skip(skipFirst ? 1 : 0).listen(actualValues.add);
        for (var value in values) {
          await proxy.add(name, value);
        }
        expect(actualValues, values);
        subscription.cancel();
      }

      await testStream(
          'playbackState', proxy.playbackState, true, Data.playbackStates);
      await testStream('queue', proxy.queue, true, [
        Data.mediaItems,
        Data.mediaItems
            .map((item) =>
                item.copyWith(displayDescription: '${item.id} description'))
            .toList(),
      ]);
      await testStream('queueTitle', proxy.queueTitle, true, ['a', 'b', 'c']);
      await testStream('mediaItem', proxy.mediaItem, true, Data.mediaItems);
      await testStream(
          'androidPlaybackInfo', proxy.androidPlaybackInfo, false, [
        Data.remotePlaybackInfo,
        LocalAndroidPlaybackInfo(),
      ]);
      await testStream('ratingStyle', proxy.ratingStyle, false, [
        RatingStyle.heart,
        RatingStyle.percentage,
      ]);
      await testStream<dynamic>(
          'customEvent', proxy.customEvent, false, <dynamic>[
        'a',
        'b',
        'c',
      ]);
      await testStream<dynamic>(
          'customState', proxy.customState, false, <dynamic>[
        'a',
        'b',
        'c',
      ]);
    });
  }
}

Future<void> runIsolateHandler() async {
  final receivePort = ReceivePort();
  isolate = await Isolate.spawn(isolateEntryPoint, receivePort.sendPort);
  final success = (await receivePort.first) as bool;
  assert(success);
}

Future<void> killIsolate() async {
  isolate!.kill();
  isolate = null;
}

void isolateEntryPoint(SendPort sendPort) {
  IsolatedAudioHandler(_MockAudioHandler());
  sendPort.send(true);
}

class _MockAudioHandler implements BaseAudioHandler {
  @override
  // ignore: close_sinks
  final BehaviorSubject<PlaybackState> playbackState =
      BehaviorSubject.seeded(PlaybackState());

  @override
  final BehaviorSubject<List<MediaItem>> queue =
      BehaviorSubject.seeded(<MediaItem>[]);

  @override
  // ignore: close_sinks
  final BehaviorSubject<String> queueTitle = BehaviorSubject.seeded('');

  @override
  // ignore: close_sinks
  final BehaviorSubject<MediaItem?> mediaItem = BehaviorSubject.seeded(null);

  @override
  // ignore: close_sinks
  final BehaviorSubject<AndroidPlaybackInfo> androidPlaybackInfo =
      BehaviorSubject();

  @override
  // ignore: close_sinks
  final BehaviorSubject<RatingStyle> ratingStyle = BehaviorSubject();

  @override
  // ignore: close_sinks
  final PublishSubject<dynamic> customEvent = PublishSubject<dynamic>();

  @override
  // ignore: close_sinks
  final BehaviorSubject<dynamic> customState = BehaviorSubject<dynamic>();

  final Map<String, int> invocationCounts = {};
  final Map<String, Invocation> invocations = {};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final member = invocation.memberName.toString().split('"')[1];
    if (invocation.isMethod) {
      if (member != 'customAction' ||
          member == 'customAction' &&
              invocation.positionalArguments[0] != 'captured') {
        // Count invocations of everything except for 'captured' itself.
        invocationCounts[member] = (invocationCounts[member] ?? 0) + 1;
        invocations[member] = invocation;
      }
      switch (member) {
        case 'customAction':
          return _handleCustomAction(invocation);
        case 'getChildren':
        case 'search':
          return Future.value(Data.mediaItems);
        case 'subscribeToChildren':
          return BehaviorSubject.seeded(<String, dynamic>{});
        case 'getMediaItem':
          return Future.value(Data.mediaItem);
        default:
          return Future.value(null);
      }
    }
    return super.noSuchMethod(invocation);
  }

  Future<dynamic> _handleCustomAction(Invocation invocation) async {
    final args = invocation.positionalArguments;
    final name = args[0] as String;
    final extras = args[1] as Map<String, dynamic>?;
    switch (name) {
      case 'captured':
        final method = extras!['method'] as String;
        return _Captured(
          invocationCounts[method] ?? 0,
          invocations[method],
        );
      case 'echo':
        return extras!['arg'] as String;
      case 'add':
        final streamName = extras!['stream'] as String;
        final dynamic arg = extras['arg'];
        <String, Subject>{
          'playbackState': playbackState,
          'queue': queue,
          'queueTitle': queueTitle,
          'mediaItem': mediaItem,
          'androidPlaybackInfo': androidPlaybackInfo,
          'ratingStyle': ratingStyle,
          'customEvent': customEvent,
          'customState': customState,
        }[streamName]!
            .add(arg);
        break;
    }
  }
}

class _Captured {
  final int count;
  final Invocation? invocation;

  _Captured(this.count, this.invocation);
}

extension AudioHandlerExtension on AudioHandler {
  /// Gets the method invocation count and parameters.
  Future<_Captured> captured(String method) async =>
      (await customAction('captured', <String, dynamic>{'method': method})
          as _Captured);

  /// Returns the sent value.
  Future<String> echo(String arg) async =>
      (await customAction('echo', <String, dynamic>{'arg': arg}) as String);

  /// Adds a value to a stream.
  Future<void> add(String stream, dynamic arg) =>
      customAction('add', <String, dynamic>{'stream': stream, 'arg': arg});

  /// Unregisters the [IsolatedAudioHandler].
  Future<void> unregister() => customAction('unregister');
}

/// Backwards compatible extensions on rxdart's ValueStream
extension _ValueStreamExtension<T> on ValueStream<T> {
  /// Backwards compatible version of valueOrNull.
  T? get nvalue => hasValue ? value : null;
}
