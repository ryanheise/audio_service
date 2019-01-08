import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  PlaybackState({
    @required this.basicState,
    @required this.actions,
    this.position,
    this.speed,
    this.updateTime,
  });
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
  dynamic _value;

  Rating._internal(this._type, this._value);

  /// Create a new heart rating.
  Rating.newHeartRating(bool hasHeart) : this._internal(RatingStyle.heart, hasHeart);

  /// Create a new percentage rating.
  factory Rating.newPercentageRating(double percent) {
    if (percent < 0 || percent > 100) throw ArgumentError();
    return Rating._internal(RatingStyle.percentage, percent);
  }

  /// Create a new star rating.
  factory Rating.newStartRating(RatingStyle starRatingStyle, int starRating) {
    if (starRatingStyle != RatingStyle.range3stars && starRatingStyle != RatingStyle.range4stars && starRatingStyle != RatingStyle.range5stars) {
      throw ArgumentError();
    }
    if (starRating > starRatingStyle.index || starRating < 0) throw ArgumentError();
    return Rating._internal(starRatingStyle, starRating);
  }

  /// Create a new thumb rating.
  Rating.newThumbRating(bool isThumbsUp) : this._internal(RatingStyle.thumbUpDown, isThumbsUp);

  /// Create a new unrated rating.
  factory Rating.newUnratedRating(RatingStyle ratingStyle) {
    return Rating._internal(ratingStyle, null);
  }

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
    if (_type != RatingStyle.range3stars && _type != RatingStyle.range4stars && _type != RatingStyle.range5stars) return -1;
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
  Rating._fromRaw(Map<dynamic, dynamic> raw) : this._internal(RatingStyle.values[raw['type']], raw['value']);
}

/// Metadata about an audio item that can be played, or a folder containing
/// audio items.
class MediaItem {
  /// A unique id
  final String id;

  /// The album this media item belongs to
  final String album;

  /// The title of this media item
  final String title;

  /// The artist of this media item
  final String artist;

  /// The genre of this media item
  final String genre;

  /// The duration in milliseconds
  final int duration;

  /// The artwork for this media item as a uri
  final String artUri;

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

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(dynamic other) => other is MediaItem && other.id == id;
}

/// A button that controls audio playback.
class MediaControl {
  /// A reference to an Android icon resource for the control (e.g.
  /// `"drawable/ic_action_pause"`)
  final String androidIcon;

  /// A label for the control
  final String label;

  /// The action to be executed by this control
  final MediaAction action;

  MediaControl({
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

  static StreamController<List<MediaItem>> _browseMediaChildrenController =
      StreamController<List<MediaItem>>.broadcast();

  /// A stream that broadcasts the children of the current browse
  /// media parent.
  static Stream<List<MediaItem>> get browseMediaChildrenStream =>
      _browseMediaChildrenController.stream;

  static StreamController<PlaybackState> _playbackStateController =
      StreamController<PlaybackState>.broadcast();

  /// A stream that broadcasts the playback state.
  static Stream<PlaybackState> get playbackStateStream =>
      _playbackStateController.stream;

  static StreamController<MediaItem> _currentMediaItemController =
      StreamController<MediaItem>.broadcast();

  /// A stream that broadcasts the current [MediaItem].
  static Stream<MediaItem> get currentMediaItemStream =>
      _currentMediaItemController.stream;

  static StreamController<List<MediaItem>> _queueController =
      StreamController<List<MediaItem>>.broadcast();

  /// A stream that broadcasts the queue.
  static Stream<List<MediaItem>> get queueStream => _queueController.stream;

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
    _channel.setMethodCallHandler((MethodCall call) {
      switch (call.method) {
        case 'onChildrenLoaded':
          final List<Map> args = List<Map>.from(call.arguments[0]);
          _browseMediaChildren = args.map(_raw2mediaItem).toList();
          _browseMediaChildrenController.add(_browseMediaChildren);
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
          _playbackStateController.add(_playbackState);
          break;
        case 'onMediaChanged':
          _currentMediaItem = _raw2mediaItem(call.arguments[0]);
          _currentMediaItemController.add(_currentMediaItem);
          break;
        case 'onQueueChanged':
          final List<Map> args = List<Map>.from(call.arguments[0]);
          _queue = args.map(_raw2mediaItem).toList();
          _queueController.add(_queue);
          break;
      }
    });
    await _channel.invokeMethod("connect");
  }

  /// Disconnects your UI from the service.
  ///
  /// This method should be called when the UI is no longer visible.
  static Future<void> disconnect() async {
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod("disconnect");
  }

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
  /// The background task is specified by [backgroundTask] which will be run
  /// within a background isolate. This function must be a top-level or static
  /// function, and it must initiate execution by calling
  /// [AudioServiceBackground.run]. Because the background task runs in an
  /// isolate, no memory is shared between the background isolate and
  /// your main UI isolate and so all communication between the background
  /// task and your UI is achieved through message passing.
  ///
  /// The [androidNotificationIcon] is specified like an XML resource reference
  /// and defaults to `"mipmap/ic_launcher"`.
  static Future<bool> start({
    @required Function backgroundTask,
    String androidNotificationChannelName = "Notifications",
    String androidNotificationChannelDescription,
    int notificationColor,
    String androidNotificationIcon = 'mipmap/ic_launcher',
    bool androidNotificationClickStartsActivity = true,
    bool resumeOnClick = true,
    bool shouldPreloadArtwork = false,
  }) async {
    final ui.CallbackHandle handle =
        ui.PluginUtilities.getCallbackHandle(backgroundTask);
    if (handle == null) {
      return false;
    }
    var callbackHandle = handle.toRawHandle();
    return await _channel.invokeMethod('start', {
      'callbackHandle': callbackHandle,
      'androidNotificationChannelName': androidNotificationChannelName,
      'androidNotificationChannelDescription':
          androidNotificationChannelDescription,
      'notificationColor': notificationColor,
      'androidNotificationIcon': androidNotificationIcon,
      'androidNotificationClickStartsActivity':
          androidNotificationClickStartsActivity,
      'resumeOnClick': resumeOnClick,
      'shouldPreloadArtwork': shouldPreloadArtwork,
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
  static Future<void> setRating(Rating rating, [Map<String, dynamic> extras]) async {
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
/// The background task that you passed to [AudioService.start] is executed in
/// an isolate that will run independently of the view. Aside from its primary
/// job of playing audio, your background task should also use methods of this
/// class to initialise the isolate, broadcast state changes to any UI that may
/// be connected, and to also handle playback actions initiated by the UI.
class AudioServiceBackground {
  static final PlaybackState _noneState =
      PlaybackState(basicState: BasicPlaybackState.none, actions: Set());
  static MethodChannel _backgroundChannel;
  static PlaybackState _state = _noneState;

  /// The current media playback state.
  ///
  /// This is the value most recently set via [setState].
  static PlaybackState get state => _state;

  /// Initialises the isolate in which your background task runs.
  ///
  /// Each callback function you supply handles an action initiated from a
  /// connected client. In particular:
  ///
  /// * [onStart] (required) is an asynchronous function that is called in
  /// response to [AudioService.start]. It is responsible for starting audio
  /// playback and should return a [Future] that completes when the background
  /// task has completely finished playing audio and is ready to be permanently
  /// shut down. After the task has completed, a new task may still be started
  /// again via [AudioService.start].
  /// * [onStop] (required) is called in response to [AudioService.stop] (or
  /// the stop button in the notification or Wear OS or Android Auto). It is
  /// [onStop]'s responsibility to perform whatever code is necessary to cause
  /// [onStart] to complete. This may be done by using a [Completer] or by
  /// setting a flag that will trigger a loop in [onStart] to complete.
  /// * [onPause] is called in response to [AudioService.pause], or the pause
  /// button in the notification or Wear OS or Android Auto.
  /// * [onClick] is called in response to [AudioService.click], or if a media
  /// button is clicked on the headset.
  /// * [onSetRating] is called in response to [AudioService.setRating], or if the
  /// rating is set from another client (like Android Auto or WearOS)
  static Future<void> run({
    @required Future<void> onStart(),
    Future<List<MediaItem>> onLoadChildren(String parentMediaId),
    VoidCallback onAudioFocusGained,
    VoidCallback onAudioFocusLost,
    VoidCallback onAudioFocusLostTransient,
    VoidCallback onAudioFocusLostTransientCanDuck,
    VoidCallback onAudioBecomingNoisy,
    void onClick(MediaButton button),
    @required VoidCallback onStop,
    VoidCallback onPause,
    VoidCallback onPrepare,
    ValueChanged<String> onPrepareFromMediaId,
    VoidCallback onPlay,
    ValueChanged<String> onPlayFromMediaId,
    ValueChanged<MediaItem> onAddQueueItem,
    void onAddQueueItemAt(MediaItem mediaItem, int index),
    ValueChanged<MediaItem> onRemoveQueueItem,
    VoidCallback onSkipToNext,
    VoidCallback onSkipToPrevious,
    VoidCallback onFastForward,
    VoidCallback onRewind,
    ValueChanged<String> onSkipToQueueItem,
    ValueChanged<int> onSeekTo,
    void Function(Rating, Map<dynamic, dynamic>) onSetRating,
    void onCustomAction(String name, dynamic arguments),
  }) async {
    _backgroundChannel =
        const MethodChannel('ryanheise.com/audioServiceBackground');
    WidgetsFlutterBinding.ensureInitialized();
    _backgroundChannel.setMethodCallHandler((MethodCall call) async {
      switch (call.method) {
        case 'onLoadChildren':
          if (onLoadChildren != null) {
            final List args = call.arguments;
            String parentMediaId = args[0];
            List<MediaItem> mediaItems = await onLoadChildren(parentMediaId);
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
            return rawMediaItems;
          } else {
            return [];
          }
          break;
        case 'onAudioFocusGained':
          if (onAudioFocusGained != null) onAudioFocusGained();
          break;
        case 'onAudioFocusLost':
          if (onAudioFocusLost != null) onAudioFocusLost();
          break;
        case 'onAudioFocusLostTransient':
          if (onAudioFocusLostTransient != null) onAudioFocusLostTransient();
          break;
        case 'onAudioFocusLostTransientCanDuck':
          if (onAudioFocusLostTransientCanDuck != null)
            onAudioFocusLostTransientCanDuck();
          break;
        case 'onAudioBecomingNoisy':
          if (onAudioBecomingNoisy != null) onAudioBecomingNoisy();
          break;
        case 'onClick':
          if (onClick != null) {
            final List args = call.arguments;
            MediaButton button = MediaButton.values[args[0]];
            onClick(button);
          }
          break;
        case 'onStop':
          onStop();
          break;
        case 'onPause':
          if (onPause != null) onPause();
          break;
        case 'onPrepare':
          if (onPrepare != null) onPrepare();
          break;
        case 'onPrepareFromMediaId':
          if (onPrepareFromMediaId != null) {
            final List args = call.arguments;
            String mediaId = args[0];
            onPrepareFromMediaId(mediaId);
          }
          break;
        case 'onPlay':
          if (onPlay != null) onPlay();
          break;
        case 'onPlayFromMediaId':
          if (onPlayFromMediaId != null) {
            final List args = call.arguments;
            String mediaId = args[0];
            onPlayFromMediaId(mediaId);
          }
          break;
        case 'onAddQueueItem':
          if (onAddQueueItem != null) {
            onAddQueueItem(_raw2mediaItem(call.arguments[0]));
          }
          break;
        case 'onAddQueueItemAt':
          if (onAddQueueItem != null) {
            final List args = call.arguments;
            MediaItem mediaItem = _raw2mediaItem(args[0]);
            int index = args[1];
            onAddQueueItemAt(mediaItem, index);
          }
          break;
        case 'onRemoveQueueItem':
          if (onRemoveQueueItem != null) {
            onRemoveQueueItem(_raw2mediaItem(call.arguments[0]));
          }
          break;
        case 'onSkipToNext':
          if (onSkipToNext != null) onSkipToNext();
          break;
        case 'onSkipToPrevious':
          if (onSkipToPrevious != null) onSkipToPrevious();
          break;
        case 'onFastForward':
          if (onFastForward != null) onFastForward();
          break;
        case 'onRewind':
          if (onRewind != null) onRewind();
          break;
        case 'onSkipToQueueItem':
          if (onSkipToQueueItem != null) {
            final List args = call.arguments;
            String mediaId = args[0];
            onSkipToQueueItem(mediaId);
          }
          break;
        case 'onSeekTo':
          if (onSeekTo != null) {
            final List args = call.arguments;
            int pos = args[0];
            onSeekTo(pos);
          }
          break;
        case 'onSetRating':
          if (onSetRating != null) {
            onSetRating(Rating._fromRaw(call.arguments[0]), call.arguments[1]);
          }
          break;
        default:
          if (onCustomAction != null) {
            if (call.method.startsWith(_CUSTOM_PREFIX)) {
              onCustomAction(
                  call.method.substring(_CUSTOM_PREFIX.length), call.arguments);
            }
          }
          break;
      }
    });
    bool enableQueue = onAddQueueItem != null ||
        onRemoveQueueItem != null ||
        onSkipToQueueItem != null;
    await _backgroundChannel.invokeMethod('ready', enableQueue);
    await onStart();
    await _backgroundChannel.invokeMethod('stopped');
    _backgroundChannel.setMethodCallHandler(null);
    _state = _noneState;
  }

  /// Sets the current playback state and dictate which controls should be
  /// visible in the notification, Wear OS and Android Auto.
  ///
  /// All clients will be notified so they can update their display.
  ///
  /// The playback [position] should be explicitly updated only when the normal
  /// continuity of time is disrupted, such as when the user performs a seek,
  /// or buffering occurs, etc. Thus, the [position] parameter indicates the
  /// playback position in milliseconds at the time the state was updated while
  /// the [updateTime] parameter indicates the precise time of that update. It
  /// is the client's responsibility to adjust this [position] by the
  /// difference between the current system clock and the recorded
  /// [updateTime].
  ///
  /// The playback [speed] is given as a double where 1.0 means normal speed.
  static Future<void> setState({
    @required List<MediaControl> controls,
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
    await _backgroundChannel.invokeMethod('setState',
        [rawControls, basicState.index, position, speed, updateTime, androidCompactActions]);
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
