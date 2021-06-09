import 'package:flutter/foundation.dart';

import 'audio_service_platform_interface.dart';

class NoOpAudioServicePlugin extends AudioServicePluginPlatform {
  @override
  Future<void> initService(InitAudioServiceRequest request) {
    return SynchronousFuture(null);
  }

  @override
  Future<void> initController(InitAudioControllerRequest request) {
    return SynchronousFuture(null);
  }

  @override
  Future<void> disposeService(DisposeAudioServiceRequest request) {
    return SynchronousFuture(null);
  }

  @override
  Future<void> disposeController(DisposeAudioControllerRequest request) {
    return SynchronousFuture(null);
  }

  @override
  Future<void> androidForceEnableMediaButtons(
      AndroidForceEnableMediaButtonsRequest request) {
    return SynchronousFuture(null);
  }
}
