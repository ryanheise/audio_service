package com.ryanheise.audioservice;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import io.flutter.app.FlutterApplication;
import android.content.Context;
import io.flutter.view.FlutterCallbackInformation;
import io.flutter.view.FlutterNativeView;
import io.flutter.view.FlutterMain;
import io.flutter.view.FlutterRunArguments;
import android.app.Activity;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import java.util.Arrays;
import android.os.RemoteException;
import android.os.SystemClock;
import io.flutter.plugin.common.PluginRegistry.PluginRegistrantCallback;
import android.support.v4.app.NotificationCompat;
import android.support.v4.media.MediaBrowserCompat;
import android.support.v4.media.MediaBrowserServiceCompat;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.MediaDescriptionCompat;
import android.content.ComponentName;
import android.os.Bundle;
import java.util.HashMap;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.media.AudioFormat;
import android.support.v4.media.session.PlaybackStateCompat;

/** AudioservicePlugin */
public class AudioServicePlugin {
	private static final String CHANNEL_AUDIO_SERVICE = "ryanheise.com/audioService";
	private static final String CHANNEL_AUDIO_SERVICE_BACKGROUND = "ryanheise.com/audioServiceBackground";

	private static PluginRegistrantCallback pluginRegistrantCallback;
	private static ClientHandler clientHandler;
	private static BackgroundHandler backgroundHandler;
	private static FlutterNativeView backgroundFlutterView;

	public static void setPluginRegistrantCallback(PluginRegistrantCallback pluginRegistrantCallback) {
		AudioServicePlugin.pluginRegistrantCallback = pluginRegistrantCallback;
	}

	/** Plugin registration. */
	public static void registerWith(Registrar registrar) {
		if (registrar.activity() != null)
			clientHandler = new ClientHandler(registrar);
		else
			backgroundHandler = new BackgroundHandler(registrar);
	}

	private static class ClientHandler implements MethodCallHandler {
		private Registrar registrar;
		private MethodChannel channel;
		private boolean playPending;
		public MediaBrowserCompat mediaBrowser;
		public MediaControllerCompat mediaController;
		public MediaControllerCompat.Callback controllerCallback = new MediaControllerCompat.Callback() {
			@Override
			public void onMetadataChanged(MediaMetadataCompat metadata) {
				invokeMethod("onMediaChanged", metadata.getDescription().getMediaId());
			}

			@Override
			public void onPlaybackStateChanged(PlaybackStateCompat state) {
				invokeMethod("onPlaybackStateChanged", state.getState(), state.getPosition(), state.getPlaybackSpeed(), state.getLastPositionUpdateTime());
			}

			@Override
			public void onQueueChanged(List<MediaSessionCompat.QueueItem> queue) {
				invokeMethod("onQueueChanged", queue2raw(queue));
			}
		};

		private final MediaBrowserCompat.ConnectionCallback connectionCallback = new MediaBrowserCompat.ConnectionCallback() {
			@Override
			public void onConnected() {
				try {
					Activity activity = registrar.activity();
					MediaSessionCompat.Token token = mediaBrowser.getSessionToken();
					mediaController = new MediaControllerCompat(activity, token);
					MediaControllerCompat.setMediaController(activity, mediaController);
					mediaController.registerCallback(controllerCallback);
					PlaybackStateCompat state = mediaController.getPlaybackState();
					controllerCallback.onPlaybackStateChanged(state);
					MediaMetadataCompat metadata = mediaController.getMetadata();
					if (metadata != null)
						controllerCallback.onMetadataChanged(metadata);
					controllerCallback.onQueueChanged(mediaController.getQueue());

					synchronized (this) {
						if (playPending) {
							mediaController.getTransportControls().play();
							playPending = false;
						}
					}
				}
				catch (RemoteException e) {
					throw new RuntimeException(e);
				}
			}

			@Override
			public void onConnectionSuspended() {
			}

			@Override
			public void onConnectionFailed() {
			}
		};

		public ClientHandler(Registrar registrar) {
			this.registrar = registrar;
			channel = new MethodChannel(registrar.messenger(), CHANNEL_AUDIO_SERVICE);
			channel.setMethodCallHandler(this);
		}

		@Override
		public void onMethodCall(MethodCall call, Result result) {
			Context context = registrar.activeContext();
			FlutterApplication application = (FlutterApplication)context.getApplicationContext();
			switch (call.method) {
			case "isRunning":
				result.success(AudioService.isRunning());
				break;
			case "start": {
				if (AudioService.isRunning()) {
					result.success(false);
					break;
				}
				Map<?,?> arguments = (Map<?,?>)call.arguments;
				final long callbackHandle = getLong(arguments.get("callbackHandle"));
				boolean androidNotificationClickStartsActivity = (Boolean)arguments.get("androidNotificationClickStartsActivity");
				boolean resumeOnClick = (Boolean)arguments.get("resumeOnClick");
				String notificationChannelName = (String)arguments.get("notificationChannelName");
				Integer notificationColor = arguments.get("notificationColor") == null ? null : getInt(arguments.get("notificationColor"));
				String androidNotificationIcon = (String)arguments.get("androidNotificationIcon");
				List<Map<?,?>> rawQueue = (List<Map<?,?>>)arguments.get("queue");
				List<MediaSessionCompat.QueueItem> queue = raw2queue(rawQueue);

				final String appBundlePath = FlutterMain.findAppBundlePath(application);
				Activity activity = application.getCurrentActivity();
				AudioService.init(activity, resumeOnClick, notificationChannelName, notificationColor, androidNotificationIcon, androidNotificationClickStartsActivity, queue, new AudioService.ServiceListener() {
					@Override
					public void onAudioFocusGained() {
						backgroundHandler.invokeMethod("onAudioFocusGained");
					}
					@Override
					public void onAudioFocusLost() {
						backgroundHandler.invokeMethod("onAudioFocusLost");
					}
					@Override
					public void onAudioFocusLostTransient() {
						backgroundHandler.invokeMethod("onAudioFocusLostTransient");
					}
					@Override
					public void onAudioFocusLostTransientCanDuck() {
						backgroundHandler.invokeMethod("onAudioFocusLostTransientCanDuck");
					}
					@Override
					public void onAudioBecomingNoisy() {
						backgroundHandler.invokeMethod("onAudioBecomingNoisy");
					}
					@Override
					public void onLoadChildren(final String parentMediaId, final MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>> result) {
						ArrayList<Object> list = new ArrayList<Object>();
						list.add(parentMediaId);
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
								List<Map<?,?>> rawMediaItems = (List<Map<?,?>>)obj;
								List<MediaBrowserCompat.MediaItem> mediaItems = new ArrayList<MediaBrowserCompat.MediaItem>();
								for (Map<?,?> rawMediaItem : rawMediaItems) {
									MediaMetadataCompat mediaMetadata = AudioService.createMediaMetadata(rawMediaItem);
									mediaItems.add(new MediaBrowserCompat.MediaItem(mediaMetadata.getDescription(), (Boolean)rawMediaItem.get("playable") ? MediaBrowserCompat.MediaItem.FLAG_PLAYABLE : MediaBrowserCompat.MediaItem.FLAG_BROWSABLE));
								}
								result.sendResult(mediaItems);
							}
						});
						result.detach();
					}
					@Override
					public void onClick(MediaControl mediaControl) {
						backgroundHandler.invokeMethod("onClick", mediaControl.ordinal());
					}
					@Override
					public void onPause() {
						backgroundHandler.invokeMethod("onPause");
					}
					@Override
					public void onPrepare() {
						backgroundHandler.invokeMethod("onPrepare");
					}
					@Override
					public void onPrepareFromMediaId(String mediaId) {
						backgroundHandler.invokeMethod("onPrepare", mediaId);
					}
					@Override
					public void onPlay() {
						if (backgroundFlutterView == null) {
							FlutterCallbackInformation cb = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle);
							if (cb == null) {
								return;
							}
							backgroundFlutterView = new FlutterNativeView(AudioService.instance, true);
							if (appBundlePath != null) {
								pluginRegistrantCallback.registerWith(backgroundFlutterView.getPluginRegistry());
								FlutterRunArguments args = new FlutterRunArguments();
								args.bundlePath = appBundlePath;
								args.entrypoint = cb.callbackName;
								args.libraryPath = cb.callbackLibraryPath;
								backgroundFlutterView.runFromBundle(args);
							}
						}
						else
							backgroundHandler.invokeMethod("onPlay");
					}
					@Override
					public void onPlayFromMediaId(String mediaId) {
						backgroundHandler.invokeMethod("onPlayFromMediaId", mediaId);
					}
					@Override
					public void onStop() {
						backgroundHandler.invokeMethod("onStop");
					}
					@Override
					public void onAddQueueItem(String mediaId) {
						backgroundHandler.invokeMethod("onAddQueueItem", mediaId);
					}
					@Override
					public void onAddQueueItemAt(String mediaId, int index) {
						backgroundHandler.invokeMethod("onAddQueueItem", mediaId, index);
					}
					@Override
					public void onRemoveQueueItem(String mediaId) {
						backgroundHandler.invokeMethod("onRemoveQueueItem", mediaId);
					}
					@Override
					public void onSkipToQueueItem(long id) {
						backgroundHandler.invokeMethod("onSkipToQueueItem", id);
					}
					@Override
					public void onSkipToNext() {
						backgroundHandler.invokeMethod("onSkipToNext");
					}
					@Override
					public void onSkipToPrevious() {
						backgroundHandler.invokeMethod("onSkipToPrevious");
					}
					@Override
					public void onSeekTo(long pos) {
						backgroundHandler.invokeMethod("onSeekTo", pos);
					}
				});

				synchronized (connectionCallback) {
					if (mediaController != null)
						mediaController.getTransportControls().play();
					else
						playPending = true;
				}

				result.success(true);
				break;
			}
			case "connect":
				if (mediaBrowser == null) {
					mediaBrowser = new MediaBrowserCompat(context,
							new ComponentName(context, AudioService.class),
							connectionCallback,
							null);
					mediaBrowser.connect();
				}

				result.success(true);
				break;
			case "disconnect":
				if (mediaController != null) {
					mediaController.unregisterCallback(controllerCallback);
					mediaController = null;
				}
				mediaBrowser.disconnect();
				mediaBrowser = null;
				result.success(true);
				break;
			case "addQueueItem": {
				Map<?,?> rawMediaItem = (Map<?,?>)call.arguments;
				MediaMetadataCompat mediaMetadata = AudioService.createMediaMetadata(rawMediaItem);
				mediaController.addQueueItem(mediaMetadata.getDescription());
				result.success(true);
				break;
			}
			case "addQueueItemAt": {
				List<?> queueAndIndex = (List<?>)call.arguments;
				Map<?,?> rawMediaItem = (Map<?,?>)queueAndIndex.get(0);
				int index = (Integer)queueAndIndex.get(1);
				MediaMetadataCompat mediaMetadata = AudioService.createMediaMetadata(rawMediaItem);
				mediaController.addQueueItem(mediaMetadata.getDescription(), index);
				result.success(true);
				break;
			}
			//case "adjustVolume"
			case "removeQueueItem": {
				Map<?,?> rawMediaItem = (Map<?,?>)call.arguments;
				MediaMetadataCompat mediaMetadata = AudioService.createMediaMetadata(rawMediaItem);
				mediaController.removeQueueItem(mediaMetadata.getDescription());
				result.success(true);
				break;
			}
			//case "setVolumeTo"
			case "click":
				int buttonIndex = (int)call.arguments;
				backgroundHandler.invokeMethod("onClick", buttonIndex);
				result.success(true);
				break;
			case "prepare":
				mediaController.getTransportControls().prepare();
				result.success(true);
				break;
			case "prepareFromMediaId":
				String mediaId = (String)call.arguments;
				mediaController.getTransportControls().prepareFromMediaId(mediaId, new Bundle());
				result.success(true);
				break;
			//prepareFromSearch
			//prepareFromUri
			case "play":
				mediaController.getTransportControls().play();
				result.success(true);
				break;
			//playFromMediaId
			//playFromSearch
			//playFromUri
			case "skipToQueueItem":
				int id = (Integer)call.arguments;
				mediaController.getTransportControls().skipToQueueItem(id);
				result.success(true);
				break;
			case "pause":
				mediaController.getTransportControls().pause();
				result.success(true);
				break;
			case "stop":
				mediaController.getTransportControls().stop();
				result.success(true);
				break;
			case "seekTo":
				int pos = (Integer)call.arguments;
				mediaController.getTransportControls().seekTo(pos);
				result.success(true);
				break;
			case "skipToNext":
				mediaController.getTransportControls().skipToNext();
				result.success(true);
				break;
			case "skipToPrevious":
				mediaController.getTransportControls().skipToPrevious();
				result.success(true);
				break;
			default:
				backgroundHandler.channel.invokeMethod(call.method, call.arguments);
				result.success(true);
				break;
			}
		}

		public void invokeMethod(String method, Object... args) {
			ArrayList<Object> list = new ArrayList<Object>(Arrays.asList(args));
			channel.invokeMethod(method, list);
		}
	}

	private static class BackgroundHandler implements MethodCallHandler {
		private Registrar registrar;
		public MethodChannel channel;
		private AudioTrack silenceAudioTrack;
		private static final int SILENCE_SAMPLE_RATE = 44100;
		private byte[] silence;

		public BackgroundHandler(Registrar registrar) {
			this.registrar = registrar;
			channel = new MethodChannel(registrar.messenger(), CHANNEL_AUDIO_SERVICE_BACKGROUND);
			channel.setMethodCallHandler(this);
		}

		@Override
		public void onMethodCall(MethodCall call, Result result) {
			Context context = registrar.activeContext();
			FlutterApplication application = (FlutterApplication)context.getApplicationContext();
			switch (call.method) {
			case "setMediaItem":
				Map<?,?> rawMediaItem = (Map<?,?>)call.arguments;
				MediaMetadataCompat mediaMetadata = AudioService.createMediaMetadata(rawMediaItem);
				AudioService.instance.setMetadata(mediaMetadata);
				result.success(true);
				break;
			case "setQueue":
				List<Map<?,?>> rawQueue = (List<Map<?,?>>)call.arguments;
				List<MediaSessionCompat.QueueItem> queue = raw2queue(rawQueue);
				AudioService.instance.setQueue(queue);
				result.success(true);
				break;
			case "setState":
				List<Object> args = (List<Object>)call.arguments;
				List<Map<?,?>> rawControls = (List<Map<?,?>>)args.get(0);
				int playbackState = (Integer)args.get(1);
				long position = getLong(args.get(2));
				float speed = (float)((double)((Double)args.get(3)));
				long updateTime = args.get(4) == null ? SystemClock.elapsedRealtime() : getLong(args.get(4));

				List<NotificationCompat.Action> actions = new ArrayList<NotificationCompat.Action>();
				int actionBits = 0;
				for (Map<?,?> rawControl : rawControls) {
					String resource = (String)rawControl.get("androidIcon");
					int actionCode = 1 << ((Integer)rawControl.get("action"));
					actionBits |= actionCode;
					actions.add(AudioService.instance.action(resource, (String)rawControl.get("label"), actionCode));
				}
				AudioService.instance.setState(actions, actionBits, playbackState, position, speed, updateTime);
				result.success(true);
				break;
			case "stopped":
				AudioService.instance.stop();
				if (silenceAudioTrack != null)
					silenceAudioTrack.release();
				backgroundFlutterView = null;
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
	}

	private static List<Map<?,?>> queue2raw(List<MediaSessionCompat.QueueItem> queue) {
		List<Map<?,?>> rawQueue = new ArrayList<Map<?,?>>();
		for (MediaSessionCompat.QueueItem queueItem : queue) {
			MediaDescriptionCompat description = queueItem.getDescription();
			Map<String,Object> raw = new HashMap<String,Object>();
			raw.put("id", description.getMediaId());
			raw.put("album", description.getSubtitle()); // XXX: Will this give me the album?
			raw.put("title", description.getTitle());
			rawQueue.add(raw);
		}
		return rawQueue;
	}

	private static List<MediaSessionCompat.QueueItem> raw2queue(List<Map<?,?>> rawQueue) {
		List<MediaSessionCompat.QueueItem> queue = new ArrayList<MediaSessionCompat.QueueItem>();
		for (Map<?,?> rawMediaItem : rawQueue) {
			MediaMetadataCompat mediaMetadata = AudioService.createMediaMetadata(rawMediaItem);
			MediaDescriptionCompat description = mediaMetadata.getDescription();
			queue.add(new MediaSessionCompat.QueueItem(description, description.hashCode()));
		}
		return queue;
	}

	private static long getLong(Object o) {
		return (o instanceof Integer) ? (Integer)o : ((Long)o).longValue();
	}

	private static int getInt(Object o) {
		return (o instanceof Integer) ? (Integer)o : (int)((Long)o).longValue();
	}
}
