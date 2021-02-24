# audio_service

This plugin wraps around your existing audio code to allow it to run in the background or with the screen turned off, and allows your app to interact with headset buttons, the Android lock screen and notification, iOS control center, wearables and Android Auto. It is suitable for:

* Music players
* Text-to-speech readers
* Podcast players
* Video players
* Navigators
* More!

## How does this plugin work?

You encapsulate your audio code in a background task which runs in a special isolate that continues to run when your UI is absent. Your background task implements callbacks to respond to playback requests coming from your Flutter UI, headset buttons, the lock screen, notification, iOS control center, car displays and smart watches:

![audio_service_callbacks](https://user-images.githubusercontent.com/19899190/84386442-b305cc80-ac34-11ea-8c2f-1b4cb126a98d.png)

You can implement these callbacks to play any sort of audio that is appropriate for your app, such as music files or streams, audio assets, text to speech, synthesised audio, or combinations of these.

| Feature                            | Android    | iOS     | macOS   | Web     |
| -------                            | :-------:  | :-----: | :-----: | :-----: |
| background audio                   | ✅         | ✅      | ✅      | ✅      |
| headset clicks                     | ✅         | ✅      | ✅      | ✅      |
| start/stop/play/pause/seek/rate    | ✅         | ✅      | ✅      | ✅      |
| fast forward/rewind                | ✅         | ✅      | ✅      | ✅      |
| repeat/shuffle mode                | ✅         | ✅      | ✅      | ✅      |
| queue manipulation, skip next/prev | ✅         | ✅      | ✅      | ✅      |
| custom actions                     | ✅         | ✅      | ✅      | ✅      |
| custom events                      | ✅         | ✅      | ✅      | ✅      |
| notifications/control center       | ✅         | ✅      | ✅      | ✅      |
| lock screen controls               | ✅         | ✅      |         | ✅      |
| album art                          | ✅         | ✅      | ✅      | ✅      |
| Android Auto, Apple CarPlay        | (untested) | ✅      |         |         |

If you'd like to help with any missing features, please join us on the [GitHub issues page](https://github.com/ryanheise/audio_service/issues).

## Preview the upcoming 0.18.0 release

A new version of audio_service is around the corner. This version removes the need for a background isolate, allowing simpler communication between your UI and audio logic, and greater compatibility with plugins that don't support multiple isolates.

If you are interested to help with testing or providing feedback, you can upgrade by following the instructions in the [Migration Guide](https://github.com/ryanheise/audio_service/wiki/Migration-Guide#0180-preview).

## Can I make use of other plugins within the background audio task?

Yes! `audio_service` is designed to let you implement the audio logic however you want, using whatever plugins you want. You can use your favourite audio plugins such as [just_audio](https://pub.dartlang.org/packages/just_audio), [flutter_radio](https://pub.dev/packages/flutter_radio), [flutter_tts](https://pub.dartlang.org/packages/flutter_tts), and others, within your background audio task. There are also plugins like [just_audio_service](https://github.com/yringler/just_audio_service) that provide default implementations of `BackgroundAudioTask` to make your job easier.

Note that this plugin will not work with other audio plugins that overlap in responsibility with this plugin (i.e. background audio, iOS control center, Android notifications, lock screen, headset buttons, etc.)

## Example

### UI code

Wrap your `/` route's widget tree in an `AudioServiceWidget`:

```dart
void main() => runApp(new MyApp());
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      home: AudioServiceWidget(child: MainScreen()),
    );
  }
}
```

Start/stop your background audio task:

```dart
await AudioService.start(backgroundTaskEntrypoint: _entrypoint);
await AudioService.stop();
```

Standard controls:

```dart
AudioService.play();
AudioService.seekTo(Duration(seconds: 10));
AudioService.setSpeed(1.5);
AudioService.pause();
```

Queue management:

```dart
var item = MediaItem(
  id: 'https://example.com/audio.mp3',
  album: 'Album name',
  title: 'Track title',
);
AudioService.addQueueItem(item);
AudioService.addQueueItemAt(item, 1);
AudioService.removeQueueItem(item);
AudioService.updateQueue([item, ...]);
AudioService.skipToNext();
AudioService.skipToPrevious();
AudioService.playFromMediaId('https://example.com/audio.mp3')
AudioService.playMediaItem(item);
```

Looping and shuffling:

```dart
AudioService.setRepeatMode(AudioServiceRepeatMode.one); // none/one/all/group
AudioService.setShuffleMode(AudioServiceShuffleMode.all); // none/all/group
```

Custom actions:

```dart
AudioService.customAction('setVolume', 0.8);
AudioService.customAction('saveBookmark');
```

Listening to state changes:

```dart
AudioService.playbackStateStream.listen((PlaybackState state) {
  if (state.playing) ... else ...
  switch (state.processingState) {
    case AudioProcessingState.none: ...
    case connecting: ...
    case ready: ...
    case buffering: ...
    case fastForwarding: ...
    case rewinding: ...
    case skippingToPrevious: ...
    case skippingToNext: ...
    case skippingToQueueItem: ...
    case completed: ...
    case stopped: ...
    case error: ...
  }
});
```

Listen to changes to the currently playing item:

```dart
AudioService.currentMediaItemStream.listen((MediaItem item) { ... });
```

Listen to changes to the queue:

```dart
AudioService.queueStream.listen((List<MediaItem> queue) { ... });
```

Listen to changes to the current playback position:

```dart
AudioService.positionStream.listen((Duration position) { ... });
```

### Background code

Define a background audio task to handle callbacks for all methods called from your UI or other clients (e.g. the media notification):

```dart
// Must be a top-level function
void _entrypoint() => AudioServiceBackground.run(() => AudioPlayerTask());

class AudioPlayerTask extends BackgroundAudioTask {
  final _player = AudioPlayer(); // e.g. just_audio
  
  // Implement callbacks here. e.g. onStart, onStop, onPlay, onPause
}
```

The purpose of this class is to encapsulate all audio logic in your app so that it is completely self-contained, and can continue to run on its own even when the Flutter UI is not present. Every message that you send from your Flutter UI (`start`, `stop`, `play`, `pause`) has a corresponding callback that you can implement in your background audio task (`onStart`, `onStop`, `onPlay`, `onPause`). Additionally, there are callbacks that respond only to events outside of your Flutter UI, such as `onClick`, which responds to a click of a headset button, and `onClose` which responds to the user swiping away the Android media notification.

Most of these callbacks can be implemented by simply delegating to your audio player plugin:

```dart
onPlay() => _player.play();
onPause() => _player.pause();
onSeekTo(Duration duration) => _player.seekTo(duration);
onSetSpeed(double speed) => _player.setSpeed(speed);
```

Your custom actions may be handled via a switch:

```dart
onCustomAction(String name, dynamic arguments) async {
  switch (name) {
    case 'setVolume':
      _player.setVolume(arguments);
      break;
    case 'saveBookmark':
      // app-specific code
      break;
  }
}
```

`onStart` is the place to initialise the player, and (usually) start playing audio:

```dart
onStart(Map<String, dynamic> params) async {
  final mediaItem = MediaItem(
    id: "https://foo.bar/baz.mp3",
    album: "Foo",
    title: "Bar",
  );
  // Tell the UI and media notification what we're playing.
  AudioServiceBackground.setMediaItem(mediaItem);
  // Listen to state changes on the player...
  _player.playerStateStream.listen((playerState) {
    // ... and forward them to all audio_service clients.
    AudioServiceBackground.setState(
      playing: playerState.playing,
      // Every state from the audio player gets mapped onto an audio_service state.
      processingState: {
        ProcessingState.none: AudioProcessingState.none,
        ProcessingState.loading: AudioProcessingState.connecting,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[playerState.processingState],
      // Tell clients what buttons/controls should be enabled in the
      // current state.
      controls: [
        playerState.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
      ],
    );
  });
  // Play when ready.
  _player.play();
  // Start loading something (will play when ready).
  await _player.setUrl(mediaItem.id);
}
```

The above implementation starts playing an initial media item, and also listens to state changes in the underlying player and broadcasts them to all audio_service clients (the Flutter UI, media notification, smart watches, etc.) so that they may update their UI state. There are 3 methods by which your background audio task can broadcast state changes to clients:

* `AudioServiceBackground.setState` broadcasts the current playback state to all clients. This includes whether or not audio is playing, but also whether audio is buffering, the current playback position and buffer position, the current playback speed, and the set of audio controls that should be made available. It is important for you to call this method whenever any of these pieces of state changes.
* `AudioServiceBackground.setMediaItem` broadcasts information about the currently playing media item to all clients. This includes the track title, artist, genre, duration, any artwork to display, and other information.
* `AudioServiceBackground.setQueue` broadcasts the current queue to all clients. Some clients like Android Auto may display this information in their user interfaces.

`onStop` is the place to dispose of any resources, stop playing audio, and shut down the background isolate:

```dart
  onStop() async {
    // Stop and dispose of the player.
    await _player.dispose();
    // Shut down the background task.
    await super.onStop();
  }
}
```

If you are instead building a text-to-speech reader, you could implement these callbacks differently:

```dart
import 'package:flutter_tts/flutter_tts.dart';
class ReaderBackgroundTask extends BackgroundAudioTask {
  final _tts = FlutterTts();
  String article;
  
  onStart() async {
    // Tell clients what we're listening to
    await AudioServiceBackground.setMediaItem(MediaItem(album: "Business Insider", ...));
    // Tell clients that we're now playing
    await AudioServiceBackground.setState(
      playing: true,
      processingState: AudioProcessingState.ready,
      controls: [MediaControl.stop],
    );
    // Play a small amount of silent audio on Android to pose as an audio player
    AudioServiceBackground.androidForceEnableMediaButtons();
    // Start speaking
    _tts.speak(article);
  }
  
  onStop() async {
    await _tts.stop();
    await AudioServiceBackground.setState(
      playing: false,
      processingState: AudioProcessingState.stopped,
      controls: [MediaControl.play],
    );
    await super.onStop();
  }
}
```

See the full example for how to handle queues/playlists, headset button clicks and media artwork.

Note that your UI and background task run in separate isolates and do not share memory. The only way they communicate is via message passing. Your Flutter UI will only use the `AudioService` API to communicate with the background task, while your background task will only use the `AudioServiceBackground` API to interact with the UI and other clients.

### Connecting to `AudioService` from the background

You can also send messages to your background audio task from another background callback (e.g. android_alarm_manager) by manually connecting to it:

```dart
await AudioService.connect(); // Note: the "await" is necessary!
AudioService.play();
```

## Configuring the audio session

If your app uses audio, you should tell the operating system what kind of usage scenario your app has and how your app will interact with other audio apps on the device. Different audio apps often have unique requirements. For example, when a navigator app speaks driving instructions, a music player should duck its audio while a podcast player should pause its audio. Depending on which one of these three apps you are building, you will need to configure your app's audio settings and callbacks to appropriately handle these interactions.

Use the [audio_session](https://pub.dev/packages/audio_session) package to change the default audio session configuration for your app. E.g. for a podcast player, you may use:

```dart
final session = await AudioSession.instance;
await session.configure(AudioSessionConfiguration.speech());
```

Each time you invoke an audio plugin to play audio, that plugin will activate your app's shared audio session to inform the operating system that your app is actively playing audio. Depending on the configuration set above, this will also inform other audio apps to either stop playing audio, or possibly continue playing at a lower volume (i.e. ducking). You normally do not need to activate the audio session yourself, however if the audio plugin you use does not activate the audio session, you can activate it yourself:

```dart
// Activate the audio session before playing audio.
if (await session.setActive(true)) {
  // Now play audio.
} else {
  // The request was denied and the app should not play audio
}
```

When another app activates its audio session, it similarly may ask your app to pause or duck its audio. Once again, the particular audio plugin you use may automatically pause or duck audio when requested. However, if it does not, you can respond to these events yourself by listening to `session.interruptionEventStream`. Similarly, if the audio plugin doesn't handle unplugged headphone events, you can respond to these yourself by listening to `session.becomingNoisyEventStream`. For more information, consult the documentation for [audio_session](https://pub.dev/packages/audio_session).

Note: If your app uses a number of different audio plugins, e.g. for audio recording, or text to speech, or background audio, it is possible that those plugins may internally override each other's audio session settings since there is only a single audio session shared by your app. Therefore, it is recommended that you apply your own preferred configuration using audio_session after all other audio plugins have loaded. You may consider asking the developer of each audio plugin you use to provide an option to not overwrite these global settings and allow them be managed externally.

## Android setup

These instructions assume that your project follows the new project template introduced in Flutter 1.12. If your project was created prior to 1.12 and uses the old project structure, you can update your project to follow the [new project template](https://github.com/flutter/flutter/wiki/Upgrading-pre-1.12-Android-projects).

Additionally:

1. Edit your project's `AndroidManifest.xml` file to declare the permission to create a wake lock, and add component entries for the `<service>` and `<receiver>`:

```xml
<manifest ...>
  <uses-permission android:name="android.permission.WAKE_LOCK"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  
  <application ...>
    
    ...
    
    <service android:name="com.ryanheise.audioservice.AudioService">
      <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
      </intent-filter>
    </service>

    <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" >
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver> 
  </application>
</manifest>
```

2. Starting from Flutter 1.12, you will need to disable the `shrinkResources` setting in your `android/app/build.gradle` file, otherwise the icon resources used in the Android notification will be removed during the build:

```
android {
    compileSdkVersion 28

    ...

    buildTypes {
        release {
            signingConfig ...
            shrinkResources false // ADD THIS LINE
        }
    }
}
```

## iOS setup

Insert this in your `Info.plist` file:

```
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
```

The example project may be consulted for context.

## macOS setup
The minimum supported macOS version is 10.12.2 (though this could be changed with some work in the future).  
Modify the platform line in `macos/Podfile` to look like the following:
```
platform :osx, '10.12.2'
```

# Where can I find more information?

* [Tutorial](https://github.com/ryanheise/audio_service/wiki/Tutorial): walks you through building a simple audio player while explaining the basic concepts.
* [Full example](https://github.com/ryanheise/audio_service/blob/master/example/lib/main.dart): The `example` subdirectory on GitHub demonstrates both music and text-to-speech use cases.
* [Frequently Asked Questions](https://github.com/ryanheise/audio_service/wiki/FAQ)
* [API documentation](https://pub.dev/documentation/audio_service/latest/audio_service/audio_service-library.html)
