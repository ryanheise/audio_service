import 'dart:async';

import 'package:audio_service_platform_interface_entities/audio_service_platform_interface_entities.dart';
import 'package:meta/meta.dart';
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
  /// render the seek bar correctly unless your
  /// [AudioServiceConfig.androidNotificationIcon] is a monochrome white icon on
  /// a transparent background, and your [AudioServiceConfig.notificationColor]
  /// is a non-transparent color.
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
    DateTime? updateTime,
    this.errorCode,
    this.errorMessage,
    this.repeatMode = AudioServiceRepeatMode.none,
    this.shuffleMode = AudioServiceShuffleMode.none,
    this.captioningEnabled = false,
    this.queueIndex,
  })  : assert(androidCompactActionIndices == null ||
            androidCompactActionIndices.length <= 3),
        this.updateTime = updateTime ?? DateTime.now();

  /// Creates a copy of this state with given fields replaced by new values,
  /// with [updateTime] set to [DateTime.now()], and unless otherwise replaced,
  /// with [updatePosition] set to [this.position]. [errorCode] and
  /// [errorMessage] will be set to null unless [processingState] is
  /// [AudioProcessingState.error].
  PlaybackState copyWith({
    AudioProcessingState? processingState,
    bool? playing,
    List<MediaControl>? controls,
    List<int>? androidCompactActionIndices,
    Set<MediaAction>? systemActions,
    Duration? updatePosition,
    Duration? bufferedPosition,
    double? speed,
    int? errorCode,
    String? errorMessage,
    AudioServiceRepeatMode? repeatMode,
    AudioServiceShuffleMode? shuffleMode,
    bool? captioningEnabled,
    int? queueIndex,
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
      queueIndex: queueIndex ?? this.queueIndex,
    );
  }

  /// The current playback position.
  Duration get position {
    if (playing && processingState == AudioProcessingState.ready) {
      return Duration(
          milliseconds: (updatePosition.inMilliseconds +
                  ((DateTime.now().millisecondsSinceEpoch -
                          updateTime.millisecondsSinceEpoch) *
                      speed))
              .toInt());
    } else {
      return updatePosition;
    }
  }

  PlaybackStateMessage toMessage() => PlaybackStateMessage(
        processingState:
            AudioProcessingStateMessage.values[processingState.index],
        playing: playing,
        controls: controls.map((control) => control.toMessage()).toList(),
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
  String toString() => '${toMessage().toMap()}';
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

  /// Constructs a rating from raw data.
  ///
  /// This constructor is useful for serialization; for other uses, use a
  /// different constructor.
  const Rating.fromRaw(RatingStyle type, dynamic value)
      : this._internal(type, value);

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

  RatingMessage toMessage() => RatingMessage(
      type: RatingStyleMessage.values[_type.index], value: _value);

  @override
  String toString() => '${toMessage().toMap()}';
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

  /// The rating of the MediaItem.
  final Rating? rating;

  /// A map of additional metadata for the media item.
  ///
  /// The values must be integers or strings.
  final Map<String, dynamic>? extras;

  /// Creates a [MediaItem].
  ///
  /// [id], [album] and [title] must not be null, and [id] must be unique for
  /// each instance.
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
  MediaItem copyWith({
    String? id,
    String? album,
    String? title,
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

  MediaItemMessage toMessage() => MediaItemMessage(
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
        rating: rating?.toMessage(),
        extras: extras,
      );

  @override
  String toString() => '${toMessage().toMap()}';
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

  MediaControlMessage toMessage() => MediaControlMessage(
        androidIcon: androidIcon,
        label: label,
        action: MediaActionMessage.values[action.index],
      );

  @override
  String toString() => '${toMessage().toMap()}';
}

/// An [AudioHandler] plays audio, provides state updates and query results to
/// clients. It implements standard protocols that allow it to be remotely
/// controlled by the lock screen, media notifications, the iOS control center,
/// headsets, smart watches, car audio systems, and other compatible agents.
///
/// Instead of subclassing this class, consider subclassing [BaseAudioHandler],
/// which provides high-level state APIs.
/// For Flutter, use `BaseFlutterAudioHandler` in `package:audio_service`.
abstract class AudioHandler {
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

  /// Remove at media item from the queue at the specified [index].
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
  Future<void> setRating(Rating rating, Map<dynamic, dynamic>? extras);

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

  /// Adjust the remote volume on Android. This works only when
  /// [AndroidPlaybackInfo.playbackType] is [AndroidPlaybackType.remote].
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
  final BehaviorSubject<dynamic> customState = BehaviorSubject();

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
  CompositeAudioHandler(AudioHandler inner) : _inner = inner;

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
  Future<void> setRating(Rating rating, Map<dynamic, dynamic>? extras) =>
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
/// [customEvent].
///
/// You can choose to implement all methods yourself, or you may leverage some
/// mixins to provide default implementations of certain behaviours:
///
/// * [QueueHandler] provides default implementations of methods for updating
/// and navigating the queue.
/// * [SeekHandler] provides default implementations of methods for seeking
/// forwards and backwards.
///
/// ## Flutter
/// To properly integrate with Flutter platforms, use `BaseFlutterAudioHandler`
/// in `package:audio_service`.
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
  // ignore: close_sinks
  final BehaviorSubject<dynamic> customState = BehaviorSubject();

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
  Future<void> stop() async {
    // await AudioService._stop();
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
  Future<void> setRating(Rating rating, Map<dynamic, dynamic>? extras) async {}

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
  /// The amount to seek forward.
  Duration get fastForwardInterval;

  /// The amount to seek back.
  Duration get rewindInterval;

  _Seeker? _seeker;

  @override
  Future<void> fastForward() => _seekRelative(fastForwardInterval);

  @override
  Future<void> rewind() => _seekRelative(-rewindInterval);

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

  start() async {
    _running = true;
    while (_running) {
      Duration newPosition =
          handler.playbackState.value!.position + positionInterval;
      if (newPosition < Duration.zero) newPosition = Duration.zero;
      if (newPosition > duration) newPosition = duration;
      handler.seek(newPosition);
      await Future.delayed(stepInterval);
    }
  }

  stop() {
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
  Future<void> updateQueue(List<MediaItem> queue) async {
    this.queue.add(
        this.queue.value!..replaceRange(0, this.queue.value!.length, queue));
    await super.updateQueue(queue);
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    this.queue.add(
        this.queue.value!..[this.queue.value!.indexOf(mediaItem)] = mediaItem);
    await super.updateMediaItem(mediaItem);
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    queue.add(this.queue.value!..remove(mediaItem));
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

  /// This should be overridden to instruct how to skip to the queue item at
  /// [index]. By default, this will broadcast [index] as
  /// [PlaybackState.queueIndex] via the [playbackState] stream, and will
  /// broadcast [queue] element [index] via the stream [mediaItem]. Your
  /// implementation may call super to reuse this default implementation, or
  /// else provide equivalent behaviour.
  @override
  Future<void> skipToQueueItem(int index) async {
    playbackState.add(playbackState.value!.copyWith(queueIndex: index));
    mediaItem.add(queue.value![index]);
    await super.skipToQueueItem(index);
  }

  Future<void> _skip(int offset) async {
    final queue = this.queue.value!;
    final index = playbackState.value!.queueIndex!;
    if (index < 0 || index >= queue.length) return;
    await skipToQueueItem(index + offset);
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

  /// [Unimplemented] This corresponds to Android's [REPEAT_MODE_GROUP](https://developer.android.com/reference/androidx/media2/common/SessionPlayer#REPEAT_MODE_GROUP).
  ///
  /// This could represent a playlist that is a smaller subset of all media items.
  group,
}

/// (Maybe) temporary.
extension AudioServiceValueStream<T> on ValueStream<T> {
  @Deprecated('Use "this" instead. Will be removed before the release')
  ValueStream<T> get stream => this;
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
  AndroidPlaybackInfoMessage toMessage();

  @override
  String toString() => '${toMessage().toMap()}';
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
  RemoteAndroidPlaybackInfoMessage toMessage() =>
      RemoteAndroidPlaybackInfoMessage(
        volumeControlType:
            AndroidVolumeControlTypeMessage.values[volumeControlType.index],
        maxVolume: maxVolume,
        volume: volume,
      );
}

class LocalAndroidPlaybackInfo extends AndroidPlaybackInfo {
  LocalAndroidPlaybackInfoMessage toMessage() =>
      LocalAndroidPlaybackInfoMessage();
}
