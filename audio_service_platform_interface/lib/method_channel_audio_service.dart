import 'package:flutter/services.dart';

import 'audio_service_platform_interface.dart';

class MethodChannelAudioService extends AudioServicePlatform {
  final MethodChannel _clientChannel =
      MethodChannel('com.ryanheise.audio_service.client.methods');
  final MethodChannel _handlerChannel =
      MethodChannel('com.ryanheise.audio_service.handler.methods');

  @override
  Future<ConfigureResponse> configure(ConfigureRequest request) async {
    return ConfigureResponse.fromMap((await _clientChannel
        .invokeMethod<Map<dynamic, dynamic>>('configure', request.toMap()))!);
  }

  @override
  Future<void> setState(SetStateRequest request) async {
    await _handlerChannel.invokeMethod('setState', request.toMap());
  }

  @override
  Future<void> setQueue(SetQueueRequest request) async {
    await _handlerChannel.invokeMethod('setQueue', request.toMap());
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {
    await _handlerChannel.invokeMethod('setMediaItem', request.toMap());
  }

  @override
  Future<void> stopService(StopServiceRequest request) async {
    await _handlerChannel.invokeMethod('stopService', request.toMap());
  }

  @override
  Future<void> androidForceEnableMediaButtons(
      AndroidForceEnableMediaButtonsRequest request) async {
    await _handlerChannel.invokeMethod(
        'androidForceEnableMediaButtons', request.toMap());
  }

  @override
  Future<void> notifyChildrenChanged(
      NotifyChildrenChangedRequest request) async {
    await _handlerChannel.invokeMethod(
        'notifyChildrenChanged', request.toMap());
  }

  @override
  Future<void> setAndroidPlaybackInfo(
      SetAndroidPlaybackInfoRequest request) async {
    await _handlerChannel.invokeMethod(
        'setAndroidPlaybackInfo', request.toMap());
  }

  void setClientCallbacks(AudioClientCallbacks callbacks) {
    _clientChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPlaybackStateChanged':
          callbacks.onPlaybackStateChanged(
              OnPlaybackStateChangedRequest.fromMap(call.arguments));
          break;
        case 'onMediaItemChanged':
          callbacks.onMediaItemChanged(
              OnMediaItemChangedRequest.fromMap(call.arguments));
          break;
        case 'onQueueChanged':
          callbacks
              .onQueueChanged(OnQueueChangedRequest.fromMap(call.arguments));
          break;
        //case 'onChildrenLoaded':
        //  callbacks.onChildrenLoaded(
        //      OnChildrenLoadedRequest.fromMap(call.arguments));
        //  break;
      }
    });
  }

  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {
    _handlerChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'getChildren':
          return (await callbacks.getChildren(GetChildrenRequest(
                  parentMediaId: call.arguments['parentMediaId'],
                  options: call.arguments['options'])))
              .toMap();
        case 'getMediaItem':
          return (await callbacks.getMediaItem(
              GetMediaItemRequest(mediaId: call.arguments['mediaId'])));
        case 'click':
          print('### received click: ${call.arguments}');
          try {
            print('button value is "${call.arguments['button']}"');
            print('type: ${call.arguments['button'].runtimeType}');
            await callbacks.click(ClickRequest(
                button: MediaButtonMessage.values[call.arguments['button']]));
          } catch (e, stackTrace) {
            print(e);
            print(stackTrace);
          }
          print('### called callbacks.click');
          return null;
        case 'stop':
          await callbacks.stop(StopRequest());
          return null;
        case 'pause':
          await callbacks.pause(PauseRequest());
          return null;
        case 'prepare':
          await callbacks.prepare(PrepareRequest());
          return null;
        case 'prepareFromMediaId':
          await callbacks.prepareFromMediaId(PrepareFromMediaIdRequest(
              mediaId: call.arguments['mediaId'],
              extras: _castMap(call.arguments['extras'])));
          return null;
        case 'prepareFromSearch':
          await callbacks.prepareFromSearch(PrepareFromSearchRequest(
              query: call.arguments['query'],
              extras: _castMap(call.arguments['extras'])));
          return null;
        case 'prepareFromUri':
          await callbacks.prepareFromUri(PrepareFromUriRequest(
              uri: Uri.parse(call.arguments['uri']),
              extras: _castMap(call.arguments['extras'])));
          return null;
        case 'play':
          await callbacks.play(PlayRequest());
          return null;
        case 'playFromMediaId':
          await callbacks.playFromMediaId(PlayFromMediaIdRequest(
              mediaId: call.arguments['mediaId'],
              extras: _castMap(call.arguments['extras'])));
          return null;
        case 'playFromSearch':
          await callbacks.playFromSearch(PlayFromSearchRequest(
              query: call.arguments['query'],
              extras: _castMap(call.arguments['extras'])));
          return null;
        case 'playFromUri':
          await callbacks.playFromUri(PlayFromUriRequest(
              uri: Uri.parse(call.arguments['uri']),
              extras: _castMap(call.arguments['extras'])));
          return null;
        case 'playMediaItem':
          await callbacks.playMediaItem(PlayMediaItemRequest(
              mediaItem:
                  MediaItemMessage.fromMap(call.arguments['mediaItem'])));
          return null;
        case 'addQueueItem':
          await callbacks.addQueueItem(AddQueueItemRequest(
              mediaItem:
                  MediaItemMessage.fromMap(call.arguments['mediaItem'])));
          return null;
        case 'insertQueueItem':
          await callbacks.insertQueueItem(InsertQueueItemRequest(
              index: call.arguments['index'],
              mediaItem:
                  MediaItemMessage.fromMap(call.arguments['mediaItem'])));
          return null;
        case 'updateQueue':
          await callbacks.updateQueue(UpdateQueueRequest(
              queue: (call.arguments['queue'] as List)
                  .map((dynamic raw) => MediaItemMessage.fromMap(raw as Map))
                  .toList()));
          return null;
        case 'updateMediaItem':
          await callbacks.updateMediaItem(UpdateMediaItemRequest(
              mediaItem:
                  MediaItemMessage.fromMap(call.arguments['mediaItem'])));
          return null;
        case 'removeQueueItem':
          await callbacks.removeQueueItem(RemoveQueueItemRequest(
              mediaItem:
                  MediaItemMessage.fromMap(call.arguments['mediaItem'])));
          return null;
        case 'removeQueueItemAt':
          await callbacks.removeQueueItemAt(
              RemoveQueueItemAtRequest(index: call.arguments['index']));
          return null;
        case 'skipToNext':
          await callbacks.skipToNext(SkipToNextRequest());
          return null;
        case 'skipToPrevious':
          await callbacks.skipToPrevious(SkipToPreviousRequest());
          return null;
        case 'fastForward':
          await callbacks.fastForward(FastForwardRequest());
          return null;
        case 'rewind':
          await callbacks.rewind(RewindRequest());
          return null;
        case 'skipToQueueItem':
          await callbacks.skipToQueueItem(
              SkipToQueueItemRequest(index: call.arguments['index']));
          return null;
        case 'seekTo':
          await callbacks.seek(SeekRequest(
              position: Duration(microseconds: call.arguments['position'])));
          return null;
        case 'setRepeatMode':
          await callbacks.setRepeatMode(SetRepeatModeRequest(
              repeatMode: AudioServiceRepeatModeMessage
                  .values[call.arguments['repeatMode']]));
          return null;
        case 'setShuffleMode':
          await callbacks.setShuffleMode(SetShuffleModeRequest(
              shuffleMode: AudioServiceShuffleModeMessage
                  .values[call.arguments['shuffleMode']]));
          return null;
        case 'setRating':
          await callbacks.setRating(SetRatingRequest(
              rating: RatingMessage.fromMap(call.arguments['rating']),
              extras: call.arguments['extras']));
          return null;
        case 'setCaptioningEnabled':
          await callbacks.setCaptioningEnabled(
              SetCaptioningEnabledRequest(enabled: call.arguments['enabled']));
          return null;
        case 'seekBackward':
          await callbacks.seekBackward(
              SeekBackwardRequest(begin: call.arguments['begin']));
          return null;
        case 'seekForward':
          await callbacks
              .seekForward(SeekForwardRequest(begin: call.arguments['begin']));
          return null;
        case 'setSpeed':
          await callbacks
              .setSpeed(SetSpeedRequest(speed: call.arguments['speed']));
          return null;
        case 'setVolumeTo':
          await callbacks.androidSetRemoteVolume(AndroidSetRemoteVolumeRequest(
              volumeIndex: call.arguments['volumeIndex']));
          return null;
        case 'adjustVolume':
          await callbacks.androidAdjustRemoteVolume(
              AndroidAdjustRemoteVolumeRequest(
                  direction: AndroidVolumeDirectionMessage
                      .values[call.arguments['direction']]!));
          return null;
        case 'onTaskRemoved':
          await callbacks.onTaskRemoved(OnTaskRemovedRequest());
          return null;
        case 'onNotificationDeleted':
          await callbacks.onNotificationDeleted(OnNotificationDeletedRequest());
          return null;
        case 'customAction':
          await callbacks.customAction(CustomActionRequest(
              name: call.arguments['name'],
              extras: _castMap(call.arguments['extras'])));
          return null;
        default:
          throw PlatformException(code: 'Unimplemented');
      }
    });
  }
}

_castMap(Map? map) => map?.cast<String, dynamic>();
