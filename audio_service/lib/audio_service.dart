import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:audio_service_dart/audio_service_dart.dart';
import 'package:audio_service_dart/base_audio_handler.dart';
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:rxdart/rxdart.dart';

export 'package:audio_service_dart/audio_service_dart.dart';

AudioServicePlatform _platform = AudioServicePlatform.instance;

/// Provides an API to manage the app's [AudioHandler]. An app must call [init]
/// during initialisation to register the [AudioHandler] that will service all
/// requests to play audio.
class AudioService {
  /// The cache to use when loading artwork. Defaults to [DefaultCacheManager].
  static BaseCacheManager get cacheManager => _cacheManager!;
  static BaseCacheManager? _cacheManager;

  static late AudioServiceConfig _config;
  static late AudioHandler _handler;

  /// The current configuration.
  static AudioServiceConfig get config => _config;

  /// The root media ID for browsing media provided by the background
  /// task.
  static const String browsableRootId = 'root';

  /// The root media ID for browsing the most recently played item(s).
  static const String recentRootId = 'recent';

  // ignore: close_sinks
  static final BehaviorSubject<bool> _notificationClickEvent =
      BehaviorSubject.seeded(false);

  /// A stream that broadcasts the status of the notificationClick event.
  static ValueStream<bool> get notificationClickEvent =>
      _notificationClickEvent;

  // ignore: close_sinks
  static BehaviorSubject<Duration>? _positionSubject;

  static late ReceivePort _customActionReceivePort;

  /// Connect to the [AudioHandler] from another isolate. The [AudioHandler]
  /// must have been initialised via [init] prior to connecting.
  static Future<AudioHandler> connectFromIsolate() async {
    WidgetsFlutterBinding.ensureInitialized();
    return _IsolateAudioHandler();
  }

  /// Register the app's [AudioHandler] with configuration options. This must be
  /// called during the app's initialisation so that it is prepared to handle
  /// audio requests immediately after a cold restart (e.g. if the user clicks
  /// on the play button in the media notification while your app is not running
  /// and your app needs to be woken up).
  ///
  /// You may optionally specify a [cacheManager] to use when loading artwork to
  /// display in the media notification and lock screen. This defaults to
  /// [DefaultCacheManager].
  static Future<T> init<T extends AudioHandler>({
    required T builder(),
    AudioServiceConfig? config,
    BaseCacheManager? cacheManager,
  }) async {
    assert(_cacheManager == null);
    config ??= AudioServiceConfig();
    print("### AudioService.init");
    WidgetsFlutterBinding.ensureInitialized();
    _cacheManager = (cacheManager ??= DefaultCacheManager());
    await _platform.configure(ConfigureRequest(config: config._toMessage()));
    _config = config;
    final handler = builder();
    _handler = handler;

    _platform.setHandlerCallbacks(_HandlerCallbacks(handler));
    // This port listens to connections from other isolates.
    if (!kIsWeb) {
      _customActionReceivePort = ReceivePort();
      _customActionReceivePort.listen((dynamic event) async {
        final request = event as _IsolateRequest;
        switch (request.method) {
          case 'prepare':
            await _handler.prepare();
            request.sendPort.send(null);
            break;
          case 'prepareFromMediaId':
            await _handler.prepareFromMediaId(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'prepareFromSearch':
            await _handler.prepareFromSearch(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'prepareFromUri':
            await _handler.prepareFromUri(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'play':
            await _handler.play();
            request.sendPort.send(null);
            break;
          case 'playFromMediaId':
            await _handler.playFromMediaId(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'playFromSearch':
            await _handler.playFromSearch(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'playFromUri':
            await _handler.playFromUri(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'playMediaItem':
            await _handler.playMediaItem(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'pause':
            await _handler.pause();
            request.sendPort.send(null);
            break;
          case 'click':
            await _handler.click(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'stop':
            await _handler.stop();
            request.sendPort.send(null);
            break;
          case 'addQueueItem':
            await _handler.addQueueItem(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'addQueueItems':
            await _handler.addQueueItems(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'insertQueueItem':
            await _handler.insertQueueItem(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'updateQueue':
            await _handler.updateQueue(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'updateMediaItem':
            await _handler.updateMediaItem(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'removeQueueItem':
            await _handler.removeQueueItem(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'removeQueueItemAt':
            await _handler.removeQueueItemAt(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'skipToNext':
            await _handler.skipToNext();
            request.sendPort.send(null);
            break;
          case 'skipToPrevious':
            await _handler.skipToPrevious();
            request.sendPort.send(null);
            break;
          case 'fastForward':
            await _handler.fastForward();
            request.sendPort.send(null);
            break;
          case 'rewind':
            await _handler.rewind();
            request.sendPort.send(null);
            break;
          case 'skipToQueueItem':
            await _handler.skipToQueueItem(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'seek':
            await _handler.seek(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'setRating':
            await _handler.setRating(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'setCaptioningEnabled':
            await _handler.setCaptioningEnabled(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'setRepeatMode':
            await _handler.setRepeatMode(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'setShuffleMode':
            await _handler.setShuffleMode(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'seekBackward':
            await _handler.seekBackward(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'seekForward':
            await _handler.seekForward(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'setSpeed':
            await _handler.setSpeed(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'customAction':
            await _handler.customAction(
                request.arguments![0], request.arguments![1]);
            request.sendPort.send(null);
            break;
          case 'onTaskRemoved':
            await _handler.onTaskRemoved();
            request.sendPort.send(null);
            break;
          case 'onNotificationDeleted':
            await _handler.onNotificationDeleted();
            request.sendPort.send(null);
            break;
          case 'getChildren':
            request.sendPort.send(await _handler.getChildren(
                request.arguments![0], request.arguments![1]));
            break;
          case 'subscribeToChildren':
            final parentMediaId = request.arguments![0] as String;
            final sendPort = request.arguments![1] as SendPort?;
            _handler
                .subscribeToChildren(parentMediaId)
                .listen((Map<String, dynamic>? options) {
              sendPort!.send(options);
            });
            break;
          case 'getMediaItem':
            request.sendPort
                .send(await _handler.getMediaItem(request.arguments![0]));
            break;
          case 'search':
            request.sendPort.send(await _handler.search(
                request.arguments![0], request.arguments![1]));
            break;
          case 'androidAdjustRemoteVolume':
            await _handler.androidAdjustRemoteVolume(request.arguments![0]);
            request.sendPort.send(null);
            break;
          case 'androidSetRemoteVolume':
            await _handler.androidSetRemoteVolume(request.arguments![0]);
            request.sendPort.send(null);
            break;
        }
      });
      //IsolateNameServer.removePortNameMapping(_isolatePortName);
      IsolateNameServer.registerPortWithName(
          _customActionReceivePort.sendPort, _isolatePortName);
    }
    _handler.mediaItem.listen((MediaItem? mediaItem) async {
      if (mediaItem == null) return;
      final artUri = mediaItem.artUri;
      if (artUri != null) {
        // We potentially need to fetch the art.
        String? filePath;
        if (artUri.scheme == 'file') {
          filePath = artUri.toFilePath();
        } else {
          final FileInfo? fileInfo =
              await cacheManager!.getFileFromMemory(artUri.toString());
          filePath = fileInfo?.file.path;
          if (filePath == null) {
            // We haven't fetched the art yet, so show the metadata now, and again
            // after we load the art.
            await _platform.setMediaItem(
                SetMediaItemRequest(mediaItem: mediaItem.toMessage()));
            // Load the art
            filePath = await _loadArtwork(mediaItem);
            // If we failed to download the art, abort.
            if (filePath == null) return;
            // If we've already set a new media item, cancel this request.
            // XXX: Test this
            //if (mediaItem != _handler.mediaItem.value) return;
          }
        }
        final extras = Map.of(mediaItem.extras ?? <String, dynamic>{});
        extras['artCacheFile'] = filePath;
        final platformMediaItem = mediaItem.copyWith(extras: extras);
        // Show the media item after the art is loaded.
        await _platform.setMediaItem(
            SetMediaItemRequest(mediaItem: platformMediaItem.toMessage()));
      } else {
        await _platform.setMediaItem(
            SetMediaItemRequest(mediaItem: mediaItem.toMessage()));
      }
    });
    _handler.androidPlaybackInfo
        .listen((AndroidPlaybackInfo playbackInfo) async {
      await _platform.setAndroidPlaybackInfo(SetAndroidPlaybackInfoRequest(
          playbackInfo: playbackInfo.toMessage()));
    });
    _handler.queue.listen((List<MediaItem>? queue) async {
      if (queue == null) return;
      if (_config.preloadArtwork) {
        _loadAllArtwork(queue);
      }
      await _platform.setQueue(SetQueueRequest(
          queue: queue.map((item) => item.toMessage()).toList()));
    });
    _handler.playbackState.listen((PlaybackState playbackState) async {
      await _platform
          .setState(SetStateRequest(state: playbackState.toMessage()));
    });

    return handler;
  }

  /// A stream tracking the current position, suitable for animating a seek bar.
  /// To ensure a smooth animation, this stream emits values more frequently on
  /// short media items where the seek bar moves more quickly, and less
  /// frequenly on long media items where the seek bar moves more slowly. The
  /// interval between each update will be no quicker than once every 16ms and
  /// no slower than once every 200ms.
  ///
  /// See [createPositionStream] for more control over the stream parameters.
  //static Stream<Duration> _positionStream;
  static Stream<Duration> getPositionStream() {
    if (_positionSubject == null) {
      _positionSubject = BehaviorSubject<Duration>(sync: true);
      _positionSubject!.addStream(createPositionStream(
          steps: 800,
          minPeriod: Duration(milliseconds: 16),
          maxPeriod: Duration(milliseconds: 200)));
    }
    return _positionSubject!.stream;
  }

  /// Creates a new stream periodically tracking the current position. The
  /// stream will aim to emit [steps] position updates at intervals of
  /// [duration] / [steps]. This interval will be clipped between [minPeriod]
  /// and [maxPeriod]. This stream will not emit values while audio playback is
  /// paused or stalled.
  ///
  /// Note: each time this method is called, a new stream is created. If you
  /// intend to use this stream multiple times, you should hold a reference to
  /// the returned stream.
  static Stream<Duration> createPositionStream({
    int steps = 800,
    Duration minPeriod = const Duration(milliseconds: 200),
    Duration maxPeriod = const Duration(milliseconds: 200),
  }) {
    assert(minPeriod <= maxPeriod);
    assert(minPeriod > Duration.zero);
    Duration? last;
    // ignore: close_sinks
    late StreamController<Duration> controller;
    late StreamSubscription<MediaItem?> mediaItemSubscription;
    late StreamSubscription<PlaybackState> playbackStateSubscription;
    Timer? currentTimer;
    Duration duration() => _handler.mediaItem.value?.duration ?? Duration.zero;
    Duration step() {
      var s = duration() ~/ steps;
      if (s < minPeriod) s = minPeriod;
      if (s > maxPeriod) s = maxPeriod;
      return s;
    }

    void yieldPosition(Timer? timer) {
      if (last != _handler.playbackState.value?.position) {
        controller.add((last = _handler.playbackState.value?.position)!);
      }
    }

    controller = StreamController.broadcast(
      sync: true,
      onListen: () {
        mediaItemSubscription =
            _handler.mediaItem.listen((MediaItem? mediaItem) {
          // Potentially a new duration
          currentTimer?.cancel();
          currentTimer = Timer.periodic(step(), yieldPosition);
        });
        playbackStateSubscription =
            _handler.playbackState.listen((PlaybackState state) {
          // Potentially a time discontinuity
          yieldPosition(currentTimer);
        });
      },
      onCancel: () {
        mediaItemSubscription.cancel();
        playbackStateSubscription.cancel();
      },
    );

    return controller.stream;
  }

  /// In Android, forces media button events to be routed to your active media
  /// session.
  ///
  /// This is necessary if you want to play TextToSpeech in the background and
  /// still respond to media button events. You should call it just before
  /// playing TextToSpeech.
  ///
  /// This is not necessary if you are playing normal audio in the background
  /// such as music because this kind of "normal" audio playback will
  /// automatically qualify your app to receive media button events.
  static Future<void> androidForceEnableMediaButtons() async {
    await _platform.androidForceEnableMediaButtons(
        AndroidForceEnableMediaButtonsRequest());
  }

  /// Stops the service.
  static Future<void> _stop() async {
    final audioSession = await AudioSession.instance;
    try {
      await audioSession.setActive(false);
    } catch (e) {
      print("While deactivating audio session: $e");
    }
    await _platform.stopService(StopServiceRequest());
  }

  static Future<void> _loadAllArtwork(List<MediaItem> queue) async {
    for (var mediaItem in queue) {
      await _loadArtwork(mediaItem);
    }
  }

  static Future<String?> _loadArtwork(MediaItem mediaItem) async {
    try {
      final artUri = mediaItem.artUri;
      if (artUri != null) {
        if (artUri.scheme == 'file') {
          return artUri.toFilePath();
        } else {
          final file =
              await cacheManager.getSingleFile(mediaItem.artUri!.toString());
          return file.path;
        }
      }
    } catch (e) {}
    return null;
  }

  // DEPRECATED members

  /// Deprecated. Use [browsableRootId] instead.
  @deprecated
  static const String MEDIA_ROOT_ID = browsableRootId;

  static final _browseMediaChildrenSubject = BehaviorSubject<List<MediaItem>>();

  /// Deprecated. Directly subscribe to a parent's children via
  /// [AudioHandler.subscribeToChildren].
  @deprecated
  static Stream<List<MediaItem>> get browseMediaChildrenStream =>
      _browseMediaChildrenSubject.stream;

  /// Deprecated. Use [AudioHandler.getChildren] instead.
  @deprecated
  static List<MediaItem>? get browseMediaChildren =>
      _browseMediaChildrenSubject.value;

  /// Deprecated. Use [AudioHandler.playbackState] instead.
  @deprecated
  static ValueStream<PlaybackState> get playbackStateStream =>
      _handler.playbackState;

  /// Deprecated. Use [AudioHandler.playbackState.value] instead.
  @deprecated
  static PlaybackState get playbackState =>
      _handler.playbackState.value ?? PlaybackState();

  /// Deprecated. Use [AudioHandler.mediaItem] instead.
  @deprecated
  static ValueStream<MediaItem?> get currentMediaItemStream =>
      _handler.mediaItem;

  /// Deprecated. Use [AudioHandler.mediaItem.value] instead.
  @deprecated
  static MediaItem? get currentMediaItem => _handler.mediaItem.value;

  /// Deprecated. Use [AudioHandler.queue] instead.
  @deprecated
  static ValueStream<List<MediaItem>?> get queueStream => _handler.queue;

  /// Deprecated. Use [AudioHandler.queue.value] instead.
  @deprecated
  static List<MediaItem>? get queue => _handler.queue.value;

  /// Deprecated. Use [AudioHandler.customEvent] instead.
  @deprecated
  static Stream<dynamic> get customEventStream => _handler.customEvent;

  /// Deprecated. Use [AudioHandler.playbackState] instead.
  @deprecated
  static ValueStream<bool> get runningStream => playbackStateStream
          .map((state) => state.processingState != AudioProcessingState.idle)
      as ValueStream<bool>;

  /// Deprecated. Use [AudioHandler.playbackState.value.processingState] instead.
  @deprecated
  static bool get running => runningStream.value ?? false;

  static StreamSubscription? _childrenSubscription;

  /// Deprecated. Instead, subscribe directly to a parent's children via
  /// [AudioHandler.subscribeToChildren].
  @deprecated
  static Future<void> setBrowseMediaParent(
      [String parentMediaId = browsableRootId]) async {
    _childrenSubscription?.cancel();
    _childrenSubscription = _handler
        .subscribeToChildren(parentMediaId)
        .listen((Map<String, dynamic>? options) async {
      _browseMediaChildrenSubject
          .add(await _handler.getChildren(parentMediaId));
    });
  }

  /// Deprecated. Use [AudioHandler.addQueueItem] instead.
  @deprecated
  static final addQueueItem = _handler.addQueueItem;

  /// Deprecated. Use [AudioHandler.addQueueItemAt] instead.
  @deprecated
  static Future<void> addQueueItemAt(MediaItem mediaItem, int index) async {
    await _handler.insertQueueItem(index, mediaItem);
  }

  /// Deprecated. Use [AudioHandler.removeQueueItem] instead.
  @deprecated
  static final removeQueueItem = _handler.removeQueueItem;

  /// Deprecated. Use [AudioHandler.addQueueItems] instead.
  @deprecated
  static Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    for (var mediaItem in mediaItems) {
      await addQueueItem(mediaItem);
    }
  }

  /// Deprecated. Use [AudioHandler.updateQueue] instead.
  @deprecated
  static final updateQueue = _handler.updateQueue;

  /// Deprecated. Use [AudioHandler.updateMediaItem] instead.
  @deprecated
  static final updateMediaItem = _handler.updateMediaItem;

  /// Deprecated. Use [AudioHandler.click] instead.
  @deprecated
  static final Future<void> Function([MediaButton]) click = _handler.click;

  /// Deprecated. Use [AudioHandler.prepare] instead.
  @deprecated
  static final prepare = _handler.prepare;

  /// Deprecated. Use [AudioHandler.prepareFromMediaId] instead.
  @deprecated
  static final Future<void> Function(String, [Map<String, dynamic>])
      prepareFromMediaId = _handler.prepareFromMediaId;

  /// Deprecated. Use [AudioHandler.play] instead.
  @deprecated
  static final play = _handler.play;

  /// Deprecated. Use [AudioHandler.playFromMediaId] instead.
  @deprecated
  static final Future<void> Function(String, [Map<String, dynamic>])
      playFromMediaId = _handler.playFromMediaId;

  /// Deprecated. Use [AudioHandler.playMediaItem] instead.
  @deprecated
  static final playMediaItem = _handler.playMediaItem;

  /// Deprecated. Use [AudioHandler.skipToQueueItem] instead.
  @deprecated
  static Future<void> skipToQueueItem(String mediaId) async {
    final queue = _handler.queue.value!;
    int index = queue.indexWhere((item) => item.id == mediaId);
    await _handler.skipToQueueItem(index);
  }

  /// Deprecated. Use [AudioHandler.pause] instead.
  @deprecated
  static final pause = _handler.pause;

  /// Deprecated. Use [AudioHandler.stop] instead.
  @deprecated
  static final stop = _handler.stop;

  /// Deprecated. Use [AudioHandler.seek] instead.
  @deprecated
  static final seekTo = _handler.seek;

  /// Deprecated. Use [AudioHandler.skipToNext] instead.
  @deprecated
  static final skipToNext = _handler.skipToNext;

  /// Deprecated. Use [AudioHandler.skipToPrevious] instead.
  @deprecated
  static final skipToPrevious = _handler.skipToPrevious;

  /// Deprecated. Use [AudioHandler.fastForward] instead.
  @deprecated
  static final Future<void> Function() fastForward = _handler.fastForward;

  /// Deprecated. Use [AudioHandler.rewind] instead.
  @deprecated
  static final Future<void> Function() rewind = _handler.rewind;

  /// Deprecated. Use [AudioHandler.setRepeatMode] instead.
  @deprecated
  static final setRepeatMode = _handler.setRepeatMode;

  /// Deprecated. Use [AudioHandler.setShuffleMode] instead.
  @deprecated
  static final setShuffleMode = _handler.setShuffleMode;

  /// Deprecated. Use [AudioHandler.setRating] instead.
  @deprecated
  static final Future<void> Function(Rating, Map<dynamic, dynamic>) setRating =
      _handler.setRating;

  /// Deprecated. Use [AudioHandler.setSpeed] instead.
  @deprecated
  static final setSpeed = _handler.setSpeed;

  /// Deprecated. Use [AudioHandler.seekBackward] instead.
  @deprecated
  static final seekBackward = _handler.seekBackward;

  /// Deprecated. Use [AudioHandler.seekForward] instead.
  @deprecated
  static final seekForward = _handler.seekForward;

  /// Deprecated. Use [AudioHandler.customAction] instead.
  @deprecated
  static final Future<dynamic> Function(String, Map<String, dynamic>)
      customAction = _handler.customAction;
}

/// This class is deprecated. Use [BaseAudioHandler] instead.
@deprecated
abstract class BackgroundAudioTask extends BaseAudioHandler {
  /// Deprecated
  Duration get fastForwardInterval => AudioService.config.fastForwardInterval;

  /// Deprecated
  Duration get rewindInterval => AudioService.config.rewindInterval;

  /// Depricated. Replaced by [AudioHandler.stop].
  @mustCallSuper
  Future<void> onStop() async {
    await super.stop();
  }

  /// Deprecated. Replaced by [AudioHandler.getChildren].
  Future<List<MediaItem>> onLoadChildren(String parentMediaId) async => [];

  /// Deprecated. Replaced by [AudioHandler.click].
  Future<void> onClick(MediaButton? button) async {
    switch (button!) {
      case MediaButton.media:
        if (playbackState.value!.playing) {
          await onPause();
        } else {
          await onPlay();
        }
        break;
      case MediaButton.next:
        await onSkipToNext();
        break;
      case MediaButton.previous:
        await onSkipToPrevious();
        break;
    }
  }

  /// Deprecated. Replaced by [AudioHandler.pause].
  Future<void> onPause() async {}

  /// Deprecated. Replaced by [AudioHandler.prepare].
  Future<void> onPrepare() async {}

  /// Deprecated. Replaced by [AudioHandler.prepareFromMediaId].
  Future<void> onPrepareFromMediaId(String mediaId) async {}

  /// Deprecated. Replaced by [AudioHandler.play].
  Future<void> onPlay() async {}

  /// Deprecated. Replaced by [AudioHandler.playFromMediaId].
  Future<void> onPlayFromMediaId(String mediaId) async {}

  /// Deprecated. Replaced by [AudioHandler.playMediaItem].
  Future<void> onPlayMediaItem(MediaItem mediaItem) async {}

  /// Deprecated. Replaced by [AudioHandler.addQueueItem].
  Future<void> onAddQueueItem(MediaItem mediaItem) async {}

  /// Deprecated. Replaced by [AudioHandler.updateQueue].
  Future<void> onUpdateQueue(List<MediaItem> queue) async {}

  /// Deprecated. Replaced by [AudioHandler.updateMediaItem].
  Future<void> onUpdateMediaItem(MediaItem mediaItem) async {}

  /// Deprecated. Replaced by [AudioHandler.insertQueueItem].
  Future<void> onAddQueueItemAt(MediaItem mediaItem, int index) async {}

  /// Deprecated. Replaced by [AudioHandler.removeQueueItem].
  Future<void> onRemoveQueueItem(MediaItem mediaItem) async {}

  /// Deprecated. Replaced by [AudioHandler.skipToNext].
  Future<void> onSkipToNext() => _skip(1);

  /// Deprecated. Replaced by [AudioHandler.skipToPrevious].
  Future<void> onSkipToPrevious() => _skip(-1);

  /// Deprecated. Replaced by [AudioHandler.fastForward].
  Future<void> onFastForward() async {}

  /// Deprecated. Replaced by [AudioHandler.rewind].
  Future<void> onRewind() async {}

  /// Deprecated. Replaced by [AudioHandler.skipToQueueItem].
  Future<void> onSkipToQueueItem(String mediaId) async {}

  /// Deprecated. Replaced by [AudioHandler.seekTo].
  Future<void> onSeekTo(Duration position) async {}

  /// Deprecated. Replaced by [AudioHandler.setRating].
  Future<void> onSetRating(
      Rating rating, Map<dynamic, dynamic>? extras) async {}

  /// Deprecated. Replaced by [AudioHandler.setRepeatMode].
  Future<void> onSetRepeatMode(AudioServiceRepeatMode repeatMode) async {}

  /// Deprecated. Replaced by [AudioHandler.setShuffleMode].
  Future<void> onSetShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  /// Deprecated. Replaced by [AudioHandler.seekBackward].
  Future<void> onSeekBackward(bool begin) async {}

  /// Deprecated. Replaced by [AudioHandler.seekForward].
  Future<void> onSeekForward(bool begin) async {}

  /// Deprecated. Replaced by [AudioHandler.setSpeed].
  Future<void> onSetSpeed(double speed) async {}

  /// Deprecated. Replaced by [AudioHandler.customAction].
  Future<dynamic> onCustomAction(String name, dynamic arguments) async {}

  /// Deprecated. Replaced by [AudioHandler.onTaskRemoved].
  Future<void> onTaskRemoved() async {}

  /// Deprecated. Replaced by [AudioHandler.onNotificationDeleted].
  Future<void> onClose() => onStop();

  Future<void> _skip(int offset) async {
    final mediaItem = this.mediaItem.value;
    if (mediaItem == null) return;
    final queue = this.queue.value ?? <MediaItem>[];
    int i = queue.indexOf(mediaItem);
    if (i == -1) return;
    int newIndex = i + offset;
    if (newIndex >= 0 && newIndex < queue.length)
      await onSkipToQueueItem(queue[newIndex].id);
  }

  @override
  Future<void> prepare() => onPrepare();

  @override
  Future<void> prepareFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) =>
      onPrepareFromMediaId(mediaId);

  @override
  Future<void> play() => onPlay();

  @override
  Future<void> playFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) =>
      onPlayFromMediaId(mediaId);

  @override
  Future<void> playMediaItem(MediaItem mediaItem) => onPlayMediaItem(mediaItem);

  @override
  Future<void> pause() => onPause();

  @override
  Future<void> click([MediaButton button = MediaButton.media]) =>
      onClick(button);

  @override
  Future<void> stop() async {
    await onStop();
    // This is redunant, but we must call super here.
    super.stop();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) => onAddQueueItem(mediaItem);

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    for (var mediaItem in mediaItems) {
      await onAddQueueItem(mediaItem);
    }
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) =>
      onAddQueueItemAt(mediaItem, index);

  @override
  Future<void> updateQueue(List<MediaItem> queue) => onUpdateQueue(queue);

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) =>
      onUpdateMediaItem(mediaItem);

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) =>
      onRemoveQueueItem(mediaItem);

  @override
  Future<void> skipToNext() => onSkipToNext();

  @override
  Future<void> skipToPrevious() => onSkipToPrevious();

  @override
  Future<void> fastForward() => onFastForward();

  @override
  Future<void> rewind() => onRewind();

  @override
  Future<void> skipToQueueItem(int index) async {
    final queue = this.queue.value ?? <MediaItem>[];
    if (index < 0 || index >= queue.length) return;
    final mediaItem = queue[index];
    return onSkipToQueueItem(mediaItem.id);
  }

  @override
  Future<void> seek(Duration position) => onSeekTo(position);

  @override
  Future<void> setRating(Rating rating, Map<dynamic, dynamic>? extras) =>
      onSetRating(rating, extras);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      onSetRepeatMode(repeatMode);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      onSetShuffleMode(shuffleMode);

  @override
  Future<void> seekBackward(bool begin) => onSeekBackward(begin);

  @override
  Future<void> seekForward(bool begin) => onSeekForward(begin);

  @override
  Future<void> setSpeed(double speed) => onSetSpeed(speed);

  @override
  Future<dynamic> customAction(String name, Map<String, dynamic>? extras) =>
      onCustomAction(name, extras);

  @override
  Future<void> onNotificationDeleted() => onClose();

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic>? options]) =>
      onLoadChildren(parentMediaId);
}

class _IsolateRequest {
  /// The send port for sending the response of this request.
  final SendPort sendPort;
  final String method;
  final List<dynamic>? arguments;

  _IsolateRequest(this.sendPort, this.method, [this.arguments]);
}

const _isolatePortName = 'com.ryanheise.audioservice.port';

class _IsolateAudioHandler extends AudioHandler {
  final _childrenSubjects = <String, BehaviorSubject<Map<String, dynamic>?>>{};

  @override
  // ignore: close_sinks
  final BehaviorSubject<PlaybackState> playbackState =
      BehaviorSubject.seeded(PlaybackState());
  @override
  // ignore: close_sinks
  final BehaviorSubject<List<MediaItem>?> queue =
      BehaviorSubject.seeded(<MediaItem>[]);
  @override
  // TODO
  // ignore: close_sinks
  final BehaviorSubject<String> queueTitle = BehaviorSubject.seeded('');
  @override
  // ignore: close_sinks
  final BehaviorSubject<MediaItem?> mediaItem = BehaviorSubject.seeded(null);
  @override
  // TODO
  // ignore: close_sinks
  final BehaviorSubject<AndroidPlaybackInfo> androidPlaybackInfo =
      BehaviorSubject();
  @override
  // TODO
  // ignore: close_sinks
  final BehaviorSubject<RatingStyle> ratingStyle = BehaviorSubject();
  @override
  // TODO
  // ignore: close_sinks
  final PublishSubject<dynamic> customEvent = PublishSubject<dynamic>();

  @override
  // TODO
  // ignore: close_sinks
  final BehaviorSubject<dynamic> customState = BehaviorSubject();

  _IsolateAudioHandler() {
    _platform.setClientCallbacks(_ClientCallbacks(this));
  }

  @override
  Future<void> prepare() => _send('prepare');

  @override
  Future<void> prepareFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) =>
      _send('prepareFromMediaId', [mediaId, extras]);

  @override
  Future<void> prepareFromSearch(String query,
          [Map<String, dynamic>? extras]) =>
      _send('prepareFromSearch', [query, extras]);

  @override
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic>? extras]) =>
      _send('prepareFromUri', [uri, extras]);

  @override
  Future<void> play() => _send('play');

  @override
  Future<void> playFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) =>
      _send('playFromMediaId', [mediaId, extras]);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) =>
      _send('playFromSearch', [query, extras]);

  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]) =>
      _send('playFromUri', [uri, extras]);

  @override
  Future<void> playMediaItem(MediaItem mediaItem) =>
      _send('playMediaItem', [mediaItem]);

  @override
  Future<void> pause() => _send('pause');

  @override
  Future<void> click([MediaButton button = MediaButton.media]) =>
      _send('click', [button]);

  @override
  @mustCallSuper
  Future<void> stop() => _send('stop');

  @override
  Future<void> addQueueItem(MediaItem mediaItem) =>
      _send('addQueueItem', [mediaItem]);

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) =>
      _send('addQueueItems', [mediaItems]);

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) =>
      _send('insertQueueItem', [index, mediaItem]);

  @override
  Future<void> updateQueue(List<MediaItem> queue) =>
      _send('updateQueue', [queue]);

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) =>
      _send('updateMediaItem', [mediaItem]);

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) =>
      _send('removeQueueItem', [mediaItem]);

  @override
  Future<void> removeQueueItemAt(int index) =>
      _send('removeQueueItemAt', [index]);

  @override
  Future<void> skipToNext() => _send('skipToNext');

  @override
  Future<void> skipToPrevious() => _send('skipToPrevious');

  @override
  Future<void> fastForward() => _send('fastForward');

  @override
  Future<void> rewind() => _send('rewind');

  @override
  Future<void> skipToQueueItem(int index) => _send('skipToQueueItem', [index]);

  @override
  Future<void> seek(Duration position) => _send('seek', [position]);

  @override
  Future<void> setRating(Rating rating, Map<dynamic, dynamic>? extras) =>
      _send('setRating', [rating, extras]);

  @override
  Future<void> setCaptioningEnabled(bool enabled) =>
      _send('setCaptioningEnabled', [enabled]);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _send('setRepeatMode', [repeatMode]);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _send('setShuffleMode', [shuffleMode]);

  @override
  Future<void> seekBackward(bool begin) => _send('seekBackward', [begin]);

  @override
  Future<void> seekForward(bool begin) => _send('seekForward', [begin]);

  @override
  Future<void> setSpeed(double speed) => _send('setSpeed', [speed]);

  @override
  Future<dynamic> customAction(String name, Map<String, dynamic>? arguments) =>
      _send('customAction', [name, arguments]);

  @override
  Future<void> onTaskRemoved() => _send('onTaskRemoved');

  @override
  Future<void> onNotificationDeleted() => _send('onNotificationDeleted');

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic>? options]) async =>
      (await _send('getChildren', [parentMediaId, options])) as List<MediaItem>;

  @override
  ValueStream<Map<String, dynamic>?> subscribeToChildren(String parentMediaId) {
    var childrenSubject = _childrenSubjects[parentMediaId];
    if (childrenSubject == null) {
      childrenSubject = _childrenSubjects[parentMediaId] = BehaviorSubject();
      final receivePort = ReceivePort();
      receivePort.listen((options) {
        childrenSubject!.add(options);
      });
      _send('subscribeToChildren', [parentMediaId, receivePort.sendPort]);
    }
    return childrenSubject;
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async =>
      (await _send('getMediaItem', [mediaId])) as MediaItem?;

  @override
  Future<List<MediaItem>> search(String query,
          [Map<String, dynamic>? extras]) async =>
      (await _send('search', [query, extras])) as List<MediaItem>;

  @override
  Future<void> androidAdjustRemoteVolume(AndroidVolumeDirection direction) =>
      _send('androidAdjustRemoteVolume', [direction]);

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) =>
      _send('androidSetRemoteVolume', [volumeIndex]);

  Future<dynamic> _send(String method, [List<dynamic>? arguments]) async {
    final sendPort = IsolateNameServer.lookupPortByName(_isolatePortName);
    if (sendPort == null) return null;
    final receivePort = ReceivePort();
    sendPort.send(_IsolateRequest(receivePort.sendPort, method, arguments));
    final result = await receivePort.first;
    print("isolate result received: $result");
    receivePort.close();
    return result;
  }
}

/// An implementation of [BaseAudioHandler] for Flutter that integrates with
/// the platform.
///
/// ## Android service lifecycle and state transitions
///
/// On Android, the [AudioHandler] runs inside an Android service. This allows
/// the audio logic to continue running in the background, and also an app that
/// had previously been terminated to wake up and resume playing audio when the
/// user click on the play button in a media notification or headset.
///
/// ### Foreground/background transitions
///
/// The underlying Android service enters the `foreground` state whenever
/// [PlaybackState.playing] becomes `true`, and enters the `background` state
/// whenever [PlaybackState.playing] becomes `false`.
///
/// ### Start/stop transitions
///
/// The underlying Android service enters the `started` state whenever
/// [PlaybackState.playing] becomes `true`, and enters the `stopped` state
/// whenever [stop] is called. If you override [stop], you must call `super` to
/// ensure that the service is stopped.
///
/// ### Create/destroy lifecycle
///
/// The underlying service is created either when a client binds to it, or when
/// it is started, and it is destroyed when no clients are bound to it AND it is
/// stopped. When the Flutter UI is attached to an Android Activity, this will
/// also bind to the service, and it will unbind from the service when the
/// Activity is destroyed. A media notification will also bind to the service.
///
/// If the service needs to be created when the app is not already running, your
/// app's `main` entrypoint will be called in the background which should
/// initialise your [AudioHandler].
class BaseFlutterAudioHandler extends BaseAudioHandler {
  /// Provides [SeekHandler.fastForwardInterval] when using [SeekHandler].
  Duration get fastForwardInterval => AudioService.config.fastForwardInterval;

  /// Provides [SeekHandler.rewindInterval] when using [SeekHandler].
  Duration get rewindInterval => AudioService.config.rewindInterval;

  @override
  @mustCallSuper
  Future<void> stop() async {
    await AudioService._stop();
  }
}

/// The configuration options to use when registering an [AudioHandler].
class AudioServiceConfig {
  final bool androidResumeOnClick;
  final String androidNotificationChannelName;
  final String? androidNotificationChannelDescription;

  /// The color to use on the background of the notification on Android. This
  /// should be a non-transparent color.
  final Color? notificationColor;

  /// The icon resource to be used in the Android media notification, specified
  /// like an XML resource reference. This should be a monochrome white icon on
  /// a transparent background. The default value is `"mipmap/ic_launcher"`.
  final String androidNotificationIcon;

  /// Whether notification badges (also known as notification dots) should
  /// appear on a launcher icon when the app has an active notification.
  final bool androidShowNotificationBadge;
  final bool androidNotificationClickStartsActivity;
  final bool androidNotificationOngoing;

  /// Whether the Android service should switch to a lower priority state when
  /// playback is paused allowing the user to swipe away the notification. Note
  /// that while in this lower priority state, the operating system will also be
  /// able to kill your service at any time to reclaim resources.
  final bool androidStopForegroundOnPause;

  /// If not null, causes the artwork specified by [MediaItem.artUri] to be
  /// downscaled to this maximum pixel width. If the resolution of your artwork
  /// is particularly high, this can help to conserve memory. If specified,
  /// [artDownscaleHeight] must also be specified.
  final int? artDownscaleWidth;

  /// If not null, causes the artwork specified by [MediaItem.artUri] to be
  /// downscaled to this maximum pixel height. If the resolution of your artwork
  /// is particularly high, this can help to conserve memory. If specified,
  /// [artDownscaleWidth] must also be specified.
  final int? artDownscaleHeight;

  /// The interval to be used in [AudioHandler.fastForward]. This value will
  /// also be used on iOS to render the skip-forward button. This value must be
  /// positive.
  final Duration fastForwardInterval;

  /// The interval to be used in [AudioHandler.rewind]. This value will also be
  /// used on iOS to render the skip-backward button. This value must be
  /// positive.
  final Duration rewindInterval;

  /// Whether queue support should be enabled on the media session on Android.
  /// If your app will run on Android and has a queue, you should set this to
  /// true.
  final bool androidEnableQueue;
  final bool preloadArtwork;

  /// Extras to report on Android in response to an `onGetRoot` request.
  final Map<String, dynamic>? androidBrowsableRootExtras;

  AudioServiceConfig({
    this.androidResumeOnClick = true,
    this.androidNotificationChannelName = "Notifications",
    this.androidNotificationChannelDescription,
    this.notificationColor,
    this.androidNotificationIcon = 'mipmap/ic_launcher',
    this.androidShowNotificationBadge = false,
    this.androidNotificationClickStartsActivity = true,
    this.androidNotificationOngoing = false,
    this.androidStopForegroundOnPause = true,
    this.artDownscaleWidth,
    this.artDownscaleHeight,
    this.fastForwardInterval = const Duration(seconds: 10),
    this.rewindInterval = const Duration(seconds: 10),
    this.androidEnableQueue = false,
    this.preloadArtwork = false,
    this.androidBrowsableRootExtras,
  })  : assert((artDownscaleWidth != null) == (artDownscaleHeight != null)),
        assert(fastForwardInterval > Duration.zero),
        assert(rewindInterval > Duration.zero);

  AudioServiceConfigMessage _toMessage() => AudioServiceConfigMessage(
        androidResumeOnClick: androidResumeOnClick,
        androidNotificationChannelName: androidNotificationChannelName,
        androidNotificationChannelDescription:
            androidNotificationChannelDescription,
        notificationColor: notificationColor,
        androidNotificationIcon: androidNotificationIcon,
        androidShowNotificationBadge: androidShowNotificationBadge,
        androidNotificationClickStartsActivity:
            androidNotificationClickStartsActivity,
        androidNotificationOngoing: androidNotificationOngoing,
        androidStopForegroundOnPause: androidStopForegroundOnPause,
        artDownscaleWidth: artDownscaleWidth,
        artDownscaleHeight: artDownscaleHeight,
        fastForwardInterval: fastForwardInterval,
        rewindInterval: rewindInterval,
        androidEnableQueue: androidEnableQueue,
        preloadArtwork: preloadArtwork,
        androidBrowsableRootExtras: androidBrowsableRootExtras,
      );

  @override
  String toString() => '${_toMessage().toMap()}';
}

/// Key/value codes for use in [MediaItem.extras] and
/// [AudioServiceConfig.androidBrowsableRootExtras] to influence how Android
/// Auto will style browsable and playable media items.
class AndroidContentStyle {
  /// Set this key to `true` in [AudioServiceConfig.androidBrowsableRootExtras]
  /// to declare that content style is supported.
  static final supportedKey = 'android.media.browse.CONTENT_STYLE_SUPPORTED';

  /// The key in [MediaItem.extras] and
  /// [AudioServiceConfig.androidBrowsableRootExtras] to configure the content
  /// style for playable items. The value can be any of the `*ItemHintValue`
  /// constants defined in this class.
  static final playableHintKey =
      'android.media.browse.CONTENT_STYLE_PLAYABLE_HINT';

  /// The key in [MediaItem.extras] and
  /// [AudioServiceConfig.androidBrowsableRootExtras] to configure the content
  /// style for browsable items. The value can be any of the `*ItemHintValue`
  /// constants defined in this class.
  static final browsableHintKey =
      'android.media.browse.CONTENT_STYLE_BROWSABLE_HINT';

  /// Specifies that items should be presented as lists.
  static final listItemHintValue = 1;

  /// Specifies that items should be presented as grids.
  static final gridItemHintValue = 2;

  /// Specifies that items should be presented as lists with vector icons.
  static final categoryListItemHintValue = 3;

  /// Specifies that items should be presented as grids with vector icons.
  static final categoryGridItemHintValue = 4;
}

extension MediaItemMessageExtension on MediaItemMessage {
  MediaItem toPlugin() => MediaItem(
        id: id,
        album: album,
        title: title,
        artist: artist,
        genre: genre,
        duration: duration,
        artUri: artUri,
        playable: playable,
        displayTitle: displayTitle,
        displaySubtitle: displaySubtitle,
        displayDescription: displayDescription,
        rating: rating?.toPlugin(),
        extras: extras,
      );
}

extension RatingMessageExtension on RatingMessage {
  Rating toPlugin() => Rating.fromRaw(RatingStyle.values[type.index], value);
}

extension AndroidVolumeDirectionMessageExtension
    on AndroidVolumeDirectionMessage {
  AndroidVolumeDirection toPlugin() => AndroidVolumeDirection.values[index]!;
}

extension MediaButtonMessageExtension on MediaButtonMessage {
  MediaButton toPlugin() => MediaButton.values[index];
}

@deprecated
class AudioServiceBackground {
  static BaseAudioHandler get _handler =>
      AudioService._handler as BaseAudioHandler;

  /// The current media item.
  ///
  /// This is the value most recently set via [setMediaItem].
  static PlaybackState get state =>
      _handler.playbackState.value ?? PlaybackState();

  /// The current queue.
  ///
  /// This is the value most recently set via [setQueue].
  static List<MediaItem>? get queue => _handler.queue.value;

  /// Broadcasts to all clients the current state, including:
  ///
  /// * Whether media is playing or paused
  /// * Whether media is buffering or skipping
  /// * The current position, buffered position and speed
  /// * The current set of media actions that should be enabled
  ///
  /// Connected clients will use this information to update their UI.
  ///
  /// You should use [controls] to specify the set of clickable buttons that
  /// should currently be visible in the notification in the current state,
  /// where each button is a [MediaControl] that triggers a different
  /// [MediaAction]. Only the following actions can be enabled as
  /// [MediaControl]s:
  ///
  /// * [MediaAction.stop]
  /// * [MediaAction.pause]
  /// * [MediaAction.play]
  /// * [MediaAction.rewind]
  /// * [MediaAction.skipToPrevious]
  /// * [MediaAction.skipToNext]
  /// * [MediaAction.fastForward]
  /// * [MediaAction.playPause]
  ///
  /// Any other action you would like to enable for clients that is not a clickable
  /// notification button should be specified in the [systemActions] parameter. For
  /// example:
  ///
  /// * [MediaAction.seekTo] (enable a seek bar)
  /// * [MediaAction.seekForward] (enable press-and-hold fast-forward control)
  /// * [MediaAction.seekBackward] (enable press-and-hold rewind control)
  ///
  /// In practice, iOS will treat all entries in [controls] and [systemActions]
  /// in the same way since you cannot customise the icons of controls in the
  /// Control Center. However, on Android, the distinction is important as clickable
  /// buttons in the notification require you to specify your own icon.
  ///
  /// Note that specifying [MediaAction.seekTo] in [systemActions] will enable
  /// a seek bar in both the Android notification and the iOS control center.
  /// [MediaAction.seekForward] and [MediaAction.seekBackward] have a special
  /// behaviour on iOS in which if you have already enabled the
  /// [MediaAction.skipToNext] and [MediaAction.skipToPrevious] buttons, these
  /// additional actions will allow the user to press and hold the buttons to
  /// activate the continuous seeking behaviour.
  ///
  /// On Android, a media notification has a compact and expanded form. In the
  /// compact view, you can optionally specify the indices of up to 3 of your
  /// [controls] that you would like to be shown via [androidCompactActions].
  ///
  /// The playback [position] should NOT be updated continuously in real time.
  /// Instead, it should be updated only when the normal continuity of time is
  /// disrupted, such as during a seek, buffering and seeking. When
  /// broadcasting such a position change, the [updateTime] specifies the time
  /// of that change, allowing clients to project the realtime value of the
  /// position as `position + (DateTime.now() - updateTime)`. As a convenience,
  /// this calculation is provided by [PlaybackState.currentPosition].
  ///
  /// The playback [speed] is given as a double where 1.0 means normal speed.
  static Future<void> setState({
    List<MediaControl>? controls,
    List<MediaAction>? systemActions,
    AudioProcessingState? processingState,
    bool? playing,
    Duration? position,
    Duration? bufferedPosition,
    double? speed,
    DateTime? updateTime,
    List<int>? androidCompactActions,
    AudioServiceRepeatMode? repeatMode,
    AudioServiceShuffleMode? shuffleMode,
  }) async {
    _handler.playbackState.add(_handler.playbackState.value!.copyWith(
      controls: controls,
      systemActions: systemActions?.toSet(),
      processingState: processingState,
      playing: playing,
      updatePosition: position,
      bufferedPosition: bufferedPosition,
      speed: speed,
      androidCompactActionIndices: androidCompactActions,
      repeatMode: repeatMode,
      shuffleMode: shuffleMode,
    ));
  }

  /// Sets the current queue and notifies all clients.
  static Future<void> setQueue(List<MediaItem> queue,
      {bool preloadArtwork = false}) async {
    if (preloadArtwork) {
      print(
          'WARNING: preloadArtwork is not enabled. Must be set via AudioService.init()');
    }
    _handler.queue.add(queue);
  }

  /// Sets the currently playing media item and notifies all clients.
  static Future<void> setMediaItem(MediaItem mediaItem) async {
    _handler.mediaItem.add(mediaItem);
  }

  /// Notifies clients that the child media items of [parentMediaId] have
  /// changed.
  ///
  /// If [parentMediaId] is unspecified, the root parent will be used.
  static Future<void> notifyChildrenChanged(
      [String parentMediaId = AudioService.browsableRootId]) async {
    await _platform.notifyChildrenChanged(
        NotifyChildrenChangedRequest(parentMediaId: parentMediaId));
  }

  /// In Android, forces media button events to be routed to your active media
  /// session.
  ///
  /// This is necessary if you want to play TextToSpeech in the background and
  /// still respond to media button events. You should call it just before
  /// playing TextToSpeech.
  ///
  /// This is not necessary if you are playing normal audio in the background
  /// such as music because this kind of "normal" audio playback will
  /// automatically qualify your app to receive media button events.
  static Future<void> androidForceEnableMediaButtons() async {
    await AudioService.androidForceEnableMediaButtons();
  }

  /// Sends a custom event to the Flutter UI.
  ///
  /// The event parameter can contain any data permitted by Dart's
  /// SendPort/ReceivePort API. Please consult the relevant documentation for
  /// further information.
  static void sendCustomEvent(dynamic event) {
    _handler.customEventSubject.add(event);
  }
}

class _HandlerCallbacks extends AudioHandlerCallbacks {
  final AudioHandler handler;

  _HandlerCallbacks(this.handler);

  @override
  Future<void> addQueueItem(AddQueueItemRequest request) =>
      handler.addQueueItem(request.mediaItem.toPlugin());

  @override
  Future<void> addQueueItems(AddQueueItemsRequest request) => handler
      .addQueueItems(request.queue.map((item) => item.toPlugin()).toList());

  @override
  Future<void> androidAdjustRemoteVolume(
          AndroidAdjustRemoteVolumeRequest request) =>
      handler.androidAdjustRemoteVolume(request.direction.toPlugin());

  @override
  Future<void> androidSetRemoteVolume(AndroidSetRemoteVolumeRequest request) =>
      handler.androidSetRemoteVolume(request.volumeIndex);

  @override
  Future<void> click(ClickRequest request) {
    print('### calling handler.click(${request.button.toPlugin()})');
    return handler.click(request.button.toPlugin());
  }

  @override
  Future customAction(CustomActionRequest request) =>
      handler.customAction(request.name, request.extras);

  @override
  Future<void> fastForward(FastForwardRequest request) => handler.fastForward();

  @override
  Future<GetChildrenResponse> getChildren(GetChildrenRequest request) async {
    final mediaItems =
        await _onLoadChildren(request.parentMediaId, request.options);
    return GetChildrenResponse(
        children: mediaItems.map((item) => item.toMessage()).toList());
  }

  @override
  Future<GetMediaItemResponse> getMediaItem(GetMediaItemRequest request) async {
    return GetMediaItemResponse(
        mediaItem: (await handler.getMediaItem(request.mediaId))?.toMessage());
  }

  @override
  Future<void> insertQueueItem(InsertQueueItemRequest request) =>
      handler.insertQueueItem(request.index, request.mediaItem.toPlugin());

  @override
  Future<void> onNotificationClicked(
      OnNotificationClickedRequest request) async {
    AudioService._notificationClickEvent.add(request.clicked);
  }

  @override
  Future<void> onNotificationDeleted(OnNotificationDeletedRequest request) =>
      handler.onNotificationDeleted();

  @override
  Future<void> onTaskRemoved(OnTaskRemovedRequest request) =>
      handler.onTaskRemoved();

  @override
  Future<void> pause(PauseRequest request) => handler.pause();

  @override
  Future<void> play(PlayRequest request) => handler.play();

  @override
  Future<void> playFromMediaId(PlayFromMediaIdRequest request) =>
      handler.playFromMediaId(request.mediaId);

  @override
  Future<void> playFromSearch(PlayFromSearchRequest request) =>
      handler.playFromSearch(request.query);

  @override
  Future<void> playFromUri(PlayFromUriRequest request) =>
      handler.playFromUri(request.uri);

  @override
  Future<void> playMediaItem(PlayMediaItemRequest request) =>
      handler.playMediaItem(request.mediaItem.toPlugin());

  @override
  Future<void> prepare(PrepareRequest request) => handler.prepare();

  @override
  Future<void> prepareFromMediaId(PrepareFromMediaIdRequest request) =>
      handler.prepareFromMediaId(request.mediaId);

  @override
  Future<void> prepareFromSearch(PrepareFromSearchRequest request) =>
      handler.prepareFromSearch(request.query);

  @override
  Future<void> prepareFromUri(PrepareFromUriRequest request) =>
      handler.prepareFromUri(request.uri);

  @override
  Future<void> removeQueueItem(RemoveQueueItemRequest request) =>
      handler.removeQueueItem(request.mediaItem.toPlugin());

  @override
  Future<void> removeQueueItemAt(RemoveQueueItemAtRequest request) =>
      handler.removeQueueItemAt(request.index);

  @override
  Future<void> rewind(RewindRequest request) => handler.rewind();

  @override
  Future<SearchResponse> search(SearchRequest request) async => SearchResponse(
      mediaItems: (await handler.search(request.query, request.extras))
          .map((item) => item.toMessage())
          .toList());

  @override
  Future<void> seek(SeekRequest request) => handler.seek(request.position);

  @override
  Future<void> seekBackward(SeekBackwardRequest request) =>
      handler.seekBackward(request.begin);

  @override
  Future<void> seekForward(SeekForwardRequest request) =>
      handler.seekForward(request.begin);

  @override
  Future<void> setCaptioningEnabled(SetCaptioningEnabledRequest request) =>
      handler.setCaptioningEnabled(request.enabled);

  @override
  Future<void> setRating(SetRatingRequest request) =>
      handler.setRating(request.rating.toPlugin(), request.extras);

  @override
  Future<void> setRepeatMode(SetRepeatModeRequest request) => handler
      .setRepeatMode(AudioServiceRepeatMode.values[request.repeatMode.index]);

  @override
  Future<void> setShuffleMode(SetShuffleModeRequest request) =>
      handler.setShuffleMode(
          AudioServiceShuffleMode.values[request.shuffleMode.index]);

  @override
  Future<void> setSpeed(SetSpeedRequest request) =>
      handler.setSpeed(request.speed);

  @override
  Future<void> skipToNext(SkipToNextRequest request) => handler.skipToNext();

  @override
  Future<void> skipToPrevious(SkipToPreviousRequest request) =>
      handler.skipToPrevious();

  @override
  Future<void> skipToQueueItem(SkipToQueueItemRequest request) =>
      handler.skipToQueueItem(request.index);

  @override
  Future<void> stop(StopRequest request) => handler.stop();

  @override
  Future<void> updateMediaItem(UpdateMediaItemRequest request) =>
      handler.updateMediaItem(request.mediaItem.toPlugin());

  @override
  Future<void> updateQueue(UpdateQueueRequest request) => handler
      .updateQueue(request.queue.map((item) => item.toPlugin()).toList());

  final Map<String, ValueStream<Map<String, dynamic>?>> _childrenSubscriptions =
      <String, ValueStream<Map<String, dynamic>>>{};

  Future<List<MediaItem>> _onLoadChildren(
      String parentMediaId, Map<String, dynamic>? options) async {
    var childrenSubscription = _childrenSubscriptions[parentMediaId];
    if (childrenSubscription == null) {
      childrenSubscription = _childrenSubscriptions[parentMediaId] =
          handler.subscribeToChildren(parentMediaId);
      childrenSubscription.listen((Map<String, dynamic>? options) {
        // Notify clients that the children of [parentMediaId] have changed.
        _platform.notifyChildrenChanged(NotifyChildrenChangedRequest(
          parentMediaId: parentMediaId,
          options: options,
        ));
      });
    }
    return await handler.getChildren(parentMediaId, options);
  }
}

class _ClientCallbacks extends AudioClientCallbacks {
  final _IsolateAudioHandler handler;

  _ClientCallbacks(this.handler);

  @override
  Future<void> onMediaItemChanged(OnMediaItemChangedRequest request) async {
    handler.mediaItem.add(request.mediaItem?.toPlugin());
  }

  @override
  Future<void> onPlaybackStateChanged(
      OnPlaybackStateChangedRequest request) async {
    final state = request.state;
    handler.playbackState.add(PlaybackState(
      processingState: AudioProcessingState.values[state.processingState.index],
      playing: state.playing,
      // We can't determine whether they are controls.
      systemActions: state.systemActions
          .map((action) => MediaAction.values[action.index])
          .toSet(),
      updatePosition: state.updatePosition,
      bufferedPosition: state.bufferedPosition,
      speed: state.speed,
      updateTime: state.updateTime,
      repeatMode: AudioServiceRepeatMode.values[state.repeatMode.index],
      shuffleMode: AudioServiceShuffleMode.values[state.shuffleMode.index],
    ));
  }

  @override
  Future<void> onQueueChanged(OnQueueChangedRequest request) async {
    handler.queue.add(request.queue.map((item) => item.toPlugin()).toList());
  }

//@override
//Future<void> onChildrenLoaded(OnChildrenLoadedRequest request) {
//  // TODO: implement onChildrenLoaded
//  throw UnimplementedError();
//}
}
