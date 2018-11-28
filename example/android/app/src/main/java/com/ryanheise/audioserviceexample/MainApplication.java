package com.ryanheise.audioserviceexample;

import io.flutter.plugin.common.PluginRegistry;
import io.flutter.app.FlutterApplication;

import io.flutter.plugins.GeneratedPluginRegistrant;
import com.ryanheise.audioservice.AudioServicePlugin;

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
