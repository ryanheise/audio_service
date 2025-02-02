import 'dart:async';
import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'js/media_session_web.dart';

class AudioServiceWeb extends AudioServicePlatform {
  static void registerWith(Registrar registrar) {
    AudioServicePlatform.instance = AudioServiceWeb();
  }

  web.MediaSession get _mediaSession => web.window.navigator.mediaSession;

  final _mediaSessionSupported = _SupportChecker(
    () => js.globalContext.hasProperty('MediaSession'.toJS).toDart,
    "MediaSession is not supported in this browser, so plugin is no-op",
  );
  final _setPositionStateSupported = _SupportChecker(
    () => web.window.navigator.mediaSession
        .hasProperty('setPositionState'.toJS)
        .toDart,
    "MediaSession.setPositionState is not supported in this browser",
  );

  AudioHandlerCallbacks? handlerCallbacks;
  MediaItemMessage? mediaItem;

  @override
  Future<void> configure(ConfigureRequest request) async {
    _mediaSessionSupported.check();
  }

  @override
  Future<void> setState(SetStateRequest request) async {
    if (!_mediaSessionSupported.check()) {
      return;
    }

    final state = request.state;

    if (state.processingState == AudioProcessingStateMessage.idle) {
      _mediaSession.playbackState = MediaSessionPlaybackState.none;
    } else {
      if (state.playing) {
        _mediaSession.playbackState = MediaSessionPlaybackState.playing;
      } else {
        _mediaSession.playbackState = MediaSessionPlaybackState.paused;
      }
    }

    for (final control in state.controls) {
      switch (control.action) {
        case MediaActionMessage.play:
          _mediaSession.setActionHandler(
            MediaSessionActions.play,
            ((MediaSessionActionDetails details) {
              handlerCallbacks?.play(const PlayRequest());
            }).toJS,
          );
          break;
        case MediaActionMessage.pause:
          _mediaSession.setActionHandler(
            MediaSessionActions.pause,
            ((MediaSessionActionDetails details) {
              handlerCallbacks?.pause(const PauseRequest());
            }).toJS,
          );
          break;
        case MediaActionMessage.skipToPrevious:
          _mediaSession.setActionHandler(
            MediaSessionActions.previoustrack,
            ((MediaSessionActionDetails details) {
              handlerCallbacks?.skipToPrevious(const SkipToPreviousRequest());
            }).toJS,
          );
          break;
        case MediaActionMessage.skipToNext:
          _mediaSession.setActionHandler(
            MediaSessionActions.nexttrack,
            ((MediaSessionActionDetails details) {
              handlerCallbacks?.skipToNext(const SkipToNextRequest());
            }).toJS,
          );
          break;
        case MediaActionMessage.rewind:
          _mediaSession.setActionHandler(
            MediaSessionActions.seekbackward,
            ((MediaSessionActionDetails details) {
              handlerCallbacks?.rewind(const RewindRequest());
            }).toJS,
          );
          break;
        case MediaActionMessage.fastForward:
          _mediaSession.setActionHandler(
            MediaSessionActions.seekforward,
            ((MediaSessionActionDetails details) {
              handlerCallbacks?.fastForward(const FastForwardRequest());
            }).toJS,
          );
          break;
        case MediaActionMessage.stop:
          _mediaSession.setActionHandler(
            MediaSessionActions.stop,
            ((MediaSessionActionDetails details) {
              handlerCallbacks?.stop(const StopRequest());
            }).toJS,
          );
          break;
        default:
          // no-op
          break;
      }
    }

    for (final message in state.systemActions) {
      switch (message) {
        case MediaActionMessage.seek:
          _mediaSession.setActionHandler(
              'seekto',
              ((MediaSessionActionDetails details) {
                // Browsers use seconds
                handlerCallbacks?.seek(SeekRequest(
                  position: Duration(
                      milliseconds: (details.seekTime! * 1000).round()),
                ));
              }).toJS);
          break;
        default:
          // no-op
          break;
      }
    }

    if (_setPositionStateSupported.check()) {
      // Update the position
      //
      // Factor out invalid states according to
      // https://developer.mozilla.org/en-US/docs/Web/API/MediaSession/setPositionState#exceptions
      final duration = mediaItem?.duration ?? Duration.zero;
      final position = _minDuration(state.updatePosition, duration);

      // Browsers expect for seconds
      _mediaSession.setPositionState(web.MediaPositionState(
        duration: duration.inMilliseconds / 1000,
        playbackRate: state.speed,
        position: position.inMilliseconds / 1000,
      ));
    }
  }

  @override
  Future<void> setQueue(SetQueueRequest request) async {
    // no-op as there is not a queue concept on the web
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {
    if (!_mediaSessionSupported.check()) {
      return;
    }
    mediaItem = request.mediaItem;
    final artist = mediaItem!.artist ?? '';
    final album = mediaItem!.album ?? '';
    final artUri = mediaItem!.artUri;

    _mediaSession.metadata = web.MediaMetadata(
      web.MediaMetadataInit(
        title: mediaItem!.title,
        artist: artist,
        album: album,
        artwork: [
          if (artUri != null)
            web.MediaImage(src: artUri.toString(), sizes: '512x512'),
        ].toJS,
      ),
    );
  }

  @override
  Future<void> stopService(StopServiceRequest request) async {
    if (!_mediaSessionSupported.check()) {
      return;
    }
    _mediaSession.metadata = null;
    mediaItem = null;
  }

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {
    if (!_mediaSessionSupported.check()) {
      return;
    }
    // Save this here so that we can modify which handlers are set based
    // on which actions are enabled
    handlerCallbacks = callbacks;
  }
}

/// Runs a [check], and prints a warning the first time check doesn't pass.
class _SupportChecker {
  final String _warningMessage;
  final ValueGetter<bool> _checkCallback;

  _SupportChecker(this._checkCallback, this._warningMessage);

  bool _logged = false;

  bool check() {
    final result = _checkCallback();
    if (!_logged && !result) {
      _logged = true;
      // ignore: avoid_print
      print("[warning] audio_service: $_warningMessage");
    }
    return result;
  }
}

Duration _minDuration(Duration a, Duration b) => a < b ? a : b;
