package com.ryanheise.audioservice;

import android.content.Context;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;

public class AudioServiceFragmentActivity extends FlutterFragmentActivity {
    @Override
    public FlutterEngine provideFlutterEngine(@NonNull Context context) {
        return AudioServicePlugin.getFlutterEngine(context);
    }

    @Override
    protected String getCachedEngineId() {
        AudioServicePlugin.getFlutterEngine(this);
        return AudioServicePlugin.getFlutterEngineId();
    }

    // The engine is created and managed by AudioServicePlugin,
    // it should not be destroyed with the activity.
    @Override
    public boolean shouldDestroyEngineWithHost() {
        return false;
    }
}
