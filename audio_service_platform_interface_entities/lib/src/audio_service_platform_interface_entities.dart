/// The different states during audio processing.
enum AudioProcessingStateMessage {
  idle,
  loading,
  buffering,
  ready,
  completed,
  error,
}

/// The actons associated with playing audio.
enum MediaActionMessage {
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

class MediaControlMessage {
  /// A reference to an Android icon resource for the control (e.g.
  /// `"drawable/ic_action_pause"`)
  final String androidIcon;

  /// A label for the control
  final String label;

  /// The action to be executed by this control
  final MediaActionMessage action;

  const MediaControlMessage({
    required this.androidIcon,
    required this.label,
    required this.action,
  });

  Map<String, dynamic> toMap() => {
        'androidIcon': androidIcon,
        'label': label,
        'action': action.index,
      };
}

/// The playback state which includes a [playing] boolean state, a processing
/// state such as [AudioProcessingState.buffering], the playback position and
/// the currently enabled actions to be shown in the Android notification or the
/// iOS control center.
class PlaybackStateMessage {
  /// The audio processing state e.g. [BasicPlaybackState.buffering].
  final AudioProcessingStateMessage processingState;

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
  final List<MediaControlMessage> controls;

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
  final Set<MediaActionMessage> systemActions;

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
  final AudioServiceRepeatModeMessage repeatMode;

  /// The current shuffle mode.
  final AudioServiceShuffleModeMessage shuffleMode;

  /// Whether captioning is enabled.
  final bool captioningEnabled;

  /// The index of the current item in the queue, if any.
  final int? queueIndex;

  /// Creates a [PlaybackState] with given field values, and with [updateTime]
  /// defaulting to [DateTime.now()].
  PlaybackStateMessage({
    this.processingState = AudioProcessingStateMessage.idle,
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
    this.repeatMode = AudioServiceRepeatModeMessage.none,
    this.shuffleMode = AudioServiceShuffleModeMessage.none,
    this.captioningEnabled = false,
    this.queueIndex,
  })  : assert(androidCompactActionIndices == null ||
            androidCompactActionIndices.length <= 3),
        this.updateTime = updateTime ?? DateTime.now();

  factory PlaybackStateMessage.fromMap(Map map) => PlaybackStateMessage(
        processingState:
            AudioProcessingStateMessage.values[map['processingState']],
        playing: map['playing'],
        controls: [],
        androidCompactActionIndices: null,
        systemActions: (map['systemActions'] as List)
            .map((dynamic action) => MediaActionMessage.values[action as int])
            .toSet(),
        updatePosition: Duration(microseconds: map['updatePosition']),
        bufferedPosition: Duration(microseconds: map['bufferedPosition']),
        speed: map['speed'],
        updateTime: DateTime.fromMillisecondsSinceEpoch(map['updateTime']),
        errorCode: map['errorCode'],
        errorMessage: map['errorMessage'],
        repeatMode: AudioServiceRepeatModeMessage.values[map['repeatMode']],
        shuffleMode: AudioServiceShuffleModeMessage.values[map['shuffleMode']],
        captioningEnabled: map['captioningEnabled'],
        queueIndex: map['queueIndex'],
      );
  Map<String, dynamic> toMap() => {
        'processingState': processingState.index,
        'playing': playing,
        'controls': controls.map((control) => control.toMap()).toList(),
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
        'queueIndex': queueIndex,
      };
}

class AndroidVolumeDirectionMessage {
  static final lower = AndroidVolumeDirectionMessage(-1);
  static final same = AndroidVolumeDirectionMessage(0);
  static final raise = AndroidVolumeDirectionMessage(1);
  static final values = <int, AndroidVolumeDirectionMessage>{
    -1: lower,
    0: same,
    1: raise,
  };
  final int index;

  AndroidVolumeDirectionMessage(this.index);

  @override
  String toString() => '$index';
}

class AndroidPlaybackTypeMessage {
  static final local = AndroidPlaybackTypeMessage(1);
  static final remote = AndroidPlaybackTypeMessage(2);
  final int index;

  AndroidPlaybackTypeMessage(this.index);

  @override
  String toString() => '$index';
}

enum AndroidVolumeControlTypeMessage { fixed, relative, absolute }

abstract class AndroidPlaybackInfoMessage {
  Map<String, dynamic> toMap();
}

class RemoteAndroidPlaybackInfoMessage extends AndroidPlaybackInfoMessage {
  //final AndroidAudioAttributes audioAttributes;
  final AndroidVolumeControlTypeMessage volumeControlType;
  final int maxVolume;
  final int volume;

  RemoteAndroidPlaybackInfoMessage({
    required this.volumeControlType,
    required this.maxVolume,
    required this.volume,
  });

  Map<String, dynamic> toMap() => {
        'playbackType': AndroidPlaybackTypeMessage.remote.index,
        'volumeControlType': volumeControlType.index,
        'maxVolume': maxVolume,
        'volume': volume,
      };

  @override
  String toString() => '${toMap()}';
}

class LocalAndroidPlaybackInfoMessage extends AndroidPlaybackInfoMessage {
  Map<String, dynamic> toMap() => {
        'playbackType': AndroidPlaybackTypeMessage.local.index,
      };

  @override
  String toString() => '${toMap()}';
}

/// The different buttons on a headset.
enum MediaButtonMessage {
  media,
  next,
  previous,
}

/// The available shuffle modes for the queue.
enum AudioServiceShuffleModeMessage { none, all, group }

/// The available repeat modes.
///
/// This defines how media items should repeat when the current one is finished.
enum AudioServiceRepeatModeMessage {
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

class MediaItemMessage {
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

  /// The rating of the MediaItemMessage.
  final RatingMessage? rating;

  /// A map of additional metadata for the media item.
  ///
  /// The values must be integers or strings.
  final Map<String, dynamic>? extras;

  /// Creates a [MediaItemMessage].
  ///
  /// [id], [album] and [title] must not be null, and [id] must be unique for
  /// each instance.
  const MediaItemMessage({
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

  /// Creates a [MediaItemMessage] from a map of key/value pairs corresponding to
  /// fields of this class.
  factory MediaItemMessage.fromMap(Map raw) => MediaItemMessage(
        id: raw['id'],
        album: raw['album'],
        title: raw['title'],
        artist: raw['artist'],
        genre: raw['genre'],
        duration: raw['duration'] != null
            ? Duration(milliseconds: raw['duration'])
            : null,
        artUri: raw['artUri'] != null ? Uri.parse(raw['artUri']) : null,
        playable: raw['playable'],
        displayTitle: raw['displayTitle'],
        displaySubtitle: raw['displaySubtitle'],
        displayDescription: raw['displayDescription'],
        rating:
            raw['rating'] != null ? RatingMessage.fromMap(raw['rating']) : null,
        extras: (raw['extras'] as Map?)?.cast<String, dynamic>(),
      );

  /// Converts this [MediaItemMessage] to a map of key/value pairs corresponding to
  /// the fields of this class.
  Map<String, dynamic> toMap() => {
        'id': id,
        'album': album,
        'title': title,
        'artist': artist,
        'genre': genre,
        'duration': duration?.inMilliseconds,
        'artUri': artUri?.toString(),
        'playable': playable,
        'displayTitle': displayTitle,
        'displaySubtitle': displaySubtitle,
        'displayDescription': displayDescription,
        'rating': rating?.toMap(),
        'extras': extras,
      };
}

/// A rating to attach to a MediaItemMessage.
class RatingMessage {
  final RatingStyleMessage type;
  final dynamic value;

  const RatingMessage({required this.type, required this.value});

  /// Returns a percentage rating value greater or equal to 0.0f, or a
  /// negative value if the rating style is not percentage-based, or
  /// if it is unrated.
  double get percentRating {
    if (type != RatingStyleMessage.percentage) return -1;
    if (value < 0 || value > 100) return -1;
    return value ?? -1;
  }

  /// Returns a rating value greater or equal to 0.0f, or a negative
  /// value if the rating style is not star-based, or if it is
  /// unrated.
  int get starRating {
    if (type != RatingStyleMessage.range3stars &&
        type != RatingStyleMessage.range4stars &&
        type != RatingStyleMessage.range5stars) return -1;
    return value ?? -1;
  }

  /// Returns true if the rating is "heart selected" or false if the
  /// rating is "heart unselected", if the rating style is not [heart]
  /// or if it is unrated.
  bool get hasHeart {
    if (type != RatingStyleMessage.heart) return false;
    return value ?? false;
  }

  /// Returns true if the rating is "thumb up" or false if the rating
  /// is "thumb down", if the rating style is not [thumbUpDown] or if
  /// it is unrated.
  bool get isThumbUp {
    if (type != RatingStyleMessage.thumbUpDown) return false;
    return value ?? false;
  }

  /// Return whether there is a rating value available.
  bool get isRated => value != null;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.index,
      'value': value,
    };
  }

  // Even though this should take a Map<String, dynamic>, that makes an error.
  RatingMessage.fromMap(Map<dynamic, dynamic> raw)
      : this(type: RatingStyleMessage.values[raw['type']], value: raw['value']);

  @override
  String toString() => '${toMap()}';
}

enum RatingStyleMessage {
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

class OnPlaybackStateChangedRequest {
  final PlaybackStateMessage state;

  OnPlaybackStateChangedRequest({
    required this.state,
  });

  factory OnPlaybackStateChangedRequest.fromMap(Map map) =>
      OnPlaybackStateChangedRequest(
          state: PlaybackStateMessage.fromMap(map['state']));

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'state': state.toMap(),
      };
}

class OnQueueChangedRequest {
  final List<MediaItemMessage> queue;

  OnQueueChangedRequest({
    required this.queue,
  });

  factory OnQueueChangedRequest.fromMap(Map map) => OnQueueChangedRequest(
      queue: map['queue'] == null
          ? []
          : (map['queue'] as List)
              .map((raw) => MediaItemMessage.fromMap(raw))
              .toList());

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'queue': queue.map((item) => item.toMap()).toList(),
      };
}

class OnMediaItemChangedRequest {
  final MediaItemMessage? mediaItem;

  OnMediaItemChangedRequest({
    required this.mediaItem,
  });

  factory OnMediaItemChangedRequest.fromMap(Map map) =>
      OnMediaItemChangedRequest(
        mediaItem: map['mediaItem'] == null
            ? null
            : MediaItemMessage.fromMap(map['mediaItem']),
      );

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaItem': mediaItem?.toMap(),
      };
}

class OnChildrenLoadedRequest {
  final String parentMediaId;
  final List<MediaItemMessage> children;

  OnChildrenLoadedRequest({
    required this.parentMediaId,
    required this.children,
  });

  factory OnChildrenLoadedRequest.fromMap(Map map) => OnChildrenLoadedRequest(
        parentMediaId: map['parentMediaId'],
        children: (map['queue'] as List)
            .map((raw) => MediaItemMessage.fromMap(raw))
            .toList(),
      );
}

class OnNotificationClickedRequest {
  final bool clicked;

  OnNotificationClickedRequest({
    required this.clicked,
  });

  factory OnNotificationClickedRequest.fromMap(Map map) =>
      OnNotificationClickedRequest(
        clicked: map['clicked'] == null,
      );

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'clicked': clicked,
      };
}

class SetStateRequest {
  final PlaybackStateMessage state;

  SetStateRequest({
    required this.state,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'state': state.toMap(),
      };
}

class SetQueueRequest {
  final List<MediaItemMessage> queue;

  SetQueueRequest({required this.queue});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'queue': queue.map((item) => item.toMap()).toList(),
      };
}

class SetMediaItemRequest {
  final MediaItemMessage mediaItem;

  SetMediaItemRequest({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaItem': mediaItem.toMap(),
      };
}

class StopServiceRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class SetAndroidPlaybackInfoRequest {
  final AndroidPlaybackInfoMessage playbackInfo;

  SetAndroidPlaybackInfoRequest({required this.playbackInfo});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'playbackInfo': playbackInfo.toMap(),
      };
}

class AndroidForceEnableMediaButtonsRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class NotifyChildrenChangedRequest {
  final String parentMediaId;
  final Map<String, dynamic>? options;

  NotifyChildrenChangedRequest({required this.parentMediaId, this.options});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'parentMediaId': parentMediaId,
        'options': options,
      };
}

class PrepareRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class PrepareFromMediaIdRequest {
  final String mediaId;
  final Map<String, dynamic>? extras;

  PrepareFromMediaIdRequest({required this.mediaId, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaId': mediaId,
      };
}

class PrepareFromSearchRequest {
  final String query;
  final Map<String, dynamic>? extras;

  PrepareFromSearchRequest({required this.query, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'query': query,
        'extras': extras,
      };
}

class PrepareFromUriRequest {
  final Uri uri;
  final Map<String, dynamic>? extras;

  PrepareFromUriRequest({required this.uri, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'uri': uri.toString(),
        'extras': extras,
      };
}

class PlayRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class PlayFromMediaIdRequest {
  final String mediaId;
  final Map<String, dynamic>? extras;

  PlayFromMediaIdRequest({required this.mediaId, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaId': mediaId,
      };
}

class PlayFromSearchRequest {
  final String query;
  final Map<String, dynamic>? extras;

  PlayFromSearchRequest({required this.query, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'query': query,
        'extras': extras,
      };
}

class PlayFromUriRequest {
  final Uri uri;
  final Map<String, dynamic>? extras;

  PlayFromUriRequest({required this.uri, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'uri': uri.toString(),
        'extras': extras,
      };
}

class PlayMediaItemRequest {
  final MediaItemMessage mediaItem;

  PlayMediaItemRequest({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaItem': mediaItem.toString(),
      };
}

class PauseRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class ClickRequest {
  final MediaButtonMessage button;

  ClickRequest({required this.button});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'button': button.index,
      };
}

class StopRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class AddQueueItemRequest {
  final MediaItemMessage mediaItem;

  AddQueueItemRequest({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaItem': mediaItem.toMap(),
      };
}

class AddQueueItemsRequest {
  final List<MediaItemMessage> queue;

  AddQueueItemsRequest({required this.queue});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'queue': queue.map((item) => item.toMap()).toList(),
      };
}

class InsertQueueItemRequest {
  final int index;
  final MediaItemMessage mediaItem;

  InsertQueueItemRequest({required this.index, required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'index': index,
        'mediaItem': mediaItem.toMap(),
      };
}

class UpdateQueueRequest {
  final List<MediaItemMessage> queue;

  UpdateQueueRequest({required this.queue});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'queue': queue.map((item) => item.toMap()).toList(),
      };
}

class UpdateMediaItemRequest {
  final MediaItemMessage mediaItem;

  UpdateMediaItemRequest({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaItem': mediaItem.toMap(),
      };
}

class RemoveQueueItemRequest {
  final MediaItemMessage mediaItem;

  RemoveQueueItemRequest({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaItem': mediaItem.toMap(),
      };
}

class RemoveQueueItemAtRequest {
  final int index;

  RemoveQueueItemAtRequest({required this.index});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'index': index,
      };
}

class SkipToNextRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class SkipToPreviousRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class FastForwardRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class RewindRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class SkipToQueueItemRequest {
  final int index;

  SkipToQueueItemRequest({required this.index});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'index': index,
      };
}

class SeekRequest {
  final Duration position;

  SeekRequest({required this.position});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'position': position.inMicroseconds,
      };
}

class SetRatingRequest {
  final RatingMessage rating;
  final Map<String, dynamic>? extras;

  SetRatingRequest({required this.rating, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'rating': rating.toMap(),
        'extras': extras,
      };
}

class SetCaptioningEnabledRequest {
  final bool enabled;

  SetCaptioningEnabledRequest({required this.enabled});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'enabled': enabled,
      };
}

class SetRepeatModeRequest {
  final AudioServiceRepeatModeMessage repeatMode;

  SetRepeatModeRequest({required this.repeatMode});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'repeatMode': repeatMode.index,
      };
}

class SetShuffleModeRequest {
  final AudioServiceShuffleModeMessage shuffleMode;

  SetShuffleModeRequest({required this.shuffleMode});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'shuffleMode': shuffleMode.index,
      };
}

class SeekBackwardRequest {
  final bool begin;

  SeekBackwardRequest({required this.begin});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'begin': begin,
      };
}

class SeekForwardRequest {
  final bool begin;

  SeekForwardRequest({required this.begin});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'begin': begin,
      };
}

class SetSpeedRequest {
  final double speed;

  SetSpeedRequest({required this.speed});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'speed': speed,
      };
}

class CustomActionRequest {
  final String name;
  final Map<String, dynamic>? extras;

  CustomActionRequest({required this.name, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'name': name,
        'extras': extras,
      };
}

class OnTaskRemovedRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class OnNotificationDeletedRequest {
  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{};
}

class GetChildrenRequest {
  final String parentMediaId;
  final Map<String, dynamic>? options;

  GetChildrenRequest({required this.parentMediaId, this.options});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'parentMediaId': parentMediaId,
        'options': options,
      };
}

class GetChildrenResponse {
  final List<MediaItemMessage> children;

  GetChildrenResponse({required this.children});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'children': children.map((item) => item.toMap()).toList(),
      };
}

class GetMediaItemRequest {
  final String mediaId;

  GetMediaItemRequest({required this.mediaId});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaId': mediaId,
      };
}

class GetMediaItemResponse {
  final MediaItemMessage? mediaItem;

  GetMediaItemResponse({required this.mediaItem});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaItem': mediaItem?.toMap(),
      };
}

class SearchRequest {
  final String query;
  final Map<String, dynamic>? extras;

  SearchRequest({required this.query, this.extras});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'query': query,
        'extras': extras,
      };
}

class SearchResponse {
  final List<MediaItemMessage> mediaItems;

  SearchResponse({required this.mediaItems});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'mediaItems': mediaItems.map((item) => item.toMap()).toList(),
      };
}

class AndroidSetRemoteVolumeRequest {
  final int volumeIndex;

  AndroidSetRemoteVolumeRequest({required this.volumeIndex});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'volumeIndex': volumeIndex,
      };
}

class AndroidAdjustRemoteVolumeRequest {
  final AndroidVolumeDirectionMessage direction;

  AndroidAdjustRemoteVolumeRequest({required this.direction});

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'direction': direction.index,
      };
}
