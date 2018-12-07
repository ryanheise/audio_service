import 'package:audioplayer/audioplayer.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';

MediaItem mediaItem = MediaItem(id: '1', album: 'Sample Album', title: 'Sample Title');

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
                    : [playButton()],
          ),
        ),
      ),
    );
  }

  IconButton playButton() => IconButton(
        icon: Icon(Icons.play_arrow),
        iconSize: 64.0,
        onPressed: () {
          if (state == PlaybackState.paused) {
            AudioService.play();
          } else {
            AudioService.start(
              backgroundTask: _backgroundCallback,
              resumeOnClick: true,
              notificationChannelName: 'Audio Service Demo',
              notificationColor: 0xFF2196f3,
              androidNotificationIcon: 'mipmap/ic_launcher',
              queue: [mediaItem],
            );
          }
        },
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

void _backgroundCallback() async {
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
  AudioPlayer audioPlayer = new AudioPlayer();
  Completer completer = Completer();
  bool playing = true;

  Future<void> run() async {
    AudioServiceBackground.setMediaItem(mediaItem);

    var playerStateSubscription = audioPlayer.onPlayerStateChanged
        .where((state) => state == AudioPlayerState.COMPLETED)
        .listen((state) {
      stop();
    });
    play();
    await completer.future;
    playerStateSubscription.cancel();
  }

  void playPause() {
    if (playing)
      pause();
    else
      play();
  }

  void play() {
    audioPlayer.play(streamUri);
    AudioServiceBackground.setState(
      controls: [pauseControl, stopControl],
      state: PlaybackState.playing,
    );
  }

  void pause() {
    audioPlayer.pause();
    AudioServiceBackground.setState(
      controls: [playControl, stopControl],
      state: PlaybackState.paused,
    );
  }

  void stop() {
    audioPlayer.stop();
    AudioServiceBackground.setState(
      controls: [],
      state: PlaybackState.stopped,
    );
    completer.complete();
  }
}
