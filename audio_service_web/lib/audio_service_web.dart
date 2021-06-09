import 'dart:async';
import 'dart:js' as js;
import 'dart:html' as html;

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'js/media_session_web.dart';

class AudioServiceWebPlugin extends AudioServicePluginPlatform {
  static void registerWith(Registrar registrar) {
    AudioServicePluginPlatform.instance = AudioServiceWebPlugin();
  }

  AudioServicePlatformCallbacks? platformCallbacks;
  MediaItemMessage? mediaItem;

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
    final session = html.window.navigator.mediaSession!;
    session.metadata = null;
    mediaItem = null;
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

class AudioServiceWeb extends AudioServicePlatform {
  final AudioServicePlatformCallbacks callbacks;
  late MediaItemMessage mediaItem;

  AudioServiceWeb({
    required ComponentName name,
    required this.callbacks,
  }) : super(name: name);

  @override
  Future<void> setConfig(SetConfigRequest request) {
    return SynchronousFuture(null);
  }

  @override
  Future<void> setAndroidPlaybackInfo(SetAndroidPlaybackInfoRequest request) {
    return SynchronousFuture(null);
  }

  @override
  Future<void> notifyChildrenChanged(NotifyChildrenChangedRequest request) {
    return SynchronousFuture(null);
  }

  @override
  Future<void> updatePlaybackState(UpdatePlaybackStateRequest request) async {
    print('Setting state');
    final session = html.window.navigator.mediaSession!;
    for (final control in request.state.controls) {
      try {
        switch (control.action) {
          case MediaActionMessage.play:
            session.setActionHandler(
              'play',
              () => callbacks.play(const PlayRequest()),
            );
            break;
          case MediaActionMessage.pause:
            session.setActionHandler(
              'pause',
              () => callbacks.pause(const PauseRequest()),
            );
            break;
          case MediaActionMessage.skipToPrevious:
            session.setActionHandler(
              'previoustrack',
              () => callbacks.skipToPrevious(const SkipToPreviousRequest()),
            );
            break;
          case MediaActionMessage.skipToNext:
            session.setActionHandler(
              'nexttrack',
              () => callbacks.skipToNext(const SkipToNextRequest()),
            );
            break;
          // The naming convention here is a bit odd but seekbackward seems more
          // analagous to rewind than seekBackward
          case MediaActionMessage.rewind:
            session.setActionHandler(
              'seekbackward',
              () => callbacks.rewind(const RewindRequest()),
            );
            break;
          case MediaActionMessage.fastForward:
            session.setActionHandler(
              'seekforward',
              () => callbacks.fastForward(const FastForwardRequest()),
            );
            break;
          case MediaActionMessage.stop:
            session.setActionHandler(
              'stop',
              () => callbacks.stop(const StopRequest()),
            );
            break;
          default:
            // no-op
            break;
        }
      } catch (e) {
        // TODO: handle this somehow?
      }
      for (final message in request.state.systemActions) {
        switch (message) {
          case MediaActionMessage.seek:
            try {
              setActionHandler('seekto', js.allowInterop((ActionResult ev) {
                // Chrome uses seconds for whatever reason
                callbacks.seek(SeekRequest(
                    position: Duration(
                  milliseconds: (ev.seekTime * 1000).round(),
                )));
              }));
            } catch (e) {
              // TODO: handle this somehow?
            }
            break;
          default:
            // no-op
            break;
        }
      }

      try {
        // Dart also doesn't expose setPositionState
        if (mediaItem != null) {
          //print(
          //    'Setting positionState Duration(${mediaItem!.duration?.inSeconds}), PlaybackRate(${args[6] ?? 1.0}), Position(${Duration(milliseconds: args[4])?.inSeconds})');

          // Chrome looks for seconds for some reason
          setPositionState(PositionState(
            duration: (mediaItem.duration?.inMilliseconds ?? 0) / 1000,
            playbackRate: request.state.speed,
            position: request.state.updatePosition.inMilliseconds / 1000,
          ));
        }
      } catch (e) {
        print(e);
      }
    }
  }

  @override
  Future<void> updateQueue(UpdateQueueRequest request) {
    // There's no queue on web
    return SynchronousFuture(null);
  }

  @override
  Future<void> updateMediaItem(UpdateMediaItemRequest request) async {
    mediaItem = request.mediaItem!;
    final artUri = mediaItem.artUri;
    try {
      metadata = html.MediaMetadata(<String, dynamic>{
        'album': mediaItem.album,
        'title': mediaItem.title,
        'artist': mediaItem.artist,
        'artwork': [
          {
            'src': artUri,
            'sizes': '512x512',
          }
        ],
      });
    } catch (e) {
      print('Metadata failed $e');
    }
  }
}
