import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:soundpool/soundpool.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

class _MyAppState extends State<MyApp> {
  PlaybackState state;

  @override
  void initState() {
    super.initState();
    AudioService.connect(
      onPlaybackStateChanged: (state, position, speed, updateTime) {
        print('demo onPlaybackStateChanged: $state');
        setState(() {
          this.state = state;
        });
      },
    );
  }

  @override
  void dispose() {
    AudioService.disconnect();
    super.dispose();
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
            children: <Widget>[
              state == PlaybackState.playing ? pauseButton() : playButton(),
              stopButton(),
            ],
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
            AudioService.resume();
          } else {
            AudioService.start(
              backgroundTask: _backgroundCallback,
              notificationChannelName: 'Audio Service Demo',
              androidNotificationIcon: 'mipmap/ic_launcher',
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
  ClickPlayer player = ClickPlayer();
  AudioServiceBackground.run(
    doTask: player.run,
    onPause: player.pause,
    onStop: player.stop,
  );
}

class ClickPlayer {
  bool running = false;
  Soundpool soundpool = Soundpool(streamType: StreamType.music);

  Future<void> run() async {
    running = true;
    soundpool = Soundpool(streamType: StreamType.music);
    String clickName = 'click.wav';
    String path = p.join((await getTemporaryDirectory()).path, clickName);
    final file = new File(path);
    await file.writeAsBytes(
        (await rootBundle.load('assets/$clickName')).buffer.asUint8List());

    int clickSoundId = await soundpool.loadUri('file://$path');
    AudioServiceBackground.setState(
      controls: [
        MediaControl(
            androidIcon: 'drawable/ic_action_stop',
            label: 'Stop',
            action: MediaAction.stop),
        MediaControl(
            androidIcon: 'drawable/ic_action_pause',
            label: 'Pause',
            action: MediaAction.pause),
      ],
      state: PlaybackState.playing,
    );
    for (int i = 1; running && i <= 100; i++) {
      await soundpool.play(clickSoundId);
      await Future.delayed(Duration(milliseconds: 1000));
    }
  }

  void stop() {
    AudioServiceBackground.setState(
      controls: [],
      state: PlaybackState.stopped,
    );
    running = false;
  }

  void pause() {
    AudioServiceBackground.setState(
      controls: [
        MediaControl(
            androidIcon: 'drawable/ic_action_stop',
            label: 'Stop',
            action: MediaAction.stop),
        MediaControl(
            androidIcon: 'drawable/ic_action_play_arrow',
            label: 'Play',
            action: MediaAction.play),
      ],
      state: PlaybackState.paused,
    );
    running = false;
  }
}
