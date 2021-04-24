import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:rxdart/rxdart.dart';

export 'package:rxdart/rxdart.dart' show ValueStreamExtensions;

AudioServicePlatform _platform = AudioServicePlatform.instance;

/// The buttons on a headset.
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
  seek,
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

/// The states of audio processing.
enum AudioProcessingState {
  /// There hasn't been any resource loaded yet.
  idle,

  /// Resource is being loaded.
  loading,

  /// Resource is being buffered.
  buffering,

  /// Resource is buffered enough and available for playback.
  ready,

  /// The end of resource was reached.
  completed,

  /// There was an error loading resource.
  ///
  /// [PlaybackState.errorCode] and [PlaybackState.errorMessage] will be not null
  /// in this state.
  error,
}

/// The playback state which includes a [playing] boolean state, a processing
/// state such as [AudioProcessingState.buffering], the playback position and
/// the currently enabled actions to be shown in the Android notification or the
/// iOS control center.
class PlaybackState {
  /// The audio processing state e.g. [AudioProcessingState.buffering].
  final AudioProcessingState processingState;

  /// Whether audio is either playing, or will play as soon as [processingState]
  /// is [AudioProcessingState.ready]. A true value should be broadcast whenever
  /// it would be appropriate for UIs to display a pause or stop button.
  ///
  /// Since [playing] and [processingState] can vary independently, it is
  /// possible distinguish a particular audio processing state while audio is
  /// playing vs paused. For example, when buffering occurs during a seek, the
  /// [processingState] can be [AudioProcessingState.buffering], but alongside
  /// that [playing] can be true to indicate that the seek was performed while
  /// playing, or false to indicate that the seek was performed while paused.
  final bool playing;

  /// The list of currently enabled controls which should be shown in the media
  /// notification. Each control represents a clickable button with a
  /// [MediaAction] that must be one of:
  ///
  /// * [MediaAction.stop]
  /// * [MediaAction.pause]
  /// * [MediaAction.play]
  /// * [MediaAction.rewind]
  /// * [MediaAction.skipToPrevious]
  /// * [MediaAction.skipToNext]
  /// * [MediaAction.fastForward]
  /// * [MediaAction.playPause]
  final List<MediaControl> controls;

  /// Up to 3 indices of the [controls] that should appear in Android's compact
  /// media notification view. When the notification is expanded, all [controls]
  /// will be shown.
  final List<int>? androidCompactActionIndices;

  /// The set of system actions currently enabled. This is for specifying any
  /// other [MediaAction]s that are not supported by [controls], because they do
  /// not represent clickable buttons. For example:
  ///
  /// * [MediaAction.seek] (enable a seek bar)
  /// * [MediaAction.seekForward] (enable press-and-hold fast-forward control)
  /// * [MediaAction.seekBackward] (enable press-and-hold rewind control)
  ///
  /// Note that specifying [MediaAction.seek] in [systemActions] will enable
  /// a seek bar in both the Android notification and the iOS control center.
  /// [MediaAction.seekForward] and [MediaAction.seekBackward] have a special
  /// behaviour on iOS in which if you have already enabled the
  /// [MediaAction.skipToNext] and [MediaAction.skipToPrevious] buttons, these
  /// additional actions will allow the user to press and hold the buttons to
  /// activate the continuous seeking behaviour.
  ///
  /// When enabling the seek bar, also note that some Android devices will not
  /// render the seek bar correctly unless your [AudioServiceConfig.androidNotificationIcon]
  /// is a monochrome white icon on a transparent background, and your
  /// [AudioServiceConfig.notificationColor] is a non-transparent color.
  final Set<MediaAction> systemActions;

  /// The playback position at [updateTime].
  ///
  /// For efficiency, the [updatePosition] should NOT be updated continuously in
  /// real time. Instead, it should be updated only when the normal continuity
  /// of time is disrupted, such as during a seek, buffering and seeking. When
  /// broadcasting such a position change, the [updateTime] specifies the time
  /// of that change, allowing clients to project the realtime value of the
  /// position as `position + (DateTime.now() - updateTime)`. As a convenience,
  /// this calculation is provided by the [position] getter.
  final Duration updatePosition;

  /// The buffered position.
  final Duration bufferedPosition;

  /// The current playback speed where 1.0 means normal speed.
  final double speed;

  /// The time at which the playback position was last updated.
  final DateTime updateTime;

  /// The error code when [processingState] is [AudioProcessingState.error].
  final int? errorCode;

  /// The error message when [processingState] is [AudioProcessingState.error].
  final String? errorMessage;

  /// The current repeat mode.
  final AudioServiceRepeatMode repeatMode;

  /// The current shuffle mode.
  final AudioServiceShuffleMode shuffleMode;

  /// Whether captioning is enabled.
  final bool captioningEnabled;

  /// The index of the current item in the queue, if any.
  final int? queueIndex;

  /// Creates a [PlaybackState] with given field values, and with [updateTime]
  /// defaulting to [DateTime.now].
  PlaybackState({
    this.processingState = AudioProcessingState.idle,
    this.playing = false,
    this.controls = const [],
    this.androidCompactActionIndices,
    this.systemActions = const {},
    this.updatePosition = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    DateTime? updateTime,
    this.errorCode,
    this.errorMessage,
    this.repeatMode = AudioServiceRepeatMode.none,
    this.shuffleMode = AudioServiceShuffleMode.none,
    this.captioningEnabled = false,
    this.queueIndex,
  })  : assert(androidCompactActionIndices == null ||
            androidCompactActionIndices.length <= 3),
        updateTime = updateTime ?? DateTime.now();

  /// Creates a copy of this state with given fields replaced by new values,
  /// with [updateTime] set to [DateTime.now], and unless otherwise replaced,
  /// with [updatePosition] set to [position].
  ///
  /// The [errorCode] and [errorMessage] will be set to null unless [processingState] is
  /// [AudioProcessingState.error].
  PlaybackStateCopyWith get copyWith => _PlaybackStateCopyWith(this);

  /// The current playback position.
  Duration get position {
    if (playing && processingState == AudioProcessingState.ready) {
      return Duration(
        milliseconds: (updatePosition.inMilliseconds +
                speed *
                    (DateTime.now().millisecondsSinceEpoch -
                        updateTime.millisecondsSinceEpoch))
            .toInt(),
      );
    } else {
      return updatePosition;
    }
  }

  PlaybackStateMessage _toMessage() => PlaybackStateMessage(
        processingState:
            AudioProcessingStateMessage.values[processingState.index],
        playing: playing,
        controls: controls.map((control) => control._toMessage()).toList(),
        androidCompactActionIndices: androidCompactActionIndices,
        systemActions: systemActions
            .map((action) => MediaActionMessage.values[action.index])
            .toSet(),
        updatePosition: updatePosition,
        bufferedPosition: bufferedPosition,
        speed: speed,
        updateTime: updateTime,
        errorCode: errorCode,
        errorMessage: errorMessage,
        repeatMode: AudioServiceRepeatModeMessage.values[repeatMode.index],
        shuffleMode: AudioServiceShuffleModeMessage.values[shuffleMode.index],
        captioningEnabled: captioningEnabled,
        queueIndex: queueIndex,
      );

  @override
  String toString() => '${_toMessage().toMap()}';
}

/// The `copyWith` function type for [PlaybackState].
abstract class PlaybackStateCopyWith {
  PlaybackState call({
    AudioProcessingState processingState,
    bool playing,
    List<MediaControl> controls,
    List<int>? androidCompactActionIndices,
    Set<MediaAction> systemActions,
    Duration updatePosition,
    Duration bufferedPosition,
    double speed,
    int? errorCode,
    String? errorMessage,
    AudioServiceRepeatMode repeatMode,
    AudioServiceShuffleMode shuffleMode,
    bool captioningEnabled,
    int? queueIndex,
  });
}

/// The implementation of [PlaybackState]'s `copyWith` function allowing
/// parameters to be explicitly set to null.
class _PlaybackStateCopyWith extends PlaybackStateCopyWith {
  static const _fakeNull = Object();

  /// The [PlaybackState] object this function applies to.
  final PlaybackState value;

  _PlaybackStateCopyWith(this.value);

  @override
  PlaybackState call({
    Object? processingState = _fakeNull,
    Object? playing = _fakeNull,
    Object? controls = _fakeNull,
    Object? androidCompactActionIndices = _fakeNull,
    Object? systemActions = _fakeNull,
    Object? updatePosition = _fakeNull,
    Object? bufferedPosition = _fakeNull,
    Object? speed = _fakeNull,
    Object? errorCode = _fakeNull,
    Object? errorMessage = _fakeNull,
    Object? repeatMode = _fakeNull,
    Object? shuffleMode = _fakeNull,
    Object? captioningEnabled = _fakeNull,
    Object? queueIndex = _fakeNull,
  }) =>
      PlaybackState(
        processingState: processingState == _fakeNull
            ? value.processingState
            : processingState as AudioProcessingState,
        playing: playing == _fakeNull ? value.playing : playing as bool,
        controls: controls == _fakeNull
            ? value.controls
            : controls as List<MediaControl>,
        androidCompactActionIndices: androidCompactActionIndices == _fakeNull
            ? value.androidCompactActionIndices
            : androidCompactActionIndices as List<int>?,
        systemActions: systemActions == _fakeNull
            ? value.systemActions
            : systemActions as Set<MediaAction>,
        updatePosition: updatePosition == _fakeNull
            ? value.updatePosition
            : updatePosition as Duration,
        bufferedPosition: bufferedPosition == _fakeNull
            ? value.bufferedPosition
            : bufferedPosition as Duration,
        speed: speed == _fakeNull ? value.speed : speed as double,
        errorCode: errorCode == _fakeNull ? value.errorCode : errorCode as int?,
        errorMessage: errorMessage == _fakeNull
            ? value.errorMessage
            : errorMessage as String?,
        repeatMode: repeatMode == _fakeNull
            ? value.repeatMode
            : repeatMode as AudioServiceRepeatMode,
        shuffleMode: shuffleMode == _fakeNull
            ? value.shuffleMode
            : shuffleMode as AudioServiceShuffleMode,
        captioningEnabled: captioningEnabled == _fakeNull
            ? value.captioningEnabled
            : captioningEnabled as bool,
        queueIndex:
            queueIndex == _fakeNull ? value.queueIndex : queueIndex as int?,
      );
}

enum RatingStyle {
  /// Indicates a rating style is not supported.
  ///
  /// A [Rating] will never have this type, but can be used by other classes
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
  final Object? _value;

  const Rating._(this._type, this._value);

  /// Creates a new heart rating.
  const Rating.newHeartRating(bool hasHeart)
      : this._(RatingStyle.heart, hasHeart);

  /// Creates a new percentage rating.
  const Rating.newPercentageRating(double percent)
      : assert(
          percent >= 0 && percent <= 100,
          'Percentage must be in range from 0 to 100',
        ),
        _type = RatingStyle.percentage,
        _value = percent;

  /// Creates a new star rating.
  Rating.newStarRating(RatingStyle style, int rating)
      : assert(
          style == RatingStyle.range3stars ||
              style == RatingStyle.range4stars ||
              style == RatingStyle.range5stars,
          'Invalid rating style',
        ),
        assert(rating >= 0 && rating <= style.index),
        _type = style,
        _value = rating;

  /// Creates a new thumb rating.
  const Rating.newThumbRating(bool isThumbsUp)
      : this._(RatingStyle.thumbUpDown, isThumbsUp);

  /// Creates a new unrated rating.
  const Rating.newUnratedRating(RatingStyle ratingStyle)
      : this._(ratingStyle, null);

  /// Return the rating style.
  RatingStyle getRatingStyle() => _type;

  /// Returns a percentage rating value greater or equal to `0.0`, or a
  /// negative value if the rating style is not percentage-based, or
  /// if it is unrated.
  double getPercentRating() {
    if (_type != RatingStyle.percentage) return -1;
    final localValue = _value as double?;
    if (localValue == null || localValue < 0 || localValue > 100) return -1;
    return localValue;
  }

  /// Returns a rating value greater or equal to `0.0`, or a negative
  /// value if the rating style is not star-based, or if it is
  /// unrated.
  int getStarRating() {
    if (_type != RatingStyle.range3stars &&
        _type != RatingStyle.range4stars &&
        _type != RatingStyle.range5stars) {
      return -1;
    }
    return _value as int? ?? -1;
  }

  /// Returns true if the rating is "heart selected" or false if the
  /// rating is "heart unselected", if the rating style is not [RatingStyle.heart]
  /// or if it is unrated.
  bool hasHeart() {
    if (_type != RatingStyle.heart) return false;
    return _value as bool? ?? false;
  }

  /// Returns true if the rating is "thumb up" or false if the rating
  /// is "thumb down", if the rating style is not [RatingStyle.thumbUpDown] or if
  /// it is unrated.
  bool isThumbUp() {
    if (_type != RatingStyle.thumbUpDown) return false;
    return _value as bool? ?? false;
  }

  /// Return whether there is a rating value available.
  bool isRated() => _value != null;

  RatingMessage _toMessage() => RatingMessage(
        type: RatingStyleMessage.values[_type.index],
        value: _value,
      );

  @override
  String toString() => '${_toMessage().toMap()}';
}

/// Metadata of an audio item that can be played, or a folder containing
/// audio items.
class MediaItem {
  /// A unique id.
  final String id;

  /// The album this media item belongs to.
  final String album;

  /// The title of this media item.
  final String title;

  /// The artist of this media item.
  final String? artist;

  /// The genre of this media item.
  final String? genre;

  /// The duration of this media item.
  final Duration? duration;

  /// The artwork for this media item as a uri.
  final Uri? artUri;

  /// Whether this is playable (i.e. not a folder).
  final bool? playable;

  /// Override the default title for display purposes.
  final String? displayTitle;

  /// Override the default subtitle for display purposes.
  final String? displaySubtitle;

  /// Override the default description for display purposes.
  final String? displayDescription;

  /// The rating of the media item.
  final Rating? rating;

  /// A map of additional metadata for the media item.
  ///
  /// The values must be integers or strings.
  final Map<String, dynamic>? extras;

  /// Creates a [MediaItem].
  ///
  /// The [id] must be unique for each instance.
  const MediaItem({
    required this.id,
    required this.album,
    required this.title,
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

  /// Creates a copy of this [MediaItem] with with the given fields replaced by
  /// new values.
  MediaItemCopyWith get copyWith => _MediaItemCopyWith(this);

  @override
  int get hashCode => id.hashCode;

  @override
  bool operator ==(dynamic other) => other is MediaItem && other.id == id;

  MediaItemMessage _toMessage() => MediaItemMessage(
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
        rating: rating?._toMessage(),
        extras: extras,
      );

  @override
  String toString() => '${_toMessage().toMap()}';
}

/// The `copyWith` function type for [MediaItem].
abstract class MediaItemCopyWith {
  MediaItem call({
    String id,
    String album,
    String title,
    String? artist,
    String? genre,
    Duration? duration,
    Uri? artUri,
    bool? playable,
    String? displayTitle,
    String? displaySubtitle,
    String? displayDescription,
    Rating? rating,
    Map<String, dynamic>? extras,
  });
}

/// The implementation of [MediaItem]'s `copyWith` function allowing
/// parameters to be explicitly set to null.
class _MediaItemCopyWith extends MediaItemCopyWith {
  static const _fakeNull = Object();

  /// The [MediaItem] object this function applies to.
  final MediaItem value;

  _MediaItemCopyWith(this.value);

  @override
  MediaItem call({
    Object? id = _fakeNull,
    Object? album = _fakeNull,
    Object? title = _fakeNull,
    Object? artist = _fakeNull,
    Object? genre = _fakeNull,
    Object? duration = _fakeNull,
    Object? artUri = _fakeNull,
    Object? playable = _fakeNull,
    Object? displayTitle = _fakeNull,
    Object? displaySubtitle = _fakeNull,
    Object? displayDescription = _fakeNull,
    Object? rating = _fakeNull,
    Object? extras = _fakeNull,
  }) =>
      MediaItem(
        id: id == _fakeNull ? value.id : id as String,
        album: album == _fakeNull ? value.album : album as String,
        title: title == _fakeNull ? value.title : title as String,
        artist: artist == _fakeNull ? value.artist : artist as String?,
        genre: genre == _fakeNull ? value.genre : genre as String?,
        duration:
            duration == _fakeNull ? value.duration : duration as Duration?,
        artUri: artUri == _fakeNull ? value.artUri : artUri as Uri?,
        playable: playable == _fakeNull ? value.playable : playable as bool?,
        displayTitle: displayTitle == _fakeNull
            ? value.displayTitle
            : displayTitle as String?,
        displaySubtitle: displaySubtitle == _fakeNull
            ? value.displaySubtitle
            : displaySubtitle as String?,
        displayDescription: displayDescription == _fakeNull
            ? value.displayDescription
            : displayDescription as String?,
        rating: rating == _fakeNull ? value.rating : rating as Rating?,
        extras: extras == _fakeNull
            ? value.extras
            : extras as Map<String, dynamic>?,
      );
}

/// A button to appear in the Android notification, lock screen, Android smart
/// watch, or Android Auto device. The set of buttons you would like to display
/// at any given moment should be streamed via [AudioHandler.playbackState].
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
    required this.androidIcon,
    required this.label,
    required this.action,
  });

  MediaControlMessage _toMessage() => MediaControlMessage(
        androidIcon: androidIcon,
        label: label,
        action: MediaActionMessage.values[action.index],
      );

  @override
  String toString() => '${_toMessage().toMap()}';
}

/// Provides an API to manage the app's [AudioHandler]. An app must call [init]
/// during initialisation to register the [AudioHandler] that will service all
/// requests to play audio.
class AudioService {
  /// The cache to use when loading artwork.
  /// Defaults to [DefaultCacheManager].
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
    required T Function() builder,
    AudioServiceConfig? config,
    BaseCacheManager? cacheManager,
  }) async {
    assert(_cacheManager == null);
    config ??= AudioServiceConfig();
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
              request.arguments![0] as String,
              request.arguments![1] as Map<String, dynamic>?,
            );
            request.sendPort.send(null);
            break;
          case 'prepareFromSearch':
            await _handler.prepareFromSearch(
              request.arguments![0] as String,
              request.arguments![1] as Map<String, dynamic>?,
            );
            request.sendPort.send(null);
            break;
          case 'prepareFromUri':
            await _handler.prepareFromUri(
              request.arguments![0] as Uri,
              request.arguments![1] as Map<String, dynamic>?,
            );
            request.sendPort.send(null);
            break;
          case 'play':
            await _handler.play();
            request.sendPort.send(null);
            break;
          case 'playFromMediaId':
            await _handler.playFromMediaId(
              request.arguments![0] as String,
              request.arguments![1] as Map<String, dynamic>?,
            );
            request.sendPort.send(null);
            break;
          case 'playFromSearch':
            await _handler.playFromSearch(
              request.arguments![0] as String,
              request.arguments![1] as Map<String, dynamic>?,
            );
            request.sendPort.send(null);
            break;
          case 'playFromUri':
            await _handler.playFromUri(
              request.arguments![0] as Uri,
              request.arguments![1] as Map<String, dynamic>?,
            );
            request.sendPort.send(null);
            break;
          case 'playMediaItem':
            await _handler.playMediaItem(request.arguments![0] as MediaItem);
            request.sendPort.send(null);
            break;
          case 'pause':
            await _handler.pause();
            request.sendPort.send(null);
            break;
          case 'click':
            await _handler.click(request.arguments![0] as MediaButton);
            request.sendPort.send(null);
            break;
          case 'stop':
            await _handler.stop();
            request.sendPort.send(null);
            break;
          case 'addQueueItem':
            await _handler.addQueueItem(request.arguments![0] as MediaItem);
            request.sendPort.send(null);
            break;
          case 'addQueueItems':
            await _handler
                .addQueueItems(request.arguments![0] as List<MediaItem>);
            request.sendPort.send(null);
            break;
          case 'insertQueueItem':
            await _handler.insertQueueItem(
              request.arguments![0] as int,
              request.arguments![1] as MediaItem,
            );
            request.sendPort.send(null);
            break;
          case 'updateQueue':
            await _handler
                .updateQueue(request.arguments![0] as List<MediaItem>);
            request.sendPort.send(null);
            break;
          case 'updateMediaItem':
            await _handler.updateMediaItem(request.arguments![0] as MediaItem);
            request.sendPort.send(null);
            break;
          case 'removeQueueItem':
            await _handler.removeQueueItem(request.arguments![0] as MediaItem);
            request.sendPort.send(null);
            break;
          case 'removeQueueItemAt':
            await _handler.removeQueueItemAt(request.arguments![0] as int);
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
            await _handler.skipToQueueItem(request.arguments![0] as int);
            request.sendPort.send(null);
            break;
          case 'seek':
            await _handler.seek(request.arguments![0] as Duration);
            request.sendPort.send(null);
            break;
          case 'setRating':
            await _handler.setRating(
              request.arguments![0] as Rating,
              request.arguments![1] as Map<String, dynamic>?,
            );
            request.sendPort.send(null);
            break;
          case 'setCaptioningEnabled':
            await _handler.setCaptioningEnabled(request.arguments![0] as bool);
            request.sendPort.send(null);
            break;
          case 'setRepeatMode':
            await _handler
                .setRepeatMode(request.arguments![0] as AudioServiceRepeatMode);
            request.sendPort.send(null);
            break;
          case 'setShuffleMode':
            await _handler.setShuffleMode(
                request.arguments![0] as AudioServiceShuffleMode);
            request.sendPort.send(null);
            break;
          case 'seekBackward':
            await _handler.seekBackward(request.arguments![0] as bool);
            request.sendPort.send(null);
            break;
          case 'seekForward':
            await _handler.seekForward(request.arguments![0] as bool);
            request.sendPort.send(null);
            break;
          case 'setSpeed':
            await _handler.setSpeed(request.arguments![0] as double);
            request.sendPort.send(null);
            break;
          case 'customAction':
            await _handler.customAction(
              request.arguments![0] as String,
              request.arguments![1] as Map<String, dynamic>?,
            );
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
              request.arguments![0] as String,
              request.arguments![1] as Map<String, dynamic>?,
            ));
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
            request.sendPort.send(
                await _handler.getMediaItem(request.arguments![0] as String));
            break;
          case 'search':
            request.sendPort.send(await _handler.search(
              request.arguments![0] as String,
              request.arguments![1] as Map<String, dynamic>?,
            ));
            break;
          case 'androidAdjustRemoteVolume':
            await _handler.androidAdjustRemoteVolume(
                request.arguments![0] as AndroidVolumeDirection);
            request.sendPort.send(null);
            break;
          case 'androidSetRemoteVolume':
            await _handler.androidSetRemoteVolume(request.arguments![0] as int);
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
          final fileInfo =
              await cacheManager!.getFileFromMemory(artUri.toString());
          filePath = fileInfo?.file.path;
          if (filePath == null) {
            // We haven't fetched the art yet, so show the metadata now, and again
            // after we load the art.
            await _platform.setMediaItem(
                SetMediaItemRequest(mediaItem: mediaItem._toMessage()));
            // Load the art
            filePath = await _loadArtwork(mediaItem);
            // If we failed to download the art, abort.
            if (filePath == null) return;
            // If we've already set a new media item, cancel this request.
            // XXX: Test this
            //if (mediaItem != _handler.mediaItem.value) return;
          }
        }
        final extras =
            Map<String, dynamic>.of(mediaItem.extras ?? <String, dynamic>{});
        extras['artCacheFile'] = filePath;
        final platformMediaItem = mediaItem.copyWith(extras: extras);
        // Show the media item after the art is loaded.
        await _platform.setMediaItem(
            SetMediaItemRequest(mediaItem: platformMediaItem._toMessage()));
      } else {
        await _platform.setMediaItem(
            SetMediaItemRequest(mediaItem: mediaItem._toMessage()));
      }
    });
    _handler.androidPlaybackInfo
        .listen((AndroidPlaybackInfo playbackInfo) async {
      await _platform.setAndroidPlaybackInfo(SetAndroidPlaybackInfoRequest(
        playbackInfo: playbackInfo._toMessage(),
      ));
    });
    _handler.queue.listen((List<MediaItem>? queue) async {
      if (queue == null) return;
      if (_config.preloadArtwork) {
        _loadAllArtwork(queue);
      }
      await _platform.setQueue(SetQueueRequest(
          queue: queue.map((item) => item._toMessage()).toList()));
    });
    _handler.playbackState.listen((PlaybackState playbackState) async {
      await _platform
          .setState(SetStateRequest(state: playbackState._toMessage()));
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
      _positionSubject!.addStream(
        createPositionStream(
            steps: 800,
            minPeriod: Duration(milliseconds: 16),
            maxPeriod: Duration(milliseconds: 200)),
      );
    }
    return _positionSubject!.stream;
  }

  /// Creates a new stream periodically tracking the current position. The
  /// stream will aim to emit [steps] position updates at intervals of
  /// current [MediaItem.duration] / [steps]. This interval will be clipped between [minPeriod]
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
      const AndroidForceEnableMediaButtonsRequest(),
    );
  }

  /// Stops the service.
  static Future<void> _stop() async {
    final audioSession = await AudioSession.instance;
    try {
      await audioSession.setActive(false);
    } catch (e) {
      print("While deactivating audio session: $e");
    }
    await _platform.stopService(const StopServiceRequest());
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
    } catch (e) {
      // TODO: handle this somehow?
    }
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

  /// Deprecated. Use `value` of  [AudioHandler.playbackState] instead.
  @deprecated
  static PlaybackState get playbackState =>
      _handler.playbackState.value ?? PlaybackState();

  /// Deprecated. Use [AudioHandler.mediaItem] instead.
  @deprecated
  static ValueStream<MediaItem?> get currentMediaItemStream =>
      _handler.mediaItem;

  /// Deprecated. Use `value` of [AudioHandler.mediaItem] instead.
  @deprecated
  static MediaItem? get currentMediaItem => _handler.mediaItem.value;

  /// Deprecated. Use [AudioHandler.queue] instead.
  @deprecated
  static ValueStream<List<MediaItem>?> get queueStream => _handler.queue;

  /// Deprecated. Use `value` of [AudioHandler.queue] instead.
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

  /// Deprecated. Use [PlaybackState.processingState] of [AudioHandler.playbackState] instead.
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

  /// Deprecated. Use [AudioHandler.insertQueueItem] instead.
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
    final index = queue.indexWhere((item) => item.id == mediaId);
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
      (Rating rating, Map<dynamic, dynamic> extras) =>
          _handler.setRating(rating, extras.cast<String, dynamic>());

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
  /// Deprecated. Use [AudioServiceConfig.fastForwardInterval] from [AudioService.config] instead.
  Duration get fastForwardInterval => AudioService.config.fastForwardInterval;

  /// Deprecated. Use [AudioServiceConfig.rewindInterval] from [AudioService.config] instead.
  Duration get rewindInterval => AudioService.config.rewindInterval;

  /// Deprecated. Replaced by [AudioHandler.stop].
  @mustCallSuper
  Future<void> onStop() => super.stop();

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

  /// Deprecated. Replaced by [AudioHandler.seek].
  Future<void> onSeekTo(Duration position) async {}

  /// Deprecated. Replaced by [AudioHandler.setRating].
  Future<void> onSetRating(Rating rating, Map<String, dynamic>? extras) async {}

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
  @override
  Future<void> onTaskRemoved() async {}

  /// Deprecated. Replaced by [AudioHandler.onNotificationDeleted].
  Future<void> onClose() => onStop();

  Future<void> _skip(int offset) async {
    final mediaItem = this.mediaItem.value;
    if (mediaItem == null) return;
    final queue = this.queue.value ?? <MediaItem>[];
    final i = queue.indexOf(mediaItem);
    if (i == -1) return;
    final newIndex = i + offset;
    if (newIndex >= 0 && newIndex < queue.length) {
      await onSkipToQueueItem(queue[newIndex].id);
    }
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
    await onSkipToQueueItem(mediaItem.id);
  }

  @override
  Future<void> seek(Duration position) => onSeekTo(position);

  @override
  Future<void> setRating(Rating rating, Map<String, dynamic>? extras) =>
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

/// An [AudioHandler] plays audio, provides state updates and query results to
/// clients. It implements standard protocols that allow it to be remotely
/// controlled by the lock screen, media notifications, the iOS control center,
/// headsets, smart watches, car audio systems, and other compatible agents.
///
/// This class cannot be subclassed directly. Implementations should subclass
/// [BaseAudioHandler], and composite behaviours should be defined as subclasses
/// of [CompositeAudioHandler].
abstract class AudioHandler {
  AudioHandler._();

  /// Prepare media items for playback.
  Future<void> prepare();

  /// Prepare a specific media item for playback.
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]);

  /// Prepare playback from a search query.
  Future<void> prepareFromSearch(String query, [Map<String, dynamic>? extras]);

  /// Prepare a media item represented by a Uri for playback.
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic>? extras]);

  /// Start or resume playback.
  Future<void> play();

  /// Play a specific media item.
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]);

  /// Begin playback from a search query.
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]);

  /// Play a media item represented by a Uri.
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]);

  /// Play a specific media item.
  Future<void> playMediaItem(MediaItem mediaItem);

  /// Pause playback.
  Future<void> pause();

  /// Process a headset button click, where [button] defaults to
  /// [MediaButton.media].
  Future<void> click([MediaButton button = MediaButton.media]);

  /// Stop playback and release resources.
  Future<void> stop();

  /// Add [mediaItem] to the queue.
  Future<void> addQueueItem(MediaItem mediaItem);

  /// Add [mediaItems] to the queue.
  Future<void> addQueueItems(List<MediaItem> mediaItems);

  /// Insert [mediaItem] into the queue at position [index].
  Future<void> insertQueueItem(int index, MediaItem mediaItem);

  /// Update to the queue to [queue].
  Future<void> updateQueue(List<MediaItem> queue);

  /// Update the properties of [mediaItem].
  Future<void> updateMediaItem(MediaItem mediaItem);

  /// Remove [mediaItem] from the queue.
  Future<void> removeQueueItem(MediaItem mediaItem);

  /// Remove media item from the queue at the specified [index].
  Future<void> removeQueueItemAt(int index);

  /// Skip to the next item in the queue.
  Future<void> skipToNext();

  /// Skip to the previous item in the queue.
  Future<void> skipToPrevious();

  /// Jump forward by [AudioServiceConfig.fastForwardInterval].
  Future<void> fastForward();

  /// Jump backward by [AudioServiceConfig.rewindInterval]. Note: this value
  /// must be positive.
  Future<void> rewind();

  /// Skip to a queue item.
  Future<void> skipToQueueItem(int index);

  /// Seek to [position].
  Future<void> seek(Duration position);

  /// Set the rating.
  Future<void> setRating(Rating rating, Map<String, dynamic>? extras);

  Future<void> setCaptioningEnabled(bool enabled);

  /// Set the repeat mode.
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode);

  /// Set the shuffle mode.
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode);

  /// Begin or end seeking backward continuously.
  Future<void> seekBackward(bool begin);

  /// Begin or end seeking forward continuously.
  Future<void> seekForward(bool begin);

  /// Set the playback speed.
  Future<void> setSpeed(double speed);

  /// A mechanism to support app-specific actions.
  Future<dynamic> customAction(String name, Map<String, dynamic>? extras);

  /// Handle the task being swiped away in the task manager (Android).
  Future<void> onTaskRemoved();

  /// Handle the notification being swiped away (Android).
  Future<void> onNotificationDeleted();

  /// Get the children of a parent media item.
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]);

  /// Get a value stream that emits service-specific options to send to the
  /// client whenever the children under the specified parent change. The
  /// emitted options may contain information about what changed. A client that
  /// is subscribed to this stream should call [getChildren] to obtain the
  /// changed children.
  ValueStream<Map<String, dynamic>?> subscribeToChildren(String parentMediaId);

  /// Get a particular media item.
  Future<MediaItem?> getMediaItem(String mediaId);

  /// Search for media items.
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]);

  /// Set the remote volume on Android. This works only when using
  /// [RemoteAndroidPlaybackInfo].
  Future<void> androidSetRemoteVolume(int volumeIndex);

  /// Adjust the remote volume on Android. This works only when using
  /// [RemoteAndroidPlaybackInfo].
  Future<void> androidAdjustRemoteVolume(AndroidVolumeDirection direction);

  /// A value stream of playback states.
  ValueStream<PlaybackState> get playbackState;

  /// A value stream of the current queue.
  ValueStream<List<MediaItem>?> get queue;

  /// A value stream of the current queueTitle.
  ValueStream<String> get queueTitle;

  /// A value stream of the current media item.
  ValueStream<MediaItem?> get mediaItem;

  /// A value stream of the current rating style.
  ValueStream<RatingStyle> get ratingStyle;

  /// A value stream of the current [AndroidPlaybackInfo].
  ValueStream<AndroidPlaybackInfo> get androidPlaybackInfo;

  /// A stream of custom events.
  Stream<dynamic> get customEvent;

  /// A stream of custom states.
  ValueStream<dynamic> get customState;
}

/// A [SwitchAudioHandler] wraps another [AudioHandler] that may be switched for
/// another at any time by setting [inner].
class SwitchAudioHandler extends CompositeAudioHandler {
  @override
  // ignore: close_sinks
  final BehaviorSubject<PlaybackState> playbackState = BehaviorSubject();
  @override
  // ignore: close_sinks
  final BehaviorSubject<List<MediaItem>?> queue = BehaviorSubject();
  @override
  // ignore: close_sinks
  final BehaviorSubject<String> queueTitle = BehaviorSubject();
  @override
  // ignore: close_sinks
  final BehaviorSubject<MediaItem?> mediaItem = BehaviorSubject();
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

  StreamSubscription<PlaybackState>? playbackStateSubscription;
  StreamSubscription<List<MediaItem>?>? queueSubscription;
  StreamSubscription<String>? queueTitleSubscription;
  StreamSubscription<MediaItem?>? mediaItemSubscription;
  StreamSubscription<AndroidPlaybackInfo>? androidPlaybackInfoSubscription;
  StreamSubscription<RatingStyle>? ratingStyleSubscription;
  StreamSubscription<dynamic>? customEventSubscription;
  StreamSubscription<dynamic>? customStateSubscription;

  SwitchAudioHandler(AudioHandler inner) : super(inner) {
    this.inner = inner;
  }

  /// The current inner [AudioHandler] that this [SwitchAudioHandler] will
  /// delegate to.
  AudioHandler get inner => _inner;

  set inner(AudioHandler newInner) {
    // Should disallow all ancestors...
    assert(newInner != this);
    playbackStateSubscription?.cancel();
    queueSubscription?.cancel();
    queueTitleSubscription?.cancel();
    mediaItemSubscription?.cancel();
    androidPlaybackInfoSubscription?.cancel();
    ratingStyleSubscription?.cancel();
    customEventSubscription?.cancel();
    customStateSubscription?.cancel();
    _inner = newInner;
    playbackStateSubscription = inner.playbackState.listen(playbackState.add);
    queueSubscription = inner.queue.listen(queue.add);
    queueTitleSubscription = inner.queueTitle.listen(queueTitle.add);
    mediaItemSubscription = inner.mediaItem.listen(mediaItem.add);
    androidPlaybackInfoSubscription =
        inner.androidPlaybackInfo.listen(androidPlaybackInfo.add);
    ratingStyleSubscription = inner.ratingStyle.listen(ratingStyle.add);
    customEventSubscription = inner.customEvent.listen(customEvent.add);
    customStateSubscription = inner.customState.listen(customState.add);
  }
}

/// A [CompositeAudioHandler] wraps another [AudioHandler] and adds additional
/// behaviour to it. Each method will by default pass through to the
/// corresponding method of the wrapped handler. If you override a method, it
/// must call super in addition to any "additional" functionality you add.
class CompositeAudioHandler extends AudioHandler {
  AudioHandler _inner;

  /// Create the [CompositeAudioHandler] with the given wrapped handler.
  CompositeAudioHandler(AudioHandler inner)
      : _inner = inner,
        super._();

  @override
  @mustCallSuper
  Future<void> prepare() => _inner.prepare();

  @override
  @mustCallSuper
  Future<void> prepareFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) =>
      _inner.prepareFromMediaId(mediaId, extras);

  @override
  @mustCallSuper
  Future<void> prepareFromSearch(String query,
          [Map<String, dynamic>? extras]) =>
      _inner.prepareFromSearch(query, extras);

  @override
  @mustCallSuper
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic>? extras]) =>
      _inner.prepareFromUri(uri, extras);

  @override
  @mustCallSuper
  Future<void> play() => _inner.play();

  @override
  @mustCallSuper
  Future<void> playFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) =>
      _inner.playFromMediaId(mediaId, extras);

  @override
  @mustCallSuper
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) =>
      _inner.playFromSearch(query, extras);

  @override
  @mustCallSuper
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]) =>
      _inner.playFromUri(uri, extras);

  @override
  @mustCallSuper
  Future<void> playMediaItem(MediaItem mediaItem) =>
      _inner.playMediaItem(mediaItem);

  @override
  @mustCallSuper
  Future<void> pause() => _inner.pause();

  @override
  @mustCallSuper
  Future<void> click([MediaButton button = MediaButton.media]) =>
      _inner.click(button);

  @override
  @mustCallSuper
  Future<void> stop() => _inner.stop();

  @override
  @mustCallSuper
  Future<void> addQueueItem(MediaItem mediaItem) =>
      _inner.addQueueItem(mediaItem);

  @override
  @mustCallSuper
  Future<void> addQueueItems(List<MediaItem> mediaItems) =>
      _inner.addQueueItems(mediaItems);

  @override
  @mustCallSuper
  Future<void> insertQueueItem(int index, MediaItem mediaItem) =>
      _inner.insertQueueItem(index, mediaItem);

  @override
  @mustCallSuper
  Future<void> updateQueue(List<MediaItem> queue) => _inner.updateQueue(queue);

  @override
  @mustCallSuper
  Future<void> updateMediaItem(MediaItem mediaItem) =>
      _inner.updateMediaItem(mediaItem);

  @override
  @mustCallSuper
  Future<void> removeQueueItem(MediaItem mediaItem) =>
      _inner.removeQueueItem(mediaItem);

  @override
  @mustCallSuper
  Future<void> removeQueueItemAt(int index) => _inner.removeQueueItemAt(index);

  @override
  @mustCallSuper
  Future<void> skipToNext() => _inner.skipToNext();

  @override
  @mustCallSuper
  Future<void> skipToPrevious() => _inner.skipToPrevious();

  @override
  @mustCallSuper
  Future<void> fastForward() => _inner.fastForward();

  @override
  @mustCallSuper
  Future<void> rewind() => _inner.rewind();

  @override
  @mustCallSuper
  Future<void> skipToQueueItem(int index) => _inner.skipToQueueItem(index);

  @override
  @mustCallSuper
  Future<void> seek(Duration position) => _inner.seek(position);

  @override
  @mustCallSuper
  Future<void> setRating(Rating rating, Map<String, dynamic>? extras) =>
      _inner.setRating(rating, extras);

  @override
  @mustCallSuper
  Future<void> setCaptioningEnabled(bool enabled) =>
      _inner.setCaptioningEnabled(enabled);

  @override
  @mustCallSuper
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _inner.setRepeatMode(repeatMode);

  @override
  @mustCallSuper
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _inner.setShuffleMode(shuffleMode);

  @override
  @mustCallSuper
  Future<void> seekBackward(bool begin) => _inner.seekBackward(begin);

  @override
  @mustCallSuper
  Future<void> seekForward(bool begin) => _inner.seekForward(begin);

  @override
  @mustCallSuper
  Future<void> setSpeed(double speed) => _inner.setSpeed(speed);

  @override
  @mustCallSuper
  Future<dynamic> customAction(String name, Map<String, dynamic>? extras) =>
      _inner.customAction(name, extras);

  @override
  @mustCallSuper
  Future<void> onTaskRemoved() => _inner.onTaskRemoved();

  @override
  @mustCallSuper
  Future<void> onNotificationDeleted() => _inner.onNotificationDeleted();

  @override
  @mustCallSuper
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic>? options]) =>
      _inner.getChildren(parentMediaId, options);

  @override
  @mustCallSuper
  ValueStream<Map<String, dynamic>?> subscribeToChildren(
          String parentMediaId) =>
      _inner.subscribeToChildren(parentMediaId);

  @override
  @mustCallSuper
  Future<MediaItem?> getMediaItem(String mediaId) =>
      _inner.getMediaItem(mediaId);

  @override
  @mustCallSuper
  Future<List<MediaItem>> search(String query,
          [Map<String, dynamic>? extras]) =>
      _inner.search(query, extras);

  @override
  @mustCallSuper
  Future<void> androidSetRemoteVolume(int volumeIndex) =>
      _inner.androidSetRemoteVolume(volumeIndex);

  @override
  @mustCallSuper
  Future<void> androidAdjustRemoteVolume(AndroidVolumeDirection direction) =>
      _inner.androidAdjustRemoteVolume(direction);

  @override
  ValueStream<PlaybackState> get playbackState => _inner.playbackState;

  @override
  ValueStream<List<MediaItem>?> get queue => _inner.queue;

  @override
  ValueStream<String> get queueTitle => _inner.queueTitle;

  @override
  ValueStream<MediaItem?> get mediaItem => _inner.mediaItem;

  @override
  ValueStream<RatingStyle> get ratingStyle => _inner.ratingStyle;

  @override
  ValueStream<AndroidPlaybackInfo> get androidPlaybackInfo =>
      _inner.androidPlaybackInfo;

  @override
  Stream<dynamic> get customEvent => _inner.customEvent;

  @override
  ValueStream<dynamic> get customState => _inner.customState;
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
  final BehaviorSubject<dynamic> customState = BehaviorSubject<dynamic>();

  _IsolateAudioHandler() : super._() {
    _platform.setClientCallbacks(_ClientCallbacks(this));
  }

  @override
  Future<void> prepare() => _send('prepare');

  @override
  Future<void> prepareFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) =>
      _send('prepareFromMediaId', <dynamic>[mediaId, extras]);

  @override
  Future<void> prepareFromSearch(String query,
          [Map<String, dynamic>? extras]) =>
      _send('prepareFromSearch', <dynamic>[query, extras]);

  @override
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic>? extras]) =>
      _send('prepareFromUri', <dynamic>[uri, extras]);

  @override
  Future<void> play() => _send('play');

  @override
  Future<void> playFromMediaId(String mediaId,
          [Map<String, dynamic>? extras]) =>
      _send('playFromMediaId', <dynamic>[mediaId, extras]);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) =>
      _send('playFromSearch', <dynamic>[query, extras]);

  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]) =>
      _send('playFromUri', <dynamic>[uri, extras]);

  @override
  Future<void> playMediaItem(MediaItem mediaItem) =>
      _send('playMediaItem', <dynamic>[mediaItem]);

  @override
  Future<void> pause() => _send('pause');

  @override
  Future<void> click([MediaButton button = MediaButton.media]) =>
      _send('click', <dynamic>[button]);

  @override
  @mustCallSuper
  Future<void> stop() => _send('stop');

  @override
  Future<void> addQueueItem(MediaItem mediaItem) =>
      _send('addQueueItem', <dynamic>[mediaItem]);

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) =>
      _send('addQueueItems', <dynamic>[mediaItems]);

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) =>
      _send('insertQueueItem', <dynamic>[index, mediaItem]);

  @override
  Future<void> updateQueue(List<MediaItem> queue) =>
      _send('updateQueue', <dynamic>[queue]);

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) =>
      _send('updateMediaItem', <dynamic>[mediaItem]);

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) =>
      _send('removeQueueItem', <dynamic>[mediaItem]);

  @override
  Future<void> removeQueueItemAt(int index) =>
      _send('removeQueueItemAt', <dynamic>[index]);

  @override
  Future<void> skipToNext() => _send('skipToNext');

  @override
  Future<void> skipToPrevious() => _send('skipToPrevious');

  @override
  Future<void> fastForward() => _send('fastForward');

  @override
  Future<void> rewind() => _send('rewind');

  @override
  Future<void> skipToQueueItem(int index) =>
      _send('skipToQueueItem', <dynamic>[index]);

  @override
  Future<void> seek(Duration position) => _send('seek', <dynamic>[position]);

  @override
  Future<void> setRating(Rating rating, Map<String, dynamic>? extras) =>
      _send('setRating', <dynamic>[rating, extras]);

  @override
  Future<void> setCaptioningEnabled(bool enabled) =>
      _send('setCaptioningEnabled', <dynamic>[enabled]);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      _send('setRepeatMode', <dynamic>[repeatMode]);

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      _send('setShuffleMode', <dynamic>[shuffleMode]);

  @override
  Future<void> seekBackward(bool begin) =>
      _send('seekBackward', <dynamic>[begin]);

  @override
  Future<void> seekForward(bool begin) =>
      _send('seekForward', <dynamic>[begin]);

  @override
  Future<void> setSpeed(double speed) => _send('setSpeed', <dynamic>[speed]);

  @override
  Future<dynamic> customAction(String name, Map<String, dynamic>? arguments) =>
      _send('customAction', <dynamic>[name, arguments]);

  @override
  Future<void> onTaskRemoved() => _send('onTaskRemoved');

  @override
  Future<void> onNotificationDeleted() => _send('onNotificationDeleted');

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic>? options]) async =>
      (await _send('getChildren', <dynamic>[parentMediaId, options]))
          as List<MediaItem>;

  @override
  ValueStream<Map<String, dynamic>?> subscribeToChildren(String parentMediaId) {
    var childrenSubject = _childrenSubjects[parentMediaId];
    if (childrenSubject == null) {
      childrenSubject = _childrenSubjects[parentMediaId] = BehaviorSubject();
      final receivePort = ReceivePort();
      receivePort.listen((dynamic options) {
        childrenSubject!.add(options as Map<String, dynamic>?);
      });
      _send('subscribeToChildren',
          <dynamic>[parentMediaId, receivePort.sendPort]);
    }
    return childrenSubject;
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async =>
      (await _send('getMediaItem', <dynamic>[mediaId])) as MediaItem?;

  @override
  Future<List<MediaItem>> search(String query,
          [Map<String, dynamic>? extras]) async =>
      (await _send('search', <dynamic>[query, extras])) as List<MediaItem>;

  @override
  Future<void> androidAdjustRemoteVolume(AndroidVolumeDirection direction) =>
      _send('androidAdjustRemoteVolume', <dynamic>[direction]);

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) =>
      _send('androidSetRemoteVolume', <dynamic>[volumeIndex]);

  Future<dynamic> _send(String method, [List<dynamic>? arguments]) async {
    final sendPort = IsolateNameServer.lookupPortByName(_isolatePortName);
    if (sendPort == null) return null;
    final receivePort = ReceivePort();
    sendPort.send(_IsolateRequest(receivePort.sendPort, method, arguments));
    final dynamic result = await receivePort.first;
    print("isolate result received: $result");
    receivePort.close();
    return result;
  }
}

/// Base class for implementations of [AudioHandler]. It provides default
/// implementations of all methods and provides controllers for holding playback state and
/// broadcasting it as stream events.
///
/// These are [BehaviorSubject]s provided by this class:
///
/// * [playbackState]
/// * [queue]
/// * [queueTitle]
/// * [androidPlaybackInfo]
/// * [ratingStyle]
///
/// Besides them, there's also [customEventSubject] that is a [PublishSubject]
/// that emits events to [customEvent].
///
/// You can choose to implement all methods yourself, or you may leverage some
/// mixins to provide default implementations of certain behaviours:
///
/// * [QueueHandler] provides default implementations of methods for updating
/// and navigating the queue.
/// * [SeekHandler] provides default implementations of methods for seeking
/// forwards and backwards.
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
class BaseAudioHandler extends AudioHandler {
  /// A controller for broadcasting the current [PlaybackState] to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// playbackState.add(playbackState.copyWith(playing: true));
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<PlaybackState> playbackState =
      BehaviorSubject.seeded(PlaybackState());

  /// A controller for broadcasting the current queue to the app's UI, media
  /// notification and other clients. Example usage:
  ///
  /// ```dart
  /// queue.add(queue + [additionalItem]);
  /// ```
  @override
  final BehaviorSubject<List<MediaItem>?> queue =
      BehaviorSubject.seeded(<MediaItem>[]);

  /// A controller for broadcasting the current queue title to the app's UI, media
  /// notification and other clients. Example usage:
  ///
  /// ```dart
  /// queueTitle.add(newTitle);
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<String> queueTitle = BehaviorSubject.seeded('');

  /// A controller for broadcasting the current media item to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// mediaItem.add(item);
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<MediaItem?> mediaItem = BehaviorSubject.seeded(null);

  /// A controller for broadcasting the current [AndroidPlaybackInfo] to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// androidPlaybackInfo.add(newPlaybackInfo);
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<AndroidPlaybackInfo> androidPlaybackInfo =
      BehaviorSubject();

  /// A controller for broadcasting the current rating style to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// ratingStyle.add(item);
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<RatingStyle> ratingStyle = BehaviorSubject();

  /// A controller for broadcasting a custom event to the app's UI.
  /// A shorthand for the event stream is [customEvent].
  /// Example usage:
  ///
  /// ```dart
  /// customEventSubject.add(MyCustomEvent(arg: 3));
  /// ```
  @protected
  // ignore: close_sinks
  final customEventSubject = PublishSubject<dynamic>();

  /// A controller for broadcasting the current custom state to the app's UI.
  /// Example usage:
  ///
  /// ```dart
  /// customState.add(MyCustomState(...));
  /// ```
  @override
  // ignore: close_sinks
  final BehaviorSubject<dynamic> customState = BehaviorSubject<dynamic>();

  BaseAudioHandler() : super._();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {}

  @override
  Future<void> prepareFromSearch(String query,
      [Map<String, dynamic>? extras]) async {}

  @override
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic>? extras]) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {}

  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {}

  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]) async {}

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (playbackState.value?.playing == true) {
          await pause();
        } else {
          await play();
        }
        break;
      case MediaButton.next:
        await skipToNext();
        break;
      case MediaButton.previous:
        await skipToPrevious();
        break;
    }
  }

  @override
  @mustCallSuper
  Future<void> stop() async {
    await AudioService._stop();
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {}

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {}

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {}

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {}

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {}

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {}

  @override
  Future<void> removeQueueItemAt(int index) async {}

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  @override
  Future<void> fastForward() async {}

  @override
  Future<void> rewind() async {}

  @override
  Future<void> skipToQueueItem(int index) async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRating(Rating rating, Map<String, dynamic>? extras) async {}

  @override
  Future<void> setCaptioningEnabled(bool enabled) async {}

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {}

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {}

  @override
  Future<void> seekBackward(bool begin) async {}

  @override
  Future<void> seekForward(bool begin) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<dynamic> customAction(
      String name, Map<String, dynamic>? arguments) async {}

  @override
  Future<void> onTaskRemoved() async {}

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic>? options]) async =>
      [];

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) =>
      BehaviorSubject.seeded(<String, dynamic>{});

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async => null;

  @override
  Future<List<MediaItem>> search(String query,
          [Map<String, dynamic>? extras]) async =>
      [];

  @override
  Future<void> androidAdjustRemoteVolume(
      AndroidVolumeDirection direction) async {}

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) async {}

  @override
  Stream<dynamic> get customEvent => customEventSubject.stream;
}

/// This mixin provides default implementations of [fastForward], [rewind],
/// [seekForward] and [seekBackward] which are all defined in terms of your own
/// implementation of [seek].
mixin SeekHandler on BaseAudioHandler {
  _Seeker? _seeker;

  @override
  Future<void> fastForward() =>
      _seekRelative(AudioService.config.fastForwardInterval);

  @override
  Future<void> rewind() => _seekRelative(-AudioService.config.rewindInterval);

  @override
  Future<void> seekForward(bool begin) async => _seekContinuously(begin, 1);

  @override
  Future<void> seekBackward(bool begin) async => _seekContinuously(begin, -1);

  /// Jumps away from the current position by [offset].
  Future<void> _seekRelative(Duration offset) async {
    var newPosition = playbackState.value!.position + offset;
    // Make sure we don't jump out of bounds.
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    final duration = mediaItem.value?.duration ?? Duration.zero;
    if (newPosition > duration) {
      newPosition = duration;
    }
    // Perform the jump via a seek.
    await seek(newPosition);
  }

  /// Begins or stops a continuous seek in [direction]. After it begins it will
  /// continue seeking forward or backward by 10 seconds within the audio, at
  /// intervals of 1 second in app time.
  void _seekContinuously(bool begin, int direction) {
    _seeker?.stop();
    if (begin && mediaItem.value?.duration != null) {
      _seeker = _Seeker(this, Duration(seconds: 10 * direction),
          Duration(seconds: 1), mediaItem.value!.duration!)
        ..start();
    }
  }
}

class _Seeker {
  final AudioHandler handler;
  final Duration positionInterval;
  final Duration stepInterval;
  final Duration duration;
  bool _running = false;

  _Seeker(
    this.handler,
    this.positionInterval,
    this.stepInterval,
    this.duration,
  );

  Future<void> start() async {
    _running = true;
    while (_running) {
      var newPosition =
          handler.playbackState.value!.position + positionInterval;
      if (newPosition < Duration.zero) newPosition = Duration.zero;
      if (newPosition > duration) newPosition = duration;
      handler.seek(newPosition);
      await Future<void>.delayed(stepInterval);
    }
  }

  void stop() {
    _running = false;
  }
}

/// This mixin provides default implementations of methods for updating and
/// navigating the queue. When using this mixin, you must add a list of
/// [MediaItem]s to [queue], override [skipToQueueItem] and initialise the queue
/// index (e.g. by calling [skipToQueueItem] with the initial queue index). The
/// [skipToNext] and [skipToPrevious] default implementations are defined by
/// this mixin in terms of your own implementation of [skipToQueueItem].
mixin QueueHandler on BaseAudioHandler {
  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    queue.add(queue.value!..add(mediaItem));
    await super.addQueueItem(mediaItem);
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    queue.add(queue.value!..addAll(mediaItems));
    await super.addQueueItems(mediaItems);
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    queue.add(queue.value!..insert(index, mediaItem));
    await super.insertQueueItem(index, mediaItem);
  }

  @override
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    queue.add(queue.value!..replaceRange(0, queue.value!.length, newQueue));
    await super.updateQueue(newQueue);
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    queue.add(queue.value!..[queue.value!.indexOf(mediaItem)] = mediaItem);
    await super.updateMediaItem(mediaItem);
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    queue.add(queue.value!..remove(mediaItem));
    await super.removeQueueItem(mediaItem);
  }

  @override
  Future<void> skipToNext() async {
    await _skip(1);
    await super.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await _skip(-1);
    await super.skipToPrevious();
  }

  /// This should be overridden to skip to the queue item at [index].
  /// Implementations should broadcast the new queue index via [playbackState],
  /// broadcast the new media item via [mediaItem], and potentially issue
  /// instructions to start the new item playing. Some implementations may
  /// choose to automatically play when skipping to a queue item while others
  /// may prefer to play the new item only if the player was already playing
  /// another item beforehand.
  ///
  /// An example implementation may look like:
  ///
  /// ```dart
  /// playbackState.add(playbackState.value!.copyWith(queueIndex: index));
  /// mediaItem.add(queue.value![index]);
  /// player.playAtIndex(index); // use your player's respective API
  /// await super.skipToQueueItem(index);
  /// ```
  @override
  Future<void> skipToQueueItem(int index) async {
    await super.skipToQueueItem(index);
  }

  Future<void> _skip(int offset) async {
    final queue = this.queue.value!;
    final index = playbackState.value!.queueIndex!;
    if (index < 0 || index >= queue.length) return;
    return skipToQueueItem(index + offset);
  }
}

/// The available shuffle modes for the queue.
enum AudioServiceShuffleMode { none, all, group }

/// The available repeat modes.
///
/// This defines how media items should repeat when the current one is finished.
enum AudioServiceRepeatMode {
  /// The current media item or queue will not repeat.
  none,

  /// The current media item will repeat.
  one,

  /// Playback will continue looping through all media items in the current list.
  all,

  /// UNIMPLEMENTED - see https://github.com/ryanheise/audio_service/issues/560
  ///
  /// This corresponds to Android's [REPEAT_MODE_GROUP](https://developer.android.com/reference/androidx/media2/common/SessionPlayer#REPEAT_MODE_GROUP).
  ///
  /// This could represent a playlist that is a smaller subset of all media items.
  group,
}

/// The configuration options to use when intializing the [AudioService].
class AudioServiceConfig {
  // TODO: either fix, or remove this https://github.com/ryanheise/audio_service/issues/638
  final bool androidResumeOnClick;

  // A name of the media notification channel, that is
  // visible to user in settings of your app.
  final String androidNotificationChannelName;

  // A description of the media notification channel, that is
  // visible to user in settings of your app.
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

  /// Whether the application activity will be opened on click on notification.
  final bool androidNotificationClickStartsActivity;

  /// Whether the notification can be swiped away.
  ///
  /// If you set this to true, [androidStopForegroundOnPause] must be true as well,
  /// otherwise this will not do anything, because when foreground service is active,
  /// it forces notification to be ongoing.
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

  /// By default artworks are loaded only when the item is fed into [AudioHandler.mediaItem].
  ///
  /// If set to `true`, artworks for items start loading as soon as they are added to
  /// [AudioHandler.queue].
  final bool preloadArtwork;

  /// Extras to report on Android in response to an `onGetRoot` request.
  final Map<String, dynamic>? androidBrowsableRootExtras;

  const AudioServiceConfig({
    this.androidResumeOnClick = true,
    this.androidNotificationChannelName = 'Notifications',
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
        assert(rewindInterval > Duration.zero),
        assert(
          !androidNotificationOngoing || androidStopForegroundOnPause,
          'The androidNotificationOngoing will make no effect with androidStopForegroundOnPause set to false',
        );

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

/// (Maybe) temporary.
extension AudioServiceValueStream<T> on ValueStream<T> {
  @Deprecated('Use "this" instead. Will be removed before the release')
  ValueStream<T> get stream => this;
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
  Rating toPlugin() => Rating._(RatingStyle.values[type.index], value);
}

extension AndroidVolumeDirectionMessageExtension
    on AndroidVolumeDirectionMessage {
  AndroidVolumeDirection toPlugin() => AndroidVolumeDirection.values[index]!;
}

extension MediaButtonMessageExtension on MediaButtonMessage {
  MediaButton toPlugin() => MediaButton.values[index];
}

class AndroidVolumeDirection {
  static final lower = AndroidVolumeDirection(-1);
  static final same = AndroidVolumeDirection(0);
  static final raise = AndroidVolumeDirection(1);
  static final values = <int, AndroidVolumeDirection>{
    -1: lower,
    0: same,
    1: raise,
  };
  final int index;

  AndroidVolumeDirection(this.index);

  @override
  String toString() => '$index';
}

enum AndroidVolumeControlType { fixed, relative, absolute }

abstract class AndroidPlaybackInfo {
  AndroidPlaybackInfoMessage _toMessage();

  @override
  String toString() => '${_toMessage().toMap()}';
}

class RemoteAndroidPlaybackInfo extends AndroidPlaybackInfo {
  //final AndroidAudioAttributes audioAttributes;
  final AndroidVolumeControlType volumeControlType;
  final int maxVolume;
  final int volume;

  RemoteAndroidPlaybackInfo({
    required this.volumeControlType,
    required this.maxVolume,
    required this.volume,
  });

  AndroidPlaybackInfo copyWith({
    AndroidVolumeControlType? volumeControlType,
    int? maxVolume,
    int? volume,
  }) =>
      RemoteAndroidPlaybackInfo(
        volumeControlType: volumeControlType ?? this.volumeControlType,
        maxVolume: maxVolume ?? this.maxVolume,
        volume: volume ?? this.volume,
      );

  @override
  RemoteAndroidPlaybackInfoMessage _toMessage() =>
      RemoteAndroidPlaybackInfoMessage(
        volumeControlType:
            AndroidVolumeControlTypeMessage.values[volumeControlType.index],
        maxVolume: maxVolume,
        volume: volume,
      );
}

class LocalAndroidPlaybackInfo extends AndroidPlaybackInfo {
  @override
  LocalAndroidPlaybackInfoMessage _toMessage() =>
      const LocalAndroidPlaybackInfoMessage();
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
  /// * [MediaAction.seek] (enable a seek bar)
  /// * [MediaAction.seekForward] (enable press-and-hold fast-forward control)
  /// * [MediaAction.seekBackward] (enable press-and-hold rewind control)
  ///
  /// In practice, iOS will treat all entries in [controls] and [systemActions]
  /// in the same way since you cannot customise the icons of controls in the
  /// Control Center. However, on Android, the distinction is important as clickable
  /// buttons in the notification require you to specify your own icon.
  ///
  /// Note that specifying [MediaAction.seek] in [systemActions] will enable
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
  /// this calculation is provided by [PlaybackState.position].
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
    final oldState = _handler.playbackState.value!;
    _handler.playbackState.add(PlaybackState(
      controls: controls ?? oldState.controls,
      systemActions: systemActions?.toSet() ?? oldState.systemActions,
      processingState: processingState ?? oldState.processingState,
      playing: playing ?? oldState.playing,
      updatePosition: position ?? oldState.position,
      bufferedPosition: bufferedPosition ?? oldState.bufferedPosition,
      speed: speed ?? oldState.speed,
      androidCompactActionIndices:
          androidCompactActions ?? oldState.androidCompactActionIndices,
      repeatMode: repeatMode ?? oldState.repeatMode,
      shuffleMode: shuffleMode ?? oldState.shuffleMode,
    ));
  }

  /// Sets the current queue and notifies all clients.
  static Future<void> setQueue(List<MediaItem> queue,
      {bool preloadArtwork = false}) async {
    if (preloadArtwork) {
      print(
        'WARNING: preloadArtwork is not enabled! '
        'This is deprecated and must be set via AudioService.init()',
      );
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
  /// [SendPort]/[ReceivePort] API. Please consult the relevant documentation for
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
        children: mediaItems.map((item) => item._toMessage()).toList());
  }

  @override
  Future<GetMediaItemResponse> getMediaItem(GetMediaItemRequest request) async {
    return GetMediaItemResponse(
        mediaItem: (await handler.getMediaItem(request.mediaId))?._toMessage());
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
          .map((item) => item._toMessage())
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
      {};

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
