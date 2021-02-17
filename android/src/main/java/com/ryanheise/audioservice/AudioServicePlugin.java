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
import io.flutter.view.FlutterCallbackInformation;
import io.flutter.view.FlutterMain;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.plugin.common.BinaryMessenger;

import android.app.Service;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.dart.DartExecutor.DartCallback;
import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry;
import io.flutter.view.FlutterNativeView;
import io.flutter.view.FlutterRunArguments;

import android.net.Uri;
import android.content.res.AssetManager;

/**
 * AudioservicePlugin
 */
public class AudioServicePlugin implements FlutterPlugin, ActivityAware {
    private static String flutterEngineId = "audio_service_engine";
    /** Must be called BEFORE any FlutterEngine is created. e.g. in Application class. */
    public static void setFlutterEngineId(String id) {
        flutterEngineId = id;
    }
    public static String getFlutterEngineId() {
        return flutterEngineId;
    }
    public static synchronized FlutterEngine getFlutterEngine(Context context) {
        FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(flutterEngineId);
        if (flutterEngine == null) {
            System.out.println("### Creating new FlutterEngine");
            // XXX: The constructor triggers onAttachedToEngine so this variable doesn't help us.
            // Maybe need a boolean flag to tell us we're currently loading the main flutter engine.
            flutterEngine = new FlutterEngine(context.getApplicationContext());
            flutterEngine.getDartExecutor().executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault());
            FlutterEngineCache.getInstance().put(flutterEngineId, flutterEngine);
        } else {
            System.out.println("### Reusing existing FlutterEngine");
        }
        return flutterEngine;
    }

    public static void disposeFlutterEngine() {
        FlutterEngine flutterEngine = FlutterEngineCache.getInstance().get(flutterEngineId);
        if (flutterEngine != null) {
            System.out.println("### FlutterEngine.destroy()");
            flutterEngine.destroy();
            FlutterEngineCache.getInstance().remove(flutterEngineId);
        }
    }

    private static final String CHANNEL_AUDIO_SERVICE = "ryanheise.com/audioService";
    private static final String CHANNEL_AUDIO_SERVICE_BACKGROUND = "ryanheise.com/audioServiceBackground";

    private static Context applicationContext;
    private static Set<ClientHandler> clientHandlers = new HashSet<ClientHandler>();
    private static ClientHandler mainClientHandler;
    private static BackgroundHandler backgroundHandler;
    private static int nextQueueItemId = 0;
    private static List<String> queueMediaIds = new ArrayList<String>();
    private static Map<String, Integer> queueItemIds = new HashMap<String, Integer>();
    private static volatile Result startResult;
    private static volatile Result stopResult;
    private static long bootTime;
    private static Result configureResult;

    static {
        bootTime = System.currentTimeMillis() - SystemClock.elapsedRealtime();
    }

    static BackgroundHandler backgroundHandler() throws Exception {
        if (backgroundHandler == null) throw new Exception("Background audio task not running");
        return backgroundHandler;
    }

    private static MediaBrowserCompat mediaBrowser;
    private static MediaControllerCompat mediaController;
    private static MediaControllerCompat.Callback controllerCallback = new MediaControllerCompat.Callback() {
        @Override
        public void onMetadataChanged(MediaMetadataCompat metadata) {
            invokeClientMethod("onMediaChanged", mediaMetadata2raw(metadata));
        }

        @Override
        public void onPlaybackStateChanged(PlaybackStateCompat state) {
            // On the native side, we represent the update time relative to the boot time.
            // On the flutter side, we represent the update time relative to the epoch.
            long updateTimeSinceBoot = state.getLastPositionUpdateTime();
            long updateTimeSinceEpoch = bootTime + updateTimeSinceBoot;
            invokeClientMethod("onPlaybackStateChanged", AudioService.instance.getProcessingState().ordinal(), AudioService.instance.isPlaying(), state.getActions(), state.getPosition(), state.getBufferedPosition(), state.getPlaybackSpeed(), updateTimeSinceEpoch, AudioService.instance.getRepeatMode(), AudioService.instance.getShuffleMode());
        }

        @Override
        public void onQueueChanged(List<MediaSessionCompat.QueueItem> queue) {
            invokeClientMethod("onQueueChanged", queue2raw(queue));
        }
    };
    private static final MediaBrowserCompat.ConnectionCallback connectionCallback = new MediaBrowserCompat.ConnectionCallback() {
        @Override
        public void onConnected() {
            System.out.println("### onConnected");
            try {
                MediaSessionCompat.Token token = mediaBrowser.getSessionToken();
                mediaController = new MediaControllerCompat(applicationContext, token);
                Activity activity = mainClientHandler != null ? mainClientHandler.activity : null;
                if (activity != null) {
                    MediaControllerCompat.setMediaController(activity, mediaController);
                }
                mediaController.registerCallback(controllerCallback);
                System.out.println("### registered mediaController callback");
                PlaybackStateCompat state = mediaController.getPlaybackState();
                controllerCallback.onPlaybackStateChanged(state);
                MediaMetadataCompat metadata = mediaController.getMetadata();
                controllerCallback.onQueueChanged(mediaController.getQueue());
                controllerCallback.onMetadataChanged(metadata);
                if (configureResult != null) {
                    configureResult.success(null);
                    configureResult = null;
                }
            } catch (Exception e) {
                e.printStackTrace();
                throw new RuntimeException(e);
            }
            System.out.println("### onConnected returned");
        }

        @Override
        public void onConnectionSuspended() {
            // TODO: Handle this
            System.out.println("### UNHANDLED: onConnectionSuspended");
        }

        @Override
        public void onConnectionFailed() {
            // TODO: Handle this
            System.out.println("### UNHANDLED: onConnectionFailed");
        }
    };
    private static void invokeClientMethod(String method, Object... args) {
        ArrayList<Object> list = new ArrayList<Object>(Arrays.asList(args));
        for (ClientHandler clientHandler : clientHandlers) {
            clientHandler.channel.invokeMethod(method, list);
        }
    }

    //
    // INSTANCE FIELDS AND METHODS
    //

    private FlutterPluginBinding flutterPluginBinding;
    private ActivityPluginBinding activityPluginBinding;
    private NewIntentListener newIntentListener;
    private ClientHandler clientHandler;

    //
    // FlutterPlugin callbacks
    //

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        System.out.println("### onAttachedToEngine");
        flutterPluginBinding = binding;
        clientHandler = new ClientHandler(flutterPluginBinding.getBinaryMessenger());
        clientHandler.setContext(flutterPluginBinding.getApplicationContext());
        clientHandlers.add(clientHandler);
        System.out.println("### " + clientHandlers.size() + " client handlers");
        if (applicationContext == null) {
            applicationContext = flutterPluginBinding.getApplicationContext();
        }
        if (backgroundHandler == null) {
            // We don't know yet whether this is the right engine that hosts the BackgroundAudioTask,
            // but we need to register a MethodCallHandler now just in case. If we're wrong, we
            // detect and correct this when receiving the "configure" message.
            backgroundHandler = new BackgroundHandler(flutterPluginBinding.getBinaryMessenger(), true /*androidEnableQueue*/);
            AudioService.init(backgroundHandler);
        }
        if (mediaBrowser == null) {
            connect();
        }
        System.out.println("### onAttachedToEngine completed");
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        System.out.println("### onDetachedFromEngine");
        System.out.println("### " + clientHandlers.size() + " client handlers");
        if (clientHandlers.size() == 1) {
            disconnect();
        }
        clientHandlers.remove(clientHandler);
        clientHandler.setContext(null);
        flutterPluginBinding = null;
        clientHandler = null;
        applicationContext = null;
        if (backgroundHandler != null) {
            backgroundHandler.destroy();
            backgroundHandler = null;
        }
        System.out.println("### onDetachedFromEngine completed");
    }

    //
    // ActivityAware callbacks
    //

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        System.out.println("### mainClientHandler set");
        activityPluginBinding = binding;
        clientHandler.setActivity(binding.getActivity());
        clientHandler.setContext(binding.getActivity());
        mainClientHandler = clientHandler;
        registerOnNewIntentListener();
        if (mediaController != null) {
            MediaControllerCompat.setMediaController(mainClientHandler.activity, mediaController);
        }
        if (mediaBrowser == null) {
            connect();
        }
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        System.out.println("### onDetachedFromActivityForConfigChanges");
        activityPluginBinding.removeOnNewIntentListener(newIntentListener);
        activityPluginBinding = null;
        clientHandler.setActivity(null);
        clientHandler.setContext(flutterPluginBinding.getApplicationContext());
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        System.out.println("### onReattachedToActivityForConfigChanges");
        activityPluginBinding = binding;
        clientHandler.setActivity(binding.getActivity());
        clientHandler.setContext(binding.getActivity());
        registerOnNewIntentListener();
    }

    @Override
    public void onDetachedFromActivity() {
        System.out.println("### onDetachedFromActivity");
        activityPluginBinding.removeOnNewIntentListener(newIntentListener);
        activityPluginBinding = null;
        newIntentListener = null;
        clientHandler.setActivity(null);
        clientHandler.setContext(flutterPluginBinding.getApplicationContext());
        if (clientHandlers.size() == 1) {
            // This unbinds from the service allowing AudioService.onDestroy to
            // happen which in turn allows the FlutterEngine to be destroyed.
            disconnect();
        }
        if (clientHandler == mainClientHandler) {
            mainClientHandler = null;
        }
    }

    private void connect() {
        System.out.println("### connect");
        /* Activity activity = mainClientHandler.activity; */
        /* if (activity != null) { */
        /*     if (clientHandler.wasLaunchedFromRecents()) { */
        /*         // We do this to avoid using the old intent. */
        /*         activity.setIntent(new Intent(Intent.ACTION_MAIN)); */
        /*     } */
        /*     if (activity.getIntent().getAction() != null) */
        /*         invokeClientMethod("notificationClicked", activity.getIntent().getAction().equals(AudioService.NOTIFICATION_CLICK_ACTION)); */
        /* } */
        if (mediaBrowser == null) {
            mediaBrowser = new MediaBrowserCompat(applicationContext,
                    new ComponentName(applicationContext, AudioService.class),
                    connectionCallback,
                    null);
            mediaBrowser.connect();
        }
        System.out.println("### connect returned");
    }

    private void disconnect() {
        System.out.println("### disconnect");
        Activity activity = mainClientHandler != null ? mainClientHandler.activity : null;
        if (activity != null) {
            // Since the activity enters paused state, we set the intent with ACTION_MAIN.
            activity.setIntent(new Intent(Intent.ACTION_MAIN));
        }

        if (mediaController != null) {
            mediaController.unregisterCallback(controllerCallback);
            mediaController = null;
        }
        if (mediaBrowser != null) {
            mediaBrowser.disconnect();
            mediaBrowser = null;
        }
        System.out.println("### disconnect returned");
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
        public final BinaryMessenger messenger;
        private MethodChannel channel;
        public long fastForwardInterval;
        public long rewindInterval;
        public Map<String, Object> params;

        private final MediaBrowserCompat.SubscriptionCallback subscriptionCallback = new MediaBrowserCompat.SubscriptionCallback() {
            @Override
            public void onChildrenLoaded(String parentId, List<MediaBrowserCompat.MediaItem> children) {
                invokeClientMethod("onChildrenLoaded", mediaItems2raw(children));
            }
        };

        public ClientHandler(BinaryMessenger messenger) {
            this.messenger = messenger;
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
            try {
                System.out.println("### ClientHandler message: " + call.method);
                switch (call.method) {
                case "configure": {
                    Map<?, ?> arguments = (Map<?, ?>)call.arguments;
                    AudioServiceConfig config = new AudioServiceConfig(context.getApplicationContext());
                    config.androidNotificationClickStartsActivity = (Boolean)arguments.get("androidNotificationClickStartsActivity");
                    config.androidNotificationOngoing = (Boolean)arguments.get("androidNotificationOngoing");
                    config.androidResumeOnClick = (Boolean)arguments.get("androidResumeOnClick");
                    config.androidNotificationChannelName = (String)arguments.get("androidNotificationChannelName");
                    config.androidNotificationChannelDescription = (String)arguments.get("androidNotificationChannelDescription");
                    config.notificationColor = arguments.get("notificationColor") == null ? -1 : getInt(arguments.get("notificationColor"));
                    config.androidNotificationIcon = (String)arguments.get("androidNotificationIcon");
                    config.androidShowNotificationBadge = (Boolean)arguments.get("androidShowNotificationBadge");
                    config.androidStopForegroundOnPause = (Boolean)arguments.get("androidStopForegroundOnPause");
                    config.artDownscaleWidth = arguments.get("artDownscaleWidth") != null ? (Integer)arguments.get("artDownscaleWidth") : -1;
                    config.artDownscaleHeight = arguments.get("artDownscaleHeight") != null ? (Integer)arguments.get("artDownscaleHeight") : -1;
                    config.setBrowsableRootExtras((Map<?,?>)arguments.get("androidBrowsableRootExtras"));
                    if (activity != null) {
                        config.activityClassName = activity.getClass().getName();
                    }
                    config.save();
                    if (AudioService.instance != null) {
                        AudioService.instance.configure(config);
                    }
                    mainClientHandler = ClientHandler.this;
                    if (backgroundHandler == null) {
                        backgroundHandler = new BackgroundHandler(messenger, true /*androidEnableQueue*/);
                        AudioService.init(backgroundHandler);
                    } else if (backgroundHandler.messenger != messenger) {
                        // We've detected this is the real engine hosting the AudioHandler,
                        // so update BackgroundHandler to connect to it.
                        backgroundHandler.switchToMessenger(messenger);
                    }
                    if (mediaController != null) {
                        result.success(null);
                    } else {
                        configureResult = result;
                    }
                    break;
                }
                default:
                    backgroundHandler().channel.invokeMethod(call.method, call.arguments, result);
                    break;
                }
            } catch (Exception e) {
                e.printStackTrace();
                result.error(e.getMessage(), null, null);
            }
        }
    }

    private static class BackgroundHandler implements MethodCallHandler, AudioService.ServiceListener {
        private boolean enableQueue;
        public BinaryMessenger messenger;
        public MethodChannel channel;
        private AudioTrack silenceAudioTrack;
        private static final int SILENCE_SAMPLE_RATE = 44100;
        private byte[] silence;

        public BackgroundHandler(BinaryMessenger messenger, boolean enableQueue) {
            System.out.println("### new BackgroundHandler");
            this.enableQueue = enableQueue;
            this.messenger = messenger;
            channel = new MethodChannel(messenger, CHANNEL_AUDIO_SERVICE_BACKGROUND);
            channel.setMethodCallHandler(this);
        }

        public void switchToMessenger(BinaryMessenger messenger) {
            channel.setMethodCallHandler(null);
            this.messenger = messenger;
            channel = new MethodChannel(messenger, CHANNEL_AUDIO_SERVICE_BACKGROUND);
            channel.setMethodCallHandler(this);
        }

        @Override
        public void onLoadChildren(final String parentMediaId, final MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>> result, Bundle options) {
            if (backgroundHandler != null) {
                ArrayList<Object> args = new ArrayList<Object>();
                args.add(parentMediaId);
                args.add(bundleToMap(options));
                backgroundHandler.channel.invokeMethod("onLoadChildren", args, new MethodChannel.Result() {
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
        public void onLoadItem(String itemId, final MediaBrowserServiceCompat.Result<MediaBrowserCompat.MediaItem> result) {
            if (backgroundHandler != null) {
                ArrayList<Object> args = new ArrayList<Object>();
                args.add(itemId);
                backgroundHandler.channel.invokeMethod("onLoadItem", args, new MethodChannel.Result() {
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
                        Map<?, ?> rawMediaItem = (Map<?, ?>)obj;
                        MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
                        MediaBrowserCompat.MediaItem mediaItem = new MediaBrowserCompat.MediaItem(mediaMetadata.getDescription(), (Boolean)rawMediaItem.get("playable") ? MediaBrowserCompat.MediaItem.FLAG_PLAYABLE : MediaBrowserCompat.MediaItem.FLAG_BROWSABLE);
                        result.sendResult(mediaItem);
                    }
                });
            }
            result.detach();
        }

        @Override
        public void onSearch(String query, Bundle extras, final MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>> result) {
            if (backgroundHandler != null) {
                ArrayList<Object> args = new ArrayList<Object>();
                args.add(query);
                args.add(bundleToMap(extras));
                backgroundHandler.channel.invokeMethod("onSearch", args, new MethodChannel.Result() {
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
        public void onPrepareFromMediaId(String mediaId, Bundle extras) {
            invokeMethod("onPrepareFromMediaId", mediaId, bundleToMap(extras));
        }

        @Override
        public void onPrepareFromSearch(String query, Bundle extras) {
            invokeMethod("onPrepareFromSearch", query, bundleToMap(extras));
        }

        @Override
        public void onPrepareFromUri(Uri uri, Bundle extras) {
            invokeMethod("onPrepareFromUri", uri.toString(), bundleToMap(extras));
        }

        @Override
        public void onPlay() {
            invokeMethod("onPlay");
        }

        @Override
        public void onPlayFromMediaId(String mediaId, Bundle extras) {
            invokeMethod("onPlayFromMediaId", mediaId, bundleToMap(extras));
        }

        @Override
        public void onPlayFromSearch(String query, Bundle extras) {
            invokeMethod("onPlayFromSearch", query, bundleToMap(extras));
        }

        @Override
        public void onPlayFromUri(Uri uri, Bundle extras) {
            invokeMethod("onPlayFromUri", uri.toString(), bundleToMap(extras));
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
        public void onRemoveQueueItemAt(int index) {
            invokeMethod("onRemoveQueueItemAt", index);
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
        public void onSetCaptioningEnabled(boolean enabled) {
            invokeMethod("onSetCaptioningEnabled", enabled);
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
        public void onCustomAction(String action, Bundle extras) {
            invokeMethod("onCustomAction", bundleToMap(extras));
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
        public void onSetVolumeTo(int volumeIndex) {
            invokeMethod("onSetVolumeTo", volumeIndex);
        }

        @Override
        public void onAdjustVolume(int direction) {
            invokeMethod("onAdjustVolume", direction);
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
        public void onDestroy() {
            disposeFlutterEngine();
        }

        @Override
        public void onMethodCall(MethodCall call, Result result) {
            System.out.println("### BackgroundHandler message: " + call.method);
            Context context = AudioService.instance;
            switch (call.method) {
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
                Map<?, ?> args = (Map<?, ?>)call.arguments;
                AudioProcessingState processingState = AudioProcessingState.values()[(Integer)args.get("processingState")];
                boolean playing = (Boolean)args.get("playing");
                List<Map<?, ?>> rawControls = (List<Map<?, ?>>)args.get("controls");
                List<Object> compactActionIndexList = (List<Object>)args.get("androidCompactActionIndices");
                List<Integer> rawSystemActions = (List<Integer>)args.get("systemActions");
                long position = getLong(args.get("updatePosition"));
                long bufferedPosition = getLong(args.get("bufferedPosition"));
                float speed = (float)((double)((Double)args.get("speed")));
                long updateTimeSinceEpoch = args.get("updateTime") == null ? System.currentTimeMillis() : getLong(args.get("updateTime"));
                Integer errorCode = (Integer)args.get("errorCode");
                String errorMessage = (String)args.get("errorMessage");
                int repeatMode = (Integer)args.get("repeatMode");
                int shuffleMode = (Integer)args.get("shuffleMode");
                boolean captioningEnabled = (Boolean)args.get("captioningEnabled");

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
                AudioService.instance.setState(
                        actions,
                        actionBits,
                        compactActionIndices,
                        processingState,
                        playing,
                        position,
                        bufferedPosition,
                        speed,
                        updateTimeSinceBoot,
                        errorCode,
                        errorMessage,
                        repeatMode,
                        shuffleMode,
                        captioningEnabled);
                result.success(true);
                break;
            case "setPlaybackInfo":
                Map<?, ?> playbackInfo = (Map<?, ?>)call.arguments;
                final int playbackType = (Integer)playbackInfo.get("playbackType");
                final int volumeControlType = (Integer)playbackInfo.get("volumeControlType");
                final int maxVolume = (Integer)playbackInfo.get("maxVolume");
                final int volume = (Integer)playbackInfo.get("volume");
                AudioService.instance.setPlaybackInfo(playbackType, volumeControlType, maxVolume, volume);
                break;
            case "notifyChildrenChanged":
                Map<?, ?> notificationInfo = (Map<?, ?>)call.arguments;
                String parentMediaId = (String)notificationInfo.get("parentMediaId");
                Map<?, ?> options = (Map<?, ?>)notificationInfo.get("options");
                AudioService.instance.notifyChildrenChanged(parentMediaId, mapToBundle(options));
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
            case "stopService":
                AudioService.instance.stopSelf();
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

        private void destroy() {
            if (silenceAudioTrack != null)
                silenceAudioTrack.release();
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
        raw.put("playable", mediaMetadata.getLong("playable_long") != 0);
        raw.put("displayTitle", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE));
        raw.put("displaySubtitle", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE));
        raw.put("displayDescription", metadataToString(mediaMetadata, MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION));
        if (mediaMetadata.containsKey(MediaMetadataCompat.METADATA_KEY_RATING)) {
            raw.put("rating", rating2raw(mediaMetadata.getRating(MediaMetadataCompat.METADATA_KEY_RATING)));
        }
        Map<String, Object> extras = bundleToMap(mediaMetadata.getBundle());
        if (extras.size() > 0) {
            raw.put("extras", extras);
        }
        return raw;
    }

    private static MediaMetadataCompat createMediaMetadata(Map<?, ?> rawMediaItem) {
        return AudioService.instance.createMediaMetadata(
                (String)rawMediaItem.get("id"),
                (String)rawMediaItem.get("album"),
                (String)rawMediaItem.get("title"),
                (String)rawMediaItem.get("artist"),
                (String)rawMediaItem.get("genre"),
                getLong(rawMediaItem.get("duration")),
                (String)rawMediaItem.get("artUri"),
                (Boolean)rawMediaItem.get("playable"),
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

    static Map<String, Object> bundleToMap(Bundle bundle) {
        if (bundle == null) return null;
        Map<String, Object> map = new HashMap<String, Object>();
        for (String key : bundle.keySet()) {
            Object value = bundle.get(key);
            if (value instanceof Integer
                    || value instanceof Long
                    || value instanceof Double
                    || value instanceof Float
                    || value instanceof Boolean
                    || value instanceof String) {
                map.put(key, value);
            }
        }
        return map;
    }

    static Bundle mapToBundle(Map<?, ?> map) {
        if (map == null) return null;
        final Bundle bundle = new Bundle();
        for (Object key : map.keySet()) {
            String skey = (String)key;
            Object value = map.get(skey);
            if (value instanceof Integer) bundle.putInt(skey, (Integer)value);
            else if (value instanceof Long) bundle.putLong(skey, (Long)value);
            else if (value instanceof Double) bundle.putDouble(skey, (Double)value);
            else if (value instanceof Boolean) bundle.putBoolean(skey, (Boolean)value);
            else if (value instanceof String) bundle.putString(skey, (String)value);
        }
        return bundle;
    }
}
