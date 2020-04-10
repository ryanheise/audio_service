# audio_service

Play audio in the background.

* Continues playing while the screen is off or the app is in the background
* Control playback from your Flutter UI, notifications, lock screen, headset, Wear OS or Android Auto
* Drive audio playback from Dart code

This plugin wraps around your existing Dart audio code to allow it to run in the background, and also respond to media button clicks on the lock screen, notifications, control center, headphone buttons and other supported remote control devices. This is necessary for a whole range of media applications such as music and podcast players, text-to-speech readers, navigators, etc.

This plugin is audio agnostic. It is designed to allow you to use your favourite audio plugins, such as [just_audio](https://pub.dartlang.org/packages/just_audio), [flutter_radio](https://pub.dev/packages/flutter_radio), [flutter_tts](https://pub.dartlang.org/packages/flutter_tts), and others. It simply wraps a special isolate around your existing audio code so that it can run in the background and enable remote control interfaces.

Note that because your app's UI and your background audio task will run in separate isolates, they do not share memory. They communicate through the message passing APIs provided by audio_service.

**NEW**: This release includes a partially working "alpha" iOS implementation. If you'd like to help with any missing features, join us on [GitHub issue #10](https://github.com/ryanheise/audio_service/issues/10).

| Feature                        | Android    | iOS        |
| -------                        | :-------:  | :-----:    |
| start/stop                     | ✅         | ✅         |
| play/pause                     | ✅         | ✅         |
| headset click                  | ✅         | ✅         |
| seek                           | ✅         | ✅         |
| skip next/prev                 | ✅         | ✅         |
| FF/rewind                      | ✅         | ✅         |
| rate                           | ✅         | ✅         |
| custom actions                 | ✅         | (untested) |
| notifications/control center   | ✅         | (partial)  |
| lock screen controls           | ✅         | (partial)  |
| album art                      | ✅         | ✅         |
| queue management               | ✅         | ✅         |
| runs in background             | ✅         | ✅         |
| Handle phonecall interruptions | ✅         |            |
| Android Auto                   | (untested) |            |

## Tutorial

A tutorial for this plugin is available at the [GitHub Wiki](https://github.com/ryanheise/audio_service/wiki/Tutorial).

## Example

When using this plugin, your user interface code will run in the main UI isolate, and your audio playing code will run in a separate background isolate, enabling it to outlive the potential suspension or destruction of the UI. To cater for this code separation, the plugin provides two sets of APIs: one for your main UI isolate (`AudioService`), and one for your background audio isolate (`AudioServiceBackground`).

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

Your background audio task should broadcast state changes which your Flutter UI can listen to via these streams:

```dart
AudioService.playbackStateStream    // playback state and position
AudioService.currentMediaItemStream // current item being played
AudioService.queueStream            // (optional) playlist
```

If the user closes your Flutter UI and then re-opens it, the connection to your background audio task will be automatically reestablished, and these streams will re-emit the most recent event allowing your UI to restore itself to the current state.

A full example is available on GitHub the `example/` directory.

### Background code

The `_backgroundTaskEntrypoint` function that you passed into `AudioService.start` must be a top-level or static function, and it will be the first function to be called as soon as the background isolate is started. It should contain a single line of code that creates your background audio task:

```dart
void myBackgroundTaskEntrypoint() {
  AudioServiceBackground.run(() => MyBackgroundTask());
}

class MyBackgroundTask extends BackgroundAudioTask {
  @override
  Future<void> onStart() async {
    // Your custom dart code to start audio playback.
    // NOTE: The background audio task will shut down
    // as soon as this async function completes.
  }
  @override
  void onStop() {
    // Your custom dart code to stop audio playback.
  }
  @override
  void onPlay() {
    // Your custom dart code to resume audio playback.
  }
  @override
  void onPause() {
    // Your custom dart code to pause audio playback.
  }
  @override
  void onClick(MediaButton button) {
    // Your custom dart code to handle a media button click.
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

At a bare minimum, you must override the `onStart` and `onStop` callbacks to manage setting up and tearing down the background audio task, while all other callbacks are optional and you can implement just those that are relevant to your app.

The full example on GitHub demonstrates how to fill in these callbacks to do audio playback and also text-to-speech.

## Android setup

These instructions assume that your project follows the new project template introduced in Flutter 1.12. If your project was created prior to 1.12 and uses the old project structure, you can update your project to follow the [new project template](https://github.com/flutter/flutter/wiki/Upgrading-pre-1.12-Android-projects).

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

3. (Optional) Versions of Flutter since 1.12 have a memory leak that affects this plugin. It will be fixed in an upcoming Flutter release but until then you can work around it by overriding the following method in your `MainActivity` class:

```java
public class MainActivity extends FlutterActivity {
  /** This is a temporary workaround to avoid a memory leak in the Flutter framework */
  @Override
  public FlutterEngine provideFlutterEngine(Context context) {
    // Instantiate a FlutterEngine.
    FlutterEngine flutterEngine = new FlutterEngine(context.getApplicationContext());

    // Start executing Dart code to pre-warm the FlutterEngine.
    flutterEngine.getDartExecutor().executeDartEntrypoint(
      DartExecutor.DartEntrypoint.createDefault()
    );

    return flutterEngine;
  }
}
```

Alternatively, if you use a cached flutter engine (as per [these instructions](https://flutter.dev/docs/development/add-to-app/android/add-flutter-screen#step-3-optional-use-a-cached-flutterengine)), you will need to change the instantiation code from `new FlutterEngine(this)` to `new FlutterEngine(getApplicationContext())`.

## iOS setup

Insert this in your `Info.plist` file:

```
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
```

The example project may be consulted for context.
