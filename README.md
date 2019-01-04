# audio_service

Play audio in the background.

* Continues playing while the screen is off or the app is in the background
* Control playback from your flutter UI, headset, Wear OS or Android Auto
* Drive audio playback from Dart code

This plugin provides a complete framework for playing audio in the background. You implement callbacks in Dart to play/pause/seek/etc audio, which means that you will need to use *other* Dart plugins in conjunction with this one to actually play the audio. This gives you the flexibility to play any kind of audio in the background. For example, if you want to play music in the background, you may use the [audioplayer](https://pub.dartlang.org/packages/audioplayer) plugin in conjunction with this one. If you would rather play text-to-speech in the background, you may use the [flutter_tts](https://pub.dartlang.org/packages/flutter_tts) plugin in conjunction with this one.

[audio_service](https://pub.dartlang.org/packages/audio_service) itself manages all of the platform-specific code for setting up the environment for background audio, and interfacing with various peripherals used to control audio playback. For Android, this means acquiring a wake lock so that audio will play with the screen turned off, acquiring audio focus so that you can control your app from a headset, creating a media session and media browser service so that your app can be controlled by wearable devices and Android Auto. The iOS side is currently not implemented and so contributors are welcome (please see the Help section at the bottom of this page).

Since background execution of Dart code is a relatively new feature of flutter, not all plugins are yet compatible with audio_service (I am contacting some of these authors to make their packages compatible.)

## Example

### Client-side code

```dart
AudioService.connect();   // When UI becomes visible
AudioService.start(       // When user clicks button to start playback
  backgroundTask: myBackgroundTask,
  androidNotificationChannelName: 'Music Player',
  androidNotificationIcon: "mipmap/ic_launcher",
);
AudioService.disconnect(); // When UI is gone
```

### Background code

```dart
void myBackgroundTask() {
  AudioServiceBackground.run(
    onStart: () async {
      // Your custom dart code to start audio playback.
      // NOTE: The background audio task will shut down
      // as soon as this async function completes.
    },
    onPlay: () {
      // Your custom dart code to resume audio playback.
    }
    onPause: () {
      // Your custom dart code to pause audio playback.
    },
    onStop: () {
      // Your custom dart code to stop audio playback.
    },
    onClick: (MediaButton button) {
      // Your custom dart code to handle a media button click.
    },
  );
}
```

### Android setup

You will need to create a custom `MainApplication` class as follows:

```java
public class MainApplication extends FlutterApplication implements PluginRegistry.PluginRegistrantCallback {
  @Override
  public void onCreate() {
    super.onCreate();
    AudioServicePlugin.setPluginRegistrantCallback(this);
  }

  @Override
  public void registerWith(PluginRegistry registry) {
    GeneratedPluginRegistrant.registerWith(registry);
  }
}
```

Edit your project's `AndroidManifest.xml` file to reference your `MainApplication` class, declare the permission to create a wake lock, and add component entries for the `<service>` and `<receiver>`:

```xml
<manifest ...>
  <uses-permission android:name="android.permission.WAKE_LOCK"/>
  
  <application
    android:name=".MainApplication"
    ...>
    
    ...
    
    <service android:name="com.ryanheise.audioservice.AudioService">
      <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
      </intent-filter>
    </service>

    <receiver android:name="android.support.v4.media.session.MediaButtonReceiver" >
      <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
      </intent-filter>
    </receiver> 
  </application>
</manifest>
```

Any icons that you want to appear in the notification should be defined as Android resources in `android/app/src/main/res`. Here you will find a subdirectory for each different resolution:

```
drawable-hdpi
drawable-mdpi
drawable-xhdpi
drawable-xxhdpi
drawable-xxxhdpi
```

You can use [Android Asset Studio](https://romannurik.github.io/AndroidAssetStudio/) to generate these different subdirectories for any standard material design icon.

## Help/Contribute

* If you know how to implement any of these features in iOS, pull requests are welcome! As a guideline, prefer to keep the same dart API for both Android and iOS where possible. In cases where there are unavoidable differences between Android and iOS, name the feature with an `android` or `ios` prefix. 

* If you find another flutter plugin (audio or otherwise) that crashes when running in the background environment, another way you can help is to file a bug report with that project, letting them know of the simple fix to make it work (see below).

### Sample bug report

Here is a sample bug report.

> Flutter's new background execution feature (described here: https://medium.com/flutter-io/executing-dart-in-the-background-with-flutter-plugins-and-geofencing-2b3e40a1a124) allows plugins to be registered in a background context (e.g. a Service). The problem is that the wifi plugin assumes that the context for plugin registration is an activity with this line of code:
> 
> `    WifiManager wifiManager = (WifiManager) registrar.activity().getApplicationContext().getSystemService(Context.WIFI_SERVICE);`
> 
> `registrar.activity()` may now return null, and this leads to a `NullPointerException`:
> 
> ```
> E/AndroidRuntime( 2453):   at com.ly.wifi.WifiPlugin.registerWith(WifiPlugin.java:23)
> E/AndroidRuntime( 2453):   at io.flutter.plugins.GeneratedPluginRegistrant.registerWith(GeneratedPluginRegistrant.java:30)
> ```
> 
> The solution is to change the above line of code to this:
> 
> `    WifiManager wifiManager = (WifiManager) registrar.activeContext().getApplicationContext().getSystemService(Context.WIFI_SERVICE);`
