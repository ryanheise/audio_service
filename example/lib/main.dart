import 'dart:math';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AudioServiceWidget(child: MainScreen()),
    );
  }
}

class MainScreen extends StatelessWidget {
  /// Tracks the position while the user drags the seek bar.
  final BehaviorSubject<double> _dragPositionSubject =
      BehaviorSubject.seeded(null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Service Demo'),
      ),
      body: Center(
        child: StreamBuilder<ScreenState>(
          stream: _screenStateStream,
          builder: (context, snapshot) {
            final screenState = snapshot.data;
            final queue = screenState?.queue;
            final mediaItem = screenState?.mediaItem;
            final state = screenState?.playbackState;
            final processingState =
                state?.processingState ?? AudioProcessingState.none;
            final playing = state?.playing ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (processingState == AudioProcessingState.none) ...[
                  audioPlayerButton(),
                  textToSpeechButton(),
                ] else ...[
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (playing) pauseButton() else playButton(),
                      stopButton(),
                    ],
                  ),
                  positionIndicator(mediaItem, state),
                  Text("Processing state: " +
                      "$processingState".replaceAll(RegExp(r'^.*\.'), '')),
                  StreamBuilder(
                    stream: AudioService.customEventStream,
                    builder: (context, snapshot) {
                      return Text("custom event: ${snapshot.data}");
                    },
                  ),
                  StreamBuilder<bool>(
                    stream: AudioService.notificationClickEventStream,
                    builder: (context, snapshot) {
                      return Text(
                        'Notification Click Status: ${snapshot.data}',
                      );
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Encapsulate all the different data we're interested in into a single
  /// stream so we don't have to nest StreamBuilders.
  Stream<ScreenState> get _screenStateStream =>
      Rx.combineLatest3<List<MediaItem>, MediaItem, PlaybackState, ScreenState>(
          AudioService.queueStream,
          AudioService.currentMediaItemStream,
          AudioService.playbackStateStream,
          (queue, mediaItem, playbackState) =>
              ScreenState(queue, mediaItem, playbackState));

  RaisedButton audioPlayerButton() => startButton(
        'AudioPlayer',
        () {
          AudioService.start(
            backgroundTaskEntrypoint: _audioPlayerTaskEntrypoint,
            androidNotificationChannelName: 'Audio Service Demo',
            // Enable this if you want the Android service to exit the foreground state on pause.
            //androidStopForegroundOnPause: true,
            androidNotificationColor: 0xFF2196f3,
            androidNotificationIcon: 'mipmap/ic_launcher',
            androidEnableQueue: true,
          );
        },
      );

  RaisedButton textToSpeechButton() => startButton(
        'TextToSpeech',
        () {
          AudioService.start(
            backgroundTaskEntrypoint: _textToSpeechTaskEntrypoint,
            androidNotificationChannelName: 'Audio Service Demo',
            androidNotificationColor: 0xFF2196f3,
            androidNotificationIcon: 'mipmap/ic_launcher',
          );
        },
      );

  RaisedButton startButton(String label, VoidCallback onPressed) =>
      RaisedButton(
        child: Text(label),
        onPressed: onPressed,
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
    double seekPos;
    return StreamBuilder(
      stream: Rx.combineLatest2<double, double, double>(
          _dragPositionSubject.stream,
          Stream.periodic(Duration(milliseconds: 200)),
          (dragPosition, _) => dragPosition),
      builder: (context, snapshot) {
        double position =
            snapshot.data ?? state.currentPosition.inMilliseconds.toDouble();
        double duration = mediaItem?.duration?.inMilliseconds?.toDouble();
        return Column(
          children: [
            if (duration != null)
              Slider(
                min: 0.0,
                max: duration,
                value: seekPos ?? max(0.0, min(position, duration)),
                onChanged: (value) {
                  _dragPositionSubject.add(value);
                },
                onChangeEnd: (value) {
                  AudioService.seekTo(Duration(milliseconds: value.toInt()));
                  // Due to a delay in platform channel communication, there is
                  // a brief moment after releasing the Slider thumb before the
                  // new position is broadcast from the platform side. This
                  // hack is to hold onto seekPos until the next state update
                  // comes through.
                  // TODO: Improve this code.
                  seekPos = value;
                  _dragPositionSubject.add(null);
                },
              ),
            Text("${state.currentPosition}"),
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

// NOTE: Your entrypoint MUST be a top-level function.
void _audioPlayerTaskEntrypoint() async {
  AudioServiceBackground.run(() => AudioPlayerTask());
}

class AudioPlayerTask extends BackgroundAudioTask {
  final _mediaLibrary = MediaLibrary();
  AudioPlayer _player = new AudioPlayer();
  AudioProcessingState _skipState;
  bool _interrupted = false;
  Seeker _seeker;

  List<MediaItem> get queue => _mediaLibrary.items;

  MediaItem get mediaItem =>
      _player.currentIndex != null ? queue[_player.currentIndex] : null;

  StreamSubscription<PlaybackEvent> _eventSubscription;

  @override
  void onStart(Map<String, dynamic> params) {
    // Broadcast media item changes.
    _player.currentIndexStream.listen((index) {
      if (index != null) AudioServiceBackground.setMediaItem(queue[index]);
    });
    // Propagate all events from the audio player to AudioService clients.
    _eventSubscription = _player.playbackEventStream.listen((event) {
      _broadcastState();
    });
    // Special processing for state transitions.
    _player.processingStateStream.listen((state) {
      switch (state) {
        case ProcessingState.completed:
          // In this example, the service stops when reaching the end.
          onStop();
          break;
        case ProcessingState.ready:
          // If we just came from skipping between tracks, clear the skip
          // state now that we're ready to play.
          _skipState = null;
          break;
        default:
          break;
      }
    });

    AudioServiceBackground.setQueue(queue);
    _load();
  }

  _load() async {
    try {
      await _player.load(ConcatenatingAudioSource(
        children:
            queue.map((item) => AudioSource.uri(Uri.parse(item.id))).toList(),
      ));
      onPlay();
    } catch (e) {
      print("Error: $e");
      onStop();
    }
  }

  Function get playPause => _player.playing ? onPause : onPlay;

  @override
  Future<void> onSkipToNext() => _skip(1);

  @override
  Future<void> onSkipToPrevious() => _skip(-1);

  Future<void> _skip(int offset) async {
    final newPos = _player.currentIndex + offset;
    if (!(newPos >= 0 && newPos < queue.length)) return;
    _skipState = offset > 0
        ? AudioProcessingState.skippingToNext
        : AudioProcessingState.skippingToPrevious;
    _player.seek(Duration.zero, index: newPos);
  }

  @override
  void onPlay() => _player.play();

  @override
  void onPause() => _player.pause();

  @override
  void onSeekTo(Duration position) => _player.seek(position);

  @override
  void onClick(MediaButton button) => playPause();

  @override
  Future<void> onFastForward() => _seekRelative(fastForwardInterval);

  @override
  Future<void> onRewind() => _seekRelative(-rewindInterval);

  @override
  Future<void> onSeekForward(bool begin) async {
    _seeker?.stop();
    if (begin) {
      _seeker = Seeker(
          _player, Duration(seconds: 10), Duration(seconds: 1), mediaItem)
        ..start();
    }
  }

  @override
  Future<void> onSeekBackward(bool begin) async {
    _seeker?.stop();
    if (begin) {
      _seeker = Seeker(
          _player, Duration(seconds: -10), Duration(seconds: 1), mediaItem)
        ..start();
    }
  }

  Future<void> _seekRelative(Duration offset) async {
    var newPosition = _player.position + offset;
    if (newPosition < Duration.zero) newPosition = Duration.zero;
    if (newPosition > mediaItem.duration) newPosition = mediaItem.duration;
    await _player.seek(newPosition);
  }

  @override
  Future<void> onStop() async {
    await _player.pause();
    await _player.dispose();
    _eventSubscription.cancel();
    await _broadcastState();
    // Shut down this task
    await super.onStop();
  }

  /* Handling Audio Focus */
  @override
  void onAudioFocusLost(AudioInterruption interruption) {
    if (_player.playing) _interrupted = true;
    switch (interruption) {
      case AudioInterruption.pause:
      case AudioInterruption.temporaryPause:
      case AudioInterruption.unknownPause:
        onPause();
        break;
      case AudioInterruption.temporaryDuck:
        _player.setVolume(0.5);
        break;
    }
  }

  @override
  void onAudioFocusGained(AudioInterruption interruption) {
    switch (interruption) {
      case AudioInterruption.temporaryPause:
        if (!_player.playing && _interrupted) onPlay();
        break;
      case AudioInterruption.temporaryDuck:
        _player.setVolume(1.0);
        break;
      default:
        break;
    }
    _interrupted = false;
  }

  @override
  void onAudioBecomingNoisy() => onPause();

  Future<void> _broadcastState() async {
    await AudioServiceBackground.setState(
      controls: getControls(),
      systemActions: [
        MediaAction.seekTo,
        MediaAction.seekForward,
        MediaAction.seekBackward
      ],
      processingState: _getProcessingState(),
      playing: _player.playing,
      position: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }

  AudioProcessingState _getProcessingState() {
    if (_skipState != null) return _skipState;
    switch (_player.processingState) {
      case ProcessingState.none:
        return AudioProcessingState.stopped;
      case ProcessingState.loading:
        return AudioProcessingState.connecting;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
      default:
        throw Exception("Invalid state: ${_player.processingState}");
    }
  }

  List<MediaControl> getControls() {
    if (_player.playing) {
      return [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.stop,
        MediaControl.skipToNext
      ];
    } else {
      return [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext
      ];
    }
  }
}

/// Provides access to a library of media items. In your app, this could come
/// from a database or web service.
class MediaLibrary {
  final _items = <MediaItem>[
    MediaItem(
      id: "https://s3.amazonaws.com/scifri-episodes/scifri20181123-episode.mp3",
      album: "Science Friday",
      title: "A Salute To Head-Scratching Science",
      artist: "Science Friday and WNYC Studios",
      duration: Duration(milliseconds: 5739820),
      artUri:
          "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg",
    ),
    MediaItem(
      id: "https://s3.amazonaws.com/scifri-segments/scifri201711241.mp3",
      album: "Science Friday",
      title: "From Cat Rheology To Operatic Incompetence",
      artist: "Science Friday and WNYC Studios",
      duration: Duration(milliseconds: 2856950),
      artUri:
          "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg",
    ),
  ];

  List<MediaItem> get items => _items;
}

// NOTE: Your entrypoint MUST be a top-level function.
void _textToSpeechTaskEntrypoint() async {
  AudioServiceBackground.run(() => TextPlayerTask());
}

class TextPlayerTask extends BackgroundAudioTask {
  FlutterTts _tts = FlutterTts();
  bool _finished = false;
  Sleeper _sleeper = Sleeper();
  Completer _completer = Completer();

  bool get _playing => AudioServiceBackground.state.playing;

  @override
  Future<void> onStart(Map<String, dynamic> params) async {
    playPause();
    for (var i = 1; i <= 10 && !_finished; i++) {
      AudioServiceBackground.setMediaItem(mediaItem(i));
      AudioServiceBackground.androidForceEnableMediaButtons();
      _tts.speak('$i');
      // Wait for the speech.
      try {
        await _sleeper.sleep(Duration(seconds: 1));
      } catch (e) {
        // Speech was interrupted
        _tts.stop();
      }
      // If we were just paused
      if (!_finished && !_playing) {
        try {
          // Wait to be unpaused
          await _sleeper.sleep();
        } catch (e) {
          // unpaused
        }
      }
    }
    await AudioServiceBackground.setState(
      controls: [],
      processingState: AudioProcessingState.stopped,
      playing: false,
    );
    if (!_finished) {
      onStop();
    }
    _completer.complete();
  }

  MediaItem mediaItem(int number) => MediaItem(
      id: 'tts_$number',
      album: 'Numbers',
      title: 'Number $number',
      artist: 'Sample Artist');

  void playPause() {
    if (_playing) {
      _tts.stop();
      AudioServiceBackground.setState(
        controls: [MediaControl.play, MediaControl.stop],
        processingState: AudioProcessingState.ready,
        playing: false,
      );
    } else {
      AudioServiceBackground.setState(
        controls: [MediaControl.pause, MediaControl.stop],
        processingState: AudioProcessingState.ready,
        playing: true,
      );
    }
    _sleeper.interrupt();
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
  Future<void> onStop() async {
    // Signal the speech to stop
    _finished = true;
    _sleeper.interrupt();
    // Wait for the speech to stop
    await _completer.future;
    // Shut down this task
    await super.onStop();
  }
}

/// An object that performs interruptable sleep.
class Sleeper {
  Completer _blockingCompleter;

  /// Sleep for a duration. If sleep is interrupted, a
  /// [SleeperInterruptedException] will be thrown.
  Future<void> sleep([Duration duration]) async {
    _blockingCompleter = Completer();
    if (duration != null) {
      await Future.any([Future.delayed(duration), _blockingCompleter.future]);
    } else {
      await _blockingCompleter.future;
    }
    final interrupted = _blockingCompleter.isCompleted;
    _blockingCompleter = null;
    if (interrupted) {
      throw SleeperInterruptedException();
    }
  }

  /// Interrupt any sleep that's underway.
  void interrupt() {
    if (_blockingCompleter?.isCompleted == false) {
      _blockingCompleter.complete();
    }
  }
}

class SleeperInterruptedException {}

class Seeker {
  final AudioPlayer player;
  final Duration positionInterval;
  final Duration stepInterval;
  final MediaItem mediaItem;
  bool _running = false;

  Seeker(
    this.player,
    this.positionInterval,
    this.stepInterval,
    this.mediaItem,
  );

  start() async {
    _running = true;
    while (_running) {
      Duration newPosition = player.position + positionInterval;
      if (newPosition < Duration.zero) newPosition = Duration.zero;
      if (newPosition > mediaItem.duration) newPosition = mediaItem.duration;
      player.seek(newPosition);
      await Future.delayed(stepInterval);
    }
  }

  stop() {
    _running = false;
  }
}
