import 'package:audioplayer/audioplayer.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

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
MediaControl stopControl = MediaControl(
  androidIcon: 'drawable/ic_action_stop',
  label: 'Stop',
  action: MediaAction.stop,
);

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  PlaybackState state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        connect();
        break;
      case AppLifecycleState.paused:
        AudioService.disconnect();
        break;
      default:
        break;
    }
  }

  void connect() {
    AudioService.connect(
      onPlaybackStateChanged: (state, position, speed, updateTime) {
        setState(() {
          this.state = state;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
        appBar: new AppBar(
          title: const Text('Audio Service Demo'),
        ),
        body: new Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: state == PlaybackState.playing
                ? [pauseButton(), stopButton()]
                : state == PlaybackState.paused
                    ? [playButton(), stopButton()]
                    : [audioPlayerButton(), textToSpeechButton()],
          ),
        ),
      ),
    );
  }

  RaisedButton audioPlayerButton() =>
      startButton('AudioPlayer', _backgroundAudioPlayerTask);

  RaisedButton textToSpeechButton() =>
      startButton('TextToSpeech', _backgroundTextToSpeechTask);

  RaisedButton startButton(String label, Function backgroundTask) =>
      RaisedButton(
        child: Text(label),
        onPressed: () {
          AudioService.start(
            backgroundTask: backgroundTask,
            resumeOnClick: true,
            notificationChannelName: 'Audio Service Demo',
            notificationColor: 0xFF2196f3,
            androidNotificationIcon: 'mipmap/ic_launcher',
          );
        },
      );

  IconButton playButton() => IconButton(
        icon: Icon(Icons.play_arrow),
        iconSize: 64.0,
        onPressed: AudioService.play,
      );

  IconButton pauseButton() => IconButton(
        icon: Icon(Icons.pause),
        iconSize: 64.0,
        onPressed: AudioService.pause,
      );

  IconButton stopButton() => IconButton(
        icon: Icon(Icons.stop),
        iconSize: 64.0,
        onPressed: AudioService.stop,
      );
}

void _backgroundAudioPlayerTask() async {
  CustomAudioPlayer player = CustomAudioPlayer();
  AudioServiceBackground.run(
    onStart: player.run,
    onPlay: player.play,
    onPause: player.pause,
    onStop: player.stop,
    onClick: (MediaButton button) => player.playPause(),
  );
}

class CustomAudioPlayer {
  static const streamUri =
      'http://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3';
  AudioPlayer _audioPlayer = new AudioPlayer();
  Completer _completer = Completer();
  bool _playing = true;

  Future<void> run() async {
    MediaItem mediaItem =
        MediaItem(id: '1', album: 'Sample Album', title: 'Sample Title');

    AudioServiceBackground.setMediaItem(mediaItem);

    var playerStateSubscription = _audioPlayer.onPlayerStateChanged
        .where((state) => state == AudioPlayerState.COMPLETED)
        .listen((state) {
      stop();
    });
    play();
    await _completer.future;
    playerStateSubscription.cancel();
  }

  void playPause() {
    if (_playing)
      pause();
    else
      play();
  }

  void play() {
    _audioPlayer.play(streamUri);
    AudioServiceBackground.setState(
      controls: [pauseControl, stopControl],
      state: PlaybackState.playing,
    );
  }

  void pause() {
    _audioPlayer.pause();
    AudioServiceBackground.setState(
      controls: [playControl, stopControl],
      state: PlaybackState.paused,
    );
  }

  void stop() {
    _audioPlayer.stop();
    AudioServiceBackground.setState(
      controls: [],
      state: PlaybackState.stopped,
    );
    _completer.complete();
  }
}

void _backgroundTextToSpeechTask() async {
  TextPlayer textPlayer = TextPlayer();
  AudioServiceBackground.run(
    onStart: textPlayer.run,
    onPlay: textPlayer.playPause,
    onPause: textPlayer.playPause,
    onStop: textPlayer.stop,
    onClick: (MediaButton button) => textPlayer.playPause(),
  );
}

class TextPlayer {
  FlutterTts _tts = FlutterTts();

  /// Represents the completion of a period of playing or pausing.
  Completer _playPauseCompleter = Completer();

  /// This wraps [_playPauseCompleter.future], replacing [_playPauseCompleter]
  /// if it has already completed.
  Future _playPauseFuture() {
    if (_playPauseCompleter.isCompleted) _playPauseCompleter = Completer();
    return _playPauseCompleter.future;
  }

  PlaybackState get _state => AudioServiceBackground.state;

  Future<void> run() async {
    playPause();
    for (var i = 1; i <= 10 && _state != PlaybackState.stopped; i++) {
      AudioServiceBackground.setMediaItem(mediaItem(i));
      AudioServiceBackground.androidForceEnableMediaButtons();
      _tts.speak('$i');
      // Wait for the speech or a pause request.
      await Future.any(
          [Future.delayed(Duration(seconds: 1)), _playPauseFuture()]);
      // If we were just paused...
      if (_playPauseCompleter.isCompleted && _state == PlaybackState.paused) {
        // Wait to be unpaused...
        await _playPauseFuture();
      }
    }
    if (_state != PlaybackState.stopped) stop();
  }

  MediaItem mediaItem(int number) =>
      MediaItem(id: '$number', album: 'Numbers', title: 'Number $number');

  void playPause() {
    if (_state == PlaybackState.playing) {
      _tts.stop();
      AudioServiceBackground.setState(
        controls: [playControl, stopControl],
        state: PlaybackState.paused,
      );
    } else {
      AudioServiceBackground.setState(
        controls: [pauseControl, stopControl],
        state: PlaybackState.playing,
      );
    }
    _playPauseCompleter.complete();
  }

  void stop() {
    if (_state == PlaybackState.stopped) return;
    _tts.stop();
    AudioServiceBackground.setState(
      controls: [],
      state: PlaybackState.stopped,
    );
    _playPauseCompleter.complete();
  }
}
