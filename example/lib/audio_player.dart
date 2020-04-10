import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

typedef PlaybackStateCallback = void Function(
    BasicPlaybackState state, int position);

abstract class AudioPlayerBase {
  void initialize(
    Function handlePlayBackCompleted,
    BasicPlaybackState skippedState,
    PlaybackStateCallback handlePlayBackEvent,
  );
  Future<void> play({String url});
  Future<void> pause();
  Future<void> seekTo(int position);
  Future<void> stop(bool cancelSubscriptions);
  void dispose();
}

class JustAudioPlayer implements AudioPlayerBase {
  AudioPlayer _player;
  StreamSubscription<AudioPlaybackState> _audioPlayBackStateStream;
  StreamSubscription<AudioPlaybackEvent> _audioPlayBackEventStream;

  @override
  void initialize(
    Function handlePlayBackCompleted,
    BasicPlaybackState skippedState,
    PlaybackStateCallback handlePlayBackEvent,
  ) {
    _player = AudioPlayer();
    _player.playbackStateStream
        .where((state) => state == AudioPlaybackState.completed)
        .listen((state) {
      handlePlayBackCompleted();
    });
    _player.playbackEventStream.listen((event) {
      if (event.state != AudioPlaybackState.stopped ||
          event.state != AudioPlaybackState.completed) {
        handlePlayBackEvent(
          _eventToBasicState(event, skippedState),
          event.position.inMilliseconds,
        );
      }
    });
  }

  @override
  Future<void> play({String url}) async {
    if (url != null) await _player.setUrl(url);
    _player.play();
  }

  @override
  Future<void> pause() async {
    _player.pause();
  }

  Future<void> seekTo(int position) async {
    await _player.seek(Duration(milliseconds: position));
  }

  Future<void> stop(bool cancelSubscriptions) async {
    await _player.stop();
    if (cancelSubscriptions) {
      _audioPlayBackStateStream.cancel();
      _audioPlayBackEventStream.cancel();
    }
  }

  @override
  void dispose() {
    _player.dispose();
  }

  BasicPlaybackState _eventToBasicState(
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
}