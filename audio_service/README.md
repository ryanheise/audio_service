# audio_service

This plugin wraps around your existing audio code to allow it to run in the background or with the screen turned off, and allows your app to interact with headset buttons, the Android lock screen and notification, iOS control center, wearables and Android Auto. It is suitable for:

* Music players
* Text-to-speech readers
* Podcast players
* Video players
* Navigators
* More!

## How does this plugin work?

You encapsulate your audio code in an audio handler which implements standard callbacks on Android, iOS and the web that allow it to respond to playback requests coming from your Flutter UI, headset buttons, the lock screen, notification, iOS control center, car displays and smart watches, even when the app is in the background:

![audio_handler](https://user-images.githubusercontent.com/19899190/100403242-762e7480-30b2-11eb-9fcf-938e08beee53.png)

You can implement these callbacks to play any sort of audio that is appropriate for your app, such as music files or streams, audio assets, text to speech, synthesised audio, or combinations of these.

| Feature                            | Android   | iOS     | macOS   | Web     |
| -------                            | :-------: | :-----: | :-----: | :-----: |
| background audio                   | ✅        | ✅      | ✅      | ✅      |
| headset clicks                     | ✅        | ✅      | ✅      | ✅      |
| start/stop/play/pause/seek/rate    | ✅        | ✅      | ✅      | ✅      |
| fast forward/rewind                | ✅        | ✅      | ✅      | ✅      |
| repeat/shuffle mode                | ✅        | ✅      | ✅      | ✅      |
| queue manipulation, skip next/prev | ✅        | ✅      | ✅      | ✅      |
| custom actions                     | ✅        | ✅      | ✅      | ✅      |
| custom events                      | ✅        | ✅      | ✅      | ✅      |
| notifications/control center       | ✅        | ✅      | ✅      | ✅      |
| lock screen controls               | ✅        | ✅      |         | ✅      |
| album art                          | ✅        | ✅      | ✅      | ✅      |
| Android Auto, Apple CarPlay        | ✅        | ✅      |         |         |

If you'd like to help with any missing features, please join us on the [GitHub issues page](https://github.com/ryanheise/audio_service/issues).

## What's new in 0.18.0?

0.18.0 removes the need for a background isolate, allowing simpler communication between your UI and audio logic and greater compatibility with plugins that don't support multiple isolates.

NOTE: This branch is not yet released and currently undergoing testing. APIs should be considered unstable and may undergo changes before the branch is released. If you want to help test it and provide feedback, use the following pubspec dependency:

```yaml
dependencies:
  audio_service:
    git: 
      url: https://github.com/ryanheise/audio_service.git
      ref: one-isolate
      path: audio_service
```

Basic migration steps:

1. On Android, edit your `AndroidManifest.xml` file by setting the `android:name` attribute of your `<activity>` element to `com.ryanheise.audioservice.AudioServiceActivity` as outlined in the "Android setup" section of this README.
2. Call `AudioService.init()` in your app's `main()` as per the example below, passing any configuration options and callbacks you previously passed into `AudioService.start()`.
3. Remove any call to `AudioService.start()`. The media notification should now show automatically on the first time you call `play()`.
4. Remove your corresponding implementation of `onStart()` and move any initialisation code into the constructor or other callbacks as appropriate.
5. If you use `customAction`/`onCustomAction`, the second argument is now required to be a `Map`.

Optional (recommended) step:

6. `BackgroundAudioTask` is deprecated and replaced by `AudioHandler`, a new composable and mixable API allowing functionality from multiple audio handlers to be combined. To migrate, change your base class from `BackgroundAudioTask` to `BaseAudioHandler`, remove the `on` prefix from each method name (e.g. rename `onPlay` to `play`), and instead of using `AudioServiceBackground.setState/setMediaItem/setQueue`, use `playbackState/mediaItem/queue.add`.

Read the [Migration Guide](https://github.com/ryanheise/audio_service/wiki/Migration-Guide#0140) for more details (TODO!).

## Can I make use of other plugins within the audio handler?

Yes! `audio_service` is designed to let you implement the audio logic however you want, using whatever plugins you want. You can use your favourite audio plugins such as [just_audio](https://pub.dartlang.org/packages/just_audio), [flutter_radio](https://pub.dev/packages/flutter_radio), [flutter_tts](https://pub.dartlang.org/packages/flutter_tts), and others, within your background audio task.

Note that this plugin will not work with other audio plugins that overlap in responsibility with this plugin (i.e. background audio, iOS control center, Android notifications, lock screen, headset buttons, etc.)

## Example

### Initialisation

Define your `AudioHandler` callbacks:

```dart
class MyAudioHandler extends BaseAudioHandler
    with QueueHandler, // mix in default implementations of queue functionality
    SeekHandler { // mix in default implementations of seek functionality
  final _player = AudioPlayer();
  
  play() => _player.play();
  pause() => _player.pause();
  seekTo(Duration position) => _player.seek(position);
  stop() async {
    await _player.stop();
    await super.stop();
  }
  
  customAction(String name, Map<String, dynamic> arguments) async {
    switch (name) {
      case 'setVolume':
        _player.setVolume(arguments['volume']);
        break;
      case 'saveBookmark':
        // app-specific code
        break;
    }
  }
}
```

Register your `AudioHandler` during app startup:

```dart
main() async {
  // store this in a singleton
  _audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelName: 'My Audio App',
      androidEnableQueue: true,
    ),
  );
  runApp(new MyApp());
}
```

### Controls

Standard controls:

```dart
_audioHandler.play();
_audioHandler.seekTo(Duration(seconds: 10));
_audioHandler.setSpeed(1.5);
_audioHandler.pause();
_audioHandler.stop();
```

Queue management:

```dart
var item = MediaItem(
  id: 'https://example.com/audio.mp3',
  album: 'Album name',
  title: 'Track title',
);
_audioHandler.addQueueItem(item);
_audioHandler.insertQueueItem(1, item);
_audioHandler.removeQueueItem(item);
_audioHandler.updateQueue([item, ...]);
_audioHandler.skipToNext();
_audioHandler.skipToPrevious();
_audioHandler.playFromMediaId('https://example.com/audio.mp3')
_audioHandler.playMediaItem(item);
```

Looping and shuffling:

```dart
_audioHandler.setRepeatMode(AudioServiceRepeatMode.one); // none/one/all/group
_audioHandler.setShuffleMode(AudioServiceShuffleMode.all); // none/all/group
```

Custom actions:

```dart
_audioHandler.customAction('setVolume', {'volume': 0.8});
_audioHandler.customAction('saveBookmark');
```

### State

Emit state changes from the `AudioHandler`:

```dart
class MyAudioHandler extends BaseAudioHandler ... {
  MyAudioHandler() {
    // Broadcast which item is currently playing
    _player.currentIndexStream.listen((index) => mediaItem.add(queue[index]));
    // Broadcast the current playback state and what controls should currently
    // be visible in the media notification
    _player.playbackEventStream.listen((event) {
      playbackState.add(playbackState.value.copyWith(
        controls: [
	  MediaControl.skipToPrevious,
	  playing ? MediaControl.pause : MediaControl.play,
	  MediaControl.skipToNext,
	],
	androidCompactActionIndices: [0, 1, 3],
	systemActions: {
	  MediaAction.seekTo,
	  MediaAction.seekForward,
	  MediaAction.seekBackward,
	},
	processingState: {
          ProcessingState.none: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
	}[_player.processingState],
	playing: player.playing,
	updatePosition: player.position,
	bufferedPosition: player.bufferedPosition,
	speed: player.speed,
      ));
    });
  }
}
```

Listen to playback state changes from the UI:

```dart
_audioHandler.playbackState.listen((PlaybackState state) {
  if (state.playing) ... else ...
  switch (state.processingState) {
    case AudioProcessingState.idle: ...
    case AudioProcessingState.loading: ...
    case AudioProcessingState.buffering: ...
    case AudioProcessingState.ready: ...
    case AudioProcessingState.completed: ...
    case AudioProcessingState.error: ...
  }
});
```

Listen to changes to the currently playing item:

```dart
_audioHandler.mediaItem.listen((MediaItem item) { ... });
```

Listen to changes to the queue:

```dart
_audioHandler.queue.listen((List<MediaItem> queue) { ... });
```

Listen to continuous changes to the current playback position:

```dart
AudioService.position.listen((Duration position) { ... });
```

## Text-to-speech example

If you are instead building a text-to-speech reader, you could implement these callbacks differently:

```dart
import 'package:flutter_tts/flutter_tts.dart';
class TtsAudioHandler extends BaseAudioHandler {
  final _tts = FlutterTts();
  MediaItem _item;
  playMediaItem(MediaItem item) async {
    _item = item;
    // Tell clients what we're listening to
    await mediaItem.add(item);
    // Tell clients that we're now playing
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      processingState: AudioProcessingState.ready,
      controls: [MediaControl.stop],
    ));
    // Play a small amount of silent audio on Android to pose as an audio player
    AudioService.androidForceEnableMediaButtons();
    // Start speaking
    _tts.speak(item.extras['text']);
  }
  
  play() {
    if (_item != null) playMediaItem(_item);
  }
  
  stop() async {
    await _tts.stop();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
      controls: [MediaControl.play],
    ));
    await super.stop();
  }
}
```

See the full example for how to handle queues/playlists, headset button clicks and media artwork.

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

1. Make the following changes to your project's `AndroidManifest.xml` file:

```xml
<manifest ...>
  <!-- ADD THESE TWO PERMISSIONS -->
  <uses-permission android:name="android.permission.WAKE_LOCK"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  
  <application ...>
    
    ...
    
    <!-- EDIT THE android:name ATTRIBUTE IN YOUR EXISTING "ACTIVITY" ELEMENT -->
    <activity android:name="com.ryanheise.audioservice.AudioServiceActivity" ...>
      ...
    </activity>
    
    <!-- ADD THIS "SERVICE" element -->
    <service android:name="com.ryanheise.audioservice.AudioService">
      <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
      </intent-filter>
    </service>

    <!-- ADD THIS "RECEIVER" element -->
    <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" >
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver> 
  </application>
</manifest>
```

2. If you use any custom icons in notification, create the file `android/app/src/main/res/raw/keep.xml` to prevent them from being stripped during the build process:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
  tools:keep="@drawable/*" />
```

By default plugin's default icons are not stipped by R8. If you don't use them, you may selectively strip them. For example, the rules below will keep all your icons and discard all the plugin's:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
  tools:keep="@drawable/*"
  tools:discard="@drawable/audio_service_*" 
/>
```

For more information about shrinking see [Android documentation](https://developer.android.com/studio/build/shrink-code#keep-resources).

### Custom Android activity

If your app uses a custom activity, you will need to override `provideFlutterEngine` as follows to ensure that your activity and service use the same shared Flutter engine:

```java
public class CustomActivity extends FlutterActivity {
  @Override
  public FlutterEngine provideFlutterEngine(Context context) {
    return AudioServicePlugin.getFlutterEngine(context);
  }
}
```

Alternatively, you can make your custom activity a subclass of `AudioServiceActivity` and thereby inherit its implementation of `provideFlutterEngine`.

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
