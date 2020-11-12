import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:rxdart/rxdart.dart';

/// Name of port used to send custom events.
const _CUSTOM_EVENT_PORT_NAME = 'customEventPort';

/// The different buttons on a headset.
enum MediaButton {
  media,
  next,
  previous,
}

/// The actons associated with playing audio.
enum MediaAction {
  stop,
  pause,
  play,
  rewind,
  skipToPrevious,
  skipToNext,
  fastForward,
  setRating,
  seekTo,
  playPause,
  playFromMediaId,
  playFromSearch,
  skipToQueueItem,
  playFromUri,
  prepare,
  prepareFromMediaId,
  prepareFromSearch,
  prepareFromUri,
  setRepeatMode,
  unused_1,
  unused_2,
  setShuffleMode,
  seekBackward,
  seekForward,
}

/// The different states during audio processing.
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
  error,
}

/// The playback state for the audio service which includes a [playing] boolean
/// state, a processing state such as [AudioProcessingState.buffering], the
/// playback position and the currently enabled actions to be shown in the
/// Android notification or the iOS control center.
class PlaybackState {
  /// The audio processing state e.g. [BasicPlaybackState.buffering].
  final AudioProcessingState processingState;

  /// Whether audio is either playing, or will play as soon as
  /// [processingState] is [AudioProcessingState.ready]. A true value should
  /// be broadcast whenever it would be appropriate for UIs to display a pause
  /// or stop button.
  ///
  /// Since [playing] and [processingState] can vary independently, it is
  /// possible distinguish a particular audio processing state while audio is
  /// playing vs paused. For example, when buffering occurs during a seek, the
  /// [processingState] can be [AudioProcessingState.buffering], but alongside
  /// that [playing] can be true to indicate that the seek was performed while
  /// playing, or false to indicate that the seek was performed while paused.
  final bool playing;

  /// The set of actions currently supported by the audio service e.g.
  /// [MediaAction.play].
  final Set<MediaAction> actions;

  /// The playback position at the last update time.
  final Duration position;

  /// The buffered position.
  final Duration bufferedPosition;

  /// The current playback speed where 1.0 means normal speed.
  final double speed;

  /// The time at which the playback position was last updated.
  final Duration updateTime;

  /// The current repeat mode.
  final AudioServiceRepeatMode repeatMode;

  /// The current shuffle mode.
  final AudioServiceShuffleMode shuffleMode;

  const PlaybackState({
    @required this.processingState,
    @required this.playing,
    @required this.actions,
    this.position,
    this.bufferedPosition = Duration.zero,
    this.speed,
    this.updateTime,
    this.repeatMode = AudioServiceRepeatMode.none,
    this.shuffleMode = AudioServiceShuffleMode.none,
  });

  /// The current playback position.
  Duration get currentPosition {
    if (playing && processingState == AudioProcessingState.ready) {
      return Duration(
          milliseconds: (position.inMilliseconds +
                  ((DateTime.now().millisecondsSinceEpoch -
                          updateTime.inMilliseconds) *
                      (speed ?? 1.0)))
              .toInt());
    } else {
      return position;
    }
  }
}

enum RatingStyle {
  /// Indicates a rating style is not supported.
  ///
  /// A Rating will never have this type, but can be used by other classes
  /// to indicate they do not support Rating.
  none,

  /// A rating style with a single degree of rating, "heart" vs "no heart".
  ///
  /// Can be used to indicate the content referred to is a favorite (or not).
  heart,

  /// A rating style for "thumb up" vs "thumb down".
  thumbUpDown,

  /// A rating style with 0 to 3 stars.
  range3stars,

  /// A rating style with 0 to 4 stars.
  range4stars,

  /// A rating style with 0 to 5 stars.
  range5stars,

  /// A rating style expressed as a percentage.
  percentage,
}

/// A rating to attach to a MediaItem.
class Rating {
  final RatingStyle _type;
  final dynamic _value;

  const Rating._internal(this._type, this._value);

  /// Create a new heart rating.
  const Rating.newHeartRating(bool hasHeart)
      : this._internal(RatingStyle.heart, hasHeart);

  /// Create a new percentage rating.
  factory Rating.newPercentageRating(double percent) {
    if (percent < 0 || percent > 100) throw ArgumentError();
    return Rating._internal(RatingStyle.percentage, percent);
  }

  /// Create a new star rating.
  factory Rating.newStartRating(RatingStyle starRatingStyle, int starRating) {
    if (starRatingStyle != RatingStyle.range3stars &&
        starRatingStyle != RatingStyle.range4stars &&
        starRatingStyle != RatingStyle.range5stars) {
      throw ArgumentError();
    }
    if (starRating > starRatingStyle.index || starRating < 0)
      throw ArgumentError();
    return Rating._internal(starRatingStyle, starRating);
  }

  /// Create a new thumb rating.
  const Rating.newThumbRating(bool isThumbsUp)
      : this._internal(RatingStyle.thumbUpDown, isThumbsUp);

  /// Create a new unrated rating.
  const Rating.newUnratedRating(RatingStyle ratingStyle)
      : this._internal(ratingStyle, null);

  /// Return the rating style.
  RatingStyle getRatingStyle() => _type;

  /// Returns a percentage rating value greater or equal to 0.0f, or a
  /// negative value if the rating style is not percentage-based, or
  /// if it is unrated.
  double getPercentRating() {
    if (_type != RatingStyle.percentage) return -1;
    if (_value < 0 || _value > 100) return -1;
    return _value ?? -1;
  }

  /// Returns a rating value greater or equal to 0.0f, or a negative
  /// value if the rating style is not star-based, or if it is
  /// unrated.
  int getStarRating() {
    if (_type != RatingStyle.range3stars &&
        _type != RatingStyle.range4stars &&
        _type != RatingStyle.range5stars) return -1;
    return _value ?? -1;
  }

  /// Returns true if the rating is "heart selected" or false if the
  /// rating is "heart unselected", if the rating style is not [heart]
  /// or if it is unrated.
  bool hasHeart() {
    if (_type != RatingStyle.heart) return false;
    return _value ?? false;
  }

  /// Returns true if the rating is "thumb up" or false if the rating
  /// is "thumb down", if the rating style is not [thumbUpDown] or if
  /// it is unrated.
  bool isThumbUp() {
    if (_type != RatingStyle.thumbUpDown) return false;
    return _value ?? false;
  }

  /// Return whether there is a rating value available.
  bool isRated() => _value != null;

  Map<String, dynamic> _toRaw() {
    return <String, dynamic>{
      'type': _type.index,
      'value': _value,
    };
  }

  // Even though this should take a Map<String, dynamic>, that makes an error.
  Rating._fromRaw(Map<dynamic, dynamic> raw)
      : this._internal(RatingStyle.values[raw['type']], raw['value']);
}

/// Metadata about an audio item that can be played, or a folder containing
/// audio items.
class MediaItem {
  /// A unique id.
  final String id;

  /// The album this media item belongs to.
  final String album;

  /// The title of this media item.
  final String title;

  /// The artist of this media item.
  final String artist;

  /// The genre of this media item.
  final String genre;

  /// The duration of this media item.
  final Duration duration;

  /// The artwork for this media item as a uri.
  final String artUri;

  /// Whether this is playable (i.e. not a folder).
  final bool playable;

  /// Override the default title for display purposes.
  final String displayTitle;

  /// Override the default subtitle for display purposes.
  final String displaySubtitle;

  /// Override the default description for display purposes.
  final String displayDescription;

  /// The rating of the MediaItem.
  final Rating rating;

  /// A map of additional metadata for the media item.
  ///
  /// The values must be integers or strings.
  final Map<String, dynamic> extras;

  /// Creates a [MediaItem].
  ///
  /// [id], [album] and [title] must not be null, and [id] must be unique for
  /// each instance.
  const MediaItem({
    @required this.id,
    @required this.album,
    @required this.title,
    this.artist,
    this.genre,
    this.duration,
    this.artUri,
    this.playable = true,
    this.displayTitle,
    this.displaySubtitle,
    this.displayDescription,
    this.rating,
    this.extras,
  });

  /// Creates a [MediaItem] from a map of key/value pairs corresponding to
  /// fields of this class.
  factory MediaItem.fromJson(Map raw) => MediaItem(
        id: raw['id'],
        album: raw['album'],
        title: raw['title'],
        artist: raw['artist'],
        genre: raw['genre'],
        duration: raw['duration'] != null
            ? Duration(milliseconds: raw['duration'])
            : null,
        artUri: raw['artUri'],
        playable: raw['playable'],
        displayTitle: raw['displayTitle'],
        displaySubtitle: raw['displaySubtitle'],
        displayDescription: raw['displayDescription'],
        rating: raw['rating'] != null ? Rating._fromRaw(raw['rating']) : null,
        extras: _raw2extras(raw['extras']),
      );

  /// Creates a copy of this [MediaItem] but with with the given fields
  /// replaced by new values.
  MediaItem copyWith({
    String id,
    String album,
    String title,
    String artist,
    String genre,
    Duration duration,
    String artUri,
    bool playable,
    String displayTitle,
    String displaySubtitle,
    String displayDescription,
    Rating rating,
    Map extras,
  }) =>
      MediaItem(
        id: id ?? this.id,
        album: album ?? this.album,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        genre: genre ?? this.genre,
        duration: duration ?? this.duration,
        artUri: artUri ?? this.artUri,
        playable: playable ?? this.playable,
        displayTitle: displayTitle ?? this.displayTitle,
        displaySubtitle: displaySubtitle ?? this.displaySubtitle,
        displayDescription: displayDescription ?? this.displayDescription,
        rating: rating ?? this.rating,
        extras: extras ?? this.extras,
      );

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(dynamic other) => other is MediaItem && other.id == id;

  @override
  String toString() => '${toJson()}';

  /// Converts this [MediaItem] to a map of key/value pairs corresponding to
  /// the fields of this class.
  Map<String, dynamic> toJson() => {
        'id': id,
        'album': album,
        'title': title,
        'artist': artist,
        'genre': genre,
        'duration': duration?.inMilliseconds,
        'artUri': artUri,
        'playable': playable,
        'displayTitle': displayTitle,
        'displaySubtitle': displaySubtitle,
        'displayDescription': displayDescription,
        'rating': rating?._toRaw(),
        'extras': extras,
      };

  static Map<String, dynamic> _raw2extras(Map raw) {
    if (raw == null) return null;
    final extras = <String, dynamic>{};
    for (var key in raw.keys) {
      extras[key as String] = raw[key];
    }
    return extras;
  }
}

/// A button to appear in the Android notification, lock screen, Android smart
/// watch, or Android Auto device. The set of buttons you would like to display
/// at any given moment should be set via [AudioServiceBackground.setState].
///
/// Each [MediaControl] button controls a specified [MediaAction]. Only the
/// following actions can be represented as buttons:
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
/// Predefined controls with default Android icons and labels are defined as
/// static fields of this class. If you wish to define your own custom Android
/// controls with your own icon resources, you will need to place the Android
/// resources in `android/app/src/main/res`. Here, you will find a subdirectory
/// for each different resolution:
///
/// ```
/// drawable-hdpi
/// drawable-mdpi
/// drawable-xhdpi
/// drawable-xxhdpi
/// drawable-xxxhdpi
/// ```
///
/// You can use [Android Asset
/// Studio](https://romannurik.github.io/AndroidAssetStudio/) to generate these
/// different subdirectories for any standard material design icon.
class MediaControl {
  /// A default control for [MediaAction.stop].
  static final stop = MediaControl(
    androidIcon: 'drawable/audio_service_stop',
    label: 'Stop',
    action: MediaAction.stop,
  );

  /// A default control for [MediaAction.pause].
  static final pause = MediaControl(
    androidIcon: 'drawable/audio_service_pause',
    label: 'Pause',
    action: MediaAction.pause,
  );

  /// A default control for [MediaAction.play].
  static final play = MediaControl(
    androidIcon: 'drawable/audio_service_play_arrow',
    label: 'Play',
    action: MediaAction.play,
  );

  /// A default control for [MediaAction.rewind].
  static final rewind = MediaControl(
    androidIcon: 'drawable/audio_service_fast_rewind',
    label: 'Rewind',
    action: MediaAction.rewind,
  );

  /// A default control for [MediaAction.skipToNext].
  static final skipToNext = MediaControl(
    androidIcon: 'drawable/audio_service_skip_next',
    label: 'Next',
    action: MediaAction.skipToNext,
  );

  /// A default control for [MediaAction.skipToPrevious].
  static final skipToPrevious = MediaControl(
    androidIcon: 'drawable/audio_service_skip_previous',
    label: 'Previous',
    action: MediaAction.skipToPrevious,
  );

  /// A default control for [MediaAction.fastForward].
  static final fastForward = MediaControl(
    androidIcon: 'drawable/audio_service_fast_forward',
    label: 'Fast Forward',
    action: MediaAction.fastForward,
  );

  /// A reference to an Android icon resource for the control (e.g.
  /// `"drawable/ic_action_pause"`)
  final String androidIcon;

  /// A label for the control
  final String label;

  /// The action to be executed by this control
  final MediaAction action;

  const MediaControl({
    @required this.androidIcon,
    @required this.label,
    @required this.action,
  });
}

const MethodChannel _channel =
    const MethodChannel('ryanheise.com/audioService');

const String _CUSTOM_PREFIX = 'custom_';

/// Client API to connect with and communciate with the background audio task.
///
/// You may use this API from your UI to send start/pause/play/stop/etc messages
/// to your background audio task, and to listen to state changes broadcast by
/// your background audio task. You may also use this API from other background
/// isolates (e.g. android_alarm_manager) to communicate with the background
/// audio task.
///
/// A client must [connect] to the service before it will be able to send
/// messages to the background audio task, and must [disconnect] when
/// communication is no longer required. In practice, a UI should maintain a
/// connection exactly while it is visible. It is strongly recommended that you
/// use [AudioServiceWidget] to manage this connection for you automatically.
class AudioService {
  /// True if the background task runs in its own isolate, false if it doesn't.
  static bool get usesIsolate => !(kIsWeb || Platform.isMacOS);

  /// The root media ID for browsing media provided by the background
  /// task.
  static const String MEDIA_ROOT_ID = "root";

  static final _browseMediaChildrenSubject = BehaviorSubject<List<MediaItem>>();

  /// A stream that broadcasts the children of the current browse
  /// media parent.
  static Stream<List<MediaItem>> get browseMediaChildrenStream =>
      _browseMediaChildrenSubject.stream;

  /// The children of the current browse media parent.
  static List<MediaItem> get browseMediaChildren =>
      _browseMediaChildrenSubject.value;

  static final _playbackStateSubject = BehaviorSubject<PlaybackState>();

  /// A stream that broadcasts the playback state.
  static Stream<PlaybackState> get playbackStateStream =>
      _playbackStateSubject.stream;

  /// The current playback state.
  static PlaybackState get playbackState => _playbackStateSubject.value;

  static final _currentMediaItemSubject = BehaviorSubject<MediaItem>();

  /// A stream that broadcasts the current [MediaItem].
  static Stream<MediaItem> get currentMediaItemStream =>
      _currentMediaItemSubject.stream;

  /// The current [MediaItem].
  static MediaItem get currentMediaItem => _currentMediaItemSubject.value;

  static final _queueSubject = BehaviorSubject<List<MediaItem>>();

  /// A stream that broadcasts the queue.
  static Stream<List<MediaItem>> get queueStream => _queueSubject.stream;

  /// The current queue.
  static List<MediaItem> get queue => _queueSubject.value;

  static final _notificationSubject = BehaviorSubject<bool>.seeded(false);

  /// A stream that broadcasts the status of the notificationClick event.
  static Stream<bool> get notificationClickEventStream =>
      _notificationSubject.stream;

  /// The status of the notificationClick event.
  static bool get notificationClickEvent => _notificationSubject.value;

  static final _customEventSubject = PublishSubject<dynamic>();

  /// A stream that broadcasts custom events sent from the background.
  static Stream<dynamic> get customEventStream => _customEventSubject.stream;

  /// If a seek is in progress, this holds the position we are seeking to.
  static Duration _seekPos;

  /// True after service stopped and !running.
  static bool _afterStop = false;

  /// Receives custom events from the background audio task.
  static ReceivePort _customEventReceivePort;
  static StreamSubscription _customEventSubscription;

  /// A queue of tasks to be processed serially. Tasks that are processed on
  /// this queue:
  ///
  /// - [connect]
  /// - [disconnect]
  /// - [start]
  ///
  /// TODO: Queue other tasks? Note, only short-running tasks should be queued.
  static final _asyncTaskQueue = _AsyncTaskQueue();

  static BehaviorSubject<Duration> _positionSubject;

  /// Connects to the service from your UI so that audio playback can be
  /// controlled.
  ///
  /// This method should be called when your UI becomes visible, and
  /// [disconnect] should be called when your UI is no longer visible. All
  /// other methods in this class will work only while connected.
  ///
  /// Use [AudioServiceWidget] to handle this automatically.
  static Future<void> connect() => _asyncTaskQueue.schedule(() async {
        if (_connected) return;
        _channel.setMethodCallHandler((MethodCall call) async {
          switch (call.method) {
            case 'onChildrenLoaded':
              final List<Map> args = List<Map>.from(call.arguments[0]);
              _browseMediaChildrenSubject
                  .add(args.map((raw) => MediaItem.fromJson(raw)).toList());
              break;
            case 'onPlaybackStateChanged':
              // If this event arrives too late, ignore it.
              if (_afterStop) return;
              final List args = call.arguments;
              int actionBits = args[2];
              _playbackStateSubject.add(PlaybackState(
                processingState: AudioProcessingState.values[args[0]],
                playing: args[1],
                actions: MediaAction.values
                    .where((action) => (actionBits & (1 << action.index)) != 0)
                    .toSet(),
                position: Duration(milliseconds: args[3]),
                bufferedPosition: Duration(milliseconds: args[4]),
                speed: args[5],
                updateTime: Duration(milliseconds: args[6]),
                repeatMode: AudioServiceRepeatMode.values[args[7]],
                shuffleMode: AudioServiceShuffleMode.values[args[8]],
              ));
              break;
            case 'onMediaChanged':
              _currentMediaItemSubject.add(call.arguments[0] != null
                  ? MediaItem.fromJson(call.arguments[0])
                  : null);
              break;
            case 'onQueueChanged':
              final List<Map> args = call.arguments[0] != null
                  ? List<Map>.from(call.arguments[0])
                  : null;
              _queueSubject
                  .add(args?.map((raw) => MediaItem.fromJson(raw))?.toList());
              break;
            case 'onStopped':
              _browseMediaChildrenSubject.add(null);
              _playbackStateSubject.add(null);
              _currentMediaItemSubject.add(null);
              _queueSubject.add(null);
              _notificationSubject.add(false);
              _runningSubject.add(false);
              _afterStop = true;
              break;
            case 'notificationClicked':
              _notificationSubject.add(call.arguments[0]);
              break;
          }
        });
        if (AudioService.usesIsolate) {
          _customEventReceivePort = ReceivePort();
          _customEventSubscription = _customEventReceivePort.listen((event) {
            _customEventSubject.add(event);
          });
          IsolateNameServer.removePortNameMapping(_CUSTOM_EVENT_PORT_NAME);
          IsolateNameServer.registerPortWithName(
              _customEventReceivePort.sendPort, _CUSTOM_EVENT_PORT_NAME);
        }
        await _channel.invokeMethod("connect");
        final running = await _channel.invokeMethod("isRunning");
        if (running != AudioService.running) {
          _runningSubject.add(running);
        }
        _connected = true;
      });

  /// Disconnects your UI from the service.
  ///
  /// This method should be called when the UI is no longer visible.
  ///
  /// Use [AudioServiceWidget] to handle this automatically.
  static Future<void> disconnect() => _asyncTaskQueue.schedule(() async {
        if (!_connected) return;
        _channel.setMethodCallHandler(null);
        _customEventSubscription?.cancel();
        _customEventSubscription = null;
        _customEventReceivePort = null;
        await _channel.invokeMethod("disconnect");
        _connected = false;
      });

  /// True if the UI is connected.
  static bool get connected => _connected;
  static bool _connected = false;

  static final _runningSubject = BehaviorSubject<bool>();

  /// A stream indicating when the [running] state changes.
  static get runningStream => _runningSubject.stream;

  /// True if the background audio task is running.
  static bool get running => _runningSubject.value;

  /// Starts a background audio task which will continue running even when the
  /// UI is not visible or the screen is turned off. Only one background audio task
  /// may be running at a time.
  ///
  /// While the background task is running, it will display a system
  /// notification showing information about the current media item being
  /// played (see [AudioServiceBackground.setMediaItem]) along with any media
  /// controls to perform any media actions that you want to support (see
  /// [AudioServiceBackground.setState]).
  ///
  /// The background task is specified by [backgroundTaskEntrypoint] which will
  /// be run within a background isolate. This function must be a top-level
  /// function, and it must initiate execution by calling
  /// [AudioServiceBackground.run]. Because the background task runs in an
  /// isolate, no memory is shared between the background isolate and your main
  /// UI isolate and so all communication between the background task and your
  /// UI is achieved through message passing.
  ///
  /// The [androidNotificationIcon] is specified like an XML resource reference
  /// and defaults to `"mipmap/ic_launcher"`.
  ///
  /// [androidShowNotificationBadge] enable notification badges (also known as notification dots)
  /// to appear on a launcher icon when the app has an active notification.
  ///
  /// If specified, [androidArtDownscaleSize] causes artwork to be downscaled
  /// to the given resolution in pixels before being displayed in the
  /// notification and lock screen. If not specified, no downscaling will be
  /// performed. If the resolution of your artwork is particularly high,
  /// downscaling can help to conserve memory.
  ///
  /// [params] provides a way to pass custom parameters through to the
  /// `onStart` method of your background audio task. If specified, this must
  /// be a map consisting of keys/values that can be encoded via Flutter's
  /// `StandardMessageCodec`.
  ///
  /// [fastForwardInterval] and [rewindInterval] are passed through to your
  /// background audio task as properties, and they represent the duration
  /// of audio that should be skipped in fast forward / rewind operations. On
  /// iOS, these values also configure the intervals for the skip forward and
  /// skip backward buttons.
  ///
  /// [androidEnableQueue] enables queue support on the media session on
  /// Android. If your app will run on Android and has a queue, you should set
  /// this to true.
  ///
  /// [androidStopForegroundOnPause] will switch the Android service to a lower
  /// priority state when playback is paused allowing the user to swipe away the
  /// notification. Note that while in this lower priority state, the operating
  /// system will also be able to kill your service at any time to reclaim
  /// resources.
  ///
  /// This method waits for [BackgroundAudioTask.onStart] to complete, and
  /// completes with true if the task was successfully started, or false
  /// otherwise.
  static Future<bool> start({
    @required Function backgroundTaskEntrypoint,
    Map<String, dynamic> params,
    String androidNotificationChannelName = "Notifications",
    String androidNotificationChannelDescription,
    String androidNotificationIcon = 'mipmap/ic_launcher',
    bool androidShowNotificationBadge = false,
    bool androidNotificationClickStartsActivity = true,
    bool androidNotificationOngoing = false,
    bool androidResumeOnClick = true,
    bool androidStopForegroundOnPause = false,
    bool androidEnableQueue = false,
    Size androidArtDownscaleSize,
    Duration fastForwardInterval = const Duration(seconds: 10),
    Duration rewindInterval = const Duration(seconds: 10),
  }) async {
    return await _asyncTaskQueue.schedule(() async {
      if (!_connected) throw Exception("Not connected");
      if (running) return false;
      _runningSubject.add(true);
      _afterStop = false;
      ui.CallbackHandle handle;
      if (AudioService.usesIsolate) {
        handle = ui.PluginUtilities.getCallbackHandle(backgroundTaskEntrypoint);
        if (handle == null) {
          return false;
        }
      }

      var callbackHandle = handle?.toRawHandle();
      if (kIsWeb) {
        // Platform throws runtime exceptions on web
      } else if (Platform.isIOS) {
        // NOTE: to maintain compatibility between the Android and iOS
        // implementations, we ensure that the iOS background task also runs in
        // an isolate. Currently, the standard Isolate API does not allow
        // isolates to invoke methods on method channels. That may be fixed in
        // the future, but until then, we use the flutter_isolate plugin which
        // creates a FlutterNativeView for us, similar to what the Android
        // implementation does.
        // TODO: remove dependency on flutter_isolate by either using the
        // FlutterNativeView API directly or by waiting until Flutter allows
        // regular isolates to use method channels.
        await FlutterIsolate.spawn(_iosIsolateEntrypoint, callbackHandle);
      }
      final success = await _channel.invokeMethod('start', {
        'callbackHandle': callbackHandle,
        'params': params,
        'androidNotificationChannelName': androidNotificationChannelName,
        'androidNotificationChannelDescription':
            androidNotificationChannelDescription,
        'androidNotificationIcon': androidNotificationIcon,
        'androidShowNotificationBadge': androidShowNotificationBadge,
        'androidNotificationClickStartsActivity':
            androidNotificationClickStartsActivity,
        'androidNotificationOngoing': androidNotificationOngoing,
        'androidResumeOnClick': androidResumeOnClick,
        'androidStopForegroundOnPause': androidStopForegroundOnPause,
        'androidEnableQueue': androidEnableQueue,
        'androidArtDownscaleSize': androidArtDownscaleSize != null
            ? {
                'width': androidArtDownscaleSize.width,
                'height': androidArtDownscaleSize.height
              }
            : null,
        'fastForwardInterval': fastForwardInterval.inMilliseconds,
        'rewindInterval': rewindInterval.inMilliseconds,
      });
      if (!success) {
        _runningSubject.add(false);
      }
      if (!AudioService.usesIsolate) backgroundTaskEntrypoint();
      return success;
    });
  }

  /// Sets the parent of the children that [browseMediaChildrenStream] broadcasts.
  /// If unspecified, the root parent will be used.
  static Future<void> setBrowseMediaParent(
      [String parentMediaId = MEDIA_ROOT_ID]) async {
    await _channel.invokeMethod('setBrowseMediaParent', parentMediaId);
  }

  /// Sends a request to your background audio task to add an item to the
  /// queue. This passes through to the `onAddQueueItem` method in your
  /// background audio task.
  static Future<void> addQueueItem(MediaItem mediaItem) async {
    await _channel.invokeMethod('addQueueItem', mediaItem.toJson());
  }

  /// Sends a request to your background audio task to add a item to the queue
  /// at a particular position. This passes through to the `onAddQueueItemAt`
  /// method in your background audio task.
  static Future<void> addQueueItemAt(MediaItem mediaItem, int index) async {
    await _channel.invokeMethod('addQueueItemAt', [mediaItem.toJson(), index]);
  }

  /// Sends a request to your background audio task to remove an item from the
  /// queue. This passes through to the `onRemoveQueueItem` method in your
  /// background audio task.
  static Future<void> removeQueueItem(MediaItem mediaItem) async {
    await _channel.invokeMethod('removeQueueItem', mediaItem.toJson());
  }

  /// A convenience method calls [addQueueItem] for each media item in the
  /// given list. Note that this will be inefficient if you are adding a lot
  /// of media items at once. If possible, you should use [updateQueue]
  /// instead.
  static Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    for (var mediaItem in mediaItems) {
      await addQueueItem(mediaItem);
    }
  }

  /// Sends a request to your background audio task to replace the queue with a
  /// new list of media items. This passes through to the `onUpdateQueue`
  /// method in your background audio task.
  static Future<void> updateQueue(List<MediaItem> queue) async {
    await _channel.invokeMethod(
        'updateQueue', queue.map((item) => item.toJson()).toList());
  }

  /// Sends a request to your background audio task to update the details of a
  /// media item. This passes through to the 'onUpdateMediaItem' method in your
  /// background audio task.
  static Future<void> updateMediaItem(MediaItem mediaItem) async {
    await _channel.invokeMethod('updateMediaItem', mediaItem.toJson());
  }

  /// Programmatically simulates a click of a media button on the headset.
  ///
  /// This passes through to `onClick` in the background audio task.
  static Future<void> click([MediaButton button = MediaButton.media]) async {
    await _channel.invokeMethod('click', button.index);
  }

  /// Sends a request to your background audio task to prepare for audio
  /// playback. This passes through to the `onPrepare` method in your
  /// background audio task.
  static Future<void> prepare() async {
    await _channel.invokeMethod('prepare');
  }

  /// Sends a request to your background audio task to prepare for playing a
  /// particular media item. This passes through to the `onPrepareFromMediaId`
  /// method in your background audio task.
  static Future<void> prepareFromMediaId(String mediaId) async {
    await _channel.invokeMethod('prepareFromMediaId', mediaId);
  }

  //static Future<void> prepareFromSearch(String query, Bundle extras) async {}
  //static Future<void> prepareFromUri(Uri uri, Bundle extras) async {}

  /// Sends a request to your background audio task to play the current media
  /// item. This passes through to 'onPlay' in your background audio task.
  static Future<void> play() async {
    await _channel.invokeMethod('play');
  }

  /// Sends a request to your background audio task to play a particular media
  /// item referenced by its media id. This passes through to the
  /// 'onPlayFromMediaId' method in your background audio task.
  static Future<void> playFromMediaId(String mediaId) async {
    await _channel.invokeMethod('playFromMediaId', mediaId);
  }

  /// Sends a request to your background audio task to play a particular media
  /// item. This passes through to the 'onPlayMediaItem' method in your
  /// background audio task.
  static Future<void> playMediaItem(MediaItem mediaItem) async {
    await _channel.invokeMethod('playMediaItem', mediaItem.toJson());
  }

  //static Future<void> playFromSearch(String query, Bundle extras) async {}
  //static Future<void> playFromUri(Uri uri, Bundle extras) async {}

  /// Sends a request to your background audio task to skip to a particular
  /// item in the queue. This passes through to the `onSkipToQueueItem` method
  /// in your background audio task.
  static Future<void> skipToQueueItem(String mediaId) async {
    await _channel.invokeMethod('skipToQueueItem', mediaId);
  }

  /// Sends a request to your background audio task to pause playback. This
  /// passes through to the `onPause` method in your background audio task.
  static Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  /// Sends a request to your background audio task to stop playback and shut
  /// down the task. This passes through to the `onStop` method in your
  /// background audio task.
  static Future<void> stop() async {
    await _channel.invokeMethod('stop');
  }

  /// Sends a request to your background audio task to seek to a particular
  /// position in the current media item. This passes through to the `onSeekTo`
  /// method in your background audio task.
  static Future<void> seekTo(Duration position) async {
    _seekPos = position;
    await _channel.invokeMethod('seekTo', position.inMilliseconds);
    _seekPos = null;
  }

  /// Sends a request to your background audio task to skip to the next item in
  /// the queue. This passes through to the `onSkipToNext` method in your
  /// background audio task.
  static Future<void> skipToNext() async {
    await _channel.invokeMethod('skipToNext');
  }

  /// Sends a request to your background audio task to skip to the previous
  /// item in the queue. This passes through to the `onSkipToPrevious` method
  /// in your background audio task.
  static Future<void> skipToPrevious() async {
    await _channel.invokeMethod('skipToPrevious');
  }

  /// Sends a request to your background audio task to fast forward by the
  /// interval passed into the [start] method. This passes through to the
  /// `onFastForward` method in your background audio task.
  static Future<void> fastForward() async {
    await _channel.invokeMethod('fastForward');
  }

  /// Sends a request to your background audio task to rewind by the interval
  /// passed into the [start] method. This passes through to the `onRewind`
  /// method in the background audio task.
  static Future<void> rewind() async {
    await _channel.invokeMethod('rewind');
  }

  //static Future<void> setCaptioningEnabled(boolean enabled) async {}

  /// Sends a request to your background audio task to set the repeat mode.
  /// This passes through to the `onSetRepeatMode` method in your background
  /// audio task.
  static Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _channel.invokeMethod('setRepeatMode', repeatMode.index);
  }

  /// Sends a request to your background audio task to set the shuffle mode.
  /// This passes through to the `onSetShuffleMode` method in your background
  /// audio task.
  static Future<void> setShuffleMode(
      AudioServiceShuffleMode shuffleMode) async {
    await _channel.invokeMethod('setShuffleMode', shuffleMode.index);
  }

  /// Sends a request to your background audio task to set a rating on the
  /// current media item. This passes through to the `onSetRating` method in
  /// your background audio task. The extras map must *only* contain primitive
  /// types!
  static Future<void> setRating(Rating rating,
      [Map<String, dynamic> extras]) async {
    await _channel.invokeMethod('setRating', {
      "rating": rating._toRaw(),
      "extras": extras,
    });
  }

  /// Sends a request to your background audio task to set the audio playback
  /// speed. This passes through to the `onSetSpeed` method in your background
  /// audio task.
  static Future<void> setSpeed(double speed) async {
    await _channel.invokeMethod('setSpeed', speed);
  }

  /// Sends a request to your background audio task to begin or end seeking
  /// backward. This method passes through to the `onSeekBackward` method in
  /// your background audio task.
  static Future<void> seekBackward(bool begin) async {
    await _channel.invokeMethod('seekBackward', begin);
  }

  /// Sends a request to your background audio task to begin or end seek
  /// forward. This method passes through to the `onSeekForward` method in your
  /// background audio task.
  static Future<void> seekForward(bool begin) async {
    await _channel.invokeMethod('seekForward', begin);
  }

  //static Future<void> sendCustomAction(PlaybackStateCompat.CustomAction customAction,
  //static Future<void> sendCustomAction(String action, Bundle args) async {}

  /// Sends a custom request to your background audio task. This passes through
  /// to the `onCustomAction` in your background audio task.
  ///
  /// This may be used for your own purposes. [arguments] can be any data that
  /// is encodable by `StandardMessageCodec`.
  static Future customAction(String name, [dynamic arguments]) async {
    return await _channel.invokeMethod('$_CUSTOM_PREFIX$name', arguments);
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
  static Stream<Duration> get positionStream {
    if (_positionSubject == null) {
      _positionSubject = BehaviorSubject<Duration>(sync: true);
      _positionSubject.addStream(createPositionStream(
          steps: 800,
          minPeriod: Duration(milliseconds: 16),
          maxPeriod: Duration(milliseconds: 200)));
    }
    return _positionSubject.stream;
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
    Duration last;
    // ignore: close_sinks
    StreamController<Duration> controller;
    StreamSubscription<MediaItem> mediaItemSubscription;
    StreamSubscription<PlaybackState> playbackStateSubscription;
    Timer currentTimer;
    Duration duration() => currentMediaItem?.duration ?? Duration.zero;
    Duration step() {
      var s = duration() ~/ steps;
      if (s < minPeriod) s = minPeriod;
      if (s > maxPeriod) s = maxPeriod;
      return s;
    }

    void yieldPosition(Timer timer) {
      if (last != (_seekPos ?? playbackState?.currentPosition)) {
        controller.add(last = (_seekPos ?? playbackState?.currentPosition));
      }
    }

    controller = StreamController.broadcast(
      sync: true,
      onListen: () {
        mediaItemSubscription = currentMediaItemStream.listen((mediaItem) {
          // Potentially a new duration
          currentTimer?.cancel();
          currentTimer = Timer.periodic(step(), yieldPosition);
        });
        playbackStateSubscription = playbackStateStream.listen((state) {
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
}

/// Background API to be used by your background audio task.
///
/// The entry point of your background task that you passed to
/// [AudioService.start] is executed in an isolate that will run independently
/// of the view. Aside from its primary job of playing audio, your background
/// task should also use methods of this class to initialise the isolate,
/// broadcast state changes to any UI that may be connected, and to also handle
/// playback actions initiated by the UI.
class AudioServiceBackground {
  static final PlaybackState _noneState = PlaybackState(
    processingState: AudioProcessingState.none,
    playing: false,
    actions: Set(),
  );
  static MethodChannel _backgroundChannel;
  static PlaybackState _state = _noneState;
  static MediaItem _mediaItem;
  static List<MediaItem> _queue;
  static BaseCacheManager _cacheManager;
  static BackgroundAudioTask _task;
  static bool _running = false;

  /// The current media playback state.
  ///
  /// This is the value most recently set via [setState].
  static PlaybackState get state => _state;

  /// The current media item.
  ///
  /// This is the value most recently set via [setMediaItem].
  static MediaItem get mediaItem => _mediaItem;

  /// The current queue.
  ///
  /// This is the value most recently set via [setQueue].
  static List<MediaItem> get queue => _queue;

  /// Runs the background audio task within the background isolate.
  ///
  /// This must be the first method called by the entrypoint of your background
  /// task that you passed into [AudioService.start]. The [BackgroundAudioTask]
  /// returned by the [taskBuilder] parameter defines callbacks to handle the
  /// initialization and distruction of the background audio task, as well as
  /// any requests by the client to play, pause and otherwise control audio
  /// playback.
  static Future<void> run(BackgroundAudioTask taskBuilder()) async {
    _running = true;
    _backgroundChannel =
        const MethodChannel('ryanheise.com/audioServiceBackground');
    WidgetsFlutterBinding.ensureInitialized();
    _task = taskBuilder();
    _cacheManager = _task.cacheManager;
    _backgroundChannel.setMethodCallHandler((MethodCall call) async {
      try {
        switch (call.method) {
          case 'onLoadChildren':
            final List args = call.arguments;
            String parentMediaId = args[0];
            List<MediaItem> mediaItems =
                await _task.onLoadChildren(parentMediaId);
            List<Map> rawMediaItems =
                mediaItems.map((item) => item.toJson()).toList();
            return rawMediaItems as dynamic;
          case 'onClick':
            final List args = call.arguments;
            MediaButton button = MediaButton.values[args[0]];
            await _task.onClick(button);
            break;
          case 'onStop':
            await _task.onStop();
            break;
          case 'onPause':
            await _task.onPause();
            break;
          case 'onPrepare':
            await _task.onPrepare();
            break;
          case 'onPrepareFromMediaId':
            final List args = call.arguments;
            String mediaId = args[0];
            await _task.onPrepareFromMediaId(mediaId);
            break;
          case 'onPlay':
            await _task.onPlay();
            break;
          case 'onPlayFromMediaId':
            final List args = call.arguments;
            String mediaId = args[0];
            await _task.onPlayFromMediaId(mediaId);
            break;
          case 'onPlayMediaItem':
            await _task.onPlayMediaItem(MediaItem.fromJson(call.arguments[0]));
            break;
          case 'onAddQueueItem':
            await _task.onAddQueueItem(MediaItem.fromJson(call.arguments[0]));
            break;
          case 'onAddQueueItemAt':
            final List args = call.arguments;
            MediaItem mediaItem = MediaItem.fromJson(args[0]);
            int index = args[1];
            await _task.onAddQueueItemAt(mediaItem, index);
            break;
          case 'onUpdateQueue':
            final List args = call.arguments;
            final List queue = args[0];
            await _task.onUpdateQueue(
                queue?.map((raw) => MediaItem.fromJson(raw))?.toList());
            break;
          case 'onUpdateMediaItem':
            await _task
                .onUpdateMediaItem(MediaItem.fromJson(call.arguments[0]));
            break;
          case 'onRemoveQueueItem':
            await _task
                .onRemoveQueueItem(MediaItem.fromJson(call.arguments[0]));
            break;
          case 'onSkipToNext':
            await _task.onSkipToNext();
            break;
          case 'onSkipToPrevious':
            await _task.onSkipToPrevious();
            break;
          case 'onFastForward':
            await _task.onFastForward();
            break;
          case 'onRewind':
            await _task.onRewind();
            break;
          case 'onSkipToQueueItem':
            final List args = call.arguments;
            String mediaId = args[0];
            await _task.onSkipToQueueItem(mediaId);
            break;
          case 'onSeekTo':
            final List args = call.arguments;
            int positionMs = args[0];
            Duration position = Duration(milliseconds: positionMs);
            await _task.onSeekTo(position);
            break;
          case 'onSetRepeatMode':
            final List args = call.arguments;
            await _task.onSetRepeatMode(AudioServiceRepeatMode.values[args[0]]);
            break;
          case 'onSetShuffleMode':
            final List args = call.arguments;
            await _task
                .onSetShuffleMode(AudioServiceShuffleMode.values[args[0]]);
            break;
          case 'onSetRating':
            await _task.onSetRating(
                Rating._fromRaw(call.arguments[0]), call.arguments[1]);
            break;
          case 'onSeekBackward':
            final List args = call.arguments;
            await _task.onSeekBackward(args[0]);
            break;
          case 'onSeekForward':
            final List args = call.arguments;
            await _task.onSeekForward(args[0]);
            break;
          case 'onSetSpeed':
            final List args = call.arguments;
            double speed = args[0];
            await _task.onSetSpeed(speed);
            break;
          case 'onTaskRemoved':
            await _task.onTaskRemoved();
            break;
          case 'onClose':
            await _task.onClose();
            break;
          default:
            if (call.method.startsWith(_CUSTOM_PREFIX)) {
              final result = await _task.onCustomAction(
                  call.method.substring(_CUSTOM_PREFIX.length), call.arguments);
              return result;
            }
            break;
        }
      } catch (e, stacktrace) {
        print('$stacktrace');
        throw PlatformException(code: '$e');
      }
    });
    Map startParams = await _backgroundChannel.invokeMethod('ready');
    Duration fastForwardInterval =
        Duration(milliseconds: startParams['fastForwardInterval']);
    Duration rewindInterval =
        Duration(milliseconds: startParams['rewindInterval']);
    Map<String, dynamic> params =
        startParams['params']?.cast<String, dynamic>();
    _task._setParams(
      fastForwardInterval: fastForwardInterval,
      rewindInterval: rewindInterval,
    );
    try {
      await _task.onStart(params);
    } catch (e) {} finally {
      // For now, we return successfully from AudioService.start regardless of
      // whether an exception occurred in onStart.
      await _backgroundChannel.invokeMethod('started');
    }
  }

  /// Shuts down the background audio task within the background isolate.
  static Future<void> _shutdown() async {
    if (!_running) return;
    // Set this to false immediately so that if duplicate shutdown requests come
    // through, they are ignored.
    _running = false;
    final audioSession = await AudioSession.instance;
    try {
      await audioSession.setActive(false);
    } catch (e) {
      print("While deactivating audio session: $e");
    }
    await _backgroundChannel.invokeMethod('stopped');
    if (kIsWeb) {
    } else if (Platform.isIOS) {
      FlutterIsolate.current?.kill();
    }
    _backgroundChannel.setMethodCallHandler(null);
    _state = _noneState;
  }

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
    @required List<MediaControl> controls,
    List<MediaAction> systemActions = const [],
    @required AudioProcessingState processingState,
    @required bool playing,
    Duration position = Duration.zero,
    Duration bufferedPosition = Duration.zero,
    double speed = 1.0,
    Duration updateTime,
    List<int> androidCompactActions,
    AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none,
    AudioServiceShuffleMode shuffleMode = AudioServiceShuffleMode.none,
  }) async {
    _state = PlaybackState(
      processingState: processingState,
      playing: playing,
      actions: controls.map((control) => control.action).toSet(),
      position: position,
      bufferedPosition: bufferedPosition,
      speed: speed,
      updateTime: updateTime,
      repeatMode: repeatMode,
      shuffleMode: shuffleMode,
    );
    List<Map> rawControls = controls
        .map((control) => {
              'androidIcon': control.androidIcon,
              'label': control.label,
              'action': control.action.index,
            })
        .toList();
    final rawSystemActions =
        systemActions.map((action) => action.index).toList();
    await _backgroundChannel.invokeMethod('setState', [
      rawControls,
      rawSystemActions,
      processingState?.index ?? AudioProcessingState.none.index,
      playing ?? false,
      position?.inMilliseconds ?? 0,
      bufferedPosition?.inMilliseconds ?? 0,
      speed ?? 1.0,
      updateTime?.inMilliseconds,
      androidCompactActions,
      repeatMode?.index ?? AudioServiceRepeatMode.none.index,
      shuffleMode?.index ?? AudioServiceShuffleMode.none.index,
    ]);
  }

  /// Sets the current queue and notifies all clients.
  static Future<void> setQueue(List<MediaItem> queue,
      {bool preloadArtwork = false}) async {
    _queue = queue;
    if (preloadArtwork) {
      _loadAllArtwork(queue);
    }
    await _backgroundChannel.invokeMethod(
        'setQueue', queue.map((item) => item.toJson()).toList());
  }

  /// Sets the currently playing media item and notifies all clients.
  ///
  /// [color] is the dominant color of the media item.
  /// It is used in the service notification on supported platforms, and may be
  /// left unset to let the system choose its own color.
  static Future<void> setMediaItem(MediaItem mediaItem, [Color color]) async {
    _mediaItem = mediaItem;
    if (mediaItem.artUri != null) {
      // We potentially need to fetch the art.
      String filePath = _getLocalPath(mediaItem.artUri);
      if (filePath == null) {
        final fileInfo = _cacheManager.getFileFromMemory(mediaItem.artUri);
        filePath = fileInfo?.file?.path;
        if (filePath == null) {
          // We haven't fetched the art yet, so show the metadata now, and again
          // after we load the art.
          await _backgroundChannel
              .invokeMethod('setMediaItem', [mediaItem.toJson(), color?.value]);
          // Load the art
          filePath = await _loadArtwork(mediaItem);
          // If we failed to download the art, abort.
          if (filePath == null) return;
          // If we've already set a new media item, cancel this request.
          if (mediaItem != _mediaItem) return;
        }
      }
      final extras = Map.of(mediaItem.extras ?? <String, dynamic>{});
      extras['artCacheFile'] = filePath;
      final platformMediaItem = mediaItem.copyWith(extras: extras);
      // Show the media item after the art is loaded.
      await _backgroundChannel.invokeMethod(
          'setMediaItem', [platformMediaItem.toJson(), color?.value]);
    } else {
      await _backgroundChannel
          .invokeMethod('setMediaItem', [mediaItem.toJson(), color?.value]);
    }
  }

  static Future<void> _loadAllArtwork(List<MediaItem> queue) async {
    for (var mediaItem in queue) {
      await _loadArtwork(mediaItem);
    }
  }

  static Future<String> _loadArtwork(MediaItem mediaItem) async {
    try {
      final artUri = mediaItem.artUri;
      if (artUri != null) {
        String local = _getLocalPath(artUri);
        if (local != null) {
          return local;
        } else {
          final file = await _cacheManager.getSingleFile(mediaItem.artUri);
          return file.path;
        }
      }
    } catch (e) {}
    return null;
  }

  static String _getLocalPath(String artUri) {
    const prefix = "file://";
    if (artUri.toLowerCase().startsWith(prefix)) {
      return artUri.substring(prefix.length);
    }
    return null;
  }

  /// Notifies clients that the child media items of [parentMediaId] have
  /// changed.
  ///
  /// If [parentMediaId] is unspecified, the root parent will be used.
  static Future<void> notifyChildrenChanged(
      [String parentMediaId = AudioService.MEDIA_ROOT_ID]) async {
    await _backgroundChannel.invokeMethod(
        'notifyChildrenChanged', parentMediaId);
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
    await _backgroundChannel.invokeMethod('androidForceEnableMediaButtons');
  }

  /// Sends a custom event to the Flutter UI.
  ///
  /// The event parameter can contain any data permitted by Dart's
  /// SendPort/ReceivePort API. Please consult the relevant documentation for
  /// further information.
  static void sendCustomEvent(dynamic event) {
    if (!AudioService.usesIsolate) {
      AudioService._customEventSubject.add(event);
    } else {
      SendPort sendPort =
          IsolateNameServer.lookupPortByName(_CUSTOM_EVENT_PORT_NAME);
      sendPort?.send(event);
    }
  }
}

/// An audio task that can run in the background and react to audio events.
///
/// You should subclass [BackgroundAudioTask] and override the callbacks for
/// each type of event that your background task wishes to react to. At a
/// minimum, you must override [onStart] and [onStop] to handle initialising
/// and shutting down the audio task.
abstract class BackgroundAudioTask {
  final BaseCacheManager cacheManager;
  Duration _fastForwardInterval;
  Duration _rewindInterval;

  /// Subclasses may supply a [cacheManager] to manage the loading of artwork,
  /// or an instance of [DefaultCacheManager] will be used by default.
  BackgroundAudioTask({BaseCacheManager cacheManager})
      : this.cacheManager = cacheManager ?? DefaultCacheManager();

  /// The fast forward interval passed into [AudioService.start].
  Duration get fastForwardInterval => _fastForwardInterval;

  /// The rewind interval passed into [AudioService.start].
  Duration get rewindInterval => _rewindInterval;

  /// Called once when this audio task is first started and ready to play
  /// audio, in response to [AudioService.start]. [params] will contain any
  /// params passed into [AudioService.start] when starting this background
  /// audio task.
  Future<void> onStart(Map<String, dynamic> params) async {}

  /// Called when a client has requested to terminate this background audio
  /// task, in response to [AudioService.stop]. You should implement this
  /// method to stop playing audio and dispose of any resources used.
  ///
  /// If you override this, make sure your method ends with a call to `await
  /// super.onStop()`. The isolate containing this task will shut down as soon
  /// as this method completes.
  @mustCallSuper
  Future<void> onStop() async {
    await AudioServiceBackground._shutdown();
  }

  /// Called when a media browser client, such as Android Auto, wants to query
  /// the available media items to display to the user.
  Future<List<MediaItem>> onLoadChildren(String parentMediaId) async => [];

  /// Called when the media button on the headset is pressed, or in response to
  /// a call from [AudioService.click]. The default behaviour is:
  ///
  /// * On [MediaButton.media], toggle [onPlay] and [onPause].
  /// * On [MediaButton.next], call [onSkipToNext].
  /// * On [MediaButton.previous], call [onSkipToPrevious].
  Future<void> onClick(MediaButton button) async {
    switch (button) {
      case MediaButton.media:
        if (AudioServiceBackground.state?.playing == true) {
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

  /// Called when a client has requested to pause audio playback, such as via a
  /// call to [AudioService.pause]. You should implement this method to pause
  /// audio playback and also broadcast the appropriate state change via
  /// [AudioServiceBackground.setState].
  Future<void> onPause() async {}

  /// Called when a client has requested to prepare audio for playback, such as
  /// via a call to [AudioService.prepare].
  Future<void> onPrepare() async {}

  /// Called when a client has requested to prepare a specific media item for
  /// audio playback, such as via a call to [AudioService.prepareFromMediaId].
  Future<void> onPrepareFromMediaId(String mediaId) async {}

  /// Called when a client has requested to resume audio playback, such as via
  /// a call to [AudioService.play]. You should implement this method to play
  /// audio and also broadcast the appropriate state change via
  /// [AudioServiceBackground.setState].
  Future<void> onPlay() async {}

  /// Called when a client has requested to play a media item by its ID, such
  /// as via a call to [AudioService.playFromMediaId]. You should implement
  /// this method to play audio and also broadcast the appropriate state change
  /// via [AudioServiceBackground.setState].
  Future<void> onPlayFromMediaId(String mediaId) async {}

  /// Called when the Flutter UI has requested to play a given media item via a
  /// call to [AudioService.playMediaItem]. You should implement this method to
  /// play audio and also broadcast the appropriate state change via
  /// [AudioServiceBackground.setState].
  ///
  /// Note: This method can only be triggered by your Flutter UI. Peripheral
  /// devices such as Android Auto will instead trigger
  /// [AudioService.onPlayFromMediaId].
  Future<void> onPlayMediaItem(MediaItem mediaItem) async {}

  /// Called when a client has requested to add a media item to the queue, such
  /// as via a call to [AudioService.addQueueItem].
  Future<void> onAddQueueItem(MediaItem mediaItem) async {}

  /// Called when the Flutter UI has requested to set a new queue.
  ///
  /// If you use a queue, your implementation of this method should call
  /// [AudioServiceBackground.setQueue] to notify all clients that the queue
  /// has changed.
  Future<void> onUpdateQueue(List<MediaItem> queue) async {}

  /// Called when the Flutter UI has requested to update the details of
  /// a media item.
  Future<void> onUpdateMediaItem(MediaItem mediaItem) async {}

  /// Called when a client has requested to add a media item to the queue at a
  /// specified position, such as via a request to
  /// [AudioService.addQueueItemAt].
  Future<void> onAddQueueItemAt(MediaItem mediaItem, int index) async {}

  /// Called when a client has requested to remove a media item from the queue,
  /// such as via a request to [AudioService.removeQueueItem].
  Future<void> onRemoveQueueItem(MediaItem mediaItem) async {}

  /// Called when a client has requested to skip to the next item in the queue,
  /// such as via a request to [AudioService.skipToNext].
  ///
  /// By default, calls [onSkipToQueueItem] with the queue item after
  /// [AudioServiceBackground.mediaItem] if it exists.
  Future<void> onSkipToNext() => _skip(1);

  /// Called when a client has requested to skip to the previous item in the
  /// queue, such as via a request to [AudioService.skipToPrevious].
  ///
  /// By default, calls [onSkipToQueueItem] with the queue item before
  /// [AudioServiceBackground.mediaItem] if it exists.
  Future<void> onSkipToPrevious() => _skip(-1);

  /// Called when a client has requested to fast forward, such as via a
  /// request to [AudioService.fastForward]. An implementation of this callback
  /// can use the [fastForwardInterval] property to determine how much audio
  /// to skip.
  Future<void> onFastForward() async {}

  /// Called when a client has requested to rewind, such as via a request to
  /// [AudioService.rewind]. An implementation of this callback can use the
  /// [rewindInterval] property to determine how much audio to skip.
  Future<void> onRewind() async {}

  /// Called when a client has requested to skip to a specific item in the
  /// queue, such as via a call to [AudioService.skipToQueueItem].
  Future<void> onSkipToQueueItem(String mediaId) async {}

  /// Called when a client has requested to seek to a position, such as via a
  /// call to [AudioService.seekTo]. If your implementation of seeking causes
  /// buffering to occur, consider broadcasting a buffering state via
  /// [AudioServiceBackground.setState] while the seek is in progress.
  Future<void> onSeekTo(Duration position) async {}

  /// Called when a client has requested to rate the current media item, such as
  /// via a call to [AudioService.setRating].
  Future<void> onSetRating(Rating rating, Map<dynamic, dynamic> extras) async {}

  /// Called when a client has requested to change the current repeat mode.
  Future<void> onSetRepeatMode(AudioServiceRepeatMode repeatMode) async {}

  /// Called when a client has requested to change the current shuffle mode.
  Future<void> onSetShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  /// Called when a client has requested to either begin or end seeking
  /// backward.
  Future<void> onSeekBackward(bool begin) async {}

  /// Called when a client has requested to either begin or end seeking
  /// forward.
  Future<void> onSeekForward(bool begin) async {}

  /// Called when the Flutter UI has requested to set the speed of audio
  /// playback. An implementation of this callback should change the audio
  /// speed and broadcast the speed change to all clients via
  /// [AudioServiceBackground.setState].
  Future<void> onSetSpeed(double speed) async {}

  /// Called when a custom action has been sent by the client via
  /// [AudioService.customAction]. The result of this method will be returned
  /// to the client.
  Future<dynamic> onCustomAction(String name, dynamic arguments) async {}

  /// Called on Android when the user swipes away your app's task in the task
  /// manager. Note that if you use the `androidStopForegroundOnPause` option to
  /// [AudioService.start], then when your audio is paused, the operating
  /// system moves your service to a lower priority level where it can be
  /// destroyed at any time to reclaim memory. If the user swipes away your
  /// task under these conditions, the operating system will destroy your
  /// service, and you may override this method to do any cleanup. For example:
  ///
  /// ```dart
  /// void onTaskRemoved() {
  ///   if (!AudioServiceBackground.state.playing) {
  ///     onStop();
  ///   }
  /// }
  /// ```
  Future<void> onTaskRemoved() async {}

  /// Called on Android when the user swipes away the notification. The default
  /// implementation (which you may override) calls [onStop]. Note that by
  /// default, the service runs in the foreground state which (despite the name)
  /// allows the service to run at a high priority in the background without the
  /// operating system killing it. While in the foreground state, the
  /// notification cannot be swiped away. You can pass a parameter value of
  /// `true` for `androidStopForegroundOnPause` in the [AudioService.start]
  /// method if you would like the service to exit the foreground state when
  /// playback is paused. This will allow the user to swipe the notification
  /// away while playback is paused (but it will also allow the operating system
  /// to kill your service at any time to free up resources).
  Future<void> onClose() => onStop();

  void _setParams({
    Duration fastForwardInterval,
    Duration rewindInterval,
  }) {
    _fastForwardInterval = fastForwardInterval;
    _rewindInterval = rewindInterval;
  }

  Future<void> _skip(int offset) async {
    final mediaItem = AudioServiceBackground.mediaItem;
    if (mediaItem == null) return;
    final queue = AudioServiceBackground.queue ?? [];
    int i = queue.indexOf(mediaItem);
    if (i == -1) return;
    int newIndex = i + offset;
    if (newIndex >= 0 && newIndex < queue.length)
      await onSkipToQueueItem(queue[newIndex]?.id);
  }
}

_iosIsolateEntrypoint(int rawHandle) async {
  ui.CallbackHandle handle = ui.CallbackHandle.fromRawHandle(rawHandle);
  Function backgroundTask = ui.PluginUtilities.getCallbackFromHandle(handle);
  backgroundTask();
}

/// A widget that maintains a connection to [AudioService].
///
/// Insert this widget at the top of your `/` route's widget tree to maintain
/// the connection across all routes. e.g.
///
/// ```
/// return MaterialApp(
///   home: AudioServiceWidget(MainScreen()),
/// );
/// ```
///
/// Note that this widget will not work if it wraps around [MateriaApp] itself,
/// you must place it in the widget tree within your route.
class AudioServiceWidget extends StatefulWidget {
  final Widget child;

  AudioServiceWidget({@required this.child});

  @override
  _AudioServiceWidgetState createState() => _AudioServiceWidgetState();
}

class _AudioServiceWidgetState extends State<AudioServiceWidget>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AudioService.connect();
  }

  @override
  void dispose() {
    AudioService.disconnect();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        AudioService.connect();
        break;
      case AppLifecycleState.paused:
        AudioService.disconnect();
        break;
      default:
        break;
    }
  }

  @override
  Future<bool> didPopRoute() async {
    AudioService.disconnect();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

enum AudioServiceShuffleMode { none, all, group }

enum AudioServiceRepeatMode { none, one, all, group }

class _AsyncTaskQueue {
  final _queuedAsyncTaskController = StreamController<_AsyncTaskQueueEntry>();

  _AsyncTaskQueue() {
    _process();
  }

  Future<void> _process() async {
    await for (var entry in _queuedAsyncTaskController.stream) {
      try {
        final result = await entry.asyncTask();
        entry.completer.complete(result);
      } catch (e, stacktrace) {
        entry.completer.completeError(e, stacktrace);
      }
    }
  }

  Future<dynamic> schedule(_AsyncTask asyncTask) async {
    final completer = Completer<dynamic>();
    _queuedAsyncTaskController.add(_AsyncTaskQueueEntry(asyncTask, completer));
    return completer.future;
  }
}

class _AsyncTaskQueueEntry {
  final _AsyncTask asyncTask;
  final Completer completer;

  _AsyncTaskQueueEntry(this.asyncTask, this.completer);
}

typedef _AsyncTask = Future<dynamic> Function();
