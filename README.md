# audio_service

This plugin wraps around your existing audio code to allow it to run in the background or with the screen turned off, and allows your app to interact with headset buttons, the Android lock screen and notification, iOS control center, wearables and Android Auto. It is suitable for:

* Music players
* Text-to-speech readers
* Podcast players
* Navigators
* More!

## How does this plugin work?

You encapsulate your audio code in a background task which runs in a special isolate that continues to run when your UI is absent. Your background task implements callbacks to respond to playback requests coming from your Flutter UI, headset buttons, the lock screen, notification, iOS control center, car displays and smart watches:

![audio_service_callbacks](https://user-images.githubusercontent.com/19899190/84386442-b305cc80-ac34-11ea-8c2f-1b4cb126a98d.png)

You can implement these callbacks to play any sort of audio that is appropriate for your app, such as music files or streams, audio assets, text to speech, synthesised audio, or combinations of these.

| Feature                            | Android    | iOS     |
| -------                            | :-------:  | :-----: |
| background audio                   | ✅         | ✅      |
| headset clicks                     | ✅         | ✅      |
| Handle phonecall interruptions     | ✅         | ✅      |
| start/stop/play/pause/seek/rate    | ✅         | ✅      |
| fast forward/rewind                | ✅         | ✅      |
| repeat/shuffle mode                | ✅         | ✅      |
| queue manipulation, skip next/prev | ✅         | ✅      |
| custom actions                     | ✅         | ✅      |
| custom events                      | ✅         | ✅      |
| notifications/control center       | ✅         | ✅      |
| lock screen controls               | ✅         | ✅      |
| album art                          | ✅         | ✅      |
| Android Auto, Apple CarPlay        | (untested) | ✅      |

If you'd like to help with any missing features, please join us on the [GitHub issues page](https://github.com/ryanheise/audio_service/issues).

## Migrating to 0.13.0

As of 0.13.0, all callbacks in `AudioBackgroundTask` are asynchronous. This allows the main isolate to await their completion and better synchronise with the background audio task.

As of 0.11.0, the background audio task terminates when `onStop` completes rather than when `onStart` completes.

As of 0.10.0, your broadcast receiver in `AndroidManifest.xml` should be replaced with the one below to ensure that headset and notification clicks continue to work:

```xml
    <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" >
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver> 
```

## Can I make use of other plugins within the background audio task?

Yes! `audio_service` is designed to let you implement the audio logic however you want, using whatever plugins you want. You can use your favourite audio plugins such as [just_audio](https://pub.dartlang.org/packages/just_audio), [flutter_radio](https://pub.dev/packages/flutter_radio), [flutter_tts](https://pub.dartlang.org/packages/flutter_tts), and others, within your background audio task. There are also plugins like [just_audio_service](https://github.com/yringler/just_audio_service) that provide default implementations of `BackgroundAudioTask` to make your job easier.

Note that this plugin will not work with other audio plugins that overlap in responsibility with this plugin (i.e. background audio, iOS control center, Android notifications, lock screen, headset buttons, etc.)

## Example

Your audio code will run in a special background isolate, separate and detachable from your app's UI. To achieve this, define a subclass of `BackgroundAudioTask` that overrides a set of callbacks to respond to client requests:

```dart
class MyBackgroundTask extends BackgroundAudioTask {
  // Initialise your audio task
  onStart(Map<String, dynamic> params) {}
  // Handle a request to stop audio and finish the task
  onStop() async {}
  // Handle a request to play audio
  onPlay() {}
  // Handle a request to pause audio
  onPause() {}
  // Handle a headset button click (play/pause, skip next/prev)
  onClick(MediaButton button) {}
  // Handle a request to skip to the next queue item
  onSkipToNext() {}
  // Handle a request to skip to the previous queue item
  onSkipToPrevious() {}
  // Handle a request to seek to a position
  onSeekTo(Duration position) {}
  // Handle a phone call or other interruption
  onAudioFocusLost(AudioInterruption interruption) {}
  // Handle the end of an audio interruption.
  onAudioFocusGained(AudioInterruption interruption) {}
}
```

You can implement these (and other) callbacks to play any type of audio depending on the requirements of your app. For example, if you are building a podcast player, you may have code such as the following:

```dart
import 'package:just_audio/just_audio.dart';
class PodcastBackgroundTask extends BackgroundAudioTask {
  AudioPlayer _player = AudioPlayer();
  onPlay() {
    _player.play();
    AudioServiceBackground.setState(playing: true, ...);
  }
```

If you are instead building a text-to-speech reader, you may have code such as the following:

```dart
import 'package:flutter_tts/flutter_tts.dart';
class ReaderBackgroundTask extends BackgroundAudioTask {
  FlutterTts _tts = FlutterTts();
  String article;
  onPlay() {
    _tts.speak(article);
    AudioServiceBackground.setState(playing: true, ...);
  }
}
```

There are several methods in the `AudioServiceBackground` class that are made available to your background audio task to allow it to communicate to clients outside the isolate, such as your Flutter UI (if present), the iOS control center, the Android notification and lock screen. These are:

* `AudioServiceBackground.setState` broadcasts the current playback state to all clients. This includes whether or not audio is playing, but also whether audio is buffering, the current playback position and buffer position, the current playback speed, and the set of audio controls that should be made available. When you broadcast this information to all clients, it allows them to update their user interfaces to show the appropriate set of buttons, and show the correct audio position on seek bars, for example. It is important for you to call this method whenever any of these pieces of state changes. You will typically want to call this method from your `onStart`, `onPlay`, `onPause`, `onSkipToNext`, `onSkipToPrevious` and `onStop` callbacks.
* `AudioServiceBackground.setMediaItem` broadcasts the currently playing media item to all clients. This includes the track title, artist, genre, duration, any artwork to display, and other information. When you broadcast this information to all clients, it allows them to update their user interface accordingly so that it is displayed on the lock screen, the notification, and in your Flutter UI (if present). You will typically want to call this method from your `onStart`, `onSkipToNext` and `onSkipToPrevious` callbacks.
* `AudioServiceBackground.setQueue` broadcasts the current queue to all clients. Some clients like Android Auto may display this information in their user interfaces. You will typically want to call this method from your `onStart` callback. Other callbacks exist where it may be appropriate to call this method such as `onAddQueueItem` and `onRemoveQueueItem`.

Once you have built your isolated background audio task, your Flutter UI connects to it by inserting an `AudioServiceWidget` at the top of your widget tree:

```dart
return MaterialApp(
  home: AudioServiceWidget(MainScreen()),
);
```

Starting the background audio task:

```dart
await AudioService.start(
  backgroundTaskEntrypoint: _myEntrypoint,
  androidNotificationIcon: 'mipmap/ic_launcher',
  // An example of passing custom parameters.
  // These will be passed through to your `onStart` callback.
  params: {'url', 'https://somewhere.com/sometrack.mp3'},
);
// this must be a top-level function
void _myEntrypoint() => AudioServiceBackground.run(() => MyBackgroundTask());
```

Shutting down the background audio task:

```dart
// This will pass through to your `onStop` callback.
AudioService.stop();
```

While your background task is running, your Flutter UI can send requests to it via methods in the `AudioService` class which pass through to the corresponding methods in your background audio task:

* `AudioService.play`
* `AudioService.pause`
* `AudioService.click`
* `AudioService.skipToNext`
* `AudioService.skipToPrevious`
* `AudioService.seekTo`

Your Flutter UI can also react to changes to the state, current media item and queue that are broadcast by your background audio task by listening to the following streams:

* `AudioService.playbackStateStream`
* `AudioService.currentMediaItemStream`
* `AudioService.queueStream`

Keep in mind that your Flutter UI and background task run in separate isolates and do not share memory. The only way they communicate is via message passing. Your Flutter UI will only use the `AudioService` API to communicate with the background task, while your background task will only use the `AudioServiceBackground` API to interact with the clients, which include the Flutter UI.

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

# Where can I find more information?

* [Tutorial](https://github.com/ryanheise/audio_service/wiki/Tutorial): walks you through building a simple audio player while explaining the basic concepts.
* [Full example](https://github.com/ryanheise/audio_service/blob/master/example/lib/main.dart): The `example` subdirectory on GitHub demonstrates both music and text-to-speech use cases.
* [Frequently Asked Questions](https://github.com/ryanheise/audio_service/wiki/FAQ)
* [API documentation](https://pub.dev/documentation/audio_service/latest/audio_service/audio_service-library.html)
