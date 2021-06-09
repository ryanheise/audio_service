import 'audio_service_platform_interface.dart';

class NoOpAudioService implements AudioServicePlatform {
  @override
  Future<ConfigureResponse> configure(ConfigureRequest request) async {
    return ConfigureResponse();
  }

  @override
  Future<void> updatePlaybackState(UpdatePlaybackStateRequest request) async {}

  @override
  Future<void> updateQueue(UpdateQueueRequest request) async {}

  @override
  Future<void> updateMediaItem(UpdateMediaItemRequest request) async {}

  @override
  Future<void> stopService(StopServiceRequest request) async {}

  @override
  Future<void> setAndroidPlaybackInfo(
      SetAndroidPlaybackInfoRequest request) async {}

  @override
  Future<void> androidForceEnableMediaButtons(
      AndroidForceEnableMediaButtonsRequest request) async {}

  @override
  Future<void> notifyChildrenChanged(
      NotifyChildrenChangedRequest request) async {}

  @override
  void handlePlatformCall(AudioServicePlatformCallbacks callbacks) {}
}
