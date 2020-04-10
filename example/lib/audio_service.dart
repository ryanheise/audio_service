import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'audio_player.dart';

class AudioServiceTask extends BackgroundAudioTask {
  final AudioPlayerBase _audioPlayer;
  AudioServiceTask(this._audioPlayer) {
    _audioPlayer.initialize(
      _handlePlaybackCompleted,
      _skipState,
      (BasicPlaybackState basicPlaybackState, int position) => _setState(
        state: basicPlaybackState,
        position: position,
      ),
    );
  }

  BasicPlaybackState _skipState;
  int _queueIndex = -1;
  bool _playing;

  final _queue = <MediaItem>[
    MediaItem(
      id: "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3",
      album: "Science Friday",
      title: "A Salute To Head-Scratching Science",
      artist: "Science Friday and WNYC Studios",
      duration: 5739820,
      artUri:
          "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg",
    ),
    MediaItem(
      id: "https://s3.amazonaws.com/scifri-segments/scifri201711241.mp3",
      album: "Science Friday",
      title: "From Cat Rheology To Operatic Incompetence",
      artist: "Science Friday and WNYC Studios",
      duration: 2856950,
      artUri:
          "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg",
    ),
  ];
  bool get hasNext => _queueIndex + 1 < _queue.length;
  bool get hasPrevious => _queueIndex > 0;
  MediaItem get mediaItem => _queue[_queueIndex];

  void _handlePlaybackCompleted() {
    if (hasNext) {
      onSkipToNext();
    } else {
      onStop();
    }
  }

  @override
  Future<void> onStart() async {
    AudioServiceBackground.setQueue(_queue);
    await onSkipToNext();
  }

  @override
  Future<void> onSkipToNext() => _skip(1);

  @override
  Future<void> onSkipToPrevious() => _skip(-1);

  Future<void> _skip(int offset) async {
    final _newIndex = _queueIndex + offset;
    if (!(_newIndex >= 0 && _newIndex < _queue.length)) return;
    if (_playing) await _audioPlayer.stop(false);
    _queueIndex = _newIndex;
    AudioServiceBackground.setMediaItem(mediaItem);
    _skipState = offset > 0
        ? BasicPlaybackState.skippingToNext
        : BasicPlaybackState.skippingToPrevious;
    await _audioPlayer.play(url: mediaItem.id);
    _skipState = null;
  }

  @override
  void onSeekTo(int position) {
    _audioPlayer.seekTo(position);
  }

  @override
  void onClick(MediaButton button) {
    if (_skipState == null) {
      if (AudioServiceBackground.state.basicState ==
          BasicPlaybackState.playing) {
        _playing = true;
        _audioPlayer.play();
      } else {
        _playing = false;
        _audioPlayer.pause();
      }
    }
  }

  @override
  void onStop() {
    _audioPlayer.stop(true);
    _setState(state: BasicPlaybackState.stopped);
  }

  void _setState({@required BasicPlaybackState state, int position}) {
    AudioServiceBackground.setState(
      controls: getControls(state),
      systemActions: [MediaAction.seekTo],
      basicState: state,
      position: position,
    );
  }

  List<MediaControl> getControls(BasicPlaybackState state) {
    if (_playing) {
      return [
        skipToPreviousControl,
        pauseControl,
        stopControl,
        skipToNextControl
      ];
    } else {
      return [
        skipToPreviousControl,
        playControl,
        stopControl,
        skipToNextControl
      ];
    }
  }
}

MediaControl playControl = MediaControl(
  androidIcon: 'drawable/ic_action_play_arrow',
  label: 'Play',
  action: MediaAction.play,
);
MediaControl pauseControl = MediaControl(
  androidIcon: 'drawable/ic_action_pause',
  label: 'Pause',
  action: MediaAction.pause,
);
MediaControl skipToNextControl = MediaControl(
  androidIcon: 'drawable/ic_action_skip_next',
  label: 'Next',
  action: MediaAction.skipToNext,
);
MediaControl skipToPreviousControl = MediaControl(
  androidIcon: 'drawable/ic_action_skip_previous',
  label: 'Previous',
  action: MediaAction.skipToPrevious,
);
MediaControl stopControl = MediaControl(
  androidIcon: 'drawable/ic_action_stop',
  label: 'Stop',
  action: MediaAction.stop,
);
