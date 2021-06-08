package com.ryanheise.audioservice;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.os.Bundle;
import android.os.SystemClock;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.UiThread;
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
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.NewIntentListener;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.plugin.common.BinaryMessenger;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;

import android.net.Uri;

/**
 * A connection bridge between {@link AudioService} and dart,
 * therefore creates and manages a {@link FlutterEngine} instance.
 *
 * With that mechanism AudioService can be start alone, creating the plugin, and then later
 * FlutterActivity attached to it, as well as FlutterActivity may be launched first
 * and create the AudioService.
 */
public class AudioServicePlugin implements FlutterPlugin, ActivityAware {
    private static final String DEFAULT_ENGINE_ID = "audio_service_engine";
    private static final String CHANNEL_CLIENT = "com.ryanheise.audio_service.client.methods";
    private static final String CHANNEL_HANDLER = "com.ryanheise.audio_service.handler.methods";

    static FlutterEngineFactory.EngineConfig engineConfig;
    @Nullable private static FlutterEngineFactory engineFactory;
    /**
     * Sets a custom factory for {@link FlutterEngine}.
     *
     * <p>By default the engine will be created with default ID and
     * will be pre-warmed and managed internally.
     */
    public static void setEngineFactory(@Nullable FlutterEngineFactory value) {
        engineFactory = value;
    }

    /** Factory callback for {@link FlutterEngine}. */
    public interface FlutterEngineFactory {
        /** Runs the factory */
        EngineConfig create();

        /** Config of the {@link FlutterEngine} for the plugin. */
        class EngineConfig {
            private String id;
            private FlutterEngine engine;

            /**
             * Creates config with ID.
             * Engine will be pre-warmed and managed internally.
             */
            public EngineConfig(String id) {
                this.id = id;
            }

            /**
             * Creates config with pre-warmed engine.
             * The provided engine must be managed by its creator.
             *
             * <p>The following illustrates how to pre-warm and cache a {@link FlutterEngine}:
             *
             * <pre>{@code
             * // Create and pre-warm a FlutterEngine.
             * FlutterEngine flutterEngine = new FlutterEngine(context);
             * flutterEngine.getDartExecutor().executeDartEntrypoint(DartEntrypoint.createDefault());
             *
             * // Cache the pre-warmed FlutterEngine in the FlutterEngineCache.
             * FlutterEngineCache.getInstance().put("my_engine", flutterEngine);
             * }</pre>
             *
             */
            public EngineConfig(FlutterEngine engine) {
                this.engine = engine;
            }

            private EngineConfig(EngineConfig other) {
                id = other.id;
                engine = other.engine;
                if (id == null && engine == null) {
                    id = DEFAULT_ENGINE_ID;
                }
            }
        }
    }

    /**
     * Returns an ID if engine should be created from ID, otherwise
     * returns null
     */
    private static String getId() {
        if (engineConfig == null)
            return DEFAULT_ENGINE_ID;
        if (engineConfig.engine != null)
            return null;
        if (engineConfig.id == null)
            return DEFAULT_ENGINE_ID;
        return engineConfig.id;
    }

    /**
     * Creates and pre-warms a {@link FlutterEngine}. This engine
     * is saved and will be kept intact until the {@link #destroy}
     * is called, after calling that method the new engine
     * will be created.
     *
     * <p>To bind the service to flutter activity, override the
     * {@link FlutterActivity#provideFlutterEngine(Context)} to return
     * the result of this method call.
     *
     * <p>Alternatively, you can just use {@link AudioServiceActivity}, which
     * does that for you.
     */
    public static synchronized FlutterEngine getFlutterEngine(Context context) {
        if (engine == null) {
            if (engineFactory != null) {
                engineConfig = new FlutterEngineFactory.EngineConfig(engineFactory.create());
            }
            String id = getId();
            if (id != null) {
                engine = FlutterEngineCache.getInstance().get(id);
                if (engine == null) {
                    engine = new FlutterEngine(context.getApplicationContext(), null);
                    engine.getDartExecutor().executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault());
                    FlutterEngineCache.getInstance().put(id, engine);
                }
            } else {
                engine = engineConfig.engine;
            }
        }
        return engine;
    }
    private static FlutterEngine engine;

    /**
     * Destroys the plugin and all the resources it holds,
     * stops the {@link AudioService}.
     *
     * After that, the next call to {@link #getFlutterEngine(Context)}
     * will create a new engine.
     *
     * <p>If engine was created by the plugin (with ID), it will be
     * destroyed.
     */
    public static synchronized void destroy() {
        if (engine != null) {
            engine = null;
            engineConfig = null;
            detachFromEngine();
            destroyEngine();
        }
    }

    private static void detachFromEngine() {
        disconnect();
        flutterPluginBinding = null;
        clientInterface = null;
        audioHandlerInterface.destroy();
        audioHandlerInterface = null;
        AudioService.instance.stop();
    }

    private static void destroyEngine() {
        String id = getId();
        if (id != null) {
            FlutterEngine engine = FlutterEngineCache.getInstance().get(id);
            if (engine != null) {
                engine.destroy();
                FlutterEngineCache.getInstance().remove(id);
            }
        }
    }

    private static Result configureResult;
    private static ClientInterface clientInterface;
    private static AudioHandlerInterface audioHandlerInterface;
    private static MediaBrowserCompat mediaBrowser;
    private static MediaControllerCompat mediaController;
    private static MediaControllerCompat.Callback controllerCallback;

    private static final long bootTime;
    static {
        bootTime = System.currentTimeMillis() - SystemClock.elapsedRealtime();
    }

    @UiThread
    private static void invokeClientMethod(String method, Object arg) {
        clientInterface.channel.invokeMethod(method, arg);
    }

    //
    // FlutterPlugin callbacks
    //

    private static FlutterPluginBinding flutterPluginBinding;
    private static ActivityPluginBinding activityPluginBinding;
    private static NewIntentListener newIntentListener;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        if (flutterPluginBinding != null) {
            throw new IllegalArgumentException(
                "Plugin supports being attached maximum to one Flutter engine. \n" +
                "This exception indicates an error in the plugin's code, since it should not " +
                "be reached when plugin is already bound to a Flutter engine."
            );
        }
        flutterPluginBinding = binding;
        clientInterface = new ClientInterface(flutterPluginBinding.getBinaryMessenger());
        audioHandlerInterface = new AudioHandlerInterface(flutterPluginBinding.getBinaryMessenger(), true);
        AudioService.init(audioHandlerInterface);
        if (mediaBrowser == null) {
            connect();
        }
    }


    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        destroy();
    }

    //
    // ActivityAware callbacks
    //

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        activityPluginBinding = binding;
        clientInterface.setActivity(binding.getActivity());
        registerOnNewIntentListener();
        if (mediaController != null) {
            MediaControllerCompat.setMediaController(clientInterface.activity, mediaController);
        }
        connect();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activityPluginBinding.removeOnNewIntentListener(newIntentListener);
        activityPluginBinding = null;
        clientInterface.setActivity(null);
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        activityPluginBinding = binding;
        clientInterface.setActivity(binding.getActivity());
        registerOnNewIntentListener();
    }

    @Override
    public void onDetachedFromActivity() {
        activityPluginBinding.removeOnNewIntentListener(newIntentListener);
        activityPluginBinding = null;
        newIntentListener = null;
        clientInterface.setActivity(null);
        disconnect();
    }

    private static void registerOnNewIntentListener() {
        activityPluginBinding.addOnNewIntentListener(newIntentListener = (intent) -> {
            clientInterface.activity.setIntent(intent);
            return true;
        });
    }

    /** Connects to the service. */
    private static void connect() {
        // Activity activity = clientInterface.activity;
        // boolean launchedFromRecents = (activity.getIntent().getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) ==
        //         Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY;
        // if (!launchedFromRecents) {
        //     invokeClientMethod("notificationClicked", activity.getIntent().getAction().equals(AudioService.NOTIFICATION_CLICK_ACTION));
        // }
        if (mediaBrowser == null) {
            Context applicationContext = flutterPluginBinding.getApplicationContext();
            mediaBrowser = new MediaBrowserCompat(
                    applicationContext,
                    new ComponentName(applicationContext, AudioService.class),
                    connectionCallback,
                    null
            );
            mediaBrowser.connect();
        }
    }

    /**
     * Disconnects from the service, allowing {@link AudioService#onDestroy} to
     * happen which in turn allows the FlutterEngine to be destroyed.
     */
    private static void disconnect() {
        if (mediaController != null) {
            mediaController.unregisterCallback(controllerCallback);
            mediaController = null;
            controllerCallback = null;
        }
        if (mediaBrowser != null) {
            mediaBrowser.disconnect();
            mediaBrowser = null;
        }
    }

    private static final MediaBrowserCompat.ConnectionCallback connectionCallback = new MediaBrowserCompat.ConnectionCallback() {
        @Override
        public void onConnected() {
            try {
                MediaSessionCompat.Token token = mediaBrowser.getSessionToken();
                mediaController = new MediaControllerCompat(flutterPluginBinding.getApplicationContext(), token);
                if (clientInterface.activity != null) {
                    // TODO: check this
                    MediaControllerCompat.setMediaController(clientInterface.activity, mediaController);
                }
                if (controllerCallback == null) {
                    controllerCallback = controllerCallback();
                }
                mediaController.registerCallback(controllerCallback);
                PlaybackStateCompat state = mediaController.getPlaybackState();
                controllerCallback.onPlaybackStateChanged(state);
                controllerCallback.onQueueChanged(mediaController.getQueue());
                controllerCallback.onMetadataChanged( mediaController.getMetadata());
                if (configureResult != null) {
                    configureResult.success(mapOf());
                    configureResult = null;
                }
            } catch (Exception e) {
                e.printStackTrace();
                throw new RuntimeException(e);
            }
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

    private static MediaControllerCompat.Callback controllerCallback()  {
        return new MediaControllerCompat.Callback() {
            @Override
            public void onMetadataChanged(MediaMetadataCompat metadata) {
                Map<String, Object> map = new HashMap<>();
                map.put("mediaItem", mediaMetadata2raw(metadata));
                invokeClientMethod("onMediaItemChanged", map);
            }

            @Override
            public void onPlaybackStateChanged(PlaybackStateCompat state) {
                // On the native side, we represent the update time relative to the boot time.
                // On the flutter side, we represent the update time relative to the epoch.
                long updateTimeSinceBoot = state.getLastPositionUpdateTime();
                long updateTimeSinceEpoch = bootTime + updateTimeSinceBoot;
                Map<String, Object> stateMap = new HashMap<>();
                stateMap.put("processingState", AudioService.instance.getProcessingState().ordinal());
                stateMap.put("playing", AudioService.instance.isPlaying());
                stateMap.put("controls", new ArrayList<>());
                long actionBits = state.getActions();
                List<Object> systemActions = new ArrayList<>();
                for (int actionIndex = 0; actionIndex < 64; actionIndex++) {
                    if ((actionBits & (1 << actionIndex)) != 0) {
                        systemActions.add(actionIndex);
                    }
                }
                stateMap.put("systemActions", systemActions);
                stateMap.put("updatePosition", state.getPosition());
                stateMap.put("bufferedPosition", state.getBufferedPosition());
                stateMap.put("speed", state.getPlaybackSpeed());
                stateMap.put("updateTime", updateTimeSinceEpoch);
                stateMap.put("repeatMode", AudioService.instance.getRepeatMode());
                stateMap.put("shuffleMode", AudioService.instance.getShuffleMode());
                Map<String, Object> map = new HashMap<>();
                map.put("state", stateMap);
                invokeClientMethod("onPlaybackStateChanged", map);
            }

            @Override
            public void onQueueChanged(List<MediaSessionCompat.QueueItem> queue) {
                Map<String, Object> map = new HashMap<>();
                map.put("queue", queue2raw(queue));
                invokeClientMethod("onQueueChanged", map);
            }

            // TODO: Add more callbacks.
        };
    }

    private static class ClientInterface implements MethodCallHandler {
        private Activity activity;
        public final BinaryMessenger messenger;
        private final MethodChannel channel;

        // This is implemented in Dart already.
        // But we may need to bring this back if we want to connect to another process's media session.
//        private final MediaBrowserCompat.SubscriptionCallback subscriptionCallback = new MediaBrowserCompat.SubscriptionCallback() {
//            @Override
//            public void onChildrenLoaded(@NonNull String parentId, @NonNull List<MediaBrowserCompat.MediaItem> children) {
//                Map<String, Object> map = new HashMap<String, Object>();
//                map.put("parentMediaId", parentId);
//                map.put("children", mediaItems2raw(children));
//                invokeClientMethod("onChildrenLoaded", map);
//            }
//        };

        public ClientInterface(BinaryMessenger messenger) {
            this.messenger = messenger;
            channel = new MethodChannel(messenger, CHANNEL_CLIENT);
            channel.setMethodCallHandler(this);
        }

        private void setActivity(Activity activity) {
            this.activity = activity;
        }

        @Override
        public void onMethodCall(@NonNull MethodCall call, @NonNull final Result result) {
            try {
                switch (call.method) {
                case "configure":
                    Map<?, ?> args = (Map<?, ?>)call.arguments;
                    Map<?, ?> configMap = (Map<?, ?>)args.get("config");
                    AudioServiceConfig config = new AudioServiceConfig(flutterPluginBinding.getApplicationContext());
                    config.androidNotificationClickStartsActivity = (Boolean)configMap.get("androidNotificationClickStartsActivity");
                    config.androidNotificationOngoing = (Boolean)configMap.get("androidNotificationOngoing");
                    config.androidResumeOnClick = (Boolean)configMap.get("androidResumeOnClick");
                    config.androidNotificationChannelName = (String)configMap.get("androidNotificationChannelName");
                    config.androidNotificationChannelDescription = (String)configMap.get("androidNotificationChannelDescription");
                    config.notificationColor = configMap.get("notificationColor") == null ? -1 : getInt(configMap.get("notificationColor"));
                    config.androidNotificationIcon = (String)configMap.get("androidNotificationIcon");
                    config.androidShowNotificationBadge = (Boolean)configMap.get("androidShowNotificationBadge");
                    config.androidStopForegroundOnPause = (Boolean)configMap.get("androidStopForegroundOnPause");
                    config.artDownscaleWidth = configMap.get("artDownscaleWidth") != null ? (Integer)configMap.get("artDownscaleWidth") : -1;
                    config.artDownscaleHeight = configMap.get("artDownscaleHeight") != null ? (Integer)configMap.get("artDownscaleHeight") : -1;
                    config.setBrowsableRootExtras((Map<?,?>)configMap.get("androidBrowsableRootExtras"));
                    if (activity != null) {
                        config.activityClassName = activity.getClass().getName();
                    }
                    config.save();
                    if (AudioService.instance != null) {
                        AudioService.instance.configure(config);
                    }
                    if (mediaController != null) {
                        result.success(mapOf());
                    } else {
                        configureResult = result;
                    }
                    break;
                }
            } catch (Exception e) {
                e.printStackTrace();
                result.error(e.getMessage(), null, null);
            }
        }
    }

    private class AudioHandlerInterface implements MethodCallHandler, AudioService.ServiceListener {
        private boolean enableQueue;
        public BinaryMessenger messenger;
        public MethodChannel channel;
        private AudioTrack silenceAudioTrack;
        private static final int SILENCE_SAMPLE_RATE = 44100;

        public AudioHandlerInterface(BinaryMessenger messenger, boolean enableQueue) {
            this.enableQueue = enableQueue;
            this.messenger = messenger;
            channel = new MethodChannel(messenger, CHANNEL_HANDLER);
            channel.setMethodCallHandler(this);
        }

        @UiThread
        public void invokeMethod(String method, Object arg) {
            if (channel != null) {
                channel.invokeMethod(method, arg);
            }
        }

        @UiThread
        public void invokeMethod(String method, Object arg, final Result result) {
            if (channel != null) {
                channel.invokeMethod(method, arg, result);
            }
        }

        private void destroy() {
            channel = null;
            if (silenceAudioTrack != null) {
                silenceAudioTrack.release();
            }
        }

        @Override
        public void onLoadChildren(@NonNull String parentMediaId, @NonNull MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>> result, @Nullable Bundle options) {
            if (audioHandlerInterface != null) {
                Map<String, Object> args = new HashMap<>();
                args.put("parentMediaId", parentMediaId);
                args.put("options", bundleToMap(options));
                invokeMethod("getChildren", args, new MethodChannel.Result() {
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
                        Map<?, ?> response = (Map<?, ?>)obj;
                        @SuppressWarnings("unchecked") List<Map<?, ?>> rawMediaItems = (List<Map<?, ?>>)response.get("children");
                        List<MediaBrowserCompat.MediaItem> mediaItems = new ArrayList<>();
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
        public void onLoadItem(String itemId, @NonNull MediaBrowserServiceCompat.Result<MediaBrowserCompat.MediaItem> result) {
            if (audioHandlerInterface != null) {
                Map<String, Object> args = new HashMap<>();
                args.put("mediaId", itemId);
                invokeMethod("getMediaItem", args, new MethodChannel.Result() {
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
                        Map<?, ?> response = (Map<?, ?>)obj;
                        Map<?, ?> rawMediaItem = (Map<?, ?>)response.get("mediaItem");
                        if (rawMediaItem != null) {
                            MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
                            MediaBrowserCompat.MediaItem mediaItem = new MediaBrowserCompat.MediaItem(mediaMetadata.getDescription(), (Boolean)rawMediaItem.get("playable") ? MediaBrowserCompat.MediaItem.FLAG_PLAYABLE : MediaBrowserCompat.MediaItem.FLAG_BROWSABLE);
                            result.sendResult(mediaItem);
                        } else {
                            result.sendResult(null);
                        }
                    }
                });
            }
            result.detach();
        }

        @Override
        public void onSearch(@NonNull String query, Bundle extras, @NonNull MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>> result) {
            if (audioHandlerInterface != null) {
                Map<String, Object> args = new HashMap<>();
                args.put("query", query);
                args.put("extras", bundleToMap(extras));
                invokeMethod("onSearch", args, new MethodChannel.Result() {
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
                        Map<?, ?> response = (Map<?, ?>)obj;
                        @SuppressWarnings("unchecked") List<Map<?, ?>> rawMediaItems = (List<Map<?, ?>>)response.get("mediaItems");
                        List<MediaBrowserCompat.MediaItem> mediaItems = new ArrayList<>();
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
            invokeMethod("click", mapOf("button", mediaControl.ordinal()));
        }

        @Override
        public void onPause() {
            invokeMethod("pause", mapOf());
        }

        @Override
        public void onPrepare() {
            invokeMethod("prepare", mapOf());
        }

        @Override
        public void onPrepareFromMediaId(String mediaId, Bundle extras) {
            invokeMethod("prepareFromMediaId", mapOf(
                        "mediaId", mediaId,
                        "extras", bundleToMap(extras)));
        }

        @Override
        public void onPrepareFromSearch(String query, Bundle extras) {
            invokeMethod("prepareFromSearch", mapOf(
                        "query", query,
                        "extras", bundleToMap(extras)));
        }

        @Override
        public void onPrepareFromUri(Uri uri, Bundle extras) {
            invokeMethod("prepareFromUri", mapOf(
                        "uri", uri.toString(),
                        "extras", bundleToMap(extras)));
        }

        @Override
        public void onPlay() {
            invokeMethod("play", mapOf());
        }

        @Override
        public void onPlayFromMediaId(String mediaId, Bundle extras) {
            invokeMethod("playFromMediaId", mapOf(
                        "mediaId", mediaId,
                        "extras", bundleToMap(extras)));
        }

        @Override
        public void onPlayFromSearch(String query, Bundle extras) {
            invokeMethod("playFromSearch", mapOf(
                        "query", query,
                        "extras", bundleToMap(extras)));
        }

        @Override
        public void onPlayFromUri(Uri uri, Bundle extras) {
            invokeMethod("playFromUri", mapOf(
                        "uri", uri.toString(),
                        "extras", bundleToMap(extras)));
        }

        @Override
        public void onPlayMediaItem(MediaMetadataCompat metadata) {
            invokeMethod("playMediaItem", mapOf("mediaItem", mediaMetadata2raw(metadata)));
        }

        @Override
        public void onStop() {
            invokeMethod("stop", mapOf());
        }

        @Override
        public void onAddQueueItem(MediaMetadataCompat metadata) {
            invokeMethod("addQueueItem", mapOf("mediaItem", mediaMetadata2raw(metadata)));
        }

        @Override
        public void onAddQueueItemAt(MediaMetadataCompat metadata, int index) {
            invokeMethod("insertQueueItem", mapOf(
                        "mediaItem", mediaMetadata2raw(metadata),
                        "index", index));
        }

        @Override
        public void onRemoveQueueItem(MediaMetadataCompat metadata) {
            invokeMethod("removeQueueItem", mapOf("mediaItem", mediaMetadata2raw(metadata)));
        }

        @Override
        public void onRemoveQueueItemAt(int index) {
            invokeMethod("removeQueueItemAt", mapOf("index", index));
        }

        @Override
        public void onSkipToQueueItem(long queueItemId) {
            invokeMethod("skipToQueueItem", mapOf("index", queueItemId));
        }

        @Override
        public void onSkipToNext() {
            invokeMethod("skipToNext", mapOf());
        }

        @Override
        public void onSkipToPrevious() {
            invokeMethod("skipToPrevious", mapOf());
        }

        @Override
        public void onFastForward() {
            invokeMethod("fastForward", mapOf());
        }

        @Override
        public void onRewind() {
            invokeMethod("rewind", mapOf());
        }

        @Override
        public void onSeekTo(long pos) {
            invokeMethod("seekTo", mapOf("position", pos*1000));
        }

        @Override
        public void onSetCaptioningEnabled(boolean enabled) {
            invokeMethod("setCaptioningEnabled", mapOf("enabled", enabled));
        }

        @Override
        public void onSetRepeatMode(int repeatMode) {
            invokeMethod("setRepeatMode", mapOf("repeatMode", repeatMode));
        }

        @Override
        public void onSetShuffleMode(int shuffleMode) {
            invokeMethod("setShuffleMode", mapOf("shuffleMode", shuffleMode));
        }

        @Override
        public void onCustomAction(String action, Bundle extras) {
            invokeMethod("onCustomAction", mapOf(
                        "name", action,
                        "extras", bundleToMap(extras)));
        }

        @Override
        public void onSetRating(RatingCompat rating) {
            invokeMethod("setRating", mapOf(
                        "rating", rating2raw(rating),
                        "extras", null));
        }

        @Override
        public void onSetRating(RatingCompat rating, Bundle extras) {
            invokeMethod("setRating", mapOf(
                        "rating", rating2raw(rating),
                        "extras", bundleToMap(extras)));
        }

        @Override
        public void onSetVolumeTo(int volumeIndex) {
            invokeMethod("setVolumeTo", mapOf("volumeIndex", volumeIndex));
        }

        @Override
        public void onAdjustVolume(int direction) {
            invokeMethod("adjustVolume", mapOf("direction", direction));
        }

        @Override
        public void onTaskRemoved() {
            invokeMethod("onTaskRemoved", mapOf());
        }

        @Override
        public void onClose() {
            invokeMethod("onNotificationDeleted", mapOf());
        }

        @Override
        public void onDestroy() {
            destroy();
        }

        @Override
        public void onMethodCall(MethodCall call, Result result) {
            Map<?, ?> args = (Map<?, ?>)call.arguments;
            switch (call.method) {
            case "setMediaItem": {
                Map<?, ?> rawMediaItem = (Map<?, ?>)args.get("mediaItem");
                MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
                AudioService.instance.setMetadata(mediaMetadata);
                result.success(null);
                break;
            }
            case "setQueue": {
                @SuppressWarnings("unchecked") List<Map<?, ?>> rawQueue = (List<Map<?, ?>>)args.get("queue");
                List<MediaSessionCompat.QueueItem> queue = raw2queue(rawQueue);
                AudioService.instance.setQueue(queue);
                result.success(null);
                break;
            }
            case "setState": {
                Map<?, ?> stateMap = (Map<?, ?>)args.get("state");
                AudioProcessingState processingState = AudioProcessingState.values()[(Integer)stateMap.get("processingState")];
                boolean playing = (Boolean)stateMap.get("playing");
                @SuppressWarnings("unchecked") List<Map<?, ?>> rawControls = (List<Map<?, ?>>)stateMap.get("controls");
                @SuppressWarnings("unchecked") List<Object> compactActionIndexList = (List<Object>)stateMap.get("androidCompactActionIndices");
                @SuppressWarnings("unchecked") List<Integer> rawSystemActions = (List<Integer>)stateMap.get("systemActions");
                long position = getLong(stateMap.get("updatePosition"));
                long bufferedPosition = getLong(stateMap.get("bufferedPosition"));
                float speed = (float)((double)((Double)stateMap.get("speed")));
                long updateTimeSinceEpoch = stateMap.get("updateTime") == null ? System.currentTimeMillis() : getLong(stateMap.get("updateTime"));
                Integer errorCode = (Integer)stateMap.get("errorCode");
                String errorMessage = (String)stateMap.get("errorMessage");
                int repeatMode = (Integer)stateMap.get("repeatMode");
                int shuffleMode = (Integer)stateMap.get("shuffleMode");
                Long queueIndex = getLong(stateMap.get("queueIndex"));
                boolean captioningEnabled = (Boolean)stateMap.get("captioningEnabled");

                // On the flutter side, we represent the update time relative to the epoch.
                // On the native side, we must represent the update time relative to the boot time.
                long updateTimeSinceBoot = updateTimeSinceEpoch - bootTime;

                List<NotificationCompat.Action> actions = new ArrayList<>();
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
                        captioningEnabled,
                        queueIndex);
                result.success(null);
                break;
            }
            case "setAndroidPlaybackInfo": {
                Map<?, ?> playbackInfo = (Map<?, ?>)args.get("playbackInfo");
                final int playbackType = (Integer)playbackInfo.get("playbackType");
                final Integer volumeControlType = (Integer)playbackInfo.get("volumeControlType");
                final Integer maxVolume = (Integer)playbackInfo.get("maxVolume");
                final Integer volume = (Integer)playbackInfo.get("volume");
                AudioService.instance.setPlaybackInfo(playbackType, volumeControlType, maxVolume, volume);
                break;
            }
            case "notifyChildrenChanged": {
                String parentMediaId = (String)args.get("parentMediaId");
                Map<?, ?> options = (Map<?, ?>)args.get("options");
                AudioService.instance.notifyChildrenChanged(parentMediaId, mapToBundle(options));
                result.success(null);
                break;
            }
            case "androidForceEnableMediaButtons": {
                // Just play a short amount of silence. This convinces Android
                // that we are playing "real" audio so that it will route
                // media buttons to us.
                // See: https://issuetracker.google.com/issues/65344811
                if (silenceAudioTrack == null) {
                    byte[] silence = new byte[2048];
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
                result.success(null);
                break;
            }
            case "stopService": {
                if (AudioService.instance != null) {
                    AudioService.instance.stop();
                }
                result.success(null);
                break;
            }
            }
        }
    }

    private static List<Map<?, ?>> mediaItems2raw(List<MediaBrowserCompat.MediaItem> mediaItems) {
        List<Map<?, ?>> rawMediaItems = new ArrayList<>();
        for (MediaBrowserCompat.MediaItem mediaItem : mediaItems) {
            MediaDescriptionCompat description = mediaItem.getDescription();
            MediaMetadataCompat mediaMetadata = AudioService.getMediaMetadata(description.getMediaId());
            rawMediaItems.add(mediaMetadata2raw(mediaMetadata));
        }
        return rawMediaItems;
    }

    private static List<Map<?, ?>> queue2raw(List<MediaSessionCompat.QueueItem> queue) {
        if (queue == null) return null;
        List<Map<?, ?>> rawQueue = new ArrayList<>();
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
        HashMap<String, Object> raw = new HashMap<>();
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
        Map<String, Object> raw = new HashMap<>();
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
       //noinspection unchecked
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

    private static List<MediaSessionCompat.QueueItem> raw2queue(List<Map<?, ?>> rawQueue) {
        List<MediaSessionCompat.QueueItem> queue = new ArrayList<>();
        int i = 0;
        for (Map<?, ?> rawMediaItem : rawQueue) {
            MediaMetadataCompat mediaMetadata = createMediaMetadata(rawMediaItem);
            MediaDescriptionCompat description = mediaMetadata.getDescription();
            queue.add(new MediaSessionCompat.QueueItem(description, i));
            i++;
        }
        return queue;
    }

    public static Long getLong(Object o) {
        return (o == null || o instanceof Long) ? (Long)o : Long.valueOf((Integer) o);
    }

    public static Integer getInt(Object o) {
        return (o == null || o instanceof Integer) ? (Integer)o : Integer.valueOf((int)((Long)o).longValue());
    }

    static Map<String, Object> bundleToMap(Bundle bundle) {
        if (bundle == null) return null;
        Map<String, Object> map = new HashMap<>();
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

    static Map<String, Object> mapOf(Object... args) {
        Map<String, Object> map = new HashMap<>();
        for (int i = 0; i < args.length; i += 2) {
            map.put((String)args[i], args[i + 1]);
        }
        return map;
    }
}
