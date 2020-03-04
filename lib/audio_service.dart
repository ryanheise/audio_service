import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:rxdart/rxdart.dart';

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
}

/// The different states during audio playback.
enum BasicPlaybackState {
  none,
  stopped,
  paused,
  playing,
  fastForwarding,
  rewinding,
  buffering,
  error,
  connecting,
  skippingToPrevious,
  skippingToNext,
  skippingToQueueItem,
}

/// The playback state for the audio service which includes a basic state such
/// as [BasicPlaybackState.paused], the playback position and the currently
/// supported actions.
class PlaybackState {
  /// The basic state e.g. [BasicPlaybackState.paused]
  final BasicPlaybackState basicState;

  /// The set of actions currently supported by the audio service e.g.
  /// [MediaAction.play]
  final Set<MediaAction> actions;

  /// The playback position in milliseconds at the last update time
  final int position;

  /// The current playback speed where 1.0 means normal speed
  final double speed;

  /// The time at which the playback position was last updated
  final int updateTime;

  const PlaybackState({
    @required this.basicState,
    @required this.actions,
    this.position,
    this.speed,
    this.updateTime,
  });

  /// The current playback position in milliseconds
  int get currentPosition {
    if (basicState == BasicPlaybackState.playing) {
      return (position +
              ((DateTime.now().millisecondsSinceEpoch - updateTime) *
                  (speed ?? 1.0)))
          .toInt();
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
  /// A unique id
  final String id;

  /// The album this media item belongs to
  final String album;

  /// The title of this media item
  String title;

  /// The artist of this media item
  final String artist;

  /// The genre of this media item
  final String genre;

  /// The duration in milliseconds
  int duration;

  /// The artwork for this media item as a uri
  String artUri;

  /// Whether this is playable (i.e. not a folder)
  final bool playable;

  /// Override the default title for display purposes
  final String displayTitle;

  /// Override the default subtitle for display purposes
  final String displaySubtitle;

  /// Override the default description for display purposes
  final String displayDescription;

  /// The rating of the MediaItem.
  final Rating rating;

  MediaItem({
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
  });

  MediaItem copyWith({
    String id,
    String album,
    String title,
    String artist,
    String genre,
    int duration,
    String artUri,
    bool playable,
    String displayTitle,
    String displaySubtitle,
    String displayDescription,
    Rating rating,
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
      );

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(dynamic other) => other is MediaItem && other.id == id;
}

/// A media action that can be controlled by a client.
///
/// The set of media controls available at any moment depends on the current
/// playback state as set by [AudioServiceBackground.setState]. For example, a
/// "pause" control should be available in the [BasicPlaybackState.playing]
/// state but not in the [BasicPlaybackState.paused] state.
///
/// A button for each media control will be shown in your app's notification,
/// Wear OS and Android Auto devices.
class MediaControl {
  /// A reference to an Android icon resource for the control (e.g.
  /// `"drawable/ic_action_pause"`)
  final String androidIcon;

  /// A label for the control
  final String label;

  /// The action to be executed by this control
  final MediaAction action;

  const MediaControl({
    this.androidIcon,
    @required this.label,
    @required this.action,
  });
}

const MethodChannel _channel =
    const MethodChannel('ryanheise.com/audioService');

Map _mediaItem2raw(MediaItem mediaItem) => {
      'id': mediaItem.id,
      'album': mediaItem.album,
      'title': mediaItem.title,
      'artist': mediaItem.artist,
      'genre': mediaItem.genre,
      'duration': mediaItem.duration,
      'artUri': mediaItem.artUri,
      'playable': mediaItem.playable,
      'displayTitle': mediaItem.displayTitle,
      'displaySubtitle': mediaItem.displaySubtitle,
      'displayDescription': mediaItem.displayDescription,
      'rating': mediaItem.rating?._toRaw(),
    };

MediaItem _raw2mediaItem(Map raw) => MediaItem(
      id: raw['id'],
      album: raw['album'],
      title: raw['title'],
      artist: raw['artist'],
      genre: raw['genre'],
      duration: raw['duration'],
      artUri: raw['artUri'],
      displayTitle: raw['displayTitle'],
      displaySubtitle: raw['displaySubtitle'],
      displayDescription: raw['displayDescription'],
      rating: raw['rating'] != null ? Rating._fromRaw(raw['rating']) : null,
    );

const String _CUSTOM_PREFIX = 'custom_';

/// Client API to start and interact with the audio service.
///
/// This class is used from your UI code to establish a connection with the
/// audio service. While connected to the service, your UI may invoke methods
/// of this class to start/pause/stop/etc. playback and listen to changes in
/// playback state and playing media.
///
/// Your UI must disconnect from the audio service when it is no longer visible
/// although the audio service will continue to run in the background. If your
/// UI once again becomes visible, you should reconnect to the audio service.
class AudioService {
  /// The root media ID for browsing media provided by the background
  /// task.
  static const String MEDIA_ROOT_ID = "root";

  static final _browseMediaChildrenSubject = BehaviorSubject<List<MediaItem>>();

  /// An instance of flutter isolate
  static FlutterIsolate _flutterIsolate;

  /// A stream that broadcasts the children of the current browse
  /// media parent.
  static Stream<List<MediaItem>> get browseMediaChildrenStream =>
      _browseMediaChildrenSubject.stream;

  static final _playbackStateSubject = BehaviorSubject<PlaybackState>();

  /// A stream that broadcasts the playback state.
  static Stream<PlaybackState> get playbackStateStream =>
      _playbackStateSubject.stream;

  static final _currentMediaItemSubject = BehaviorSubject<MediaItem>();

  /// A stream that broadcasts the current [MediaItem].
  static Stream<MediaItem> get currentMediaItemStream =>
      _currentMediaItemSubject.stream;

  static final _queueSubject = BehaviorSubject<List<MediaItem>>();

  /// A stream that broadcasts the queue.
  static Stream<List<MediaItem>> get queueStream => _queueSubject.stream;

  /// The children of the current browse media parent.
  static List<MediaItem> get browseMediaChildren => _browseMediaChildren;
  static List<MediaItem> _browseMediaChildren;

  /// The current playback state.
  static PlaybackState get playbackState => _playbackState;
  static PlaybackState _playbackState;

  /// The current media item.
  static MediaItem get currentMediaItem => _currentMediaItem;
  static MediaItem _currentMediaItem;

  /// The current queue.
  static List<MediaItem> get queue => _queue;
  static List<MediaItem> _queue;

  /// Connects to the service from your UI so that audio playback can be
  /// controlled.
  ///
  /// This method should be called when your UI becomes visible, and
  /// [disconnect] should be called when your UI is no longer visible. All
  /// other methods in this class will work only while connected.
  static Future<void> connect() async {
    _channel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'onChildrenLoaded':
          final List<Map> args = List<Map>.from(call.arguments[0]);
          _browseMediaChildren = args.map(_raw2mediaItem).toList();
          _browseMediaChildrenSubject.add(_browseMediaChildren);
          break;
        case 'onPlaybackStateChanged':
          final List args = call.arguments;
          int actionBits = args[1];
          _playbackState = PlaybackState(
            basicState: BasicPlaybackState.values[args[0]],
            actions: MediaAction.values
                .where((action) => (actionBits & (1 << action.index)) != 0)
                .toSet(),
            position: args[2],
            speed: args[3],
            updateTime: args[4],
          );
          _playbackStateSubject.add(_playbackState);
          break;
        case 'onMediaChanged':
          _currentMediaItem = call.arguments[0] != null
              ? _raw2mediaItem(call.arguments[0])
              : null;
          _currentMediaItemSubject.add(_currentMediaItem);
          break;
        case 'onQueueChanged':
          final List<Map> args = call.arguments[0] != null
              ? List<Map>.from(call.arguments[0])
              : null;
          _queue = args?.map(_raw2mediaItem)?.toList();
          _queueSubject.add(_queue);
          break;
        case 'onStopped':
          _browseMediaChildren = null;
          _browseMediaChildrenSubject.add(null);
          _playbackState = null;
          _playbackStateSubject.add(null);
          _currentMediaItem = null;
          _currentMediaItemSubject.add(null);
          _queue = null;
          _queueSubject.add(null);
          break;
      }
    });
    await _channel.invokeMethod("connect");
    _connected = true;
  }

  /// Disconnects your UI from the service.
  ///
  /// This method should be called when the UI is no longer visible.
  static Future<void> disconnect() async {
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod("disconnect");
    _connected = false;
  }

  /// True if the UI is connected.
  static bool get connected => _connected;
  static bool _connected = false;

  /// True if the background audio task is running.
  static Future<bool> get running async {
    return await _channel.invokeMethod("isRunning");
  }

  /// Starts a background audio task which will continue running even when the
  /// UI is not visible or the screen is turned off.
  ///
  /// While the background task is running, it will display a system
  /// notification showing information about the current media item being
  /// played (see [AudioServiceBackground.setMediaItem]) along with any media
  /// controls to perform any media actions that you want to support (see
  /// [AudioServiceBackground.setState]).
  ///
  /// The background task is specified by [backgroundTaskEntrypoint] which will
  /// be run within a background isolate. This function must be a top-level or
  /// static function, and it must initiate execution by calling
  /// [AudioServiceBackground.run]. Because the background task runs in an
  /// isolate, no memory is shared between the background isolate and your main
  /// UI isolate and so all communication between the background task and your
  /// UI is achieved through message passing.
  ///
  /// The [androidNotificationIcon] is specified like an XML resource reference
  /// and defaults to `"mipmap/ic_launcher"`.
  static Future<bool> start({
    @required Function backgroundTaskEntrypoint,
    String androidNotificationChannelName = "Notifications",
    String androidNotificationChannelDescription,
    int notificationColor,
    String androidNotificationIcon = 'mipmap/ic_launcher',
    bool androidNotificationClickStartsActivity = true,
    bool androidNotificationOngoing = false,
    bool resumeOnClick = true,
    bool shouldPreloadArtwork = false,
    bool androidStopForegroundOnPause = false,
    bool enableQueue = false,
    bool androidStopOnRemoveTask = false,
  }) async {
    final ui.CallbackHandle handle =
        ui.PluginUtilities.getCallbackHandle(backgroundTaskEntrypoint);
    if (handle == null) {
      return false;
    }
    var callbackHandle = handle.toRawHandle();
    if (Platform.isIOS) {
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
      AudioService._flutterIsolate = await FlutterIsolate.spawn(_iosIsolateEntrypoint, callbackHandle);
    }
    return await _channel.invokeMethod('start', {
      'callbackHandle': callbackHandle,
      'androidNotificationChannelName': androidNotificationChannelName,
      'androidNotificationChannelDescription':
          androidNotificationChannelDescription,
      'notificationColor': notificationColor,
      'androidNotificationIcon': androidNotificationIcon,
      'androidNotificationClickStartsActivity':
          androidNotificationClickStartsActivity,
      'androidNotificationOngoing': androidNotificationOngoing,
      'resumeOnClick': resumeOnClick,
      'shouldPreloadArtwork': shouldPreloadArtwork,
      'androidStopForegroundOnPause': androidStopForegroundOnPause,
      'enableQueue': enableQueue,
      'androidStopOnRemoveTask': androidStopOnRemoveTask,
    });
  }

  /// Sets the parent of the children that [browseMediaChildrenStream] broadcasts.
  /// If unspecified, the root parent will be used.
  static Future<void> setBrowseMediaParent(
      [String parentMediaId = MEDIA_ROOT_ID]) async {
    await _channel.invokeMethod('setBrowseMediaParent', parentMediaId);
  }

  /// Passes through to `onAddQueueItem` in the background task.
  static Future<void> addQueueItem(MediaItem mediaItem) async {
    await _channel.invokeMethod('addQueueItem', _mediaItem2raw(mediaItem));
  }

  /// Passes through to `onAddQueueItemAt` in the background task.
  static Future<void> addQueueItemAt(MediaItem mediaItem, int index) async {
    await _channel
        .invokeMethod('addQueueItemAt', [_mediaItem2raw(mediaItem), index]);
  }

  /// Passes through to `onRemoveQueueItem` in the background task.
  static Future<void> removeQueueItem(MediaItem mediaItem) async {
    await _channel.invokeMethod('removeQueueItem', _mediaItem2raw(mediaItem));
  }

  /// Programmatically simulates a click of a media button on the headset.
  ///
  /// This passes through to `onClick` in the background task.
  static Future<void> click([MediaButton button = MediaButton.media]) async {
    await _channel.invokeMethod('click', button.index);
  }

  /// Passes through to `onPrepare` in the background task.
  static Future<void> prepare() async {
    await _channel.invokeMethod('prepare');
  }

  /// Passes through to `onPrepareFromMediaId` in the background task.
  static Future<void> prepareFromMediaId(String mediaId) async {
    await _channel.invokeMethod('prepareFromMediaId', mediaId);
  }

  //static Future<void> prepareFromSearch(String query, Bundle extras) async {}
  //static Future<void> prepareFromUri(Uri uri, Bundle extras) async {}

  /// Passes through to 'onPlay' in the background task.
  static Future<void> play() async {
    await _channel.invokeMethod('play');
  }

  /// Passes through to 'onPlayFromMediaId' in the background task.
  static Future<void> playFromMediaId(String mediaId) async {
    await _channel.invokeMethod('playFromMediaId', mediaId);
  }

  //static Future<void> playFromSearch(String query, Bundle extras) async {}
  //static Future<void> playFromUri(Uri uri, Bundle extras) async {}

  /// Passes through to `skipToQueueItem` in the background task.
  static Future<void> skipToQueueItem(String mediaId) async {
    await _channel.invokeMethod('skipToQueueItem', mediaId);
  }

  /// Passes through to `onPause` in the background task.
  static Future<void> pause() async {
    await _channel.invokeMethod('pause');
  }

  /// Passes through to `onStop` in the background task.
  static Future<void> stop() async {
    await _channel.invokeMethod('stop');
  }

  /// Passes through to `onSeekTo` in the background task.
  static Future<void> seekTo(int pos) async {
    await _channel.invokeMethod('seekTo', pos);
  }

  /// Passes through to `onSkipToNext` in the background task.
  static Future<void> skipToNext() async {
    await _channel.invokeMethod('skipToNext');
  }

  /// Passes through to `onSkipToPrevious` in the background task.
  static Future<void> skipToPrevious() async {
    await _channel.invokeMethod('skipToPrevious');
  }

  /// Passes through to `onFastForward` in the background task.
  static Future<void> fastForward() async {
    await _channel.invokeMethod('fastForward');
  }

  /// Passes through to `onRewind` in the background task.
  static Future<void> rewind() async {
    await _channel.invokeMethod('rewind');
  }

  /// Passes through to `onSetRating` in the background task.
  /// The extras map must *only* contain primitive types!
  static Future<void> setRating(Rating rating,
      [Map<String, dynamic> extras]) async {
    await _channel.invokeMethod('setRating', {
      "rating": rating._toRaw(),
      "extras": extras,
    });
  }

  //static Future<void> setCaptioningEnabled(boolean enabled) async {}
  //static Future<void> setRepeatMode(@PlaybackStateCompat.RepeatMode int repeatMode) async {}
  //static Future<void> setShuffleMode(@PlaybackStateCompat.ShuffleMode int shuffleMode) async {}
  //static Future<void> sendCustomAction(PlaybackStateCompat.CustomAction customAction,
  //static Future<void> sendCustomAction(String action, Bundle args) async {}

  /// Passes through to `onCustomAction` in the background task.
  ///
  /// This may be used for your own purposes.
  static Future customAction(String name, [dynamic arguments]) async {
    return await _channel.invokeMethod('$_CUSTOM_PREFIX$name', arguments);
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
  static final PlaybackState _noneState =
      PlaybackState(basicState: BasicPlaybackState.none, actions: Set());
  static MethodChannel _backgroundChannel;
  static PlaybackState _state = _noneState;

  /// The current media playback state.
  ///
  /// This is the value most recently set via [setState].
  static PlaybackState get state => _state;

  /// Runs the background audio task within the background isolate.
  ///
  /// This must be the first method called by the entrypoint of your background
  /// task that you passed into [AudioService.start]. The [BackgroundAudioTask]
  /// parameter defines callbacks to handle the initialization and distruction
  /// of the task, as well as any requests by the client to play, pause and
  /// otherwise control audio playback.
  static Future<void> run(BackgroundAudioTask taskBuilder()) async {
    _backgroundChannel =
        const MethodChannel('ryanheise.com/audioServiceBackground');
    WidgetsFlutterBinding.ensureInitialized();
    final task = taskBuilder();
    _backgroundChannel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'onLoadChildren':
          final List args = call.arguments;
          String parentMediaId = args[0];
          List<MediaItem> mediaItems = await task.onLoadChildren(parentMediaId);
          List<Map> rawMediaItems = mediaItems
              .map((mediaItem) => {
                    'id': mediaItem.id,
                    'album': mediaItem.album,
                    'title': mediaItem.title,
                    'artist': mediaItem.artist,
                    'genre': mediaItem.genre,
                    'duration': mediaItem.duration,
                    'artUri': mediaItem.artUri,
                    'playable': mediaItem.playable,
                    'displayTitle': mediaItem.displayTitle,
                    'displaySubtitle': mediaItem.displaySubtitle,
                    'displayDescription': mediaItem.displayDescription,
                  })
              .toList();
          return rawMediaItems as dynamic;
        case 'onAudioFocusGained':
          task.onAudioFocusGained();
          break;
        case 'onAudioFocusLost':
          task.onAudioFocusLost();
          break;
        case 'onAudioFocusLostTransient':
          task.onAudioFocusLostTransient();
          break;
        case 'onAudioFocusLostTransientCanDuck':
          task.onAudioFocusLostTransientCanDuck();
          break;
        case 'onAudioBecomingNoisy':
          task.onAudioBecomingNoisy();
          break;
        case 'onClick':
          final List args = call.arguments;
          MediaButton button = MediaButton.values[args[0]];
          task.onClick(button);
          break;
        case 'onStop':
          task.onStop();
          break;
        case 'onPause':
          task.onPause();
          break;
        case 'onPrepare':
          task.onPrepare();
          break;
        case 'onPrepareFromMediaId':
          final List args = call.arguments;
          String mediaId = args[0];
          task.onPrepareFromMediaId(mediaId);
          break;
        case 'onPlay':
          task.onPlay();
          break;
        case 'onPlayFromMediaId':
          final List args = call.arguments;
          String mediaId = args[0];
          task.onPlayFromMediaId(mediaId);
          break;
        case 'onAddQueueItem':
          task.onAddQueueItem(_raw2mediaItem(call.arguments[0]));
          break;
        case 'onAddQueueItemAt':
          final List args = call.arguments;
          MediaItem mediaItem = _raw2mediaItem(args[0]);
          int index = args[1];
          task.onAddQueueItemAt(mediaItem, index);
          break;
        case 'onRemoveQueueItem':
          task.onRemoveQueueItem(_raw2mediaItem(call.arguments[0]));
          break;
        case 'onSkipToNext':
          task.onSkipToNext();
          break;
        case 'onSkipToPrevious':
          task.onSkipToPrevious();
          break;
        case 'onFastForward':
          task.onFastForward();
          break;
        case 'onRewind':
          task.onRewind();
          break;
        case 'onSkipToQueueItem':
          final List args = call.arguments;
          String mediaId = args[0];
          task.onSkipToQueueItem(mediaId);
          break;
        case 'onSeekTo':
          final List args = call.arguments;
          int pos = args[0];
          task.onSeekTo(pos);
          break;
        case 'onSetRating':
          task.onSetRating(
              Rating._fromRaw(call.arguments[0]), call.arguments[1]);
          break;
        default:
          if (call.method.startsWith(_CUSTOM_PREFIX)) {
            task.onCustomAction(
                call.method.substring(_CUSTOM_PREFIX.length), call.arguments);
          }
          break;
      }
    });
    await _backgroundChannel.invokeMethod('ready');
    await task.onStart();
    await _backgroundChannel.invokeMethod('stopped');
    if (Platform.isIOS) {
      AudioService._flutterIsolate?.kill();
    }
    _backgroundChannel.setMethodCallHandler(null);
    _state = _noneState;
  }

  /// Sets the current playback state and dictates which media actions can be
  /// controlled by clients and which media controls and actions should be
  /// enabled in the notification, Wear OS and Android Auto. Each control
  /// listed in [controls] will appear as a button in the notification and its
  /// action will also be made available to all clients such as Wear OS and
  /// Android Auto.  Any additional actions that you would like to enable for
  /// clients that do not correspond to a button can be listed in
  /// [systemActions]. For example, include [MediaAction.seekTo] in
  /// [systemActions] and the system will provide a seek bar in the
  /// notification.
  ///
  /// All clients will be notified so they can update their display.
  ///
  /// The playback [position] should be explicitly updated only when the normal
  /// continuity of time is disrupted, such as when the user performs a seek,
  /// or buffering occurs, etc. Thus, the [position] parameter indicates the
  /// playback position in milliseconds at the time the state was updated while
  /// the [updateTime] parameter indicates the precise time of that update.
  ///
  /// The playback [speed] is given as a double where 1.0 means normal speed.
  static Future<void> setState({
    @required List<MediaControl> controls,
    List<MediaAction> systemActions = const [],
    @required BasicPlaybackState basicState,
    int position = 0,
    double speed = 1.0,
    int updateTime,
    List<int> androidCompactActions,
  }) async {
    _state = PlaybackState(
      basicState: basicState,
      actions: controls.map((control) => control.action).toSet(),
      position: position,
      speed: speed,
      updateTime: updateTime,
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
      basicState.index,
      position,
      speed,
      updateTime,
      androidCompactActions
    ]);
  }

  /// Sets the current queue and notifies all clients.
  static Future<void> setQueue(List<MediaItem> queue) async {
    await _backgroundChannel.invokeMethod(
        'setQueue', queue.map(_mediaItem2raw).toList());
  }

  /// Sets the currently playing media item and notifies all clients.
  static Future<void> setMediaItem(MediaItem mediaItem) async {
    await _backgroundChannel.invokeMethod(
        'setMediaItem', _mediaItem2raw(mediaItem));
  }

  /// Notify clients that the child media items of [parentMediaId] have
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
}

/// Describes an audio task that can run in the background and react to audio
/// events.
///
/// You should subclass [BackgroundAudioTask] and override the callbacks for
/// each type of event that your background task wishes to react to.
abstract class BackgroundAudioTask {
  /// Called once when this audio task is first started and ready to play
  /// audio, in response to [AudioService.start]. When the returned future
  /// completes, this task will be immediately terminated.
  Future<void> onStart();

  /// Called in response to [AudioService.stop] to request that this task be
  /// terminated. The implementation should cause any audio playback to stop,
  /// resources to be released, and the future returned by [onStart] to
  /// complete.
  void onStop();

  /// Called when a media browser client, such as Android Auto, wants to query
  /// the available media items to display to the user.
  Future<List<MediaItem>> onLoadChildren(String parentMediaId) async => [];

  /// Called on Android when your app gains the audio focus.
  void onAudioFocusGained() {}

  /// Called on Android when your app loses audio focus for an unknown
  /// duration.
  void onAudioFocusLost() {}

  /// Called on Android when your app loses audio focus temporarily and should
  /// pause audio output for that duration.
  void onAudioFocusLostTransient() {}

  /// Called on Android when your app loses audio focus temporarily and may
  /// lower the audio output volume for that duration.
  void onAudioFocusLostTransientCanDuck() {}

  /// Called on Android when your audio output is about to become noisy due
  /// to the user unplugging the headphones.
  void onAudioBecomingNoisy() {}

  /// Called when the media button on the headset is pressed, or in response to
  /// a call from [AudioService.click].
  void onClick(MediaButton button) {}

  /// Called when a client has requested to pause audio playback, such as via a
  /// call to [AudioService.pause].
  void onPause() {}

  /// Called when a client has requested to prepare audio for playback, such as
  /// via a call to [AudioService.prepare].
  void onPrepare() {}

  /// Called when a client has requested to prepare a specific media item for
  /// audio playback, such as via a call to [AudioService.prepareFromMediaId].
  void onPrepareFromMediaId(String mediaId) {}

  /// Called when a client has requested to resume audio playback, such as via
  /// a call to [AudioService.play].
  void onPlay() {}

  /// Called when a client has requested to play a specific media item, such as
  /// via a call to [AudioService.playFromMediaId].
  void onPlayFromMediaId(String mediaId) {}

  /// Called when a client has requested to add a media item to the queue, such
  /// as via a call to [AudioService.addQueueItem].
  void onAddQueueItem(MediaItem mediaItem) {}

  /// Called when a client has requested to add a media item to the queue at a
  /// specified position, such as via a request to
  /// [AudioService.addQueueItemAt].
  void onAddQueueItemAt(MediaItem mediaItem, int index) {}

  /// Called when a client has requested to remove a media item from the queue,
  /// such as via a request to [AudioService.removeQueueItem].
  void onRemoveQueueItem(MediaItem mediaItem) {}

  /// Called when a client has requested to skip to the next item in the queue,
  /// such as via a request to [AudioService.skipToNext].
  void onSkipToNext() {}

  /// Called when a client has requested to skip to the previous item in the
  /// queue, such as via a request to [AudioService.skipToPrevious].
  void onSkipToPrevious() {}

  /// Called when the client has requested to fast forward, such as via a
  /// request to [AudioService.fastForward].
  void onFastForward() {}

  /// Called when the client has requested to rewind, such as via a request to
  /// [AudioService.rewind].
  void onRewind() {}

  /// Called when the client has requested to skip to a specific item in the
  /// queue, such as via a call to [AudioService.skipToQueueItem].
  void onSkipToQueueItem(String mediaId) {}

  /// Called when the client has requested to seek to a position, such as via a
  /// call to [AudioService.seekTo].
  void onSeekTo(int position) {}

  /// Called when the client has requested to rate the current media item, such as
  /// via a call to [AudioService.setRating].
  void onSetRating(Rating rating, Map<dynamic, dynamic> extras) {}

  /// Called when a custom action has been sent by the client via
  /// [AudioService.customAction].
  void onCustomAction(String name, dynamic arguments) {}
}

_iosIsolateEntrypoint(int rawHandle) async {
  ui.CallbackHandle handle = ui.CallbackHandle.fromRawHandle(rawHandle);
  Function backgroundTask = ui.PluginUtilities.getCallbackFromHandle(handle);
  backgroundTask();
}
