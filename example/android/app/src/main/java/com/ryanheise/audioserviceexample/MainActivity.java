package com.ryanheise.audioserviceexample;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import android.content.Context;
import io.flutter.embedding.android.FlutterActivity;

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
