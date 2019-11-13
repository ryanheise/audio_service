import 'package:audioplayer/audioplayer.dart';
import 'package:flutter/material.dart';
import 'dart:async';

// NOTE!
//
// I have temporarily commented out the TextToSpeech demo because I couldn't
// get it to compile on XCode 10.1 which is the newest version that is compatible
// with the borrowed Mac I'm using.
//
// TODO: Fix this.

import 'package:audio_service/audio_service.dart';
//import 'package:flutter_tts/flutter_tts.dart';
import 'package:rxdart/rxdart.dart';

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    connect();
  }

  @override
  void dispose() {
    disconnect();
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
        disconnect();
        break;
      default:
        break;
    }
  }

  void connect() async {
    await AudioService.connect();
  }

  void disconnect() {
    AudioService.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: WillPopScope(
        onWillPop: () {
          disconnect();
          return Future.value(true);
        },
        child: new Scaffold(
          appBar: new AppBar(
            title: const Text('Audio Service Demo'),
          ),
          body: new Center(
            child: StreamBuilder(
              stream: AudioService.playbackStateStream,
              builder: (context, snapshot) {
                PlaybackState state = snapshot.data;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (state?.basicState == BasicPlaybackState.connecting) ...[
                      stopButton(),
                      Text("Connecting..."),
                    ] else if (state?.basicState ==
                        BasicPlaybackState.playing) ...[
                      pauseButton(),
                      stopButton(),
                      positionIndicator(state),
                    ] else if (state?.basicState ==
                        BasicPlaybackState.paused) ...[
                      playButton(),
                      stopButton(),
                      positionIndicator(state),
                    ] else ...[
                      audioPlayerButton(),
                      textToSpeechButton(),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  RaisedButton audioPlayerButton() =>
      startButton('AudioPlayer', _audioPlayerTaskEntrypoint);

  //RaisedButton textToSpeechButton() =>
  //    startButton('TextToSpeech', _textToSpeechTaskEntrypoint);
  Widget textToSpeechButton() => SizedBox();

  RaisedButton startButton(String label, Function entrypoint) =>
      RaisedButton(
        child: Text(label),
        onPressed: () {
          AudioService.start(
            backgroundTaskEntrypoint: entrypoint,
            resumeOnClick: true,
            androidNotificationChannelName: 'Audio Service Demo',
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

  Widget positionIndicator(PlaybackState state) => StreamBuilder(
        stream: Observable.periodic(Duration(milliseconds: 200)),
        builder: (context, snapshdot) =>
            Text("${(state.currentPosition / 1000).toStringAsFixed(3)}"),
      );
}

void _audioPlayerTaskEntrypoint() async {
  AudioServiceBackground.run(() => CustomAudioPlayer());
}

class CustomAudioPlayer extends BackgroundAudioTask {
  static const streamUri =
      'https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3';
  AudioPlayer _audioPlayer = new AudioPlayer();
  Completer _completer = Completer();
  int _position;

  @override
  Future<void> onStart() async {
    MediaItem mediaItem = MediaItem(
        id: 'audio_1',
        album: 'Sample Album',
        title: 'Sample Title',
        artist: 'Sample Artist');

    AudioServiceBackground.setMediaItem(mediaItem);

    var playerStateSubscription = _audioPlayer.onPlayerStateChanged
        .where((state) => state == AudioPlayerState.COMPLETED)
        .listen((state) {
      onStop();
    });
    var audioPositionSubscription =
        _audioPlayer.onAudioPositionChanged.listen((when) {
      final connected = _position == null;
      _position = when.inMilliseconds;
      if (connected) {
        // After a delay, we finally start receiving audio positions
        // from the AudioPlayer plugin, so we can set the state to
        // playing.
        _setPlayingState();
      }
    });
    onPlay();
    await _completer.future;
    playerStateSubscription.cancel();
    audioPositionSubscription.cancel();
  }

  void _setPlayingState() {
    AudioServiceBackground.setState(
      controls: [pauseControl, stopControl],
      basicState: BasicPlaybackState.playing,
      position: _position,
    );
  }

  void playPause() {
    if (AudioServiceBackground.state.basicState == BasicPlaybackState.playing)
      onPause();
    else
      onPlay();
  }

  @override
  void onPlay() {
    _audioPlayer.play(streamUri);
    if (_position == null) {
      // There may be a delay while the AudioPlayer plugin connects.
      AudioServiceBackground.setState(
        controls: [stopControl],
        basicState: BasicPlaybackState.connecting,
        position: 0,
      );
    } else {
      // We've already connected, so no delay.
      _setPlayingState();
    }
  }

  @override
  void onPause() {
    _audioPlayer.pause();
    AudioServiceBackground.setState(
      controls: [playControl, stopControl],
      basicState: BasicPlaybackState.paused,
      position: _position,
    );
  }

  @override
  void onClick(MediaButton button) {
    playPause();
  }

  @override
  void onStop() {
    _audioPlayer.stop();
    AudioServiceBackground.setState(
      controls: [],
      basicState: BasicPlaybackState.stopped,
    );
    _completer.complete();
  }
}

//void _textToSpeechTaskEntrypoint() async {
//  AudioServiceBackground.run(() => TextPlayer());
//}

//class TextPlayer extends BackgroundAudioTask {
//  FlutterTts _tts = FlutterTts();
//
//  /// Represents the completion of a period of playing or pausing.
//  Completer _playPauseCompleter = Completer();
//
//  /// This wraps [_playPauseCompleter.future], replacing [_playPauseCompleter]
//  /// if it has already completed.
//  Future _playPauseFuture() {
//    if (_playPauseCompleter.isCompleted) _playPauseCompleter = Completer();
//    return _playPauseCompleter.future;
//  }
//
//  BasicPlaybackState get _basicState => AudioServiceBackground.state.basicState;
//
//  @override
//  Future<void> onStart() async {
//    playPause();
//    for (var i = 1; i <= 10 && _basicState != BasicPlaybackState.stopped; i++) {
//      AudioServiceBackground.setMediaItem(mediaItem(i));
//      AudioServiceBackground.androidForceEnableMediaButtons();
//      _tts.speak('$i');
//      // Wait for the speech or a pause request.
//      await Future.any(
//          [Future.delayed(Duration(seconds: 1)), _playPauseFuture()]);
//      // If we were just paused...
//      if (_playPauseCompleter.isCompleted &&
//          _basicState == BasicPlaybackState.paused) {
//        // Wait to be unpaused...
//        await _playPauseFuture();
//      }
//    }
//    if (_basicState != BasicPlaybackState.stopped) onStop();
//  }
//
//  MediaItem mediaItem(int number) => MediaItem(
//      id: 'tts_$number',
//      album: 'Numbers',
//      title: 'Number $number',
//      artist: 'Sample Artist');
//
//  void playPause() {
//    if (_basicState == BasicPlaybackState.playing) {
//      _tts.stop();
//      AudioServiceBackground.setState(
//        controls: [playControl, stopControl],
//        basicState: BasicPlaybackState.paused,
//      );
//    } else {
//      AudioServiceBackground.setState(
//        controls: [pauseControl, stopControl],
//        basicState: BasicPlaybackState.playing,
//      );
//    }
//    _playPauseCompleter.complete();
//  }
//
//  @override
//  void onClick(MediaButton button) {
//    playPause();
//  }
//
//  @override
//  void onStop() {
//    if (_basicState == BasicPlaybackState.stopped) return;
//    _tts.stop();
//    AudioServiceBackground.setState(
//      controls: [],
//      basicState: BasicPlaybackState.stopped,
//    );
//    _playPauseCompleter.complete();
//  }
//}
