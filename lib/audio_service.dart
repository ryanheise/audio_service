import 'dart:async';
import 'dart:io' show HttpOverrides;
import 'dart:isolate';
import 'dart:ui';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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

/// The different states during audio processing.
enum AudioProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
  error,
}

/// The playback state which includes a [playing] boolean state, a processing
/// state such as [AudioProcessingState.buffering], the playback position and
/// the currently enabled actions to be shown in the Android notification or the
/// iOS control center.
class PlaybackState {
  /// The audio processing state e.g. [BasicPlaybackState.buffering].
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
  final List<int> androidCompactActionIndices;

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
  final int errorCode;

  /// The error message when [processingState] is [AudioProcessingState.error].
  final String errorMessage;

  /// The current repeat mode.
  final AudioServiceRepeatMode repeatMode;

  /// The current shuffle mode.
  final AudioServiceShuffleMode shuffleMode;

  /// Whether captioning is enabled.
  final bool captioningEnabled;

  /// Creates a [PlaybackState] with given field values, and with [updateTime]
  /// defaulting to [DateTime.now()].
  PlaybackState({
    this.processingState = AudioProcessingState.idle,
    this.playing = false,
    this.controls = const [],
    this.androidCompactActionIndices,
    this.systemActions = const {},
    this.updatePosition = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    DateTime updateTime,
    this.errorCode,
    this.errorMessage,
    this.repeatMode = AudioServiceRepeatMode.none,
    this.shuffleMode = AudioServiceShuffleMode.none,
    this.captioningEnabled = false,
  })  : assert(processingState != null),
        assert(playing != null),
        assert(controls != null),
        assert(androidCompactActionIndices == null ||
            androidCompactActionIndices.length <= 3),
        assert(systemActions != null),
        assert(updatePosition != null),
        assert(bufferedPosition != null),
        assert(speed != null),
        assert(repeatMode != null),
        assert(shuffleMode != null),
        assert(captioningEnabled != null),
        this.updateTime = updateTime ?? DateTime.now();

  /// Creates a copy of this state with given fields replaced by new values,
  /// with [updateTime] set to [DateTime.now()], and unless otherwise replaced,
  /// with [updatePosition] set to [this.position]. [errorCode] and
  /// [errorMessage] will be set to null unless [processingState] is
  /// [AudioProcessingState.error].
  PlaybackState copyWith({
    AudioProcessingState processingState,
    bool playing,
    List<MediaControl> controls,
    List<int> androidCompactActionIndices,
    Set<MediaAction> systemActions,
    Duration updatePosition,
    Duration bufferedPosition,
    double speed,
    int errorCode,
    String errorMessage,
    AudioServiceRepeatMode repeatMode,
    AudioServiceShuffleMode shuffleMode,
  }) {
    processingState ??= this.processingState;
    return PlaybackState(
      processingState: processingState,
      playing: playing ?? this.playing,
      controls: controls ?? this.controls,
      androidCompactActionIndices:
          androidCompactActionIndices ?? this.androidCompactActionIndices,
      systemActions: systemActions ?? this.systemActions,
      updatePosition: updatePosition ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      errorCode: processingState != AudioProcessingState.error
          ? null
          : (errorCode ?? this.errorCode),
      errorMessage: processingState != AudioProcessingState.error
          ? null
          : (errorMessage ?? this.errorMessage),
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      captioningEnabled: captioningEnabled ?? this.captioningEnabled,
    );
  }

  /// The current playback position.
  Duration get position {
    if (playing && processingState == AudioProcessingState.ready) {
      return Duration(
          milliseconds: (updatePosition.inMilliseconds +
                  ((DateTime.now().millisecondsSinceEpoch -
                          updateTime.millisecondsSinceEpoch) *
                      (speed ?? 1.0)))
              .toInt());
    } else {
      return updatePosition;
    }
  }

  Map<String, dynamic> toJson() => {
        'processingState': processingState.index,
        'playing': playing,
        'controls': controls.map((control) => control.toJson()).toList(),
        'androidCompactActionIndices': androidCompactActionIndices,
        'systemActions': systemActions.map((action) => action.index).toList(),
        'updatePosition': updatePosition.inMilliseconds,
        'bufferedPosition': bufferedPosition.inMilliseconds,
        'speed': speed,
        'updateTime': updateTime.millisecondsSinceEpoch,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'repeatMode': repeatMode.index,
        'shuffleMode': shuffleMode.index,
        'captioningEnabled': captioningEnabled,
      };
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

  /// Creates a new heart rating.
  const Rating.newHeartRating(bool hasHeart)
      : this._internal(RatingStyle.heart, hasHeart);

  /// Creates a new percentage rating.
  factory Rating.newPercentageRating(double percent) {
    if (percent < 0 || percent > 100) throw ArgumentError();
    return Rating._internal(RatingStyle.percentage, percent);
  }

  /// Creates a new star rating.
  factory Rating.newStarRating(RatingStyle starRatingStyle, int starRating) {
    if (starRatingStyle != RatingStyle.range3stars &&
        starRatingStyle != RatingStyle.range4stars &&
        starRatingStyle != RatingStyle.range5stars) {
      throw ArgumentError();
    }
    if (starRating > starRatingStyle.index || starRating < 0)
      throw ArgumentError();
    return Rating._internal(starRatingStyle, starRating);
  }

  /// Creates a new thumb rating.
  const Rating.newThumbRating(bool isThumbsUp)
      : this._internal(RatingStyle.thumbUpDown, isThumbsUp);

  /// Creates a new unrated rating.
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

  /// Creates a copy of this [MediaItem] with with the given fields replaced by
  /// new values.
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
    Map<String, dynamic> extras,
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

  Map<String, dynamic> toJson() => {
        'androidIcon': androidIcon,
        'label': label,
        'action': action.index,
      };
}

const MethodChannel _channel =
    const MethodChannel('ryanheise.com/audioService');

const MethodChannel _backgroundChannel =
    const MethodChannel('ryanheise.com/audioServiceBackground');

/// Provides an API to manage the app's [AudioHandler]. An app must call [init]
/// during initialisation to register the [AudioHandler] that will service all
/// requests to play audio.
class AudioService {
  /// The cache to use when loading artwork. Defaults to [DefaultCacheManager].
  static BaseCacheManager get cacheManager => _cacheManager;
  static BaseCacheManager _cacheManager;

  static AudioServiceConfig _config;
  static AudioHandler _handler;

  /// The current configuration.
  static AudioServiceConfig get config => _config;

  /// The root media ID for browsing media provided by the background
  /// task.
  static const String browsableRootId = 'root';

  /// The root media ID for browsing the most recently played item(s).
  static const String recentRootId = 'recent';

  static final _notificationSubject = BehaviorSubject<bool>.seeded(false);

  /// A stream that broadcasts the status of the notificationClick event.
  static Stream<bool> get notificationClickEventStream =>
      _notificationSubject.stream;

  /// The status of the notificationClick event.
  static bool get notificationClickEvent => _notificationSubject.value;

  static BehaviorSubject<Duration> _positionSubject;

  static ReceivePort _customEventReceivePort;

  /// Connect to the [AudioHandler] from another isolate. The [AudioHandler]
  /// must have been initialised via [init] prior to connecting.
  static Future<AudioHandler> connectFromIsolate() async {
    WidgetsFlutterBinding.ensureInitialized();
    return _ClientAudioHandler(_IsolateAudioHandler());
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
  static Future<AudioHandler> init({
    @required AudioHandler builder(),
    AudioServiceConfig config,
    BaseCacheManager cacheManager,
  }) async {
    config ??= AudioServiceConfig();
    print("### AudioService.init");
    WidgetsFlutterBinding.ensureInitialized();
    _cacheManager = cacheManager ?? DefaultCacheManager();
    final methodHandler = (MethodCall call) async {
      print("### UI received ${call.method}");
      switch (call.method) {
        case 'notificationClicked':
          _notificationSubject.add(call.arguments[0]);
          break;
      }
    };
    if (_testing) {
      MethodChannel('ryanheise.com/audioServiceInverse')
          .setMockMethodCallHandler(methodHandler);
    } else {
      _channel.setMethodCallHandler(methodHandler);
    }
    await _channel.invokeMethod('configure', config.toJson());
    final _impl = await _register(
      builder: builder,
      config: config,
    );
    final client = _ClientAudioHandler(_impl);
    return client;
  }

  static Future<AudioHandler> _register({
    @required AudioHandler builder(),
    AudioServiceConfig config,
  }) async {
    config ??= AudioServiceConfig();
    assert(_config == null && _handler == null);
    print("### AudioServiceBackground._register");
    _config = config;
    _handler = builder();
    final methodHandler = (MethodCall call) async {
      print('### background received ${call.method}');
      try {
        switch (call.method) {
          case 'onLoadChildren':
            final mediaItems = await _onLoadChildren(call.arguments[0]);
            List<Map> rawMediaItems =
                mediaItems.map((item) => item.toJson()).toList();
            return rawMediaItems as dynamic;
          case 'onLoadItem':
            return (await _handler.getMediaItem(call.arguments[0])).toJson();
          case 'onClick':
            return _handler.click(MediaButton.values[call.arguments[0]]);
          case 'onStop':
            return _handler.stop();
          case 'onPause':
            return _handler.pause();
          case 'onPrepare':
            return _handler.prepare();
          case 'onPrepareFromMediaId':
            return _handler.prepareFromMediaId(
                call.arguments[0], _castMap(call.arguments[1]));
          case 'onPrepareFromSearch':
            return _handler.prepareFromSearch(
                call.arguments[0], _castMap(call.arguments[1]));
          case 'onPrepareFromUri':
            return _handler.prepareFromUri(
                Uri.parse(call.arguments[0]), _castMap(call.arguments[1]));
          case 'onPlay':
            return _handler.play();
          case 'onPlayFromMediaId':
            return _handler.playFromMediaId(
                call.arguments[0], _castMap(call.arguments[1]));
          case 'onPlayFromSearch':
            return _handler.playFromSearch(
                call.arguments[0], _castMap(call.arguments[1]));
          case 'onPlayFromUri':
            return _handler.playFromUri(
                Uri.parse(call.arguments[0]), _castMap(call.arguments[1]));
          case 'onPlayMediaItem':
            return _handler
                .playMediaItem(MediaItem.fromJson(call.arguments[0]));
          case 'onAddQueueItem':
            return _handler.addQueueItem(MediaItem.fromJson(call.arguments[0]));
          case 'onAddQueueItemAt':
            final List args = call.arguments;
            MediaItem mediaItem = MediaItem.fromJson(args[0]);
            int index = args[1];
            return _handler.insertQueueItem(index, mediaItem);
          case 'onUpdateQueue':
            final List args = call.arguments;
            final List queue = args[0];
            return _handler.updateQueue(
                queue?.map((raw) => MediaItem.fromJson(raw))?.toList());
          case 'onUpdateMediaItem':
            return _handler
                .updateMediaItem(MediaItem.fromJson(call.arguments[0]));
          case 'onRemoveQueueItem':
            return _handler
                .removeQueueItem(MediaItem.fromJson(call.arguments[0]));
          case 'onRemoveQueueItemAt':
            return _handler.removeQueueItemAt(call.arguments[0]);
          case 'onSkipToNext':
            return _handler.skipToNext();
          case 'onSkipToPrevious':
            return _handler.skipToPrevious();
          case 'onFastForward':
            return _handler.fastForward(_config.fastForwardInterval);
          case 'onRewind':
            return _handler.rewind(_config.rewindInterval);
          case 'onSkipToQueueItem':
            return _handler.skipToQueueItem(call.arguments[0]);
          case 'onSeekTo':
            return _handler.seek(Duration(milliseconds: call.arguments[0]));
          case 'onSetRepeatMode':
            return _handler.setRepeatMode(
                AudioServiceRepeatMode.values[call.arguments[0]]);
          case 'onSetShuffleMode':
            return _handler.setShuffleMode(
                AudioServiceShuffleMode.values[call.arguments[0]]);
          case 'onSetRating':
            return _handler.setRating(
                Rating._fromRaw(call.arguments[0]), call.arguments[1]);
          case 'onSetCaptioningEnabled':
            return _handler.setCaptioningEnabled(call.arguments[0]);
          case 'onSeekBackward':
            return _handler.seekBackward(call.arguments[0]);
          case 'onSeekForward':
            return _handler.seekForward(call.arguments[0]);
          case 'onSetSpeed':
            return _handler.setSpeed(call.arguments[0]);
          case 'onSetVolumeTo':
            return _handler.androidSetRemoteVolume(call.arguments[0]);
          case 'onAdjustVolume':
            return _handler.androidAdjustRemoteVolume(
                AndroidVolumeDirection.values[call.arguments[0]]);
          case 'onTaskRemoved':
            return _handler.onTaskRemoved();
          case 'onClose':
            return _handler.onNotificationDeleted();
          case 'onCustomAction':
            return _handler.customAction(
                call.arguments[0], _castMap(call.arguments[1]));
          default:
            throw PlatformException(code: 'Unimplemented');
        }
      } catch (e, stacktrace) {
        print('$stacktrace');
        throw PlatformException(code: '$e');
      }
    };
    // Mock method call handlers only work in one direction so we need to set up
    // a separate channel for each direction when testing.
    if (_testing) {
      MethodChannel('ryanheise.com/audioServiceBackgroundInverse')
          .setMockMethodCallHandler(methodHandler);
    } else {
      _backgroundChannel.setMethodCallHandler(methodHandler);
    }
    // This port listens to connections from other isolates.
    _customEventReceivePort = ReceivePort();
    _customEventReceivePort.listen((event) async {
      final request = event as _IsolateRequest;
      switch (request.method) {
        case 'play':
          await _handler.play();
          request.sendPort.send(null);
          break;
      }
    });
    //IsolateNameServer.removePortNameMapping(_isolatePortName);
    IsolateNameServer.registerPortWithName(
        _customEventReceivePort.sendPort, _isolatePortName);
    _handler.mediaItem.stream.listen((mediaItem) async {
      if (mediaItem == null) return;
      if (mediaItem.artUri != null) {
        // We potentially need to fetch the art.
        String filePath = _getLocalPath(mediaItem.artUri);
        if (filePath == null) {
          final fileInfo = cacheManager.getFileFromMemory(mediaItem.artUri);
          filePath = fileInfo?.file?.path;
          if (filePath == null) {
            // We haven't fetched the art yet, so show the metadata now, and again
            // after we load the art.
            await _backgroundChannel.invokeMethod(
                'setMediaItem', mediaItem.toJson());
            // Load the art
            filePath = await _loadArtwork(mediaItem);
            // If we failed to download the art, abort.
            if (filePath == null) return;
          }
        }
        final extras = Map.of(mediaItem.extras ?? <String, dynamic>{});
        extras['artCacheFile'] = filePath;
        final platformMediaItem = mediaItem.copyWith(extras: extras);
        // Show the media item after the art is loaded.
        await _backgroundChannel.invokeMethod(
            'setMediaItem', platformMediaItem.toJson());
      } else {
        await _backgroundChannel.invokeMethod(
            'setMediaItem', mediaItem.toJson());
      }
    });
    _handler.androidPlaybackInfo.stream.listen((playbackInfo) async {
      await _backgroundChannel.invokeMethod(
          'setPlaybackInfo', playbackInfo.toJson());
    });
    _handler.queue.stream.listen((queue) async {
      if (queue == null) return;
      if (_config.preloadArtwork) {
        _loadAllArtwork(queue);
      }
      await _backgroundChannel.invokeMethod(
          'setQueue', queue.map((item) => item.toJson()).toList());
    });
    _handler.playbackState.stream.listen((playbackState) async {
      await _backgroundChannel.invokeMethod('setState', playbackState.toJson());
    });

    return _handler;
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
    Duration duration() => _handler.mediaItem?.value?.duration ?? Duration.zero;
    Duration step() {
      var s = duration() ~/ steps;
      if (s < minPeriod) s = minPeriod;
      if (s > maxPeriod) s = maxPeriod;
      return s;
    }

    void yieldPosition(Timer timer) {
      if (last != _handler.playbackState?.value?.position) {
        controller.add(last = _handler.playbackState?.value?.position);
      }
    }

    controller = StreamController.broadcast(
      sync: true,
      onListen: () {
        mediaItemSubscription = _handler.mediaItem.stream.listen((mediaItem) {
          // Potentially a new duration
          currentTimer?.cancel();
          currentTimer = Timer.periodic(step(), yieldPosition);
        });
        playbackStateSubscription =
            _handler.playbackState.stream.listen((state) {
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
    await _backgroundChannel.invokeMethod('androidForceEnableMediaButtons');
  }

  /// Stops the service.
  static Future<void> _stop() async {
    final audioSession = await AudioSession.instance;
    try {
      await audioSession.setActive(false);
    } catch (e) {
      print("While deactivating audio session: $e");
    }
    await _backgroundChannel.invokeMethod('stopService');
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
          final file = await cacheManager.getSingleFile(mediaItem.artUri);
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

  static final _childrenStreams = <String, ValueStream<List<MediaItem>>>{};
  static Future<List<MediaItem>> _onLoadChildren(String parentMediaId) async {
    var childrenStream = _childrenStreams[parentMediaId];
    if (childrenStream == null) {
      childrenStream = _childrenStreams[parentMediaId] =
          _handler.getChildrenStream(parentMediaId);
      childrenStream.listen((children) {
        // Notify clients that the children of [parentMediaId] have changed.
        _backgroundChannel.invokeMethod('notifyChildrenChanged', parentMediaId);
      });
    }
    return _childrenStreams[parentMediaId].value;
  }
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
      [Map<String, dynamic> extras]);

  /// Prepare playback from a search query.
  Future<void> prepareFromSearch(String query, [Map<String, dynamic> extras]);

  /// Prepare a media item represented by a Uri for playback.
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic> extras]);

  /// Start or resume playback.
  Future<void> play();

  /// Play a specific media item.
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic> extras]);

  /// Begin playback from a search query.
  Future<void> playFromSearch(String query, [Map<String, dynamic> extras]);

  /// Play a media item represented by a Uri.
  Future<void> playFromUri(Uri uri, [Map<String, dynamic> extras]);

  /// Play a specific media item.
  Future<void> playMediaItem(MediaItem mediaItem);

  /// Pause playback.
  Future<void> pause();

  /// Process a headset button click, where [button] defaults to
  /// [MediaButton.media].
  Future<void> click([MediaButton button]);

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

  /// Remove at media item from the queue at the specified [index].
  Future<void> removeQueueItemAt(int index);

  /// Skip to the next item in the queue.
  Future<void> skipToNext();

  /// Skip to the previous item in the queue.
  Future<void> skipToPrevious();

  /// Jump forward by [interval], defaulting to
  /// [AudioServiceConfig.fastForwardInterval].
  Future<void> fastForward([Duration interval]);

  /// Jump backward by [interval], defaulting to
  /// [AudioServiceConfig.rewindInterval]. Note: this value must be positive.
  Future<void> rewind([Duration interval]);

  /// Skip to a media item.
  Future<void> skipToQueueItem(String mediaId);

  /// Seek to [position].
  Future<void> seek(Duration position);

  /// Set the rating.
  Future<void> setRating(Rating rating, Map<dynamic, dynamic> extras);

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
  Future<dynamic> customAction(String name, Map<String, dynamic> extras);

  /// Handle the task being swiped away in the task manager (Android).
  Future<void> onTaskRemoved();

  /// Handle the notification being swiped away (Android).
  Future<void> onNotificationDeleted();

  /// Get the children of a parent media item.
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic> options]);

  /// Get a value stream of the children of a parent media item.
  ValueStream<List<MediaItem>> getChildrenStream(String parentMediaId,
      [Map<String, dynamic> options]);

  /// Get a particular media item.
  Future<MediaItem> getMediaItem(String mediaId);

  /// Search for media items.
  Future<List<MediaItem>> search(String query, [Map<String, dynamic> extras]);

  /// Set the remote volume on Android. This works only when
  /// [AndroidPlaybackInfo.playbackType] is [AndroidPlaybackType.remote].
  Future<void> androidSetRemoteVolume(int volumeIndex);

  /// Adjust the remote volume on Android. This works only when
  /// [AndroidPlaybackInfo.playbackType] is [AndroidPlaybackType.remote].
  Future<void> androidAdjustRemoteVolume(AndroidVolumeDirection direction);

  /// A value stream of playback states.
  StreamableValue<PlaybackState> get playbackState;

  /// A value stream of the current queue.
  StreamableValue<List<MediaItem>> get queue;

  /// A value stream of the current queueTitle.
  StreamableValue<String> get queueTitle;

  /// A value stream of the current media item.
  StreamableValue<MediaItem> get mediaItem;

  /// A value stream of the current rating style.
  StreamableValue<RatingStyle> get ratingStyle;

  /// A value stream of the current [AndroidPlaybackInfo].
  StreamableValue<AndroidPlaybackInfo> get androidPlaybackInfo;

  /// A stream of custom events.
  Stream<dynamic> get customEventStream;

  /// A stream of custom states.
  StreamableValue<dynamic> get customState;
}

/// A [SwitchAudioHandler] wraps another [AudioHandler] that may be switched for
/// another at any time by setting [inner].
class SwitchAudioHandler extends CompositeAudioHandler {
  @override
  final StreamableValueSubject<PlaybackState> playbackState =
      StreamableValueSubject();
  @override
  final StreamableValueSubject<List<MediaItem>> queue =
      StreamableValueSubject();
  @override
  final StreamableValueSubject<String> queueTitle = StreamableValueSubject();
  @override
  final StreamableValueSubject<MediaItem> mediaItem = StreamableValueSubject();
  @override
  final StreamableValueSubject<AndroidPlaybackInfo> androidPlaybackInfo =
      StreamableValueSubject();
  @override
  final StreamableValueSubject<RatingStyle> ratingStyle =
      StreamableValueSubject();
  // ignore: close_sinks
  final _customEventSubject = PublishSubject<dynamic>();
  @override
  final StreamableValueSubject<dynamic> customState = StreamableValueSubject();

  StreamSubscription<PlaybackState> playbackStateSubscription;
  StreamSubscription<List<MediaItem>> queueSubscription;
  StreamSubscription<String> queueTitleSubscription;
  StreamSubscription<MediaItem> mediaItemSubscription;
  StreamSubscription<AndroidPlaybackInfo> androidPlaybackInfoSubscription;
  StreamSubscription<RatingStyle> ratingStyleSubscription;
  StreamSubscription<dynamic> customEventSubscription;
  StreamSubscription<dynamic> customStateSubscription;

  SwitchAudioHandler(AudioHandler inner) : super(inner) {
    this.inner = inner;
  }

  /// The current inner [AudioHandler] that this [SwitchAudioHandler] will
  /// delegate to.
  AudioHandler get inner => _inner;

  set inner(AudioHandler newInner) {
    assert(newInner != null && newInner != this);
    playbackStateSubscription?.cancel();
    queueSubscription?.cancel();
    queueTitleSubscription?.cancel();
    mediaItemSubscription?.cancel();
    androidPlaybackInfoSubscription?.cancel();
    ratingStyleSubscription?.cancel();
    customEventSubscription?.cancel();
    customStateSubscription?.cancel();
    _inner = newInner;
    playbackStateSubscription =
        inner.playbackState.stream.listen(playbackState.add);
    queueSubscription = inner.queue.stream.listen(queue.add);
    queueTitleSubscription = inner.queueTitle.stream.listen(queueTitle.add);
    mediaItemSubscription = inner.mediaItem.stream.listen(mediaItem.add);
    androidPlaybackInfoSubscription =
        inner.androidPlaybackInfo.stream.listen(androidPlaybackInfo.add);
    ratingStyleSubscription = inner.ratingStyle.stream.listen(ratingStyle.add);
    customEventSubscription =
        inner.customEventStream.listen(_customEventSubject.add);
    customStateSubscription = inner.customState.stream.listen(customState.add);
  }

  @override
  Stream<dynamic> get customEventStream => _customEventSubject;
}

/// A [CompositeAudioHandler] wraps another [AudioHandler] and adds additional
/// behaviour to it. Each method will by default pass through to the
/// corresponding method of the wrapped handler. If you override a method, it
/// must call super in addition to any "additional" functionality you add.
class CompositeAudioHandler extends AudioHandler {
  AudioHandler _inner;

  /// Create the [CompositeAudioHandler] with the given wrapped handler.
  CompositeAudioHandler(AudioHandler inner)
      : assert(inner != null),
        _inner = inner,
        super._();

  @override
  @mustCallSuper
  Future<void> prepare() => _inner.prepare();

  @override
  @mustCallSuper
  Future<void> prepareFromMediaId(String mediaId,
          [Map<String, dynamic> extras]) =>
      _inner.prepareFromMediaId(mediaId, extras);

  @override
  @mustCallSuper
  Future<void> prepareFromSearch(String query, [Map<String, dynamic> extras]) =>
      _inner.prepareFromSearch(query, extras);

  @override
  @mustCallSuper
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic> extras]) =>
      _inner.prepareFromUri(uri, extras);

  @override
  @mustCallSuper
  Future<void> play() => _inner.play();

  @override
  @mustCallSuper
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic> extras]) =>
      _inner.playFromMediaId(mediaId, extras);

  @override
  @mustCallSuper
  Future<void> playFromSearch(String query, [Map<String, dynamic> extras]) =>
      _inner.playFromSearch(query, extras);

  @override
  @mustCallSuper
  Future<void> playFromUri(Uri uri, [Map<String, dynamic> extras]) =>
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
  Future<void> click([MediaButton button]) => _inner.click(button);

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
  Future<void> fastForward([Duration interval]) => _inner.fastForward(interval);

  @override
  @mustCallSuper
  Future<void> rewind([Duration interval]) => _inner.rewind();

  @override
  @mustCallSuper
  Future<void> skipToQueueItem(String mediaId) =>
      _inner.skipToQueueItem(mediaId);

  @override
  @mustCallSuper
  Future<void> seek(Duration position) => _inner.seek(position);

  @override
  @mustCallSuper
  Future<void> setRating(Rating rating, Map<dynamic, dynamic> extras) =>
      _inner.setRating(rating, extras);

  @override
  @override
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
  Future<dynamic> customAction(String name, Map<String, dynamic> extras) =>
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
          [Map<String, dynamic> options]) =>
      _inner.getChildren(parentMediaId);

  @override
  @mustCallSuper
  ValueStream<List<MediaItem>> getChildrenStream(String parentMediaId,
          [Map<String, dynamic> options]) =>
      _inner.getChildrenStream(parentMediaId);

  @override
  @mustCallSuper
  Future<MediaItem> getMediaItem(String mediaId) =>
      _inner.getMediaItem(mediaId);

  @override
  @mustCallSuper
  Future<List<MediaItem>> search(String query, [Map<String, dynamic> extras]) =>
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
  StreamableValue<PlaybackState> get playbackState => _inner.playbackState;

  @override
  StreamableValue<List<MediaItem>> get queue => _inner.queue;

  @override
  StreamableValue<String> get queueTitle => _inner.queueTitle;

  @override
  StreamableValue<MediaItem> get mediaItem => _inner.mediaItem;

  @override
  StreamableValue<RatingStyle> get ratingStyle => _inner.ratingStyle;

  @override
  StreamableValue<AndroidPlaybackInfo> get androidPlaybackInfo =>
      _inner.androidPlaybackInfo;

  @override
  Stream<dynamic> get customEventStream => _inner.customEventStream;

  @override
  StreamableValue<dynamic> get customState => _inner.customState;
}

class _IsolateRequest {
  /// The send port for sending the response of this request.
  final SendPort sendPort;
  final String method;
  final List<dynamic> arguments;

  _IsolateRequest(this.sendPort, this.method, [this.arguments]);
}

const _isolatePortName = 'com.ryanheise.audioservice.port';

class _IsolateAudioHandler extends AudioHandler {
  @override
  final StreamableValueSubject<PlaybackState> playbackState =
      StreamableValueSubject.seeded(PlaybackState());
  @override
  final StreamableValueSubject<List<MediaItem>> queue =
      StreamableValueSubject.seeded(<MediaItem>[]);
  @override
  // TODO
  final StreamableValueSubject<String> queueTitle =
      StreamableValueSubject.seeded('');
  @override
  final StreamableValueSubject<MediaItem> mediaItem =
      StreamableValueSubject.seeded(null);
  @override
  // TODO
  final StreamableValueSubject<AndroidPlaybackInfo> androidPlaybackInfo =
      StreamableValueSubject();
  @override
  // TODO
  final StreamableValueSubject<RatingStyle> ratingStyle =
      StreamableValueSubject();
  // TODO
  // ignore: close_sinks
  final _customEventSubject = PublishSubject<dynamic>();
  @override
  // TODO
  final StreamableValueSubject<dynamic> customState = StreamableValueSubject();

  _IsolateAudioHandler() : super._() {
    final methodHandler = (MethodCall call) async {
      print("### client received ${call.method}");
      final List args = call.arguments;
      switch (call.method) {
        case 'onPlaybackStateChanged':
          int actionBits = args[2];
          playbackState.add(PlaybackState(
            processingState: AudioProcessingState.values[args[0]],
            playing: args[1],
            // We can't determine whether they are controls.
            systemActions: MediaAction.values
                .where((action) => (actionBits & (1 << action.index)) != 0)
                .toSet(),
            updatePosition: Duration(milliseconds: args[3]),
            bufferedPosition: Duration(milliseconds: args[4]),
            speed: args[5],
            updateTime: DateTime.fromMillisecondsSinceEpoch(args[6]),
            repeatMode: AudioServiceRepeatMode.values[args[7]],
            shuffleMode: AudioServiceShuffleMode.values[args[8]],
          ));
          break;
        case 'onMediaChanged':
          mediaItem.add(args[0] != null ? MediaItem.fromJson(args[0]) : null);
          break;
        case 'onQueueChanged':
          final List<Map> args = call.arguments[0] != null
              ? List<Map>.from(call.arguments[0])
              : null;
          queue.add(args?.map((raw) => MediaItem.fromJson(raw))?.toList());
          break;
      }
    };
    _channel.setMethodCallHandler(methodHandler);
  }

  @override
  Future<void> prepare() => _send('prepare');

  @override
  Future<void> prepareFromMediaId(String mediaId,
          [Map<String, dynamic> extras]) =>
      _send('prepareFromMediaId', [mediaId, extras]);

  @override
  Future<void> prepareFromSearch(String query, [Map<String, dynamic> extras]) =>
      _send('prepareFromSearch', [query, extras]);

  @override
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic> extras]) =>
      _send('prepareFromUri', [uri, extras]);

  @override
  Future<void> play() => _send('play');

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic> extras]) =>
      _send('playFromMediaId', [mediaId, extras]);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic> extras]) =>
      _send('playFromSearch', [query, extras]);

  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic> extras]) =>
      _send('playFromUri', [uri, extras]);

  @override
  Future<void> playMediaItem(MediaItem mediaItem) =>
      _send('playMediaItem', [mediaItem]);

  @override
  Future<void> pause() => _send('pause');

  @override
  Future<void> click([MediaButton button]) => _send('click', [button]);

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
  Future<void> fastForward([Duration interval]) =>
      _send('fastForward', [interval]);

  @override
  Future<void> rewind([Duration interval]) => _send('rewind', [interval]);

  @override
  Future<void> skipToQueueItem(String mediaId) =>
      _send('skipToQueueItem', [mediaId]);

  @override
  Future<void> seek(Duration position) => _send('seek', [position]);

  @override
  Future<void> setRating(Rating rating, Map<dynamic, dynamic> extras) =>
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
  Future<dynamic> customAction(String name, Map<String, dynamic> arguments) =>
      _send('customAction', [name, arguments]);

  @override
  Future<void> onTaskRemoved() => _send('onTaskRemoved');

  @override
  Future<void> onNotificationDeleted() => _send('onNotificationDeleted');

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic> options]) =>
      _send('getChildren', [parentMediaId, options]);

  // Not supported yet.
  @override
  ValueStream<List<MediaItem>> getChildrenStream(String parentMediaId,
          [Map<String, dynamic> options]) =>
      null;

  @override
  Future<MediaItem> getMediaItem(String mediaId) =>
      _send('getMediaItem', [mediaId]);

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic> extras]) =>
      _send('search', [query, extras]);

  @override
  Future<void> androidAdjustRemoteVolume(AndroidVolumeDirection direction) =>
      _send('androidAdjustRemoteVolume', [direction]);

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) =>
      _send('androidSetRemoteVolume', [volumeIndex]);

  @override
  Stream<dynamic> get customEventStream => _customEventSubject.stream;

  Future<dynamic> _send(String method, [List<dynamic> arguments]) async {
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

/// The implementation of [AudioHandler] that is provided to the app. It inserts
/// default parameter values for [click], [fastForward] and [rewind].
class _ClientAudioHandler extends CompositeAudioHandler {
  _ClientAudioHandler(AudioHandler impl) : super(impl);

  @override
  Future<void> click([MediaButton button]) async {
    await super.click(button ?? MediaButton.media);
  }

  @override
  Future<void> fastForward([Duration interval]) async {
    await super
        .fastForward(interval ?? AudioService.config.fastForwardInterval);
  }

  @override
  Future<void> rewind([Duration interval]) async {
    await super.rewind(interval ?? AudioService.config.rewindInterval);
  }
}

/// Base class for implementations of [AudioHandler]. It provides default
/// implementations of all methods and provides controllers for emitting stream
/// events:
///
/// * [playbackStateSubject] is a [BehaviorSubject] that emits events to
/// [playbackStateStream].
/// * [queueSubject] is a [BehaviorSubject] that emits events to [queueStream].
/// * [mediaItemSubject] is a [BehaviorSubject] that emits events to
/// [mediaItemStream].
/// * [customEventSubject] is a [PublishSubject] that emits events to
/// [customEventStream].
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
  final StreamableValueSubject<PlaybackState> playbackState =
      StreamableValueSubject.seeded(PlaybackState());

  /// A controller for broadcasting the current queue to the app's UI, media
  /// notification and other clients. Example usage:
  ///
  /// ```dart
  /// queue.add(queue + [additionalItem]);
  /// ```
  @override
  final StreamableValueSubject<List<MediaItem>> queue =
      StreamableValueSubject.seeded(<MediaItem>[]);

  /// A controller for broadcasting the current queue title to the app's UI, media
  /// notification and other clients. Example usage:
  ///
  /// ```dart
  /// queueTitle.add(newTitle);
  /// ```
  @override
  final StreamableValueSubject<String> queueTitle =
      StreamableValueSubject.seeded('');

  /// A controller for broadcasting the current media item to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// mediaItem.add(item);
  /// ```
  @override
  final StreamableValueSubject<MediaItem> mediaItem =
      StreamableValueSubject.seeded(null);

  /// A controller for broadcasting the current [AndroidPlaybackInfo] to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// androidPlaybackInfo.add(newPlaybackInfo);
  /// ```
  @override
  final StreamableValueSubject<AndroidPlaybackInfo> androidPlaybackInfo =
      StreamableValueSubject();

  /// A controller for broadcasting the current rating style to the app's UI,
  /// media notification and other clients. Example usage:
  ///
  /// ```dart
  /// ratingStyle.add(item);
  /// ```
  @override
  final StreamableValueSubject<RatingStyle> ratingStyle =
      StreamableValueSubject();

  /// A controller for broadcasting a custom event to the app's UI. Example
  /// usage:
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
  final StreamableValueSubject<dynamic> customState = StreamableValueSubject();

  BaseAudioHandler() : super._();

  @override
  Future<void> prepare() async {}

  @override
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic> extras]) async {}

  @override
  Future<void> prepareFromSearch(String query,
      [Map<String, dynamic> extras]) async {}

  @override
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic> extras]) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic> extras]) async {}

  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic> extras]) async {}

  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic> extras]) async {}

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> click([MediaButton button]) async {
    switch (button) {
      case MediaButton.media:
        if (playbackState?.value?.playing == true) {
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
  Future<void> fastForward([Duration interval]) async {}

  @override
  Future<void> rewind([Duration interval]) async {}

  @override
  Future<void> skipToQueueItem(String mediaId) async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRating(Rating rating, Map<dynamic, dynamic> extras) async {}

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
      String name, Map<String, dynamic> arguments) async {}

  @override
  Future<void> onTaskRemoved() async {}

  @override
  Future<void> onNotificationDeleted() async {
    await stop();
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
          [Map<String, dynamic> options]) async =>
      null;

  @override
  ValueStream<List<MediaItem>> getChildrenStream(String parentMediaId,
          [Map<String, dynamic> options]) =>
      null;

  @override
  Future<MediaItem> getMediaItem(String mediaId) => null;

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic> extras]) =>
      null;

  @override
  Future<void> androidAdjustRemoteVolume(
      AndroidVolumeDirection direction) async {}

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) async {}

  @override
  Stream<dynamic> get customEventStream => customEventSubject.stream;
}

/// This mixin provides default implementations of [fastForward], [rewind],
/// [seekForward] and [seekBackward] which are all defined in terms of your own
/// implementation of [seek].
mixin SeekHandler on BaseAudioHandler {
  _Seeker _seeker;

  @override
  Future<void> fastForward([Duration interval]) => _seekRelative(interval);

  @override
  Future<void> rewind([Duration interval]) => _seekRelative(-interval);

  @override
  Future<void> seekForward(bool begin) async => _seekContinuously(begin, 1);

  @override
  Future<void> seekBackward(bool begin) async => _seekContinuously(begin, -1);

  /// Jumps away from the current position by [offset].
  Future<void> _seekRelative(Duration offset) async {
    var newPosition = playbackState.value.position + offset;
    // Make sure we don't jump out of bounds.
    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }
    if (newPosition > mediaItem.value.duration) {
      newPosition = mediaItem.value.duration;
    }
    // Perform the jump via a seek.
    await seek(newPosition);
  }

  /// Begins or stops a continuous seek in [direction]. After it begins it will
  /// continue seeking forward or backward by 10 seconds within the audio, at
  /// intervals of 1 second in app time.
  void _seekContinuously(bool begin, int direction) {
    _seeker?.stop();
    if (begin) {
      _seeker = _Seeker(this, Duration(seconds: 10 * direction),
          Duration(seconds: 1), mediaItem.value)
        ..start();
    }
  }
}

class _Seeker {
  final AudioHandler handler;
  final Duration positionInterval;
  final Duration stepInterval;
  final MediaItem mediaItem;
  bool _running = false;

  _Seeker(
    this.handler,
    this.positionInterval,
    this.stepInterval,
    this.mediaItem,
  );

  start() async {
    _running = true;
    while (_running) {
      Duration newPosition =
          handler.playbackState.value.position + positionInterval;
      if (newPosition < Duration.zero) newPosition = Duration.zero;
      if (newPosition > mediaItem.duration) newPosition = mediaItem.duration;
      handler.seek(newPosition);
      await Future.delayed(stepInterval);
    }
  }

  stop() {
    _running = false;
  }
}

/// This mixin provides default implementations of methods for updating and
/// navigating the queue. The [skipToNext] and [skipToPrevious] default
/// implementations are defined in terms of your own implementation of
/// [skipToQueueItem].
mixin QueueHandler on BaseAudioHandler {
  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    queue.add(queue.value..add(mediaItem));
    await super.addQueueItem(mediaItem);
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    queue.add(queue.value..addAll(mediaItems));
    await super.addQueueItems(mediaItems);
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    queue.add(queue.value..insert(index, mediaItem));
    await super.insertQueueItem(index, mediaItem);
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    this
        .queue
        .add(this.queue.value..replaceRange(0, this.queue.value.length, queue));
    await super.updateQueue(queue);
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.queue.add(
        this.queue.value..[this.queue.value.indexOf(mediaItem)] = mediaItem);
    await super.updateMediaItem(mediaItem);
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    queue.add(this.queue.value..remove(mediaItem));
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

  /// This should be overridden to instruct how to skip to the media item
  /// identified by [mediaId]. By default, this will find the [MediaItem]
  /// identified by [mediaId] and broadcast this on the [mediaItemStream]. Your
  /// implementation may call super to reuse this default implementation, or
  /// else provide equivalent behaviour.
  @override
  Future<void> skipToQueueItem(String mediaId) async {
    final mediaItem =
        queue.value.firstWhere((mediaItem) => mediaItem.id == mediaId);
    this.mediaItem.add(mediaItem);
    await super.skipToQueueItem(mediaId);
  }

  Future<void> _skip(int offset) async {
    if (mediaItem == null) return;
    int i = queue.value.indexOf(mediaItem.value);
    if (i == -1) return;
    int newIndex = i + offset;
    if (newIndex >= 0 && newIndex < queue.value.length) {
      await skipToQueueItem(queue.value[newIndex]?.id);
    }
  }
}

/// The available shuffle modes for the queue.
enum AudioServiceShuffleMode { none, all, group }

/// The available repeat modes.
///
/// This defines how media items should repeat when the current one is finished.
enum AudioServiceRepeatMode { 
  /// When the current media item finishes, playback will stop.
  none, 
  
  /// The current media item will repeat.
  one, 
  
  /// Playback will continue looping through all media items in the current list.
  all, 
  
  /// [Unimplemented] This corresponds to Android's [REPEAT_MODE_GROUP](https://developer.android.com/reference/androidx/media2/common/SessionPlayer#REPEAT_MODE_GROUP).
  ///
  /// This could represent a playlist that is a smaller subset of all media items.
  group, 
}

bool get _testing => HttpOverrides.current != null;

/// The configuration options to use when registering an [AudioHandler].
class AudioServiceConfig {
  final bool androidResumeOnClick;
  final String androidNotificationChannelName;
  final String androidNotificationChannelDescription;
  final Color notificationColor;

  /// The icon resource to be used in the Android media notification, specified
  /// like an XML resource reference. This defaults to `"mipmap/ic_launcher"`.
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
  final int artDownscaleWidth;

  /// If not null, causes the artwork specified by [MediaItem.artUri] to be
  /// downscaled to this maximum pixel height. If the resolution of your artwork
  /// is particularly high, this can help to conserve memory. If specified,
  /// [artDownscaleWidth] must also be specified.
  final int artDownscaleHeight;

  /// The interval to be used in [AudioHandler.fastForward] by default. This
  /// value will also be used on iOS to render the skip-forward button. This
  /// value must be positive.
  final Duration fastForwardInterval;

  /// The interval to be used in [AudioHandler.rewind] by default. This value
  /// will also be used on iOS to render the skip-backward button. This value
  /// must be positive.
  final Duration rewindInterval;

  /// Whether queue support should be enabled on the media session on Android.
  /// If your app will run on Android and has a queue, you should set this to
  /// true.
  final bool androidEnableQueue;
  final bool preloadArtwork;

  /// Extras to report on Android in response to an `onGetRoot` request.
  final Map<String, dynamic> androidBrowsableRootExtras;

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

  Map<String, dynamic> toJson() => {
        'androidResumeOnClick': androidResumeOnClick,
        'androidNotificationChannelName': androidNotificationChannelName,
        'androidNotificationChannelDescription':
            androidNotificationChannelDescription,
        'notificationColor': notificationColor?.value,
        'androidNotificationIcon': androidNotificationIcon,
        'androidShowNotificationBadge': androidShowNotificationBadge,
        'androidNotificationClickStartsActivity':
            androidNotificationClickStartsActivity,
        'androidNotificationOngoing': androidNotificationOngoing,
        'androidStopForegroundOnPause': androidStopForegroundOnPause,
        'artDownscaleWidth': artDownscaleWidth,
        'artDownscaleHeight': artDownscaleHeight,
        'fastForwardInterval': fastForwardInterval.inMilliseconds,
        'rewindInterval': rewindInterval.inMilliseconds,
        'androidEnableQueue': androidEnableQueue,
        'preloadArtwork': preloadArtwork,
        'androidBrowsableRootExtras': androidBrowsableRootExtras,
      };
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

abstract class StreamableValue<T> {
  ValueStream<T> get stream;
  T get value => stream.value;
}

class StreamableValueSubject<T> extends StreamableValue<T> {
  // ignore: close_sinks
  final BehaviorSubject<T> _subject;
  StreamableValueSubject._(BehaviorSubject<T> subject) : _subject = subject;
  StreamableValueSubject() : this._(BehaviorSubject<T>());
  StreamableValueSubject.seeded(T initialValue)
      : this._(BehaviorSubject.seeded(initialValue));

  ValueStream<T> get stream => _subject.stream;

  void add(T event) => _subject.add(event);
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
}

class AndroidPlaybackType {
  static final local = AndroidPlaybackType(1);
  static final remote = AndroidPlaybackType(2);
  static final values = <int, AndroidPlaybackType>{
    1: local,
    2: remote,
  };
  final int index;

  AndroidPlaybackType(this.index);
}

enum AndroidVolumeControlType { fixed, relative, absolute }

class AndroidPlaybackInfo {
  final AndroidPlaybackType playbackType;
  //final AndroidAudioAttributes audioAttributes;
  final AndroidVolumeControlType volumeControlType;
  final int maxVolume;
  final int volume;

  AndroidPlaybackInfo._({
    this.playbackType,
    this.volumeControlType,
    this.maxVolume,
    this.volume,
  });

  AndroidPlaybackInfo.local()
      : this._(
          playbackType: AndroidPlaybackType.local,
        );

  AndroidPlaybackInfo.remote({
    final int audioStream,
    final AndroidVolumeControlType volumeControlType,
    final int maxVolume,
    final int volume,
  }) : this._(
          playbackType: AndroidPlaybackType.remote,
          volumeControlType: volumeControlType,
          maxVolume: maxVolume,
          volume: volume,
        );

  AndroidPlaybackInfo copyLocalWith() => AndroidPlaybackInfo.local();

  AndroidPlaybackInfo copyRemoteWith({
    AndroidVolumeControlType volumeControlType,
    int maxVolume,
    int volume,
  }) =>
      AndroidPlaybackInfo.remote(
        volumeControlType: volumeControlType ?? this.volumeControlType,
        maxVolume: maxVolume ?? this.maxVolume,
        volume: volume ?? this.volume,
      );

  Map<String, dynamic> toJson() => {
        'playbackType': playbackType.index,
        'volumeControlType': volumeControlType?.index,
        'maxVolume': maxVolume,
        'volume': volume,
      };
}

_castMap(Map map) => map?.cast<String, dynamic>();
