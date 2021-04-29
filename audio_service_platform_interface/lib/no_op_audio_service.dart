import 'audio_service_platform_interface.dart';

class NoOpAudioService extends AudioServicePlatform {
  @override
  Future<ConfigureResponse> configure(ConfigureRequest request) async {
    return ConfigureResponse();
  }

  @override
  Future<void> setState(SetStateRequest request) async {}

  @override
  Future<void> setQueue(SetQueueRequest request) async {}

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {}

  @override
  Future<void> stopService(StopServiceRequest request) async {}

  @override
  Future<void> androidForceEnableMediaButtons(
      AndroidForceEnableMediaButtonsRequest request) async {}

  @override
  Future<void> notifyChildrenChanged(
      NotifyChildrenChangedRequest request) async {}

  @override
  Future<void> setAndroidPlaybackInfo(
      SetAndroidPlaybackInfoRequest request) async {}

  @override
  void setClientCallbacks(AudioClientCallbacks callbacks) {}

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {}
}
