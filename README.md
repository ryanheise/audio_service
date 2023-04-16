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
| play/pause/seek/rate/stop          | ✅        | ✅      | ✅      | ✅      |
| fast forward/rewind                | ✅        | ✅      | ✅      | ✅      |
| repeat/shuffle mode                | ✅        | ✅      | ✅      | ✅      |
| queue manipulation, skip next/prev | ✅        | ✅      | ✅      | ✅      |
| custom actions/events/states       | ✅        | ✅      | ✅      | ✅      |
| notifications/control center       | ✅        | ✅      | ✅      | ✅      |
| lock screen controls               | ✅        | ✅      |         | ✅      |
| album art                          | ✅        | ✅      | ✅      | ✅      |
| Android Auto, Apple CarPlay        | ✅        | ✅      |         |         |

If you'd like to help with any missing features, please join us on the [GitHub issues page](https://github.com/ryanheise/audio_service/issues).

## Tutorials and documentation

* [Background audio in Flutter with Audio Service and Just Audio](https://suragch.medium.com/background-audio-in-flutter-with-audio-service-and-just-audio-3cce17b4a7d?sk=0837a1b1773e27a4f879ff3072e90305) by @suragch
* [Tutorial](https://github.com/ryanheise/audio_service/wiki/Tutorial): walks you through building a simple audio player while explaining the basic concepts.
* [Full example](https://github.com/ryanheise/audio_service): The `example` subdirectory on GitHub demonstrates both music and text-to-speech use cases.
* [Frequently Asked Questions](https://github.com/ryanheise/audio_service/wiki/FAQ)
* [API documentation](https://pub.dev/documentation/audio_service/latest/audio_service/audio_service-library.html)

## What's new in 0.18.0?

0.18.0 removes the need for a background isolate, allowing simpler communication between your UI and audio logic and greater compatibility with plugins that don't support multiple isolates. It also comes with many other new features listed in the [CHANGELOG](https://pub.dev/packages/audio_service/changelog).

Read the [Migration Guide](https://github.com/ryanheise/audio_service/wiki/Migration-Guide#0180) for instructions on how to update your code.

## Can I make use of other plugins within the audio handler?

Yes! `audio_service` is designed to let you implement the audio logic however you want, using whatever plugins you want. You can use your favourite audio plugins such as [just_audio](https://pub.dartlang.org/packages/just_audio), [flutter_tts](https://pub.dartlang.org/packages/flutter_tts), and others, within your audio handler. There are also plugins like [just_audio_handlers](https://github.com/yringler/inside-app/tree/master/just_audio_handlers) that provide default implementations of `AudioHandler` to make your job easier.

Note that this plugin will not work with other audio plugins that overlap in responsibility with this plugin (i.e. background audio, iOS control center, Android notifications, lock screen, headset buttons, etc.)

## Example

### Initialisation

Define your `AudioHandler` with the callbacks that you want your app to handle:

```dart
class MyAudioHandler extends BaseAudioHandler
    with QueueHandler, // mix in default queue callback implementations
    SeekHandler { // mix in default seek callback implementations
  
  // The most common callbacks:
  Future<void> play() async {
    // All 'play' requests from all origins route to here. Implement this
    // callback to start playing audio appropriate to your app. e.g. music.
  }
  Future<void> pause() async {}
  Future<void> stop() async {}
  Future<void> seek(Duration position) async {}
  Future<void> skipToQueueItem(int i) async {}
}
```

Register your `AudioHandler` during app startup:

```dart
Future<void> main() async {
  // store this in a singleton
  _audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.mycompany.myapp.channel.audio',
      androidNotificationChannelName: 'Music playback',
    ),
  );
  runApp(new MyApp());
}
```

### Sending requests to the audio handler from Flutter

Standard controls:

```dart
_audioHandler.play();
_audioHandler.seek(Duration(seconds: 10));
_audioHandler.setSpeed(1.5);
_audioHandler.pause();
_audioHandler.stop();
```

Playing specific media items:

```dart
var item = MediaItem(
  id: 'https://example.com/audio.mp3',
  album: 'Album name',
  title: 'Track title',
  artist: 'Artist name',
  duration: const Duration(milliseconds: 123456),
  artUri: Uri.parse('https://example.com/album.jpg'),
);

_audioHandler.playMediaItem(item);
_audioHandler.playFromSearch(queryString);
_audioHandler.playFromUri(uri);
_audioHandler.playFromMediaId(id);
```

Queue management:

```dart
_audioHandler.addQueueItem(item);
_audioHandler.insertQueueItem(1, item);
_audioHandler.removeQueueItem(item);
_audioHandler.updateQueue([item, ...]);
_audioHandler.skipToNext();
_audioHandler.skipToPrevious();
_audioHandler.skipToQueueItem(2);
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

### Broadcasting state changes

Your audio handler must broadcast state changes so that the system notification and smart watches (etc) know what state to display. Your app's Flutter UI may also listen to these state changes so that it knows what state to display. Thus, the audio handler provides a single source of truth for your audio state to all clients.

Broadcast the current media item:

```dart
class MyAudioHandler extends BaseAudioHandler ... {
    ...
    mediaItem.add(item1);
    ...
```

Broadcast the current queue:

```dart
  ...
  queue.add(<MediaItem>[item1, item2, item3]);
  ...
```

Broadcast the current playback state:

```dart
    ...
    // All options shown:
    playbackState.add(PlaybackState(
      // Which buttons should appear in the notification now
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.pause,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      // Which other actions should be enabled in the notification
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Which controls to show in Android's compact view.
      androidCompactActionIndices: const [0, 1, 3],
      // Whether audio is ready, buffering, ...
      processingState: AudioProcessingState.ready,
      // Whether audio is playing
      playing: true,
      // The current position as of this update. You should not broadcast
      // position changes continuously because listeners will be able to
      // project the current position after any elapsed time based on the
      // current speed and whether audio is playing and ready. Instead, only
      // broadcast position updates when they are different from expected (e.g.
      // buffering, or seeking).
      updatePosition: Duration(milliseconds: 54321),
      // The current buffered position as of this update
      bufferedPosition: Duration(milliseconds: 65432),
      // The current speed
      speed: 1.0,
      // The current queue position
      queueIndex: 0,
    ));
```

Broadcasting mutations of the current playback state using `copyWith`:

```dart
    playbackState.add(playbackState.value.copyWith(
      // Keep all existing state the same with only the speed changed:
      speed: newSpeed,
    ));
```

### Listening to state changes

Listen to changes to the currently playing item from the Flutter UI:

```dart
_audioHandler.mediaItem.listen((MediaItem item) { ... });
```

Listen to changes to the queue from the Flutter UI:

```dart
_audioHandler.queue.listen((List<MediaItem> queue) { ... });
```

Listen to playback state changes from the Flutter UI:

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

Listen to a stream of continuous changes to the current playback position:

```dart
AudioService.position.listen((Duration position) { ... });
```

### Advanced features

Compose multiple audio handler classes:

```dart
_audioHandler = await AudioService.init(
  builder: () => AnalyticsAudioHandler(
    PersistingAudioHandler(
      MyAudioHandler())),
);
```

Connecting from another isolate:

```dart
// Wrap audio handler in IsolatedAudioHandler:
_audioHandler = await AudioService.init(
  builder: () => IsolatedAudioHandler(
    MyAudioHandler(),
    portName: 'my_audio_handler',
  ),
);
// From another isolate, obtain a proxy reference:
_proxyAudioHandler = await IsolatedAudioHandler.lookup(
  portName: 'my_audio_handler',
);
```

See the full example for how to handle queues/playlists, headset button clicks, media artwork and text to speech.

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

These instructions assume that your project follows the Flutter 1.12 project template or later. If your project was created prior to 1.12 and uses the old project structure, you can update your project to follow the [new project template](https://github.com/flutter/flutter/wiki/Upgrading-pre-1.12-Android-projects).

Additionally:

1. Make the following changes to your project's `AndroidManifest.xml` file:

```xml
<manifest xmlns:tools="http://schemas.android.com/tools" ...>
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
    <service android:name="com.ryanheise.audioservice.AudioService"
        android:foregroundServiceType="mediaPlayback"
        android:exported="true" tools:ignore="Instantiatable">
      <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
      </intent-filter>
    </service>

    <!-- ADD THIS "RECEIVER" element -->
    <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
        android:exported="true" tools:ignore="Instantiatable">
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver> 
  </application>
</manifest>
```

Note: when targeting Android 12 or above, you must set `android:exported` on each component that has an intent filter (the main activity, the service and the receiver). If the manifest merging process causes `"Instantiable"` lint warnings, use `tools:ignore="Instantiable"` (as above) to suppress them.

2. If you use any custom icons in notification, create the file `android/app/src/main/res/raw/keep.xml` to prevent them from being stripped during the build process:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
  tools:keep="@drawable/*" />
```

By default plugin's default icons are not stripped by R8. If you don't use them, you may selectively strip them. For example, the rules below will keep all your icons and discard all the plugin's:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources xmlns:tools="http://schemas.android.com/tools"
  tools:keep="@drawable/*"
  tools:discard="@drawable/audio_service_*" 
/>
```

For more information about shrinking see [Android documentation](https://developer.android.com/studio/build/shrink-code#keep-resources).


### Custom Android activity

If your app needs to use its own custom activity, make sure you update your `AndroidManifest.xml` file to reference your activity's class name instead of `AudioServiceActivity`. For example, if your activity class is named `MainActivity`, then use:

```xml
    <activity android:name=".MainActivity" ...>
```

Depending on whether you activity is a regular `Activity` or a `FragmentActivity`, you must also include some code to link to audio_service's shared `FlutterEngine`. The easiest way to accomplish this is to inherit that code from one of audio_service's provided base classes.

1. Integration as an `Activity`:

```java
import com.ryanheise.audioservice.AudioServiceActivity;

class MainActivity extends AudioServiceActivity {
    // ...
}
```

2. Integration as a `FragmentActivity`:

```java
import com.ryanheise.audioservice.AudioServiceFragmentActivity;

class MainActivity extends AudioServiceFragmentActivity {
    // ...
}
```

You can also write your own activity class from scratch, and override the `provideFlutterEngine`, `getCachedEngineId` and `shouldDestroyEngineWithHost` methods yourself. For inspiration, see the source code of the provided `AudioServiceActivity` and `AudioServiceFragmentActivity` classes.

## iOS setup

Insert this in your `Info.plist` file:

```
  <key>UIBackgroundModes</key>
  <array>
    <string>audio</string>
  </array>
```

The example project may be consulted for context.

Note that the `audio` background mode permits an app to run in the background only for the purpose of playing audio. The OS may kill your process if it sits idly without playing audio, for example, by using a timer to sleep for a few seconds. If your app needs to pause for a few seconds between audio tracks, consider playing a silent audio track to create that effect rather than using an idle timer.

## macOS setup

The minimum supported macOS version is 10.12.2 (though this could be changed with some work in the future).  
Modify the platform line in `macos/Podfile` to look like the following:

```
platform :osx, '10.12.2'
```
