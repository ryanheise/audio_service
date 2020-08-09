package com.ryanheise.audioservice;

import io.flutter.embedding.engine.plugins.service.*;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.os.Bundle;
import android.os.RemoteException;
import android.os.SystemClock;

import androidx.core.app.NotificationCompat;

import android.support.v4.media.MediaBrowserCompat;

import androidx.media.MediaBrowserServiceCompat;

import android.support.v4.media.MediaDescriptionCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.RatingCompat;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.app.FlutterApplication;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.NewIntentListener;
import io.flutter.plugin.common.PluginRegistry.PluginRegistrantCallback;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.plugin.common.PluginRegistry.ViewDestroyListener;
import io.flutter.view.FlutterCallbackInformation;
import io.flutter.view.FlutterMain;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.plugin.common.BinaryMessenger;

import android.app.Service;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.dart.DartExecutor.DartCallback;

import android.content.res.AssetManager;

import io.flutter.view.FlutterNativeView;
import io.flutter.view.FlutterRunArguments;

/**
 * AudioservicePlugin
 */
public class AudioServicePlugin implements FlutterPlugin, ActivityAware {
	private static final String CHANNEL_AUDIO_SERVICE = "ryanheise.com/audioService";
	private static final String CHANNEL_AUDIO_SERVICE_BACKGROUND = "ryanheise.com/audioServiceBackground";
	private static final String NOTIFICATION_CLICK_ACTION = "com.ryanheise.audioservice.NOTIFICATION_CLICK";

	private static PluginRegistrantCallback pluginRegistrantCallback;
	private static Set<ClientHandler> clientHandlers = new HashSet<ClientHandler>();
	private static ClientHandler mainClientHandler;
	private static BackgroundHandler backgroundHandler;
	private static FlutterEngine backgroundFlutterEngine;
	private static int nextQueueItemId = 0;
	private static List<String> queueMediaIds = new ArrayList<String>();
	private static Map<String, Integer> queueItemIds = new HashMap<String, Integer>();
	private static volatile Result connectResult;
	private static volatile Result startResult;
	private static volatile Result stopResult;
	private static String subscribedParentMediaId;
	private static long bootTime;

	static {
		bootTime = System.currentTimeMillis() - SystemClock.elapsedRealtime();
	}

	public static void setPluginRegistrantCallback(PluginRegistrantCallback pluginRegistrantCallback) {
		AudioServicePlugin.pluginRegistrantCallback = pluginRegistrantCallback;
	}

	/**
	 * v1 plugin registration.
	 */
	public static void registerWith(Registrar registrar) {
		if (registrar.activity() != null) {
			mainClientHandler = new ClientHandler(registrar.messenger());
			mainClientHandler.setActivity(registrar.activity());
			mainClientHandler.setContext(registrar.activity());
			clientHandlers.add(mainClientHandler);
			registrar.addViewDestroyListener(new ViewDestroyListener() {
				@Override
				public boolean onViewDestroy(FlutterNativeView view) {
					mainClientHandler = null;
					clientHandlers.remove(mainClientHandler);
					return false;
				}
			});
		} else {
			backgroundHandler.init(registrar.messenger());
		}
	}

	private FlutterPluginBinding flutterPluginBinding;
	private ActivityPluginBinding activityPluginBinding;
	private NewIntentListener newIntentListener;
	private ClientHandler clientHandler; // v2 only

	//
	// FlutterPlugin callbacks
	//

	@Override
	public void onAttachedToEngine(FlutterPluginBinding binding) {
		flutterPluginBinding = binding;
		clientHandler = new ClientHandler(flutterPluginBinding.getBinaryMessenger());
		clientHandler.setContext(flutterPluginBinding.getApplicationContext());
		clientHandlers.add(clientHandler);
	}

	@Override
	public void onDetachedFromEngine(FlutterPluginBinding binding) {
		clientHandlers.remove(clientHandler);
		clientHandler.setContext(null);
		flutterPluginBinding = null;
		clientHandler = null;
	}

	//
	// ActivityAware callbacks
	//

	@Override
	public void onAttachedToActivity(ActivityPluginBinding binding) {
		activityPluginBinding = binding;
		clientHandler.setActivity(binding.getActivity());
		clientHandler.setContext(binding.getActivity());
		mainClientHandler = clientHandler;
		registerOnNewIntentListener();
	}

	@Override
	public void onDetachedFromActivityForConfigChanges() {
		activityPluginBinding.removeOnNewIntentListener(newIntentListener);
	}

	@Override
	public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
		activityPluginBinding = binding;
		clientHandler.setActivity(binding.getActivity());
		clientHandler.setContext(binding.getActivity());
		registerOnNewIntentListener();
	}

	@Override
	public void onDetachedFromActivity() {
		activityPluginBinding.removeOnNewIntentListener(newIntentListener);
		newIntentListener = null;
		activityPluginBinding = null;
		clientHandler.setActivity(null);
		clientHandler.setContext(flutterPluginBinding.getApplicationContext());
		if (clientHandler == mainClientHandler) {
			mainClientHandler = null;
		}
	}

	private void registerOnNewIntentListener() {
		activityPluginBinding.addOnNewIntentListener(newIntentListener = new NewIntentListener() {
			@Override
			public boolean onNewIntent(Intent intent) {
				clientHandler.activity.setIntent(intent);
				return true;
			}
		});
	}


	private static void sendConnectResult(boolean result) {
		if (connectResult != null) {
			connectResult.success(result);
			connectResult = null;
		}
	}

	private static void sendStartResult(boolean result) {
		if (startResult != null) {
			startResult.success(result);
			startResult = null;
		}
	}

	private static void sendStopResult(boolean result) {
		if (stopResult != null) {
			stopResult.success(result);
			stopResult = null;
		}
	}

	private static class ClientHandler implements MethodCallHandler {
		private Context context;
		private Activity activity;
		private MethodChannel channel;
		private boolean initEnginePending;
		public long fastForwardInterval;
		public long rewindInterval;
		public Map<String, Object> params;
		public MediaBrowserCompat mediaBrowser;
		public MediaControllerCompat mediaController;
		public MediaControllerCompat.Callback controllerCallback = new MediaControllerCompat.Callback() {
			@Override
			public void onMetadataChanged(MediaMetadataCompat metadata) {
				invokeMethod("onMediaChanged", mediaMetadata2raw(metadata));
			}

			@Override
			public void onPlaybackStateChanged(PlaybackStateCompat state) {
				// On the native side, we represent the update time relative to the boot time.
				// On the flutter side, we represent the update time relative to the epoch.
				long updateTimeSinceBoot = state.getLastPositionUpdateTime();
				long updateTimeSinceEpoch = bootTime + updateTimeSinceBoot;
				invokeMethod("onPlaybackStateChanged", AudioService.getProcessingState().ordinal(), AudioService.isPlaying(), state.getActions(), state.getPosition(), state.getBufferedPosition(), state.getPlaybackSpeed(), updateTimeSinceEpoch, AudioService.getRepeatMode(), AudioService.getShuffleMode());
			}

			@Override
			public void onQueueChanged(List<MediaSessionCompat.QueueItem> queue) {
				invokeMethod("onQueueChanged", queue2raw(queue));
			}
		};

		private final MediaBrowserCompat.SubscriptionCallback subscriptionCallback = new MediaBrowserCompat.SubscriptionCallback() {
			@Override
			public void onChildrenLoaded(String parentId, List<MediaBrowserCompat.MediaItem> children) {
				invokeMethod("onChildrenLoaded", mediaItems2raw(children));
			}
		};

		private final MediaBrowserCompat.ConnectionCallback connectionCallback = new MediaBrowserCompat.ConnectionCallback() {
			@Override
			public void onConnected() {
				try {
					//Activity activity = registrar.activity();
					MediaSessionCompat.Token token = mediaBrowser.getSessionToken();
					mediaController = new MediaControllerCompat(context, token);
					if (activity != null) {
						MediaControllerCompat.setMediaController(activity, mediaController);
					}
					mediaController.registerCallback(controllerCallback);
					PlaybackStateCompat state = mediaController.getPlaybackState();
					controllerCallback.onPlaybackStateChanged(state);
					MediaMetadataCompat metadata = mediaController.getMetadata();
					controllerCallback.onQueueChanged(mediaController.getQueue());
					controllerCallback.onMetadataChanged(metadata);

					synchronized (this) {
						if (initEnginePending) {
							backgroundHandler.initEngine();
							initEnginePending = false;
						}
					}
					sendConnectResult(true);
				} catch (RemoteException e) {
					sendConnectResult(false);
					throw new RuntimeException(e);
				}
			}

			@Override
			public void onConnectionSuspended() {
				// TODO: Handle this
			}

			@Override
			public void onConnectionFailed() {
				sendConnectResult(false);
			}
		};

		public ClientHandler(BinaryMessenger messenger) {
			channel = new MethodChannel(messenger, CHANNEL_AUDIO_SERVICE);
			channel.setMethodCallHandler(this);
		}

		private void setContext(Context context) {
			this.context = context;
		}

		private void setActivity(Activity activity) {
			this.activity = activity;
		}

		// See: https://stackoverflow.com/questions/13135545/android-activity-is-using-old-intent-if-launching-app-from-recent-task
		protected boolean wasLaunchedFromRecents() {
			return (activity.getIntent().getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY;
		}

		@Override
		public void onMethodCall(MethodCall call, final Result result) {
			switch (call.method) {
			case "isRunning":
				result.success(AudioService.isRunning());
				break;
			case "start": {
				startResult = result; // The result will be sent after the background task actually starts.
				if (AudioService.isRunning()) {
					sendStartResult(false);
					break;
				}
				if (activity == null) {
					System.out.println("AudioService can only be started from an activity");
					sendStartResult(false);
					break;
				}
				Map<?, ?> arguments = (Map<?, ?>)call.arguments;
				final long callbackHandle = getLong(arguments.get("callbackHandle"));
				params = (Map<String, Object>)arguments.get("params");
				boolean androidNotificationClickStartsActivity = (Boolean)arguments.get("androidNotificationClickStartsActivity");
				boolean androidNotificationOngoing = (Boolean)arguments.get("androidNotificationOngoing");
				boolean androidResumeOnClick = (Boolean)arguments.get("androidResumeOnClick");
				String androidNotificationChannelName = (String)arguments.get("androidNotificationChannelName");
				String androidNotificationChannelDescription = (String)arguments.get("androidNotificationChannelDescription");
				Integer androidNotificationColor = arguments.get("androidNotificationColor") == null ? null : getInt(arguments.get("androidNotificationColor"));
				String androidNotificationIcon = (String)arguments.get("androidNotificationIcon");
				final boolean androidEnableQueue = (Boolean)arguments.get("androidEnableQueue");
				final boolean androidStopForegroundOnPause = (Boolean)arguments.get("androidStopForegroundOnPause");
				final Map<String, Double> artDownscaleSizeMap = (Map)arguments.get("androidArtDownscaleSize");
				final Size artDownscaleSize = artDownscaleSizeMap == null ? null
						: new Size((int)Math.round(artDownscaleSizeMap.get("width")), (int)Math.round(artDownscaleSizeMap.get("height")));
				fastForwardInterval = getLong(arguments.get("fastForwardInterval"));
				rewindInterval = getLong(arguments.get("rewindInterval"));

				final String appBundlePath = FlutterMain.findAppBundlePath(context.getApplicationContext());
				backgroundHandler = new BackgroundHandler(callbackHandle, appBundlePath, androidEnableQueue);
				AudioService.init(activity, androidResumeOnClick, androidNotificationChannelName, androidNotificationChannelDescription, NOTIFICATION_CLICK_ACTION, androidNotificationColor, androidNotificationIcon, androidNotificationClickStartsActivity, androidNotificationOngoing, androidStopForegroundOnPause, artDownscaleSize, backgroundHandler);

				synchronized (connectionCallback) {
					if (mediaController != null)
						backgroundHandler.initEngine();
					else
						initEnginePending = true;
				}

				break;
			}
			case "connect":
				if (activity != null) {
					if (wasLaunchedFromRecents()) {
						// We do this to avoid using the old intent.
						activity.setIntent(new Intent(Intent.ACTION_MAIN));
					}
					if (activity.getIntent().getAction() != null)
						invokeMethod("notificationClicked", activity.getIntent().getAction().equals(NOTIFICATION_CLICK_ACTION));
				}
				if (mediaBrowser == null) {
					connectResult = result;
					mediaBrowser = new MediaBrowserCompat(context,
							new ComponentName(context, AudioService.class),
							connectionCallback,
							null);
					mediaBrowser.connect();
				} else {
					result.success(true);
				}
				break;
			case "disconnect":
				// Since the activity enters paused state, we set the intent with ACTION_MAIN.
				activity.setIntent(new Intent(Intent.ACTION_MAIN));

				if (mediaController != null) {
					mediaController.unregisterCallback(controllerCallback);
					mediaController = null;
				}
				if (subscribedParentMediaId != null) {
					mediaBrowser.unsubscribe(subscribedParentMediaId);
					subscribedParentMediaId = null;
				}
				if (mediaBrowser != null) {
					mediaBrowser.disconnect();
					mediaBrowser = null;
				}
				result.success(true);
				break;
			case "setBrowseMediaParent":
				String parentMediaId = (String)call.arguments;
				// If the ID has changed, unsubscribe from the old one
				if (subscribedParentMediaId != null && !subscribedParentMediaId.equals(parentMediaId)) {
					mediaBrowser.unsubscribe(subscribedParentMediaId);
					subscribedParentMediaId = null;
				}
				// Subscribe to the new one.
				// Don't subscribe if we're still holding onto the old one
				// Don't subscribe if the new ID is null.
				if (subscribedParentMediaId == null && parentMediaId != null) {
					subscribedParentMediaId = parentMediaId;
					mediaBrowser.subscribe(parentMediaId, subscriptionCallback);
				}
				// If the new ID is null, send clients an empty list
				if (subscribedParentMediaId == null) {
					subscriptionCallback.onChildrenLoaded(subscribedParentMediaId, new ArrayList<MediaBrowserCompat.MediaItem>());
				}
				result.success(true);
				break;
			case "addQueueItem": {
				Map<?, ?> rawMediaItem = (Map<?, ?>)call.arguments;
				// Cache item
				createMediaMetadata(rawMediaItem);
				// Pass through
				backgroundHandler.invokeMethod(result, "onAddQueueItem", call.arguments);
				break;
			}
			case "addQueueItemAt": {
				List<?> queueAndIndex = (List<?>)call.arguments;
				Map<?, ?> rawMediaItem = (Map<?, ?>)queueAndIndex.get(0);
				int index = (Integer)queueAndIndex.get(1);
				// Cache item
				createMediaMetadata(rawMediaItem);
				// Pass through
				backgroundHandler.invokeMethod(result, "onAddQueueItemAt", rawMediaItem, index);
				break;
			}
			case "removeQueueItem": {
				Map<?, ?> rawMediaItem = (Map<?, ?>)call.arguments;
				// Cache item
				createMediaMetadata(rawMediaItem);
				// Pass through
				backgroundHandler.invokeMethod(result, "onRemoveQueueItem", call.arguments);
				break;
			}
			case "updateQueue": {
				backgroundHandler.invokeMethod(result, "onUpdateQueue", call.arguments);
				break;
			}
			case "updateMediaItem": {
				backgroundHandler.invokeMethod(result, "onUpdateMediaItem", call.arguments);
				break;
			}
			//case "setVolumeTo"
			//case "adjustVolume"
			case "click":
				int buttonIndex = (int)call.arguments;
				if (backgroundHandler != null)
					backgroundHandler.invokeMethod(result, "onClick", buttonIndex);
				else
					result.success(true);
				break;
			case "prepare":
				backgroundHandler.invokeMethod(result, "onPrepare");
				break;
			case "prepareFromMediaId": {
				String mediaId = (String)call.arguments;
				backgroundHandler.invokeMethod(result, "onPrepareFromMediaId", mediaId);
				break;
			}
			//prepareFromSearch
			//prepareFromUri
			case "play":
				backgroundHandler.invokeMethod(result, "onPlay");
				break;
			case "playFromMediaId": {
				String mediaId = (String)call.arguments;
				backgroundHandler.invokeMethod(result, "onPlayFromMediaId", mediaId);
				break;
			}
			case "playMediaItem": {
				Map<?, ?> rawMediaItem = (Map<?, ?>)call.arguments;
				// Cache item
				createMediaMetadata(rawMediaItem);
				// Pass through
				backgroundHandler.invokeMethod(result, "onPlayMediaItem", call.arguments);
				break;
			}
			//playFromSearch
			//playFromUri
			case "skipToQueueItem": {
				String mediaId = (String)call.arguments;
				backgroundHandler.invokeMethod(result, "onSkipToQueueItem", mediaId);
				break;
			}
			case "pause":
				backgroundHandler.invokeMethod(result, "onPause");
				break;
			case "stop":
				stopResult = result;
				backgroundHandler.invokeMethod("onStop");
				break;
			case "seekTo":
				int pos = (Integer)call.arguments;
				backgroundHandler.invokeMethod(result, "onSeekTo", pos);
				break;
			case "skipToNext":
				backgroundHandler.invokeMethod(result, "onSkipToNext");
				break;
			case "skipToPrevious":
				backgroundHandler.invokeMethod(result, "onSkipToPrevious");
				break;
			case "fastForward":
				backgroundHandler.invokeMethod(result, "onFastForward");
				break;
			case "rewind":
				backgroundHandler.invokeMethod(result, "onRewind");
				break;
			case "setRepeatMode":
				int repeatMode = (Integer)call.arguments;
				backgroundHandler.invokeMethod(result, "onSetRepeatMode", repeatMode);
				break;
			case "setShuffleMode":
				int shuffleMode = (Integer)call.arguments;
				backgroundHandler.invokeMethod(result, "onSetShuffleMode", shuffleMode);
				break;
			case "setRating":
				HashMap<String, Object> arguments = (HashMap<String, Object>)call.arguments;
				backgroundHandler.invokeMethod(result, "onSetRating", arguments.get("rating"), arguments.get("extras"));
				break;
			case "setSpeed":
				float speed = (float)((double)((Double)call.arguments));
				backgroundHandler.invokeMethod(result, "onSetSpeed", speed);
				break;
			case "seekForward": {
				boolean begin = (Boolean)call.arguments;
				backgroundHandler.invokeMethod(result, "onSeekForward", begin);
				break;
			}
			case "seekBackward": {
				boolean begin = (Boolean)call.arguments;
				backgroundHandler.invokeMethod(result, "onSeekBackward", begin);
				break;
			}
			default:
				if (backgroundHandler != null) {
					backgroundHandler.channel.invokeMethod(call.method, call.arguments, result);
				}
				break;
			}
		}

		public void invokeMethod(String method, Object... args) {
			ArrayList<Object> list = new ArrayList<Object>(Arrays.asList(args));
			channel.invokeMethod(method, list);
		}
	}

	private static class BackgroundHandler implements MethodCallHandler, AudioService.ServiceListener {
		private long callbackHandle;
		private String appBundlePath;
		private boolean enableQueue;
		public MethodChannel channel;
		private AudioTrack silenceAudioTrack;
		private static final int SILENCE_SAMPLE_RATE = 44100;
		private byte[] silence;
		private AudioInterruption interruption = AudioInterruption.temporaryPause;

		public BackgroundHandler(long callbackHandle, String appBundlePath, boolean enableQueue) {
			this.callbackHandle = callbackHandle;
			this.appBundlePath = appBundlePath;
			this.enableQueue = enableQueue;
		}

		public void init(BinaryMessenger messenger) {
			if (channel != null) return;
			channel = new MethodChannel(messenger, CHANNEL_AUDIO_SERVICE_BACKGROUND);
			channel.setMethodCallHandler(this);
		}

		public void initEngine() {
			Context context = AudioService.instance;
			backgroundFlutterEngine = new FlutterEngine(context.getApplicationContext());
			FlutterCallbackInformation cb = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle);
			if (cb == null || appBundlePath == null) {
				sendStartResult(false);
				return;
			}
			if (enableQueue)
				AudioService.instance.enableQueue();
			// Register plugins in background isolate if app is using v1 embedding
			if (pluginRegistrantCallback != null) {
				pluginRegistrantCallback.registerWith(new ShimPluginRegistry(backgroundFlutterEngine));
			}

			DartExecutor executor = backgroundFlutterEngine.getDartExecutor();
			init(executor);
			DartCallback dartCallback = new DartCallback(context.getAssets(), appBundlePath, cb);

			executor.executeDartCallback(dartCallback);
		}

		@Override
		public void onAudioFocusGained() {
			invokeMethod("onAudioFocusGained", interruption.ordinal());
			interruption = AudioInterruption.temporaryPause;
		}

		@Override
		public void onAudioFocusLost() {
			interruption = AudioInterruption.pause;
			invokeMethod("onAudioFocusLost", interruption.ordinal());
		}

		@Override
		public void onAudioFocusLostTransient() {
			interruption = AudioInterruption.temporaryPause;
			invokeMethod("onAudioFocusLost", interruption.ordinal());
		}

		@Override
		public void onAudioFocusLostTransientCanDuck() {
			interruption = AudioInterruption.temporaryDuck;
			invokeMethod("onAudioFocusLost", interruption.ordinal());
		}

		@Override
		public void onAudioBecomingNoisy() {
			invokeMethod("onAudioBecomingNoisy");
		}

		@Override
		public void onLoadChildren(final String parentMediaId, final MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>> result) {
			ArrayList<Object> list = new ArrayList<Object>();
			list.add(parentMediaId);
			if (backgroundHandler != null) {
				backgroundHandler.channel.invokeMethod("onLoadChildren", list, new MethodChannel.Result() {
					@Override
					public void error(String errorCode, String errorMessage, Object errorDetails) {
						result.sendError(new Bundle());
					}

					@Override
					public void notImplemented() {
						result.sendError(new Bundle());
					}

					@Override
					public void success(Object obj) {
						List<Map<?, ?>> rawMediaItems = (List<Map<?, ?>>)obj;
						List<MediaBrowserCompat.MediaItem> mediaItems = new ArrayList<MediaBrowserCompat.MediaItem>();
						for (Map<?, ?> rawMediaItem : rawMediaItems) {
							MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
							mediaItems.add(new MediaBrowserCompat.MediaItem(mediaMetadata.getDescription(), (Boolean)rawMediaItem.get("playable") ? MediaBrowserCompat.MediaItem.FLAG_PLAYABLE : MediaBrowserCompat.MediaItem.FLAG_BROWSABLE));
						}
						result.sendResult(mediaItems);
					}
				});
			}
			result.detach();
		}

		@Override
		public void onClick(MediaControl mediaControl) {
			invokeMethod("onClick", mediaControl.ordinal());
		}

		@Override
		public void onPause() {
			invokeMethod("onPause");
		}

		@Override
		public void onPrepare() {
			invokeMethod("onPrepare");
		}

		@Override
		public void onPrepareFromMediaId(String mediaId) {
			invokeMethod("onPrepareFromMediaId", mediaId);
		}

		@Override
		public void onPlay() {
			if (backgroundFlutterEngine == null) {
				initEngine();
			} else
				invokeMethod("onPlay");
		}

		@Override
		public void onPlayFromMediaId(String mediaId) {
			invokeMethod("onPlayFromMediaId", mediaId);
		}

		@Override
		public void onPlayMediaItem(MediaMetadataCompat metadata) {
			invokeMethod("onPlayMediaItem", mediaMetadata2raw(metadata));
		}

		@Override
		public void onStop() {
			invokeMethod("onStop");
		}

		@Override
		public void onDestroy() {
			clear();
		}

		@Override
		public void onAddQueueItem(MediaMetadataCompat metadata) {
			invokeMethod("onAddQueueItem", mediaMetadata2raw(metadata));
		}

		@Override
		public void onAddQueueItemAt(MediaMetadataCompat metadata, int index) {
			invokeMethod("onAddQueueItemAt", mediaMetadata2raw(metadata), index);
		}

		@Override
		public void onRemoveQueueItem(MediaMetadataCompat metadata) {
			invokeMethod("onRemoveQueueItem", mediaMetadata2raw(metadata));
		}

		@Override
		public void onSkipToQueueItem(long queueItemId) {
			String mediaId = queueMediaIds.get((int)queueItemId);
			invokeMethod("onSkipToQueueItem", mediaId);
		}

		@Override
		public void onSkipToNext() {
			invokeMethod("onSkipToNext");
		}

		@Override
		public void onSkipToPrevious() {
			invokeMethod("onSkipToPrevious");
		}

		@Override
		public void onFastForward() {
			invokeMethod("onFastForward");
		}

		@Override
		public void onRewind() {
			invokeMethod("onRewind");
		}

		@Override
		public void onSeekTo(long pos) {
			invokeMethod("onSeekTo", pos);
		}

		@Override
		public void onSetRepeatMode(int repeatMode) {
			invokeMethod("onSetRepeatMode", repeatMode);
		}

		@Override
		public void onSetShuffleMode(int shuffleMode) {
			invokeMethod("onSetShuffleMode", shuffleMode);
		}

		@Override
		public void onSetRating(RatingCompat rating) {
			invokeMethod("onSetRating", rating2raw(rating), null);
		}

		@Override
		public void onSetRating(RatingCompat rating, Bundle extras) {
			invokeMethod("onSetRating", rating2raw(rating), extras.getSerializable("extrasMap"));
		}

		@Override
		public void onTaskRemoved() {
			invokeMethod("onTaskRemoved");
		}

		@Override
		public void onClose() {
			invokeMethod("onClose");
		}

		@Override
		public void onMethodCall(MethodCall call, Result result) {
			Context context = AudioService.instance;
			switch (call.method) {
			case "ready":
				Map<String, Object> startParams = new HashMap<String, Object>();
				startParams.put("fastForwardInterval", mainClientHandler.fastForwardInterval);
				startParams.put("rewindInterval", mainClientHandler.rewindInterval);
				startParams.put("params", mainClientHandler.params);
				result.success(startParams);
				break;
			case "started":
				sendStartResult(true);
				// If the client subscribed to browse children before we
				// started, process the pending request.
				// TODO: It should be possible to browse children before
				// starting.
				if (subscribedParentMediaId != null)
					AudioService.instance.notifyChildrenChanged(subscribedParentMediaId);
				result.success(true);
				break;
			case "setMediaItem":
				Map<?, ?> rawMediaItem = (Map<?, ?>)call.arguments;
				MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
				AudioService.instance.setMetadata(mediaMetadata);
				result.success(true);
				break;
			case "setQueue":
				List<Map<?, ?>> rawQueue = (List<Map<?, ?>>)call.arguments;
				List<MediaSessionCompat.QueueItem> queue = raw2queue(rawQueue);
				AudioService.instance.setQueue(queue);
				result.success(true);
				break;
			case "setState":
				List<Object> args = (List<Object>)call.arguments;
				List<Map<?, ?>> rawControls = (List<Map<?, ?>>)args.get(0);
				List<Integer> rawSystemActions = (List<Integer>)args.get(1);
				AudioProcessingState processingState = AudioProcessingState.values()[(Integer)args.get(2)];
				boolean playing = (Boolean)args.get(3);
				long position = getLong(args.get(4));
				long bufferedPosition = getLong(args.get(5));
				float speed = (float)((double)((Double)args.get(6)));
				long updateTimeSinceEpoch = args.get(7) == null ? System.currentTimeMillis() : getLong(args.get(7));
				List<Object> compactActionIndexList = (List<Object>)args.get(8);
				int repeatMode = (Integer)args.get(9);
				int shuffleMode = (Integer)args.get(10);

				// On the flutter side, we represent the update time relative to the epoch.
				// On the native side, we must represent the update time relative to the boot time.
				long updateTimeSinceBoot = updateTimeSinceEpoch - bootTime;

				List<NotificationCompat.Action> actions = new ArrayList<NotificationCompat.Action>();
				int actionBits = 0;
				for (Map<?, ?> rawControl : rawControls) {
					String resource = (String)rawControl.get("androidIcon");
					int actionCode = 1 << ((Integer)rawControl.get("action"));
					actionBits |= actionCode;
					actions.add(AudioService.instance.action(resource, (String)rawControl.get("label"), actionCode));
				}
				for (Integer rawSystemAction : rawSystemActions) {
					int actionCode = 1 << rawSystemAction;
					actionBits |= actionCode;
				}
				int[] compactActionIndices = null;
				if (compactActionIndexList != null) {
					compactActionIndices = new int[Math.min(AudioService.MAX_COMPACT_ACTIONS, compactActionIndexList.size())];
					for (int i = 0; i < compactActionIndices.length; i++)
						compactActionIndices[i] = (Integer)compactActionIndexList.get(i);
				}
				AudioService.instance.setState(actions, actionBits, compactActionIndices, processingState, playing, position, bufferedPosition, speed, updateTimeSinceBoot, repeatMode, shuffleMode);
				result.success(true);
				break;
			case "stopped":
				clear();
				result.success(true);
				sendStopResult(true);
				break;
			case "notifyChildrenChanged":
				String parentMediaId = (String)call.arguments;
				AudioService.instance.notifyChildrenChanged(parentMediaId);
				result.success(true);
				break;
			case "androidForceEnableMediaButtons":
				// Just play a short amount of silence. This convinces Android
				// that we are playing "real" audio so that it will route
				// media buttons to us.
				// See: https://issuetracker.google.com/issues/65344811
				if (silenceAudioTrack == null) {
					silence = new byte[2048];
					silenceAudioTrack = new AudioTrack(
							AudioManager.STREAM_MUSIC,
							SILENCE_SAMPLE_RATE,
							AudioFormat.CHANNEL_CONFIGURATION_MONO,
							AudioFormat.ENCODING_PCM_8BIT,
							silence.length,
							AudioTrack.MODE_STATIC);
					silenceAudioTrack.write(silence, 0, silence.length);
				}
				silenceAudioTrack.reloadStaticData();
				silenceAudioTrack.play();
				result.success(true);
				break;
			}
		}

		public void invokeMethod(String method, Object... args) {
			ArrayList<Object> list = new ArrayList<Object>(Arrays.asList(args));
			channel.invokeMethod(method, list);
		}

		public void invokeMethod(final Result result, String method, Object... args) {
			ArrayList<Object> list = new ArrayList<Object>(Arrays.asList(args));
			channel.invokeMethod(method, list, result);
		}

		private void clear() {
			AudioService.instance.stop();
			if (silenceAudioTrack != null)
				silenceAudioTrack.release();
			if (mainClientHandler != null && mainClientHandler.activity != null) {
				mainClientHandler.activity.setIntent(new Intent(Intent.ACTION_MAIN));
			}
			AudioService.instance.setState(new ArrayList<NotificationCompat.Action>(), 0, new int[]{}, AudioProcessingState.none, false, 0, 0, 0.0f, 0, 0, 0);
			for (ClientHandler eachClientHandler : clientHandlers) {
				eachClientHandler.invokeMethod("onStopped");
			}
			backgroundFlutterEngine.destroy();
			backgroundFlutterEngine = null;
			backgroundHandler = null;
		}
	}

	private static List<Map<?, ?>> mediaItems2raw(List<MediaBrowserCompat.MediaItem> mediaItems) {
		List<Map<?, ?>> rawMediaItems = new ArrayList<Map<?, ?>>();
		for (MediaBrowserCompat.MediaItem mediaItem : mediaItems) {
			MediaDescriptionCompat description = mediaItem.getDescription();
			MediaMetadataCompat mediaMetadata = AudioService.getMediaMetadata(description.getMediaId());
			rawMediaItems.add(mediaMetadata2raw(mediaMetadata));
		}
		return rawMediaItems;
	}

	private static List<Map<?, ?>> queue2raw(List<MediaSessionCompat.QueueItem> queue) {
		if (queue == null) return null;
		List<Map<?, ?>> rawQueue = new ArrayList<Map<?, ?>>();
		for (MediaSessionCompat.QueueItem queueItem : queue) {
			MediaDescriptionCompat description = queueItem.getDescription();
			MediaMetadataCompat mediaMetadata = AudioService.getMediaMetadata(description.getMediaId());
			rawQueue.add(mediaMetadata2raw(mediaMetadata));
		}
		return rawQueue;
	}

	private static RatingCompat raw2rating(Map<String, Object> raw) {
		if (raw == null) return null;
		Integer type = (Integer)raw.get("type");
		Object value = raw.get("value");
		if (value != null) {
			switch (type) {
			case RatingCompat.RATING_3_STARS:
			case RatingCompat.RATING_4_STARS:
			case RatingCompat.RATING_5_STARS:
				return RatingCompat.newStarRating(type, (int)value);
			case RatingCompat.RATING_HEART:
				return RatingCompat.newHeartRating((boolean)value);
			case RatingCompat.RATING_PERCENTAGE:
				return RatingCompat.newPercentageRating((float)value);
			case RatingCompat.RATING_THUMB_UP_DOWN:
				return RatingCompat.newThumbRating((boolean)value);
			default:
				return RatingCompat.newUnratedRating(type);
			}
		} else {
			return RatingCompat.newUnratedRating(type);
		}
	}

	private static HashMap<String, Object> rating2raw(RatingCompat rating) {
		HashMap<String, Object> raw = new HashMap<String, Object>();
		raw.put("type", rating.getRatingStyle());
		if (rating.isRated()) {
			switch (rating.getRatingStyle()) {
			case RatingCompat.RATING_3_STARS:
			case RatingCompat.RATING_4_STARS:
			case RatingCompat.RATING_5_STARS:
				raw.put("value", rating.getStarRating());
				break;
			case RatingCompat.RATING_HEART:
				raw.put("value", rating.hasHeart());
				break;
			case RatingCompat.RATING_PERCENTAGE:
				raw.put("value", rating.getPercentRating());
				break;
			case RatingCompat.RATING_THUMB_UP_DOWN:
				raw.put("value", rating.isThumbUp());
				break;
			case RatingCompat.RATING_NONE:
				raw.put("value", null);
			}
		} else {
			raw.put("value", null);
		}
		return raw;
	}

	private static String metadataToString(MediaMetadataCompat mediaMetadata, String key) {
		CharSequence value = mediaMetadata.getText(key);
		if (value != null && value.length() > 0)
			return value.toString();
		return null;
	}

	private static Map<?, ?> mediaMetadata2raw(MediaMetadataCompat mediaMetadata) {
		if (mediaMetadata == null) return null;
		MediaDescriptionCompat description = mediaMetadata.getDescription();
		Map<String, Object> raw = new HashMap<String, Object>();
		raw.put("id", description.getMediaId());
		raw.put("album", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_ALBUM));
		raw.put("title", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_TITLE));
		if (description.getIconUri() != null)
			raw.put("artUri", description.getIconUri().toString());
		raw.put("artist", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_ARTIST));
		raw.put("genre", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_GENRE));
		if (mediaMetadata.containsKey(MediaMetadataCompat.METADATA_KEY_DURATION))
			raw.put("duration", mediaMetadata.getLong(MediaMetadataCompat.METADATA_KEY_DURATION));
		raw.put("displayTitle", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE));
		raw.put("displaySubtitle", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE));
		raw.put("displayDescription", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION));
		if (mediaMetadata.containsKey(MediaMetadataCompat.METADATA_KEY_RATING)) {
			raw.put("rating", rating2raw(mediaMetadata.getRating(MediaMetadataCompat.METADATA_KEY_RATING)));
		}
		Map<String, Object> extras = new HashMap<>();
		for (String key : mediaMetadata.keySet()) {
			if (key.startsWith("extra_long_")) {
				String rawKey = key.substring("extra_long_".length());
				extras.put(rawKey, mediaMetadata.getLong(key));
			} else if (key.startsWith("extra_string_")) {
				String rawKey = key.substring("extra_string_".length());
				extras.put(rawKey, mediaMetadata.getString(key));
			}
		}
		if (extras.size() > 0) {
			raw.put("extras", extras);
		}
		return raw;
	}

	private static MediaMetadataCompat createMediaMetadata(Map<?, ?> rawMediaItem) {
		return AudioService.createMediaMetadata(
				(String)rawMediaItem.get("id"),
				(String)rawMediaItem.get("album"),
				(String)rawMediaItem.get("title"),
				(String)rawMediaItem.get("artist"),
				(String)rawMediaItem.get("genre"),
				getLong(rawMediaItem.get("duration")),
				(String)rawMediaItem.get("artUri"),
				(String)rawMediaItem.get("displayTitle"),
				(String)rawMediaItem.get("displaySubtitle"),
				(String)rawMediaItem.get("displayDescription"),
				raw2rating((Map<String, Object>)rawMediaItem.get("rating")),
				(Map<?, ?>)rawMediaItem.get("extras")
		);
	}

	private static synchronized int generateNextQueueItemId(String mediaId) {
		queueMediaIds.add(mediaId);
		queueItemIds.put(mediaId, nextQueueItemId);
		return nextQueueItemId++;
	}

	private static List<MediaSessionCompat.QueueItem> raw2queue(List<Map<?, ?>> rawQueue) {
		List<MediaSessionCompat.QueueItem> queue = new ArrayList<MediaSessionCompat.QueueItem>();
		for (Map<?, ?> rawMediaItem : rawQueue) {
			MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
			MediaDescriptionCompat description = mediaMetadata.getDescription();
			queue.add(new MediaSessionCompat.QueueItem(description, generateNextQueueItemId(description.getMediaId())));
		}
		return queue;
	}

	public static Long getLong(Object o) {
		return (o == null || o instanceof Long) ? (Long)o : new Long(((Integer)o).intValue());
	}

	public static Integer getInt(Object o) {
		return (o == null || o instanceof Integer) ? (Integer)o : new Integer((int)((Long)o).longValue());
	}
}
