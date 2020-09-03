import 'dart:async';
import 'dart:html' as html;
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

class Art {
  String src;
  String type;
  String sizes;
  Art({this.src, this.type, this.sizes});
}

class AudioServicePlugin {
  // BackgroundAudioTask _task;
  int fastForwardInterval;
  int rewindInterval;
  bool started = false;
  MethodChannel serviceChannel;
  MethodChannel backgroundChannel;

  static void registerWith(Registrar registrar) {
    final MethodChannel serviceChannel = MethodChannel(
      'ryanheise.com/audioService',
      const StandardMethodCodec(),
      registrar.messenger,
    );

    final MethodChannel backgroundChannel = MethodChannel(
      'ryanheise.com/audioServiceBackground',
      const StandardMethodCodec(),
      registrar.messenger,
    );
    final AudioServicePlugin instance = AudioServicePlugin();
    instance.serviceChannel = serviceChannel;
    instance.backgroundChannel = backgroundChannel;
    //'ryanheise.com/audioServiceBackground'
    serviceChannel.setMethodCallHandler(instance.handleServiceMethodCall);
    backgroundChannel.setMethodCallHandler(instance.handleBackgroundMethodCall);
  }

  Future<dynamic> handleServiceMethodCall(MethodCall call) async {
    print("Method call ${call.method}");
    switch (call.method) {
      case 'start':
        fastForwardInterval = call.arguments['fastForwardInterval'];
        rewindInterval = call.arguments['rewindInterval'];
        started = true;
        return started;
      case 'connect':
        print('Connecting! ${call.arguments}');
        return false;
      case 'isRunning':
        print('Running: $started');
        return started;
      case 'rewind':
        return backgroundChannel.invokeMethod('onRewind');
      case 'fastForward':
        return backgroundChannel.invokeMethod('onFastForward');
      case 'skipToPrevious':
        return backgroundChannel.invokeMethod('onSkipToPrevious');
      case 'skipToNext':
        return backgroundChannel.invokeMethod('onSkipToNext');
      case 'play':
        return backgroundChannel.invokeMethod('onPlay');
      case 'pause':
        return backgroundChannel.invokeMethod('onPause');
      case 'stop':
        return backgroundChannel.invokeMethod('onStop');
      case 'prepareFromMediaId':
        return backgroundChannel.invokeMethod(
            'onPrepareFromMediaId', call.arguments);
      case 'playFromMediaId':
        return backgroundChannel.invokeMethod(
            'onPlayFromMediaId', call.arguments);
      default:
        // return true;
        throw PlatformException(
            code: 'Unimplemented',
            details: "The audio Service plugin for web doesn't implement "
                "the method '${call.method}'");
    }
  }

  Future<dynamic> handleBackgroundMethodCall(MethodCall call) async {
    final session = html.window.navigator.mediaSession;
    print("Method call ${call.method}");
    switch (call.method) {
      case 'started':
        return true;
      case 'ready':
        return {
          'fastForwardInterval': fastForwardInterval ?? 30000,
          'rewindInterval': rewindInterval ?? 30000,
        };
      case 'stopped':
        session.metadata = null;
        started = false;
        break;
      case 'setState':
        print(call.arguments);
        final List<MediaControl> controls = call.arguments[0]
            .map<MediaControl>((element) => MediaControl(
                action: MediaAction.values[element['action']],
                androidIcon: element['androidIcon'],
                label: element['label']))
            .toList();

        session.setActionHandler('play', null);
        session.setActionHandler('pause', null);
        session.setActionHandler('previoustrack', null);
        session.setActionHandler('nexttrack', null);
        session.setActionHandler('seekbackward', null);
        session.setActionHandler('seekforward', null);
        session.setActionHandler('stop', null);

        for (final control in controls) {
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
            case MediaAction.rewind:
              session.setActionHandler('seekbackward', AudioService.rewind);
              break;
            case MediaAction.fastForward:
              session.setActionHandler('seekforward', AudioService.fastForward);
              break;
            case MediaAction.stop:
              session.setActionHandler('stop', AudioService.stop);
              break;
              // Not really possible at the moment because the seekto handler
              // should take a details argument but the dart method expects nothing
              // case MediaAction.seekTo:
              //   session
              //       .setActionHandler('seekto', AudioService.seekTo);
              break;
            default:
              // no-op
              break;
          }
        }
        break;
      case 'setMediaItem':
        final mediaItem = MediaItem.fromJson(call.arguments);
        print('mediaItem: $mediaItem');
        final mapped = <String, dynamic>{
          'title': mediaItem.title,
          'artist': mediaItem.artist,
          'album': mediaItem.album,
          if (mediaItem.artUri != null)
            'artwork': [
              Art(src: mediaItem.artUri),
            ]
        };
        html.window.navigator.mediaSession.metadata =
            html.MediaMetadata(mapped);

        break;
      case 'setQueue':
        //no-op
        break;
      case 'androidForceEnableMediaButtons':
        //no-op
        break;
      default:
        // return true;
        throw PlatformException(
            code: 'Unimplemented',
            details:
                "The audio service background plugin for web doesn't implement "
                "the method '${call.method}'");
    }
  }
}
