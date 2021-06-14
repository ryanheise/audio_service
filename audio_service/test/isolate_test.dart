import 'dart:async';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

import 'mock_audio_handler.dart';

const isolateInitMessage = Object();

const id = 'id';
const query = 'query';
final uri = Uri.file('uri');
const map = <String, dynamic>{'key': 'value'};
const mediaItem = MediaItem(id: 'id', title: 'title');
const queue = [
  MediaItem(id: 'id1', title: 'title'),
  MediaItem(id: 'id2', title: 'title'),
  MediaItem(id: 'id3', title: 'title'),
];
const mediaButton = MediaButton.next;
const duration = Duration(seconds: 123);
const rating = Rating.newPercentageRating(50);
const repeatMode = AudioServiceRepeatMode.all;
const shuffleMode = AudioServiceShuffleMode.all;
const customActionName = 'customActionName';
const customActionArguments = <String, dynamic>{
  'arg1': [1, 2, 3],
  'arg2': map,
};
const androidVolumeDirection = AndroidVolumeDirection.lower;

final playbackStateStreamValues = <PlaybackState>[
  PlaybackState(),
  PlaybackState(
    processingState: AudioProcessingState.loading,
  ),
  PlaybackState(
    processingState: AudioProcessingState.completed,
  ),
];

final queueStreamValues = <List<MediaItem>?>[
  [mediaItem],
  null,
  [mediaItem, mediaItem, mediaItem],
];

final queueTitleStreamValues = <String>[
  'title_1',
  'title_2',
  'title_3',
];

const mediaItemStreamValues = <MediaItem?>[
  MediaItem(id: 'id_1', title: ''),
  null,
  MediaItem(id: 'id_3', title: ''),
];

const ratingStyleStreamValues = <RatingStyle>[
  RatingStyle.percentage,
  RatingStyle.range4stars,
  RatingStyle.heart,
];

const androidPlaybackInfoStreamValues = <AndroidPlaybackInfo>[
  LocalAndroidPlaybackInfo(),
  RemoteAndroidPlaybackInfo(
    volumeControlType: AndroidVolumeControlType.absolute,
    maxVolume: 100,
    volume: 0,
  ),
  RemoteAndroidPlaybackInfo(
    volumeControlType: AndroidVolumeControlType.absolute,
    maxVolume: 100,
    volume: 50,
  ),
];

const customEventStreamValues = <int>[
  1,
  2,
  3,
];

const customStateStreamValues = <int>[
  1,
  2,
  3,
];

class MockIsolateAudioHandler extends IsolateAudioHandler {
  final bool _syncSubjects;
  MockIsolateAudioHandler({bool syncSubjects = false})
      : _syncSubjects = syncSubjects;

  @override
  void syncSubjects() {
    if (_syncSubjects) {
      super.syncSubjects();
    }
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final handler = MockBaseAudioHandler();
  await AudioService.hostHandler(handler);

  Isolate? isolate;

  /// Runs the isolate and waits until it returns a result.
  Future<T> runIsolate<T extends Object?>(Function(SendPort) function) async {
    final receivePort = ReceivePort();
    isolate = await Isolate.spawn(function, receivePort.sendPort);
    final result = await receivePort.first as T;
    return result;
  }

  /// Runs isolate, but doesn't wait until it returns a result.
  Future<ReceivePort> runIsolateWithDeferredResult(
      Function(SendPort) function) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(function, receivePort.sendPort);
    return receivePort;
  }

  setUp(() {
    handler.reset();
  });

  tearDown(() {
    if (isolate != null) {
      isolate!.kill(priority: Isolate.immediate);
    }
  });

  group("Connection setup ▮", () {
    test("throws when attempting to host IsolateAudioHandler", () {
      expect(
        () => AudioService.hostHandler(MockIsolateAudioHandler()),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            "Registering IsolateAudioHandler is not allowed, as this will lead "
                "to an infinite loop when its methods are called",
          ),
        ),
      );
    });

    test("throws when attempting to host more than once", () async {
      expect(
        () => AudioService.hostHandler(BaseAudioHandler()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            "Some isolate has already hosted a handler",
          ),
        ),
      );
    });
  });

  group("IsolateAudioHandler ▮", () {
    void expectCall(String method, [List<Object?> arguments = const [null]]) {
      final actualMethod = handler.log.firstOrNull;
      final actualArguments = handler.argumentsLog.firstOrNull;
      expect(actualMethod, method);
      expect(actualArguments, arguments);
    }

    test("subjects receive the most recent update", () async {
      handler.stubPlaybackState =
          BehaviorSubject.seeded(playbackStateStreamValues[0]);
      final receivePort = await runIsolateWithDeferredResult(subjectsAreRecent);
      final values = <PlaybackState>[];
      final isolateValues = <PlaybackState>[];
      handler.stubPlaybackState.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message as PlaybackState);
          if (message.processingState ==
              playbackStateStreamValues.last.processingState) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our message
      handler.stubPlaybackState.add(playbackStateStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('playbackState');
      expect(
        values.map((e) => e.processingState).toList(),
        playbackStateStreamValues.map((e) => e.processingState).toList(),
      );
      expect(
        isolateValues.single.processingState,
        playbackStateStreamValues.last.processingState,
      );
    });

    test("playbackState", () async {
      handler.stubPlaybackState =
          BehaviorSubject.seeded(playbackStateStreamValues[0]);
      final receivePort =
          await runIsolateWithDeferredResult(playbackStateSubject);
      final values = <PlaybackState>[];
      final isolateValues = <PlaybackState>[];
      handler.stubPlaybackState.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message as PlaybackState);
          if (isolateValues.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our message
      handler.stubPlaybackState.add(playbackStateStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('playbackState');
      expect(
        values.map((e) => e.toString()).toList(),
        isolateValues.map((e) => e.toString()).toList(),
      );
    });

    test("queue", () async {
      handler.stubQueue = BehaviorSubject.seeded(queueStreamValues[0]);
      final receivePort = await runIsolateWithDeferredResult(queueSubject);
      final values = <List<MediaItem>?>[];
      final isolateValues = <List<MediaItem>?>[];
      handler.stubQueue.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message as List<MediaItem>?);
          if (isolateValues.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our message
      handler.stubQueue.add(queueStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('queue');
      expect(
        values.map((e) => e.toString()).toList(),
        isolateValues.map((e) => e.toString()).toList(),
      );
    });

    test("queueTitle", () async {
      handler.stubQueueTitle =
          BehaviorSubject.seeded(queueTitleStreamValues[0]);
      final receivePort = await runIsolateWithDeferredResult(queueTitleSubject);
      final values = <String>[];
      final isolateValues = <String>[];
      handler.stubQueueTitle.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message as String);
          if (isolateValues.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our message
      handler.stubQueueTitle.add(queueTitleStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('queueTitle');
      expect(
        values.map((e) => e.toString()).toList(),
        isolateValues.map((e) => e.toString()).toList(),
      );
    });

    test("mediaItem", () async {
      handler.stubMediaItem = BehaviorSubject.seeded(mediaItemStreamValues[0]);
      final receivePort = await runIsolateWithDeferredResult(mediaItemSubject);
      final values = <MediaItem?>[];
      final isolateValues = <MediaItem?>[];
      handler.stubMediaItem.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message as MediaItem?);
          if (isolateValues.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our message
      handler.stubMediaItem.add(mediaItemStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('mediaItem');
      expect(
        values.map((e) => e.toString()).toList(),
        isolateValues.map((e) => e.toString()).toList(),
      );
    });

    test("ratingStyle", () async {
      handler.stubRatingStyle =
          BehaviorSubject.seeded(ratingStyleStreamValues[0]);
      final receivePort =
          await runIsolateWithDeferredResult(ratingStyleSubject);
      final values = <RatingStyle>[];
      final isolateValues = <RatingStyle>[];
      handler.stubRatingStyle.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message as RatingStyle);
          if (isolateValues.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our message
      handler.stubRatingStyle.add(ratingStyleStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('ratingStyle');
      expect(
        values.map((e) => e.toString()).toList(),
        isolateValues.map((e) => e.toString()).toList(),
      );
    });

    test("androidPlaybackInfo", () async {
      handler.stubAndroidPlaybackInfo =
          BehaviorSubject.seeded(androidPlaybackInfoStreamValues[0]);
      final receivePort =
          await runIsolateWithDeferredResult(androidPlaybackInfoSubject);
      final values = <AndroidPlaybackInfo>[];
      final isolateValues = <AndroidPlaybackInfo>[];
      handler.stubAndroidPlaybackInfo.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message as AndroidPlaybackInfo);
          if (isolateValues.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our message
      handler.stubAndroidPlaybackInfo.add(androidPlaybackInfoStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('androidPlaybackInfo');
      expect(
        values.map((e) => e.toString()).toList(),
        isolateValues.map((e) => e.toString()).toList(),
      );
    });

    test("customEvent", () async {
      handler.stubCustomEvent = PublishSubject();
      final receivePort =
          await runIsolateWithDeferredResult(customEventSubject);
      final values = <Object?>[];
      final isolateValues = <Object?>[];
      handler.stubCustomEvent.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message);
          if (isolateValues.length == 1) {
            completer.complete();
            completer = Completer();
          } else if (isolateValues.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our messages
      handler.stubCustomEvent.add(customEventStreamValues[0]);
      await completer.future;
      handler.stubCustomEvent.add(customEventStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('customEvent');
      expect(
        values.map((e) => e.toString()).toList(),
        isolateValues.map((e) => e.toString()).toList(),
      );
    });

    test("customState", () async {
      handler.stubCustomState =
          BehaviorSubject.seeded(customStateStreamValues[0]);
      final receivePort =
          await runIsolateWithDeferredResult(customStateSubject);
      final values = <Object?>[];
      final isolateValues = <Object?>[];
      handler.stubCustomState.listen((value) {
        values.add(value);
      });
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          isolateValues.add(message);
          if (isolateValues.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      // send our messages
      handler.stubCustomState.add(customStateStreamValues[1]);

      // and the last one is sent from the isolate

      // wait until isolate delivers all results back
      await completer.future;
      expectCall('customState');
      expect(
        values.map((e) => e.toString()).toList(),
        isolateValues.map((e) => e.toString()).toList(),
      );
    });

    test("prepare", () async {
      await runIsolate(prepare);
      expectCall('prepare');
    });

    test("prepareFromMediaId", () async {
      await runIsolate(prepareFromMediaId);
      expectCall('prepareFromMediaId', const [id, map]);
    });

    test("prepareFromSearch", () async {
      await runIsolate(prepareFromSearch);
      expectCall('prepareFromSearch', const [query, map]);
    });

    test("prepareFromUri", () async {
      await runIsolate(prepareFromUri);
      expectCall('prepareFromUri', [uri, map]);
    });

    test("play", () async {
      await runIsolate(play);
      expectCall('play');
    });

    test("playFromMediaId", () async {
      await runIsolate(playFromMediaId);
      expectCall('playFromMediaId', const [id, map]);
    });

    test("playFromSearch", () async {
      await runIsolate(playFromSearch);
      expectCall('playFromSearch', const [query, map]);
    });

    test("playFromUri", () async {
      await runIsolate(playFromUri);
      expectCall('playFromUri', [uri, map]);
    });

    test("playMediaItem", () async {
      await runIsolate(playMediaItem);
      expectCall('playMediaItem', const [mediaItem]);
    });

    test("pause", () async {
      await runIsolate(pause);
      expectCall('pause');
    });

    test("click", () async {
      await runIsolate(click);
      expectCall('click', const [mediaButton]);
    });

    test("stop", () async {
      await runIsolate(stop);
      expectCall('stop');
    });

    test("addQueueItem", () async {
      await runIsolate(addQueueItem);
      expectCall('addQueueItem', const [mediaItem]);
    });

    test("addQueueItems", () async {
      await runIsolate(addQueueItems);
      expectCall('addQueueItems', const [queue]);
    });

    test("insertQueueItem", () async {
      await runIsolate(insertQueueItem);
      expectCall('insertQueueItem', const [0, mediaItem]);
    });

    test("updateQueue", () async {
      await runIsolate(updateQueue);
      expectCall('updateQueue', const [queue]);
    });

    test("updateMediaItem", () async {
      await runIsolate(updateMediaItem);
      expectCall('updateMediaItem', const [mediaItem]);
    });

    test("removeQueueItem", () async {
      await runIsolate(removeQueueItem);
      expectCall('removeQueueItem', const [mediaItem]);
    });

    test("removeQueueItemAt", () async {
      await runIsolate(removeQueueItemAt);
      expectCall('removeQueueItemAt', const [0]);
    });

    test("skipToNext", () async {
      await runIsolate(skipToNext);
      expectCall('skipToNext');
    });

    test("skipToPrevious", () async {
      await runIsolate(skipToPrevious);
      expectCall('skipToPrevious');
    });

    test("fastForward", () async {
      await runIsolate(fastForward);
      expectCall('fastForward');
    });

    test("rewind", () async {
      await runIsolate(rewind);
      expectCall('rewind');
    });

    test("skipToQueueItem", () async {
      await runIsolate(skipToQueueItem);
      expectCall('skipToQueueItem', const [0]);
    });

    test("seek", () async {
      await runIsolate(seek);
      expectCall('seek', const [duration]);
    });

    test("setRating", () async {
      await runIsolate(setRating);
      expectCall('setRating', const [rating, map]);
    });

    test("setCaptioningEnabled", () async {
      await runIsolate(setCaptioningEnabled);
      expectCall('setCaptioningEnabled', const [false]);
    });

    test("setRepeatMode", () async {
      await runIsolate(setRepeatMode);
      expectCall('setRepeatMode', const [repeatMode]);
    });

    test("setShuffleMode", () async {
      await runIsolate(setShuffleMode);
      expectCall('setShuffleMode', const [shuffleMode]);
    });

    test("seekBackward", () async {
      await runIsolate(seekBackward);
      expectCall('seekBackward', const [false]);
    });

    test("seekForward", () async {
      await runIsolate(seekForward);
      expectCall('seekForward', const [false]);
    });

    test("setSpeed", () async {
      await runIsolate(setSpeed);
      expectCall('setSpeed', const [0.1]);
    });

    test("customAction", () async {
      final expectedResult = 'custom_action_result';
      handler.stubCustomAction = expectedResult;
      final result = await runIsolate(customAction);
      expectCall(
          'customAction', const [customActionName, customActionArguments]);
      expect(result, expectedResult);
    });

    test("onTaskRemoved", () async {
      await runIsolate(onTaskRemoved);
      expectCall('onTaskRemoved');
    });

    test("onNotificationDeleted", () async {
      await runIsolate(onNotificationDeleted);
      expectCall('onNotificationDeleted');
    });

    test("getChildren", () async {
      final expectedResult = queue;
      handler.stubGetChildren = expectedResult;
      final result = await runIsolate(getChildren);
      expectCall('getChildren', const [id, map]);
      expect(result, expectedResult);
    });

    test("subscribeToChildren", () async {
      final expectedResult = <Map<String, Object?>>[
        {'key1': 'value1'},
        {'key2': 'value2'},
        {'key3': 'value3'}
      ];
      handler.stubSubscribeToChildren = BehaviorSubject();
      final receivePort =
          await runIsolateWithDeferredResult(subscribeToChildren);
      final result = <Map<String, Object?>>[];
      var completer = Completer<void>();
      receivePort.listen((Object? message) {
        if (result.isEmpty && message == isolateInitMessage) {
          completer.complete();
          completer = Completer();
        } else {
          result.add(message as Map<String, Object?>);
          if (result.length == 3) {
            completer.complete();
          }
        }
      });
      // wait until isolate connects
      await completer.future;

      for (final options in expectedResult) {
        handler.stubSubscribeToChildren.add(options);
      }
      // wait until isolate delivers all results
      await completer.future;
      expectCall('subscribeToChildren', const [id]);
      expect(result, expectedResult);
    });

    test("getMediaItem", () async {
      final expectedResult = mediaItem;
      handler.stubGetMediaItem = expectedResult;
      final result = await runIsolate(getMediaItem);
      expectCall('getMediaItem', const [id]);
      expect(result, expectedResult);
    });

    test("search", () async {
      final expectedResult = queue;
      handler.stubSearch = expectedResult;
      final result = await runIsolate(search);
      expectCall('search', const [query, map]);
      expect(result, expectedResult);
    });

    test("androidAdjustRemoteVolume", () async {
      await runIsolate(androidAdjustRemoteVolume);
      expectCall('androidAdjustRemoteVolume', [androidVolumeDirection]);
    });

    test("androidSetRemoteVolume", () async {
      await runIsolate(androidSetRemoteVolume);
      expectCall('androidSetRemoteVolume', [0]);
    });
  });
}

void subjectsAreRecent(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final playbackState = handler.playbackState;
  await handler.syncSubject(playbackState, 'playbackState');
  port.send(isolateInitMessage);
  playbackState.listen((value) {
    port.send(value);
  });
  playbackState.add(playbackStateStreamValues[2]);
}

void playbackStateSubject(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final playbackState = handler.playbackState;
  await handler.syncSubject(playbackState, 'playbackState');
  port.send(isolateInitMessage);
  var updates = 0;
  playbackState.listen((value) {
    port.send(value);
    updates += 1;
    if (updates == 2) {
      playbackState.add(playbackStateStreamValues[2]);
    }
  });
}

void queueSubject(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final queue = handler.queue;
  await handler.syncSubject(queue, 'queue');
  port.send(isolateInitMessage);
  var updates = 0;
  queue.listen((value) {
    port.send(value);
    updates += 1;
    if (updates == 2) {
      queue.add(queueStreamValues[2]);
    }
  });
}

void queueTitleSubject(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final queueTitle = handler.queueTitle;
  await handler.syncSubject(queueTitle, 'queueTitle');
  port.send(isolateInitMessage);
  var updates = 0;
  queueTitle.listen((value) {
    port.send(value);
    updates += 1;
    if (updates == 2) {
      queueTitle.add(queueTitleStreamValues[2]);
    }
  });
}

void mediaItemSubject(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final mediaItem = handler.mediaItem;
  await handler.syncSubject(mediaItem, 'mediaItem');
  port.send(isolateInitMessage);
  var updates = 0;
  mediaItem.listen((value) {
    port.send(value);
    updates += 1;
    if (updates == 2) {
      mediaItem.add(mediaItemStreamValues[2]);
    }
  });
}

void ratingStyleSubject(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final ratingStyle = handler.ratingStyle;
  await handler.syncSubject(ratingStyle, 'ratingStyle');
  port.send(isolateInitMessage);
  var updates = 0;
  ratingStyle.listen((value) {
    port.send(value);
    updates += 1;
    if (updates == 2) {
      ratingStyle.add(ratingStyleStreamValues[2]);
    }
  });
}

void androidPlaybackInfoSubject(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final androidPlaybackInfo = handler.androidPlaybackInfo;
  await handler.syncSubject(androidPlaybackInfo, 'androidPlaybackInfo');
  port.send(isolateInitMessage);
  var updates = 0;
  androidPlaybackInfo.listen((value) {
    port.send(value);
    updates += 1;
    if (updates == 2) {
      androidPlaybackInfo.add(androidPlaybackInfoStreamValues[2]);
    }
  });
}

void customEventSubject(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final customEvent = handler.customEvent;
  await handler.syncSubject(customEvent, 'customEvent');
  port.send(isolateInitMessage);
  var updates = 0;
  customEvent.listen((dynamic value) {
    port.send(value);
    updates += 1;
    if (updates == 2) {
      customEvent.add(customEventStreamValues[2]);
    }
  });
}

void customStateSubject(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final customState = handler.customState;
  await handler.syncSubject(customState, 'customState');
  port.send(isolateInitMessage);
  var updates = 0;
  customState.listen((dynamic value) {
    port.send(value);
    updates += 1;
    if (updates == 2) {
      customState.add(customStateStreamValues[2]);
    }
  });
}

void prepare(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.prepare();
  port.send(isolateInitMessage);
}

void prepareFromMediaId(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.prepareFromMediaId(id, map);
  port.send(isolateInitMessage);
}

void prepareFromSearch(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.prepareFromSearch(query, map);
  port.send(isolateInitMessage);
}

void prepareFromUri(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.prepareFromUri(uri, map);
  port.send(isolateInitMessage);
}

void play(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.play();
  port.send(isolateInitMessage);
}

void playFromMediaId(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.playFromMediaId(id, map);
  port.send(isolateInitMessage);
}

void playFromSearch(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.playFromSearch(query, map);
  port.send(isolateInitMessage);
}

void playFromUri(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.playFromUri(uri, map);
  port.send(isolateInitMessage);
}

void playMediaItem(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.playMediaItem(mediaItem);
  port.send(isolateInitMessage);
}

void pause(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.pause();
  port.send(isolateInitMessage);
}

void click(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.click(MediaButton.next);
  port.send(isolateInitMessage);
}

void stop(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.stop();
  port.send(isolateInitMessage);
}

void addQueueItem(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.addQueueItem(mediaItem);
  port.send(isolateInitMessage);
}

void addQueueItems(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.addQueueItems(queue);
  port.send(isolateInitMessage);
}

void insertQueueItem(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.insertQueueItem(0, mediaItem);
  port.send(isolateInitMessage);
}

void updateQueue(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.updateQueue(queue);
  port.send(isolateInitMessage);
}

void updateMediaItem(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.updateMediaItem(mediaItem);
  port.send(isolateInitMessage);
}

void removeQueueItem(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.removeQueueItem(mediaItem);
  port.send(isolateInitMessage);
}

void removeQueueItemAt(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.removeQueueItemAt(0);
  port.send(isolateInitMessage);
}

void skipToNext(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.skipToNext();
  port.send(isolateInitMessage);
}

void skipToPrevious(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.skipToPrevious();
  port.send(isolateInitMessage);
}

void fastForward(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.fastForward();
  port.send(isolateInitMessage);
}

void rewind(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.rewind();
  port.send(isolateInitMessage);
}

void skipToQueueItem(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.skipToQueueItem(0);
  port.send(isolateInitMessage);
}

void seek(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.seek(duration);
  port.send(isolateInitMessage);
}

void setRating(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.setRating(rating, map);
  port.send(isolateInitMessage);
}

void setCaptioningEnabled(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.setCaptioningEnabled(false);
  port.send(isolateInitMessage);
}

void setRepeatMode(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.setRepeatMode(repeatMode);
  port.send(isolateInitMessage);
}

void setShuffleMode(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.setShuffleMode(shuffleMode);
  port.send(isolateInitMessage);
}

void seekBackward(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.seekBackward(false);
  port.send(isolateInitMessage);
}

void seekForward(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.seekForward(false);
  port.send(isolateInitMessage);
}

void setSpeed(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.setSpeed(0.1);
  port.send(isolateInitMessage);
}

void customAction(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  port.send(await handler.customAction(
    customActionName,
    customActionArguments,
  ));
}

void onTaskRemoved(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.onTaskRemoved();
  port.send(isolateInitMessage);
}

void onNotificationDeleted(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.onNotificationDeleted();
  port.send(isolateInitMessage);
}

void getChildren(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  port.send(await handler.getChildren(id, map));
}

void subscribeToChildren(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  final result = handler.subscribeToChildren(id);
  port.send(isolateInitMessage);
  result.listen((event) {
    port.send(event);
  });
}

void getMediaItem(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  port.send(await handler.getMediaItem(id));
}

void search(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  port.send(await handler.search(query, map));
}

void androidAdjustRemoteVolume(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.androidAdjustRemoteVolume(androidVolumeDirection);
  port.send(isolateInitMessage);
}

void androidSetRemoteVolume(SendPort port) async {
  final handler = MockIsolateAudioHandler();
  await handler.androidSetRemoteVolume(0);
  port.send(isolateInitMessage);
}
