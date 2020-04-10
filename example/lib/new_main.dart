// import 'dart:math';

// import 'package:flutter/material.dart';
// import 'dart:async';

// import 'package:audio_service/audio_service.dart';
// import 'package:just_audio/just_audio.dart';
// import 'package:rxdart/rxdart.dart';

// void main() => runApp(new MyApp());

// class MyApp extends StatefulWidget {
//   @override
//   _MyAppState createState() => new _MyAppState();
// }

// class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
//   final BehaviorSubject<double> _dragPositionSubject =
//       BehaviorSubject.seeded(null);

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     connect();
//   }

//   @override
//   void dispose() {
//     disconnect();
//     WidgetsBinding.instance.removeObserver(this);
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     switch (state) {
//       case AppLifecycleState.resumed:
//         connect();
//         break;
//       case AppLifecycleState.paused:
//         disconnect();
//         break;
//       default:
//         break;
//     }
//   }

//   void connect() async {
//     await AudioService.connect();
//   }

//   void disconnect() {
//     AudioService.disconnect();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return new MaterialApp(
//       home: WillPopScope(
//         onWillPop: () {
//           disconnect();
//           return Future.value(true);
//         },
//         child: new Scaffold(
//           appBar: new AppBar(
//             title: const Text('Audio Service Demo'),
//           ),
//           body: new Center(
//             child: StreamBuilder<ScreenState>(
//               stream: Rx.combineLatest3<List<MediaItem>, MediaItem,
//                       PlaybackState, ScreenState>(
//                   AudioService.queueStream,
//                   AudioService.currentMediaItemStream,
//                   AudioService.playbackStateStream,
//                   (queue, mediaItem, playbackState) =>
//                       ScreenState(queue, mediaItem, playbackState)),
//               builder: (context, snapshot) {
//                 final screenState = snapshot.data;
//                 final queue = screenState?.queue;
//                 final mediaItem = screenState?.mediaItem;
//                 final state = screenState?.playbackState;
//                 final basicState = state?.basicState ?? BasicPlaybackState.none;
//                 return Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     if (queue != null && queue.isNotEmpty)
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           IconButton(
//                             icon: Icon(Icons.skip_previous),
//                             iconSize: 64.0,
//                             onPressed: mediaItem == queue.first
//                                 ? null
//                                 : AudioService.skipToPrevious,
//                           ),
//                           IconButton(
//                             icon: Icon(Icons.skip_next),
//                             iconSize: 64.0,
//                             onPressed: mediaItem == queue.last
//                                 ? null
//                                 : AudioService.skipToNext,
//                           ),
//                         ],
//                       ),
//                     if (mediaItem?.title != null) Text(mediaItem.title),
//                     if (basicState == BasicPlaybackState.none) ...[
//                       RaisedButton(
//                         child: Text("audio service"),
//                         onPressed: () {
//                           AudioService.start(
//                             backgroundTaskEntrypoint: () async =>
//                                 AudioServiceBackground.run(
//                                     () => AudioPlayerTask()),
//                             androidNotificationChannelName:
//                                 'Audio Service Demo',
//                             notificationColor: 0xFF2196f3,
//                             androidNotificationIcon: 'mipmap/ic_launcher',
//                             enableQueue: true,
//                           );
//                         },
//                       )
//                     ] else
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: [
//                           if (basicState == BasicPlaybackState.playing)
//                             pauseButton()
//                           else if (basicState == BasicPlaybackState.paused)
//                             playButton()
//                           else if (basicState == BasicPlaybackState.buffering ||
//                               basicState == BasicPlaybackState.skippingToNext ||
//                               basicState ==
//                                   BasicPlaybackState.skippingToPrevious)
//                             Padding(
//                               padding: const EdgeInsets.all(8.0),
//                               child: SizedBox(
//                                 width: 64.0,
//                                 height: 64.0,
//                                 child: CircularProgressIndicator(),
//                               ),
//                             ),
//                           stopButton(),
//                         ],
//                       ),
//                     if (basicState != BasicPlaybackState.none &&
//                         basicState != BasicPlaybackState.stopped) ...[
//                       positionIndicator(mediaItem, state),
//                       Text("State: " +
//                           "$basicState".replaceAll(RegExp(r'^.*\.'), '')),
//                       RaisedButton(
//                           child: Text("print items"),
//                           onPressed: () {
//                             print(AudioService.queue.toString());
//                           }),
//                       RaisedButton(
//                         child: Text("add item"),
//                         onPressed: () {
//                           AudioService.addQueueItem(
//                             MediaItem(
//                               id: "https://dl.irangfx.com/gerama/albums/ali-jafari-pouyan/1-6/music/ali-jafari-pouyan-1-6-2019.mp3",
//                               album: "Gerama album",
//                               title: "Gerama title",
//                               artist: "Gerama artist",
//                               duration: 444000,
//                               artUri:
//                                   "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg",
//                             ),
//                           );
//                         },
//                       ),
//                     ],
//                   ],
//                 );
//               },
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   IconButton playButton() => IconButton(
//         icon: Icon(Icons.play_arrow),
//         iconSize: 64.0,
//         onPressed: AudioService.play,
//       );

//   IconButton pauseButton() => IconButton(
//         icon: Icon(Icons.pause),
//         iconSize: 64.0,
//         onPressed: AudioService.pause,
//       );

//   IconButton stopButton() => IconButton(
//         icon: Icon(Icons.stop),
//         iconSize: 64.0,
//         onPressed: AudioService.stop,
//       );

//   Widget positionIndicator(MediaItem mediaItem, PlaybackState state) {
//     double seekPos;
//     return StreamBuilder(
//       stream: Rx.combineLatest2<double, double, double>(
//           _dragPositionSubject.stream,
//           Stream.periodic(Duration(milliseconds: 200)),
//           (dragPosition, _) => dragPosition),
//       builder: (context, snapshot) {
//         double position = snapshot.data ?? state.currentPosition.toDouble();
//         double duration = mediaItem?.duration?.toDouble();
//         return Column(
//           children: [
//             if (duration != null)
//               Slider(
//                 min: 0.0,
//                 max: duration,
//                 value: seekPos ?? max(0.0, min(position, duration)),
//                 onChanged: (value) {
//                   _dragPositionSubject.add(value);
//                 },
//                 onChangeEnd: (value) {
//                   AudioService.seekTo(value.toInt());
//                   // Due to a delay in platform channel communication, there is
//                   // a brief moment after releasing the Slider thumb before the
//                   // new position is broadcast from the platform side. This
//                   // hack is to hold onto seekPos until the next state update
//                   // comes through.
//                   // TODO: Improve this code.
//                   seekPos = value;
//                   _dragPositionSubject.add(null);
//                 },
//               ),
//             Text("${(state.position / 100).toStringAsFixed(3)}"),
//           ],
//         );
//       },
//     );
//   }
// }