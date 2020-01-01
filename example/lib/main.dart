import 'dart:math';

import 'package:audioplayer/audioplayer.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:rxdart/rxdart.dart';

// NOTE: Since Flutter 1.12, the audioplayer plugin will crash your release
// builds. As an alternative, I am developing a new audio player plugin called
// just_audio which I will switch to once the iOS implementation catches up to
// the Android implementation. In the meantime, or if you really want to use
// audioplayer, you may need to fork it and update compileSdkVersion = 28 and
// update the gradle wrapper to the latest.

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
  final BehaviorSubject<double> _dragPositionSubject =
      BehaviorSubject.seeded(null);

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
            child: StreamBuilder<ScreenState>(
              stream: Rx.combineLatest3<List<MediaItem>, MediaItem,
                      PlaybackState, ScreenState>(
                  AudioService.queueStream,
                  AudioService.currentMediaItemStream,
                  AudioService.playbackStateStream,
                  (queue, mediaItem, playbackState) =>
                      ScreenState(queue, mediaItem, playbackState)),
              builder: (context, snapshot) {
                final screenState = snapshot.data;
                final queue = screenState?.queue;
                final mediaItem = screenState?.mediaItem;
                final state = screenState?.playbackState;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (queue != null && queue.isNotEmpty)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.skip_previous),
                            iconSize: 64.0,
                            onPressed: mediaItem == queue.first
                                ? null
                                : AudioService.skipToPrevious,
                          ),
                          IconButton(
                            icon: Icon(Icons.skip_next),
                            iconSize: 64.0,
                            onPressed: mediaItem == queue.last
                                ? null
                                : AudioService.skipToNext,
                          ),
                        ],
                      ),
                    if (mediaItem?.title != null) Text(mediaItem.title),
                    if (state?.basicState == BasicPlaybackState.connecting) ...[
                      stopButton(),
                      Text("Connecting..."),
                    ] else if (state?.basicState ==
                        BasicPlaybackState.skippingToNext) ...[
                      stopButton(),
                      Text("Skipping..."),
                    ] else if (state?.basicState ==
                        BasicPlaybackState.skippingToPrevious) ...[
                      stopButton(),
                      Text("Skipping..."),
                    ] else if (state?.basicState ==
                        BasicPlaybackState.playing) ...[
                      pauseButton(),
                      stopButton(),
                      positionIndicator(mediaItem, state),
                    ] else if (state?.basicState ==
                        BasicPlaybackState.paused) ...[
                      playButton(),
                      stopButton(),
                      positionIndicator(mediaItem, state),
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

  RaisedButton textToSpeechButton() =>
      startButton('TextToSpeech', _textToSpeechTaskEntrypoint);

  RaisedButton startButton(String label, Function entrypoint) => RaisedButton(
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

  Widget positionIndicator(MediaItem mediaItem, PlaybackState state) {
    return StreamBuilder(
      stream: Rx.combineLatest2<double, double, double>(
          _dragPositionSubject.stream,
          Stream.periodic(Duration(milliseconds: 200),
              (_) => state.currentPosition.toDouble()),
          (dragPosition, statePosition) => dragPosition ?? statePosition),
      builder: (context, snapshot) {
        var position = snapshot.data ?? 0.0;
        double duration = mediaItem?.duration?.toDouble();
        return Column(
          children: [
            if (duration != null)
              Slider(
                min: 0.0,
                max: duration,
                value: max(0.0, min(position, duration)),
                onChanged: (value) {
                  _dragPositionSubject.add(value);
                },
                onChangeEnd: (value) {
                  AudioService.seekTo(value.toInt());
                  _dragPositionSubject.add(null);
                },
              ),
            Text("${(state.currentPosition / 1000).toStringAsFixed(3)}"),
          ],
        );
      },
    );
  }
}

class ScreenState {
  final List<MediaItem> queue;
  final MediaItem mediaItem;
  final PlaybackState playbackState;

  ScreenState(this.queue, this.mediaItem, this.playbackState);
}

void _audioPlayerTaskEntrypoint() async {
  AudioServiceBackground.run(() => AudioPlayerTask());
}

class AudioPlayerTask extends BackgroundAudioTask {
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
  int _queueIndex = 0;
  AudioPlayer _audioPlayer = new AudioPlayer();
  Completer _completer = Completer();
  int _position;

  bool get hasNext => _queueIndex + 1 < _queue.length;

  bool get hasPrevious => _queueIndex > 0;

  MediaItem get mediaItem => _queue[_queueIndex];

  @override
  Future<void> onStart() async {
    var playerStateSubscription = _audioPlayer.onPlayerStateChanged
        .where((state) => state == AudioPlayerState.COMPLETED)
        .listen((state) {
      _handlePlaybackCompleted();
    });
    var audioPositionSubscription =
        _audioPlayer.onAudioPositionChanged.listen((when) {
      final wasConnecting = _position == null;
      _position = when.inMilliseconds;
      if (wasConnecting) {
        // After a delay, we finally start receiving audio positions from the
        // AudioPlayer plugin, so we can broadcast the playing state.
        _setPlayState();
      }
    });

    _setState(state: BasicPlaybackState.connecting, position: 0);
    AudioServiceBackground.setQueue(_queue);
    AudioServiceBackground.setMediaItem(mediaItem);
    onPlay();
    await _completer.future;
    playerStateSubscription.cancel();
    audioPositionSubscription.cancel();
  }

  void _setPlayState() {
    _setState(state: BasicPlaybackState.playing, position: _position);
  }

  void _handlePlaybackCompleted() {
    if (hasNext) {
      onSkipToNext();
    } else {
      onStop();
    }
  }

  void playPause() {
    if (AudioServiceBackground.state.basicState == BasicPlaybackState.playing)
      onPause();
    else
      onPlay();
  }

  @override
  void onSkipToNext() {
    if (!hasNext) return;
    if (AudioServiceBackground.state.basicState == BasicPlaybackState.playing) {
      _audioPlayer.stop();
    }
    _queueIndex++;
    _position = null;
    _setState(state: BasicPlaybackState.skippingToNext, position: 0);
    AudioServiceBackground.setMediaItem(mediaItem);
    onPlay();
  }

  @override
  void onSkipToPrevious() {
    if (!hasPrevious) return;
    if (AudioServiceBackground.state.basicState == BasicPlaybackState.playing) {
      _audioPlayer.stop();
      _queueIndex--;
      _position = null;
    }
    _setState(state: BasicPlaybackState.skippingToPrevious, position: 0);
    AudioServiceBackground.setMediaItem(mediaItem);
    onPlay();
  }

  @override
  void onPlay() {
    _audioPlayer.play(mediaItem.id);
    if (_position != null) {
      _setPlayState();
      // Otherwise we are still loading the audio.
    }
  }

  @override
  void onPause() {
    _audioPlayer.pause();
    _setState(state: BasicPlaybackState.paused, position: _position);
  }

  @override
  void onSeekTo(int position) {
    _audioPlayer.seek(position / 1000.0);
    final state = AudioServiceBackground.state.basicState;
    _setState(state: state, position: position);
  }

  @override
  void onClick(MediaButton button) {
    playPause();
  }

  @override
  void onStop() {
    _audioPlayer.stop();
    _setState(state: BasicPlaybackState.stopped);
    _completer.complete();
  }

  void _setState({@required BasicPlaybackState state, int position = 0}) {
    AudioServiceBackground.setState(
      controls: getControls(state),
      systemActions: [MediaAction.seekTo],
      basicState: state,
      position: position,
    );
  }

  List<MediaControl> getControls(BasicPlaybackState state) {
    switch (state) {
      case BasicPlaybackState.playing:
        return [pauseControl, stopControl];
      case BasicPlaybackState.paused:
        return [playControl, stopControl];
      default:
        return [stopControl];
    }
  }
}

void _textToSpeechTaskEntrypoint() async {
  AudioServiceBackground.run(() => TextPlayerTask());
}

class TextPlayerTask extends BackgroundAudioTask {
  FlutterTts _tts = FlutterTts();

  /// Represents the completion of a period of playing or pausing.
  Completer _playPauseCompleter = Completer();

  /// This wraps [_playPauseCompleter.future], replacing [_playPauseCompleter]
  /// if it has already completed.
  Future _playPauseFuture() {
    if (_playPauseCompleter.isCompleted) _playPauseCompleter = Completer();
    return _playPauseCompleter.future;
  }

  BasicPlaybackState get _basicState => AudioServiceBackground.state.basicState;

  @override
  Future<void> onStart() async {
    playPause();
    for (var i = 1; i <= 10 && _basicState != BasicPlaybackState.stopped; i++) {
      AudioServiceBackground.setMediaItem(mediaItem(i));
      AudioServiceBackground.androidForceEnableMediaButtons();
      _tts.speak('$i');
      // Wait for the speech or a pause request.
      await Future.any(
          [Future.delayed(Duration(seconds: 1)), _playPauseFuture()]);
      // If we were just paused...
      if (_playPauseCompleter.isCompleted &&
          _basicState == BasicPlaybackState.paused) {
        // Wait to be unpaused...
        await _playPauseFuture();
      }
    }
    if (_basicState != BasicPlaybackState.stopped) onStop();
  }

  MediaItem mediaItem(int number) => MediaItem(
      id: 'tts_$number',
      album: 'Numbers',
      title: 'Number $number',
      artist: 'Sample Artist');

  void playPause() {
    if (_basicState == BasicPlaybackState.playing) {
      _tts.stop();
      AudioServiceBackground.setState(
        controls: [playControl, stopControl],
        basicState: BasicPlaybackState.paused,
      );
    } else {
      AudioServiceBackground.setState(
        controls: [pauseControl, stopControl],
        basicState: BasicPlaybackState.playing,
      );
    }
    _playPauseCompleter.complete();
  }

  @override
  void onPlay() {
    playPause();
  }

  @override
  void onPause() {
    playPause();
  }

  @override
  void onClick(MediaButton button) {
    playPause();
  }

  @override
  void onStop() {
    if (_basicState == BasicPlaybackState.stopped) return;
    _tts.stop();
    AudioServiceBackground.setState(
      controls: [],
      basicState: BasicPlaybackState.stopped,
    );
    _playPauseCompleter.complete();
  }
}
