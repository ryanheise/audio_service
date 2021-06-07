package com.ryanheise.audioserviceexample;

import com.ryanheise.audioservice.AudioServicePlugin;

import io.flutter.app.FlutterApplication;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister;

public class Application extends FlutterApplication {
    private static FlutterEngine engine;
    static FlutterEngine getEngine() { return engine; }

    @Override
    public void onCreate() {
        super.onCreate();
        // Create a flutter engine, but not register plugins yet
        engine = new FlutterEngine(getApplicationContext(), null, false);
        // Run dart code
        engine.getDartExecutor().executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault());
        // Cache the engine
        FlutterEngineCache.getInstance().put("my_engine", engine);
        // Provide an engine to the audio service by setting a factory
        AudioServicePlugin.setEngineFactory(() -> new AudioServicePlugin.FlutterEngineFactory.EngineConfig(engine));
        // Register remaining plugins
        GeneratedPluginRegister.registerGeneratedPlugins(engine);
    }
}
