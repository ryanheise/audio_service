import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

// You might want to provide this using dependency injection rather than a
// global variable.
AudioHandler _audioHandler;

Future<void> main() async {
  _audioHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelName: 'Audio Service Demo',
      androidNotificationOngoing: true,
      androidEnableQueue: true,
    ),
  );
  runApp(new MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Service Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Queue display/controls.
            StreamBuilder<QueueState>(
              stream: _queueStateStream,
              builder: (context, snapshot) {
                final queueState = snapshot.data;
                final queue = queueState?.queue ?? [];
                final mediaItem = queueState?.mediaItem;
                return Column(
                  mainAxisSize: MainAxisSize.min,
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
                                : _audioHandler.skipToPrevious,
                          ),
                          IconButton(
                            icon: Icon(Icons.skip_next),
                            iconSize: 64.0,
                            onPressed: mediaItem == queue.last
                                ? null
                                : _audioHandler.skipToNext,
                          ),
                        ],
                      ),
                    if (mediaItem?.title != null) Text(mediaItem.title),
                  ],
                );
              },
            ),
            // Play/pause/stop buttons.
            StreamBuilder<bool>(
              stream: _audioHandler.playbackState.stream
                  .map((state) => state.playing)
                  .distinct(),
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (playing) pauseButton() else playButton(),
                    stopButton(),
                  ],
                );
              },
            ),
            // A seek bar.
            StreamBuilder<MediaState>(
              stream: _mediaStateStream,
              builder: (context, snapshot) {
                final mediaState = snapshot.data;
                return SeekBar(
                  duration: mediaState?.mediaItem?.duration ?? Duration.zero,
                  position: mediaState?.position ?? Duration.zero,
                  onChangeEnd: (newPosition) {
                    _audioHandler.seek(newPosition);
                  },
                );
              },
            ),
            // Display the processing state.
            StreamBuilder<AudioProcessingState>(
              stream: _audioHandler.playbackState.stream
                  .map((state) => state.processingState)
                  .distinct(),
              builder: (context, snapshot) {
                final processingState =
                    snapshot.data ?? AudioProcessingState.idle;
                return Text(
                    "Processing state: ${describeEnum(processingState)}");
              },
            ),
            // Display the latest custom event.
            StreamBuilder(
              stream: _audioHandler.customEventStream,
              builder: (context, snapshot) {
                return Text("custom event: ${snapshot.data}");
              },
            ),
            // Display the notification click status.
            StreamBuilder<bool>(
              stream: AudioService.notificationClickEventStream,
              builder: (context, snapshot) {
                return Text(
                  'Notification Click Status: ${snapshot.data}',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// A stream reporting the combined state of the current media item and its
  /// current position.
  Stream<MediaState> get _mediaStateStream =>
      Rx.combineLatest2<MediaItem, Duration, MediaState>(
          _audioHandler.mediaItem.stream,
          AudioService.getPositionStream(),
          (mediaItem, position) => MediaState(mediaItem, position));

  /// A stream reporting the combined state of the current queue and the current
  /// media item within that queue.
  Stream<QueueState> get _queueStateStream =>
      Rx.combineLatest2<List<MediaItem>, MediaItem, QueueState>(
          _audioHandler.queue.stream,
          _audioHandler.mediaItem.stream,
          (queue, mediaItem) => QueueState(queue, mediaItem));

  RaisedButton startButton(String label, VoidCallback onPressed) =>
      RaisedButton(
        child: Text(label),
        onPressed: onPressed,
      );

  IconButton playButton() => IconButton(
        icon: Icon(Icons.play_arrow),
        iconSize: 64.0,
        onPressed: _audioHandler.play,
      );

  IconButton pauseButton() => IconButton(
        icon: Icon(Icons.pause),
        iconSize: 64.0,
        onPressed: _audioHandler.pause,
      );

  IconButton stopButton() => IconButton(
        icon: Icon(Icons.stop),
        iconSize: 64.0,
        onPressed: _audioHandler.stop,
      );
}

class QueueState {
  final List<MediaItem> queue;
  final MediaItem mediaItem;

  QueueState(this.queue, this.mediaItem);
}

class MediaState {
  final MediaItem mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

class SeekBar extends StatefulWidget {
  final Duration duration;
  final Duration position;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration> onChangeEnd;

  SeekBar({
    @required this.duration,
    @required this.position,
    this.onChanged,
    this.onChangeEnd,
  });

  @override
  _SeekBarState createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double _dragValue;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final value = min(_dragValue ?? widget.position?.inMilliseconds?.toDouble(),
        widget.duration.inMilliseconds.toDouble());
    if (_dragValue != null && !_dragging) {
      _dragValue = null;
    }
    return Stack(
      children: [
        Slider(
          min: 0.0,
          max: widget.duration.inMilliseconds.toDouble(),
          value: value,
          onChanged: (value) {
            if (!_dragging) {
              _dragging = true;
            }
            setState(() {
              _dragValue = value;
            });
            if (widget.onChanged != null) {
              widget.onChanged(Duration(milliseconds: value.round()));
            }
          },
          onChangeEnd: (value) {
            if (widget.onChangeEnd != null) {
              widget.onChangeEnd(Duration(milliseconds: value.round()));
            }
            _dragging = false;
          },
        ),
        Positioned(
          right: 16.0,
          bottom: 0.0,
          child: Text(
              RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$')
                      .firstMatch("$_remaining")
                      ?.group(1) ??
                  '$_remaining',
              style: Theme.of(context).textTheme.caption),
        ),
      ],
    );
  }

  Duration get _remaining => widget.duration - widget.position;
}

/// This task defines logic for playing a list of podcast episodes.
class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final _mediaLibrary = MediaLibrary();
  AudioPlayer _player;
  StreamSubscription<PlaybackEvent> _eventSubscription;

  int get index => _player?.currentIndex;

  AudioPlayerHandler() {
    _init();
  }

  Future<void> _init() async {
    // We configure the audio session for speech since we're playing a podcast.
    // You can also put this in your app's initialisation if your app doesn't
    // switch between two types of audio as this example does.
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.speech());
    // Load and broadcast the queue
    queueSubject.add(_mediaLibrary.items);
    _ensurePlayer();
  }

  Future<void> _ensurePlayer() async {
    print("### _ensurePlayer");
    if (_player == null) {
      print("### new AudioPlayer()");
      _player = AudioPlayer();
      // Broadcast media item changes.
      _player.currentIndexStream.listen((index) {
        if (index != null) mediaItemSubject.add(queue.value[index]);
      });
      // Propagate all events from the audio player to AudioService clients.
      _eventSubscription = _player.playbackEventStream.listen((event) {
        _broadcastState();
      });
      // In this example, the service stops when reaching the end.
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) stop();
      });
      try {
        print("### _player.load");
        // After a cold restart (on Android), _player.load jumps straight from
        // the loading state to the completed state. Inserting a delay makes it
        // work. Not sure why!
        //await Future.delayed(Duration(seconds: 2)); // magic delay
        await _player.load(ConcatenatingAudioSource(
          children: queue.value
              .map((item) => AudioSource.uri(Uri.parse(item.id)))
              .toList(),
        ));
        print("### loaded");
      } catch (e) {
        print("Error: $e");
      }
    }
  }

  @override
  Future<void> skipToQueueItem(String mediaId) async {
    // Then default implementations of skipToNext and skipToPrevious provided by
    // the [QueueHandler] mixin will delegate to this method.
    final newIndex = queue.value.indexWhere((item) => item.id == mediaId);
    if (newIndex == -1) return;
    // This jumps to the beginning of the queue item at newIndex.
    _player.seek(Duration.zero, index: newIndex);
  }

  @override
  Future<void> play() async {
    await _ensurePlayer();
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() async {
    await _player?.dispose();
    _player = null;
    print("stop. _player = null");
    _eventSubscription.cancel();
    _broadcastState();
    // Shut down this task
    await super.stop();
  }

  /// Broadcasts the current state to all clients.
  void _broadcastState() {
    final playing = _player?.playing ?? false;
    playbackStateSubject.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: [0, 1, 3],
      processingState: {
        ProcessingState.none: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player?.processingState ?? ProcessingState.none],
      playing: playing,
      updatePosition: _player?.position ?? Duration.zero,
      bufferedPosition: _player?.bufferedPosition ?? Duration.zero,
      speed: _player?.speed ?? 1.0,
    ));
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

///// This task defines logic for speaking a sequence of numbers using
///// text-to-speech.
//class TextPlayerTask extends BackgroundAudioTask {
//  Tts _tts = Tts();
//  bool _finished = false;
//  Sleeper _sleeper = Sleeper();
//  Completer _completer = Completer();
//  bool _interrupted = false;
//
//  bool get _playing => AudioServiceBackground.state.playing;
//
//  @override
//  Future<void> onStart(Map<String, dynamic> params) async {
//    // flutter_tts resets the AVAudioSession category to playAndRecord and the
//    // options to defaultToSpeaker whenever this background isolate is loaded,
//    // so we need to set our preferred audio session configuration here after
//    // that has happened.
//    final session = await AudioSession.instance;
//    await session.configure(AudioSessionConfiguration.speech());
//    // Handle audio interruptions.
//    session.interruptionEventStream.listen((event) {
//      if (event.begin) {
//        if (_playing) {
//          onPause();
//          _interrupted = true;
//        }
//      } else {
//        switch (event.type) {
//          case AudioInterruptionType.pause:
//          case AudioInterruptionType.duck:
//            if (!_playing && _interrupted) {
//              onPlay();
//            }
//            break;
//          case AudioInterruptionType.unknown:
//            break;
//        }
//        _interrupted = false;
//      }
//    });
//    // Handle unplugged headphones.
//    session.becomingNoisyEventStream.listen((_) {
//      if (_playing) onPause();
//    });
//
//    // Start playing.
//    await _playPause();
//    for (var i = 1; i <= 10 && !_finished;) {
//      AudioServiceBackground.setMediaItem(mediaItem(i));
//      AudioServiceBackground.androidForceEnableMediaButtons();
//      try {
//        await _tts.speak('$i');
//        i++;
//        await _sleeper.sleep(Duration(milliseconds: 300));
//      } catch (e) {
//        // Speech was interrupted
//      }
//      // If we were just paused
//      if (!_finished && !_playing) {
//        try {
//          // Wait to be unpaused
//          await _sleeper.sleep();
//        } catch (e) {
//          // unpaused
//        }
//      }
//    }
//    await AudioServiceBackground.setState(
//      controls: [],
//      processingState: AudioProcessingState.stopped,
//      playing: false,
//    );
//    if (!_finished) {
//      onStop();
//    }
//    _completer.complete();
//  }
//
//  @override
//  Future<void> onPlay() => _playPause();
//
//  @override
//  Future<void> onPause() => _playPause();
//
//  @override
//  Future<void> onStop() async {
//    // Signal the speech to stop
//    _finished = true;
//    _sleeper.interrupt();
//    _tts.interrupt();
//    // Wait for the speech to stop
//    await _completer.future;
//    // Shut down this task
//    await super.onStop();
//  }
//
//  MediaItem mediaItem(int number) => MediaItem(
//      id: 'tts_$number',
//      album: 'Numbers',
//      title: 'Number $number',
//      artist: 'Sample Artist');
//
//  Future<void> _playPause() async {
//    if (_playing) {
//      _interrupted = false;
//      await AudioServiceBackground.setState(
//        controls: [MediaControl.play, MediaControl.stop],
//        processingState: AudioProcessingState.ready,
//        playing: false,
//      );
//      _sleeper.interrupt();
//      _tts.interrupt();
//    } else {
//      final session = await AudioSession.instance;
//      // flutter_tts doesn't activate the session, so we do it here. This
//      // allows the app to stop other apps from playing audio while we are
//      // playing audio.
//      if (await session.setActive(true)) {
//        // If we successfully activated the session, set the state to playing
//        // and resume playback.
//        await AudioServiceBackground.setState(
//          controls: [MediaControl.pause, MediaControl.stop],
//          processingState: AudioProcessingState.ready,
//          playing: true,
//        );
//        _sleeper.interrupt();
//      }
//    }
//  }
//}
//
///// An object that performs interruptable sleep.
//class Sleeper {
//  Completer _blockingCompleter;
//
//  /// Sleep for a duration. If sleep is interrupted, a
//  /// [SleeperInterruptedException] will be thrown.
//  Future<void> sleep([Duration duration]) async {
//    _blockingCompleter = Completer();
//    if (duration != null) {
//      await Future.any([Future.delayed(duration), _blockingCompleter.future]);
//    } else {
//      await _blockingCompleter.future;
//    }
//    final interrupted = _blockingCompleter.isCompleted;
//    _blockingCompleter = null;
//    if (interrupted) {
//      throw SleeperInterruptedException();
//    }
//  }
//
//  /// Interrupt any sleep that's underway.
//  void interrupt() {
//    if (_blockingCompleter?.isCompleted == false) {
//      _blockingCompleter.complete();
//    }
//  }
//}
//
//class SleeperInterruptedException {}
//
///// A wrapper around FlutterTts that makes it easier to wait for speech to
///// complete.
//class Tts {
//  final FlutterTts _flutterTts = new FlutterTts();
//  Completer _speechCompleter;
//  bool _interruptRequested = false;
//  bool _playing = false;
//
//  Tts() {
//    _flutterTts.setCompletionHandler(() {
//      _speechCompleter?.complete();
//    });
//  }
//
//  bool get playing => _playing;
//
//  Future<void> speak(String text) async {
//    _playing = true;
//    if (!_interruptRequested) {
//      _speechCompleter = Completer();
//      await _flutterTts.speak(text);
//      await _speechCompleter.future;
//      _speechCompleter = null;
//    }
//    _playing = false;
//    if (_interruptRequested) {
//      _interruptRequested = false;
//      throw TtsInterruptedException();
//    }
//  }
//
//  Future<void> stop() async {
//    if (_playing) {
//      await _flutterTts.stop();
//      _speechCompleter?.complete();
//    }
//  }
//
//  void interrupt() {
//    if (_playing) {
//      _interruptRequested = true;
//      stop();
//    }
//  }
//}
//
//class TtsInterruptedException {}
