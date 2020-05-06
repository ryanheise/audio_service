# audio_service

This plugin wraps around your existing audio code to allow it to run in the background, and it provides callbacks to allow your app to respond to the media buttons on your headset, Android lock screen and notification, iOS control center, wearables and Android Auto.

The plugin gives you complete flexibility concerning the audio you want to play. It is suitable for:

* Music players
* Text-to-speech readers
* Podcast players
* Navigators
* Complex combinations of the above
* Any app that wishes to play any other sort of audio in the background

The plugin works by creating a container for your audio code to run in that survives the absence or destruction of your app's UI. You will therefore need to write your code in such a way that your UI code is kept separate from your audio playing code.

Because this plugin wraps around your existing audio code, you are free to continue using your favourite audio plugins, such as [just_audio](https://pub.dartlang.org/packages/just_audio), [flutter_radio](https://pub.dev/packages/flutter_radio), [flutter_tts](https://pub.dartlang.org/packages/flutter_tts), and others, to play the actual audio. Note that this plugin will not work with other plugins that that overlap in responsibilities with this plugin. In particular, `audio_service` is responsible for establishing the background execution environment, updating information in the Android notification and lock screen, the iOS control center and now playing info, and for handling callbacks when users interact with media controls on those screens or headsets for example. If you use another plugin that also provides any of these features, it will likely interfere with the operation of this plugin.

If you'd like to help with any missing features, join us on the [GitHub issues page](https://github.com/ryanheise/audio_service/issues).

| Feature                        | Android    | iOS       |
| -------                        | :-------:  | :-----:   |
| start/stop                     | ✅         | ✅        |
| play/pause                     | ✅         | ✅        |
| headset click                  | ✅         | ✅        |
| seek                           | ✅         | ✅        |
| skip next/prev                 | ✅         | ✅        |
| FF/rewind                      | ✅         | ✅        |
| rate                           | ✅         | ✅        |
| custom actions                 | ✅         | ✅        |
| custom events                  | ✅         | ✅        |
| notifications/control center   | ✅         | (partial) |
| lock screen controls           | ✅         | (partial) |
| album art                      | ✅         | ✅        |
| queue management               | ✅         | ✅        |
| runs in background             | ✅         | ✅        |
| Handle phonecall interruptions | ✅         |           |
| Android Auto                   | (untested) |           |

## Documentation

* [Tutorial](https://github.com/ryanheise/audio_service/wiki/Tutorial)
* [Frequently Asked Questions](https://github.com/ryanheise/audio_service/wiki/FAQ)
* [API documentation](https://pub.dev/documentation/audio_service/latest/audio_service/audio_service-library.html)

## Example

When using this plugin, your user interface code will run in the main UI isolate, and your audio playing code will run in a separate background isolate, enabling it to outlive the potential suspension or destruction of the UI. These two isolates do not share memory and communicate through a set of message passing APIs. To cater for this code separation, the plugin provides two sets of APIs: one for your main UI isolate (`AudioService`), and one for your background audio isolate (`AudioServiceBackground`).

### UI code

Insert an `AudioServiceWidget` at the top of your widget tree to maintain a connection to `AudioService` shared by all of your app's routes:

```dart
return MaterialApp(
  home: AudioServiceWidget(MainScreen()),
);
```

Once connected, your Flutter UI can start up and shut down the background audio task, and send messages to it:

```dart
AudioService.start(backgroundTaskEntrypoint: _backgroundTaskEntrypoint);
AudioService.pause();
AudioService.play();
AudioService.skipToNext();
AudioService.skipToPrevious();
AudioService.seekTo(10000);
AudioService.stop(); // shuts down the background audio task
```

Your Flutter UI can listen to any changes in the state of audio playback via these streams:

```dart
AudioService.playbackStateStream    // playback state and position
AudioService.currentMediaItemStream // current item being played
AudioService.queueStream            // (optional) playlist
```

Consider the Flutter widget [StreamBuilder](https://api.flutter.dev/flutter/widgets/StreamBuilder-class.html) to display data from the stream so that it automatically updates your UI as new events come through.

If the user closes your Flutter UI and then re-opens it, the connection to your background audio task will be automatically reestablished, and these streams will re-emit the most recent event allowing your UI to restore itself to the current state.

### Background code

The `_backgroundTaskEntrypoint` function that you passed into `AudioService.start` must be a top-level or static function, and it will be the first function to be called as soon as the background isolate is started. It should contain a single line of code that creates your background audio task:

```dart
void myBackgroundTaskEntrypoint() {
  AudioServiceBackground.run(() => MyBackgroundTask());
}

class MyBackgroundTask extends BackgroundAudioTask {
  AudioPlayer _audioPlayer = AudioPlayer();
  Completer _completer = Completer();
  
  @override
  Future<void> onStart() async {
    // Your custom dart code to start audio playback.
    // NOTE: The background audio task will shut down
    // as soon as this async function completes.
    return _completer.future;
  }
  @override
  void onStop() {
    // Your custom dart code to stop audio playback. e.g.:
    _audioPlayer.stop();
    // Cause the audio task to shut down.
    _completer.complete();
  }
  @override
  void onPlay() {
    // Your custom dart code to resume audio playback. e.g.:
    _audioPlayer.play();
    // Broadcast the state change to all user interfaces:
    AudioServiceBackground.setState(basicState: BasicPlaybackState.playing, ...);
  }
  @override
  void onPause() {
    // Your custom dart code to pause audio playback. e.g.:
    _audioPlayer.pause();
    // Broadcast the state change to all user interfaces:
    AudioServiceBackground.setState(basicState: BasicPlaybackState.paused, ...);
  }
  @override
  void onClick(MediaButton button) {
    // Your custom dart code to handle a click on a headset.
  }
  @override
  void onSkipToNext() {
    // Your custom dart code to skip to the next queue item.
  }
  @override
  void onSkipToPrevious() {
    // Your custom dart code to skip to the previous queue item.
  }
  @override
  void onSeekTo(int position) {
    // Your custom dart code to seek to a position.
  }
}
```

These callbacks get called not only in response to method calls from your UI (like `AudioService.play`) but also when the user clicks on a button in your Android notification, lock screen, iOS control center, or headphone buttons (in the case of `onClick`).

At a bare minimum, you must override the `onStart` and `onStop` callbacks to manage setting up and tearing down the background audio task, while all other callbacks are optional depending on your app's requirements.

During the operation of your background audio task, you should broadcast any state changes to all user interfaces using these methods:

```dart
// Tell all UIs the playback state has changed (playing/paused/...)
AudioServiceBackground.setState
// Tell all UIs we're now playing a particular item (title/artist/image/...)
AudioServiceBackground.setMediaItem
// Tell all UIs the queue/playlist has changed
AudioServiceBackground.setQueue
```

This allows not only your Flutter UI, but also the Android notification, iOS command center, etc. to update the information they display to the user.

A [full example](https://github.com/ryanheise/audio_service/blob/master/example/lib/main.dart) is provided on GitHub demonstrating both music and text-to-speech use cases.

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

    <receiver android:name="androidx.media.session.MediaButtonReceiver" >
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver> 
  </application>
</manifest>
```

2. Any icons that you want to appear in the notification (see the `MediaControl` class) should be defined as Android resources in `android/app/src/main/res`. Here you will find a subdirectory for each different resolution:

```
drawable-hdpi
drawable-mdpi
drawable-xhdpi
drawable-xxhdpi
drawable-xxxhdpi
```

You can use [Android Asset Studio](https://romannurik.github.io/AndroidAssetStudio/) to generate these different subdirectories for any standard material design icon.

Starting from Flutter 1.12, you will also need to disable the `shrinkResources` setting in your `android/app/build.gradle` file, otherwise your icon resources will be removed during the build:

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
