import 'package:audio_service/audio_service.dart';

const asciiSquare = '▮';

class Data {
  static final playbackState = PlaybackState(
    processingState: AudioProcessingState.buffering,
    playing: true,
    controls: [MediaControl.pause],
    androidCompactActionIndices: [0],
    systemActions: {MediaAction.seek},
    updatePosition: const Duration(seconds: 30),
    bufferedPosition: const Duration(seconds: 35),
    speed: 1.5,
    updateTime: DateTime.now(),
    errorCode: 3,
    errorMessage: 'error message',
    repeatMode: AudioServiceRepeatMode.all,
    shuffleMode: AudioServiceShuffleMode.all,
    captioningEnabled: true,
    queueIndex: 0,
  );
  static final playbackStates = [
    PlaybackState(playing: true),
    PlaybackState(processingState: AudioProcessingState.buffering),
    PlaybackState(speed: 1.5),
  ];
  static const query = 'query';
  static final uri = Uri.parse('https://example.com/foo');
  static const mediaId = '1';
  static const mediaItem = MediaItem(id: '1', title: 'title1');
  static final mediaItems = [
    const MediaItem(id: '1', title: 'title1'),
    const MediaItem(id: '2', title: 'title2'),
    const MediaItem(id: '3', title: 'title3'),
  ];
  static const extras = <String, dynamic>{
    'key': 'value',
  };
  static final remotePlaybackInfo = RemoteAndroidPlaybackInfo(
    volumeControlType: AndroidVolumeControlType.absolute,
    maxVolume: 10,
    volume: 5,
  );
}
