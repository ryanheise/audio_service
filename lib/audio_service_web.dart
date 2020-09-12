import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:audio_service/js/media_metadata.dart';

import 'js/media_session_web.dart';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

const String _CUSTOM_PREFIX = 'custom_';

class Art {
  String src;
  String type;
  String sizes;
  Art({this.src, this.type, this.sizes});
}

class AudioServicePlugin {
  int fastForwardInterval;
  int rewindInterval;
  Map params;
  bool started = false;
  ClientHandler clientHandler;
  BackgroundHandler backgroundHandler;

  static void registerWith(Registrar registrar) {
    AudioServicePlugin(registrar);
  }

  AudioServicePlugin(Registrar registrar) {
    clientHandler = ClientHandler(this, registrar);
    backgroundHandler = BackgroundHandler(this, registrar);
  }
}

class ClientHandler {
  final AudioServicePlugin plugin;
  final MethodChannel channel;

  ClientHandler(this.plugin, Registrar registrar)
      : channel = MethodChannel(
          'ryanheise.com/audioService',
          const StandardMethodCodec(),
          registrar.messenger,
        ) {
    channel.setMethodCallHandler(handleServiceMethodCall);
  }

  Future<T> invokeMethod<T>(String method, [dynamic arguments]) =>
      channel.invokeMethod(method, arguments);

  Future<dynamic> handleServiceMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'start':
        plugin.fastForwardInterval = call.arguments['fastForwardInterval'];
        plugin.rewindInterval = call.arguments['rewindInterval'];
        plugin.params = call.arguments['params'];
        plugin.started = true;
        return plugin.started;
      case 'connect':
        // No-op not really anything for us to do with connect on the web, the
        // streams should all be hydrated
        break;
      case 'disconnect':
        // No-op not really anything for us to do with disconnect on the web,
        // the streams should stay hydrated because everything is static and we
        // aren't working with isolates
        break;
      case 'isRunning':
        return plugin.started;
      case 'rewind':
        return plugin.backgroundHandler.invokeMethod('onRewind');
      case 'fastForward':
        return plugin.backgroundHandler.invokeMethod('onFastForward');
      case 'skipToPrevious':
        return plugin.backgroundHandler.invokeMethod('onSkipToPrevious');
      case 'skipToNext':
        return plugin.backgroundHandler.invokeMethod('onSkipToNext');
      case 'play':
        return plugin.backgroundHandler.invokeMethod('onPlay');
      case 'pause':
        return plugin.backgroundHandler.invokeMethod('onPause');
      case 'stop':
        return plugin.backgroundHandler.invokeMethod('onStop');
      case 'seekTo':
        return plugin.backgroundHandler
            .invokeMethod('onSeekTo', [call.arguments]);
      case 'prepareFromMediaId':
        return plugin.backgroundHandler
            .invokeMethod('onPrepareFromMediaId', [call.arguments]);
      case 'playFromMediaId':
        return plugin.backgroundHandler
            .invokeMethod('onPlayFromMediaId', [call.arguments]);
      case 'setBrowseMediaParent':
        return plugin.backgroundHandler
            .invokeMethod('onLoadChildren', [call.arguments]);
      case 'onClick':
        // No-op we don't really have the idea of a bluetooth button click on
        // the web
        break;
      case 'addQueueItem':
        return plugin.backgroundHandler
            .invokeMethod('onAddQueueItem', [call.arguments]);
      case 'addQueueItemAt':
        return plugin.backgroundHandler
            .invokeMethod('onQueueItemAt', call.arguments);
      case 'removeQueueItem':
        return plugin.backgroundHandler
            .invokeMethod('onRemoveQueueItem', [call.arguments]);
      case 'updateQueue':
        return plugin.backgroundHandler
            .invokeMethod('onUpdateQueue', [call.arguments]);
      case 'updateMediaItem':
        return plugin.backgroundHandler
            .invokeMethod('onUpdateMediaItem', [call.arguments]);
      case 'prepare':
        return plugin.backgroundHandler.invokeMethod('onPrepare');
      case 'playMediaItem':
        return plugin.backgroundHandler
            .invokeMethod('onPlayMediaItem', [call.arguments]);
      case 'skipToQueueItem':
        return plugin.backgroundHandler
            .invokeMethod('onSkipToMediaItem', [call.arguments]);
      case 'setRepeatMode':
        return plugin.backgroundHandler
            .invokeMethod('onSetRepeatMode', [call.arguments]);
      case 'setShuffleMode':
        return plugin.backgroundHandler
            .invokeMethod('onSetShuffleMode', [call.arguments]);
      case 'setRating':
        return plugin.backgroundHandler.invokeMethod('onSetRating',
            [call.arguments['rating'], call.arguments['extras']]);
      case 'setSpeed':
        return plugin.backgroundHandler
            .invokeMethod('onSetSpeed', [call.arguments]);
      default:
        if (call.method.startsWith(_CUSTOM_PREFIX)) {
          final result = await plugin.backgroundHandler
              .invokeMethod(call.method, call.arguments);
          return result;
        }
        throw PlatformException(
            code: 'Unimplemented',
            details: "The audio Service plugin for web doesn't implement "
                "the method '${call.method}'");
    }
  }
}

class BackgroundHandler {
  final AudioServicePlugin plugin;
  final MethodChannel channel;
  MediaItem mediaItem;

  BackgroundHandler(this.plugin, Registrar registrar)
      : channel = MethodChannel(
          'ryanheise.com/audioServiceBackground',
          const StandardMethodCodec(),
          registrar.messenger,
        ) {
    channel.setMethodCallHandler(handleBackgroundMethodCall);
  }

  Future<T> invokeMethod<T>(String method, [dynamic arguments]) =>
      channel.invokeMethod(method, arguments);

  Future<dynamic> handleBackgroundMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'started':
        return started(call);
      case 'ready':
        return ready(call);
      case 'stopped':
        return stopped(call);
      case 'setState':
        return setState(call);
      case 'setMediaItem':
        return setMediaItem(call);
      case 'setQueue':
        return setQueue(call);
      case 'androidForceEnableMediaButtons':
        //no-op
        break;
      default:
        throw PlatformException(
            code: 'Unimplemented',
            details:
                "The audio service background plugin for web doesn't implement "
                "the method '${call.method}'");
    }
  }

  Future<bool> started(MethodCall call) async => true;

  Future<dynamic> ready(MethodCall call) async => {
        'fastForwardInterval': plugin.fastForwardInterval ?? 30000,
        'rewindInterval': plugin.rewindInterval ?? 30000,
        'params': plugin.params
      };

  Future<void> stopped(MethodCall call) async {
    final session = html.window.navigator.mediaSession;
    session.metadata = null;
    plugin.started = false;
    mediaItem = null;
    plugin.clientHandler.invokeMethod('onStopped');
  }

  Future<void> setState(MethodCall call) async {
    final session = html.window.navigator.mediaSession;
    final List args = call.arguments;
    final List<MediaControl> controls = call.arguments[0]
        .map<MediaControl>((element) => MediaControl(
            action: MediaAction.values[element['action']],
            androidIcon: element['androidIcon'],
            label: element['label']))
        .toList();

    // Reset the handlers
    // TODO: Make this better... Like only change ones that have been changed
    try {
      session.setActionHandler('play', null);
      session.setActionHandler('pause', null);
      session.setActionHandler('previoustrack', null);
      session.setActionHandler('nexttrack', null);
      session.setActionHandler('seekbackward', null);
      session.setActionHandler('seekforward', null);
      session.setActionHandler('stop', null);
    } catch (e) {}

    int actionBits = 0;
    for (final control in controls) {
      try {
        switch (control.action) {
          case MediaAction.play:
            session.setActionHandler('play', AudioService.play);
            break;
          case MediaAction.pause:
            session.setActionHandler('pause', AudioService.pause);
            break;
          case MediaAction.skipToPrevious:
            session.setActionHandler(
                'previoustrack', AudioService.skipToPrevious);
            break;
          case MediaAction.skipToNext:
            session.setActionHandler('nexttrack', AudioService.skipToNext);
            break;
          // The naming convention here is a bit odd but seekbackward seems more
          // analagous to rewind than seekBackward
          case MediaAction.rewind:
            session.setActionHandler('seekbackward', AudioService.rewind);
            break;
          case MediaAction.fastForward:
            session.setActionHandler('seekforward', AudioService.fastForward);
            break;
          case MediaAction.stop:
            session.setActionHandler('stop', AudioService.stop);
            break;
          default:
            // no-op
            break;
        }
      } catch (e) {}
      int actionCode = 1 << control.action.index;
      actionBits |= actionCode;
    }

    for (int rawSystemAction in call.arguments[1]) {
      MediaAction action = MediaAction.values[rawSystemAction];

      switch (action) {
        case MediaAction.seekTo:
          try {
            setActionHandler('seekto', js.allowInterop((ActionResult ev) {
              print(ev.action);
              print(ev.seekTime);
              // Chrome uses seconds for whatever reason
              AudioService.seekTo(Duration(
                milliseconds: (ev.seekTime * 1000).round(),
              ));
            }));
          } catch (e) {}
          break;
        default:
          // no-op
          break;
      }

      int actionCode = 1 << rawSystemAction;
      actionBits |= actionCode;
    }

    try {
      // Dart also doesn't expose setPositionState
      if (mediaItem != null) {
        print(
            'Setting positionState Duration(${mediaItem.duration.inSeconds}), PlaybackRate(${args[6] ?? 1.0}), Position(${Duration(milliseconds: args[4]).inSeconds})');

        // Chrome looks for seconds for some reason
        setPositionState(PositionState(
          duration: (mediaItem.duration?.inMilliseconds ?? 0) / 1000,
          playbackRate: args[6] ?? 1.0,
          position: (args[4] ?? 0) / 1000,
        ));
      }
    } catch (e) {
      print(e);
    }

    plugin.clientHandler.invokeMethod('onPlaybackStateChanged', [
      args[2], // Processing state
      args[3], // Playing
      actionBits, // Action bits
      args[4], // Position
      args[5], // bufferedPosition
      args[6] ?? 1.0, // speed
      args[7] ?? DateTime.now().millisecondsSinceEpoch, // updateTime
      args[9], // repeatMode
      args[10], // shuffleMode
    ]);
  }

  Future<void> setMediaItem(MethodCall call) async {
    mediaItem = MediaItem.fromJson(call.arguments);
    // This would be how we could pull images out of the cache... But nothing is actually cached on web
    final artUri = /* mediaItem.extras['artCacheFile'] ?? */
        mediaItem.artUri;

    try {
      metadata = MediaMetadata(MetadataLiteral(
        album: mediaItem.album,
        title: mediaItem.title,
        artist: mediaItem.artist,
        artwork: [
          MetadataArtwork(
            src: artUri,
            sizes: '512x512',
          )
        ],
      ));
    } catch (e) {
      print('Metadata failed $e');
    }

    plugin.clientHandler.invokeMethod('onMediaChanged', [mediaItem.toJson()]);
  }

  Future<void> setQueue(MethodCall call) async {
    plugin.clientHandler.invokeMethod('onQueueChanged', [call.arguments]);
  }
}
