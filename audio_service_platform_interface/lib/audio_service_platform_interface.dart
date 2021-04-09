import 'package:audio_service_platform_interface_entities/audio_service_platform_interface_entities.dart';
import 'package:flutter/material.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_audio_service.dart';

export 'package:audio_service_platform_interface_entities/audio_service_platform_interface_entities.dart';

abstract class AudioServicePlatform extends PlatformInterface {
  /// Constructs an AudioServicePlatform.
  AudioServicePlatform() : super(token: _token);

  static final Object _token = Object();

  static AudioServicePlatform _instance = MethodChannelAudioService();

  /// The default instance of [AudioServicePlatform] to use.
  ///
  /// Defaults to [MethodChannelAudioService].
  static AudioServicePlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [AudioServicePlatform] when they register themselves.
  // TODO(amirh): Extract common platform interface logic.
  // https://github.com/flutter/flutter/issues/43368
  static set instance(AudioServicePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<ConfigureResponse> configure(ConfigureRequest request) {
    throw UnimplementedError('configure() has not been implemented.');
  }

  Future<void> setState(SetStateRequest request) {
    throw UnimplementedError('setState() has not been implemented.');
  }

  Future<void> setQueue(SetQueueRequest request) {
    throw UnimplementedError('setQueue() has not been implemented.');
  }

  Future<void> setMediaItem(SetMediaItemRequest request) {
    throw UnimplementedError('setMediaItem() has not been implemented.');
  }

  Future<void> stopService(StopServiceRequest request) {
    throw UnimplementedError('stopService() has not been implemented.');
  }

  Future<void> setAndroidPlaybackInfo(
      SetAndroidPlaybackInfoRequest request) async {}

  Future<void> androidForceEnableMediaButtons(
      AndroidForceEnableMediaButtonsRequest request) async {}

  Future<void> notifyChildrenChanged(
      NotifyChildrenChangedRequest request) async {}

  void setClientCallbacks(AudioClientCallbacks callbacks);

  void setHandlerCallbacks(AudioHandlerCallbacks callbacks);
}

/// Callbacks from the platform to a client running in another isolate.
abstract class AudioClientCallbacks {
  Future<void> onPlaybackStateChanged(OnPlaybackStateChangedRequest request);

  Future<void> onQueueChanged(OnQueueChangedRequest request);

  Future<void> onMediaItemChanged(OnMediaItemChangedRequest request);

  // We currently implement children notification in Dart through inter-isolate
  // send/receive ports.
  // XXX: Could we actually implement the above 3 callbacks in the same way?
  // If so, then platform->client communication should be reserved for a future
  // feature where an app can observe another process's media session.
  //Future<void> onChildrenLoaded(OnChildrenLoadedRequest request);

  // TODO: Add more callbacks
}

/// Callbacks from the platform to the handler.
abstract class AudioHandlerCallbacks {
  /// Prepare media items for playback.
  Future<void> prepare(PrepareRequest request);

  /// Prepare a specific media item for playback.
  Future<void> prepareFromMediaId(PrepareFromMediaIdRequest request);

  /// Prepare playback from a search query.
  Future<void> prepareFromSearch(PrepareFromSearchRequest request);

  /// Prepare a media item represented by a Uri for playback.
  Future<void> prepareFromUri(PrepareFromUriRequest request);

  /// Start or resume playback.
  Future<void> play(PlayRequest request);

  /// Play a specific media item.
  Future<void> playFromMediaId(PlayFromMediaIdRequest request);

  /// Begin playback from a search query.
  Future<void> playFromSearch(PlayFromSearchRequest request);

  /// Play a media item represented by a Uri.
  Future<void> playFromUri(PlayFromUriRequest request);

  /// Play a specific media item.
  Future<void> playMediaItem(PlayMediaItemRequest request);

  /// Pause playback.
  Future<void> pause(PauseRequest request);

  /// Process a headset button click, where [button] defaults to
  /// [MediaButton.media].
  Future<void> click(ClickRequest request);

  /// Stop playback and release resources.
  Future<void> stop(StopRequest request);

  /// Add [mediaItem] to the queue.
  Future<void> addQueueItem(AddQueueItemRequest request);

  /// Add [mediaItems] to the queue.
  Future<void> addQueueItems(AddQueueItemsRequest request);

  /// Insert [mediaItem] into the queue at position [index].
  Future<void> insertQueueItem(InsertQueueItemRequest request);

  /// Update to the queue to [queue].
  Future<void> updateQueue(UpdateQueueRequest request);

  /// Update the properties of [mediaItem].
  Future<void> updateMediaItem(UpdateMediaItemRequest request);

  /// Remove [mediaItem] from the queue.
  Future<void> removeQueueItem(RemoveQueueItemRequest request);

  /// Remove at media item from the queue at the specified [index].
  Future<void> removeQueueItemAt(RemoveQueueItemAtRequest request);

  /// Skip to the next item in the queue.
  Future<void> skipToNext(SkipToNextRequest request);

  /// Skip to the previous item in the queue.
  Future<void> skipToPrevious(SkipToPreviousRequest request);

  /// Jump forward by [AudioServiceConfig.fastForwardInterval].
  Future<void> fastForward(FastForwardRequest request);

  /// Jump backward by [AudioServiceConfig.rewindInterval]. Note: this value
  /// must be positive.
  Future<void> rewind(RewindRequest request);

  /// Skip to a queue item.
  Future<void> skipToQueueItem(SkipToQueueItemRequest request);

  /// Seek to [position].
  Future<void> seek(SeekRequest request);

  /// Set the rating.
  Future<void> setRating(SetRatingRequest request);

  Future<void> setCaptioningEnabled(SetCaptioningEnabledRequest request);

  /// Set the repeat mode.
  Future<void> setRepeatMode(SetRepeatModeRequest request);

  /// Set the shuffle mode.
  Future<void> setShuffleMode(SetShuffleModeRequest request);

  /// Begin or end seeking backward continuously.
  Future<void> seekBackward(SeekBackwardRequest request);

  /// Begin or end seeking forward continuously.
  Future<void> seekForward(SeekForwardRequest request);

  /// Set the playback speed.
  Future<void> setSpeed(SetSpeedRequest request);

  /// A mechanism to support app-specific actions.
  Future<dynamic> customAction(CustomActionRequest request);

  /// Handle the task being swiped away in the task manager (Android).
  Future<void> onTaskRemoved(OnTaskRemovedRequest request);

  /// Handle the notification being swiped away (Android).
  Future<void> onNotificationDeleted(OnNotificationDeletedRequest request);

  Future<void> onNotificationClicked(OnNotificationClickedRequest request);

  /// Get the children of a parent media item.
  Future<GetChildrenResponse> getChildren(GetChildrenRequest request);

  /// Get a particular media item.
  Future<GetMediaItemResponse> getMediaItem(GetMediaItemRequest request);

  /// Search for media items.
  Future<SearchResponse> search(SearchRequest request);

  /// Set the remote volume on Android. This works only when
  /// [AndroidPlaybackInfo.playbackType] is [AndroidPlaybackType.remote].
  Future<void> androidSetRemoteVolume(AndroidSetRemoteVolumeRequest request);

  /// Adjust the remote volume on Android. This works only when
  /// [AndroidPlaybackInfo.playbackType] is [AndroidPlaybackType.remote].
  Future<void> androidAdjustRemoteVolume(
      AndroidAdjustRemoteVolumeRequest request);
}

class AudioServiceConfigMessage {
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

  /// If not null, causes the artwork specified by [MediaItemMessage.artUri] to be
  /// downscaled to this maximum pixel width. If the resolution of your artwork
  /// is particularly high, this can help to conserve memory. If specified,
  /// [artDownscaleHeight] must also be specified.
  final int? artDownscaleWidth;

  /// If not null, causes the artwork specified by [MediaItemMessage.artUri] to be
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

  AudioServiceConfigMessage({
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

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
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

class ConfigureRequest {
  final AudioServiceConfigMessage config;

  ConfigureRequest({
    required this.config,
  });

  Map<dynamic, dynamic> toMap() => <dynamic, dynamic>{
        'config': config.toMap(),
      };
}

class ConfigureResponse {
  static ConfigureResponse fromMap(Map<dynamic, dynamic> map) =>
      ConfigureResponse();
}
