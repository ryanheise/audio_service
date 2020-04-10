import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

typedef HandlePlayBackEvent = Function Function(BasicPlaybackState skippedState);

abstract class AudioPlayerBase {
  void initialize(
      Function handlePlayBackCompleted, HandlePlayBackEvent handlePlayBackEvent);
  void setUrl(String url);
  void dispose();
  Stream<Duration> get bufferedPositionStream;
  Stream<Duration> get getPositionStream;
  Stream<Duration> get durationStream;
  Stream<FullAudioPlaybackState> get audioPlaybackState;
}

class JustAudioPlayer implements AudioPlayerBase {
  AudioPlayer _player;

  @override
  void initialize(
      Function handlePlayBackCompleted, Function handlePlayBackEvent) {
    _player = AudioPlayer();
    _player.playbackStateStream
        .where((state) => state == AudioPlaybackState.completed)
        .listen((state) {
      handlePlayBackCompleted();
    });
    _player.playbackEventStream.listen((event) {
      if (event.state != AudioPlaybackState.stopped || event.state != AudioPlaybackState.completed) {
        handlePlayBackEvent();
      }
    });
  }

  @override
  void setUrl(String url) {
    _player.setUrl(url);
  }

  @override
  void dispose() {
    _player.dispose();
  }

  BasicPlaybackState eventToBasicState(
      AudioPlaybackEvent event, BasicPlaybackState isSkippedState) {
    if (event.buffering) {
      return BasicPlaybackState.buffering;
    } else {
      switch (event.state) {
        case AudioPlaybackState.none:
          return BasicPlaybackState.none;
        case AudioPlaybackState.stopped:
          return BasicPlaybackState.stopped;
        case AudioPlaybackState.paused:
          return BasicPlaybackState.paused;
        case AudioPlaybackState.playing:
          return BasicPlaybackState.playing;
        case AudioPlaybackState.connecting:
          return isSkippedState ?? BasicPlaybackState.connecting;
        case AudioPlaybackState.completed:
          return BasicPlaybackState.stopped;
        default:
          throw Exception("Illegal state");
      }
    }
  }

  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  @override
  Stream<Duration> get getPositionStream => _player.getPositionStream();
  @override
  Stream<Duration> get durationStream => _player.durationStream;
  @override
  Stream<FullAudioPlaybackState> get audioPlaybackState =>
      _player.fullPlaybackStateStream;

  // Stream<AudioServicePlaybackState> get audioServicePlaybackStream =>
  //     _player.playbackEventStream.map(_eventToBasicState);
}
