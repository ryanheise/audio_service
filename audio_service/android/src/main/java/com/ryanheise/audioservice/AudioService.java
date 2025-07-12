package com.ryanheise.audioservice;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.util.Log;
import android.app.PendingIntent;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.os.PowerManager;
import android.support.v4.media.MediaBrowserCompat;
import android.support.v4.media.MediaDescriptionCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.RatingCompat;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;
import android.util.LruCache;
import android.util.Size;
import android.view.KeyEvent;

import androidx.annotation.RequiresApi;
import androidx.core.app.ServiceCompat;
import androidx.core.content.ContextCompat;
import androidx.core.app.NotificationCompat;
import androidx.media.MediaBrowserServiceCompat;
import androidx.media.VolumeProviderCompat;
import androidx.media.app.NotificationCompat.MediaStyle;
import androidx.media.utils.MediaConstants;

import java.io.FileDescriptor;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import androidx.media.utils.MediaConstants;

import io.flutter.embedding.engine.FlutterEngine;

public class AudioService extends MediaBrowserServiceCompat {
    public static final String CONTENT_STYLE_SUPPORTED = "android.media.browse.CONTENT_STYLE_SUPPORTED";
    public static final String CONTENT_STYLE_PLAYABLE_HINT = "android.media.browse.CONTENT_STYLE_PLAYABLE_HINT";
    public static final String CONTENT_STYLE_BROWSABLE_HINT = "android.media.browse.CONTENT_STYLE_BROWSABLE_HINT";
    public static final String EXTRA_RECENT = "android.service.media.extra.RECENT";
    public static final String EXTRA_OFFLINE = "android.service.media.extra.OFFLINE";
    public static final String EXTRA_SUGGESTION_KEYWORDS = "android.service.media.extra.SUGGESTION_KEYWORDS";
    public static final int CONTENT_STYLE_GRID_ITEM_HINT_VALUE = 2;
    public static final int CONTENT_STYLE_CATEGORY_LIST_ITEM_HINT_VALUE = 3;
    public static final int CONTENT_STYLE_CATEGORY_GRID_ITEM_HINT_VALUE = 4;

    private static final String SHARED_PREFERENCES_NAME = "audio_service_preferences";
    
    private static final String RECENT_PREFS_KEY = "recent_song";
    private static final int MAX_RECENT_ITEMS = 20;
    private static final int NOTIFICATION_ID = 1124;
    private static final int REQUEST_CONTENT_INTENT = 1000;
    public static final String NOTIFICATION_CLICK_ACTION = "com.ryanheise.audioservice.NOTIFICATION_CLICK";
    public static final String CUSTOM_ACTION_STOP = "com.ryanheise.audioservice.action.STOP";
    public static final String CUSTOM_ACTION_FAST_FORWARD = "com.ryanheise.audioservice.action.FAST_FORWARD";
    public static final String CUSTOM_ACTION_REWIND = "com.ryanheise.audioservice.action.REWIND";
    private static final String BROWSABLE_ROOT_ID = "root";
   
    private static final String RECENT_ROOT_ID = "recent";

    // 4 Tab IDs for Android Auto
    private static final String TAB_HOME_ID = "tab_home";
    private static final String TAB_RECENTS_ID = "tab_recents";
    private static final String TAB_BROWSE_ID = "tab_browse";
    private static final String TAB_LIBRARY_ID = "tab_library";
    // See the comment in onMediaButtonEvent to understand how the BYPASS keycodes work.
    // We hijack KEYCODE_MUTE and KEYCODE_MEDIA_RECORD since the media session subsystem
    // considers these keycodes relevant to media playback and will pass them on to us.
    public static final int KEYCODE_BYPASS_PLAY = KeyEvent.KEYCODE_MUTE;
    public static final int KEYCODE_BYPASS_PAUSE = KeyEvent.KEYCODE_MEDIA_RECORD;
    public static final int MAX_COMPACT_ACTIONS = 3;
    private static final long AUTO_ENABLED_ACTIONS = PlaybackStateCompat.ACTION_STOP
            | PlaybackStateCompat.ACTION_PAUSE
            | PlaybackStateCompat.ACTION_PLAY
            | PlaybackStateCompat.ACTION_REWIND
            // Auto-enabling these is bad for Android Auto since it forces the
            // previous/next buttons to always show.
            //| PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
            //| PlaybackStateCompat.ACTION_SKIP_TO_NEXT
            | PlaybackStateCompat.ACTION_FAST_FORWARD
            | PlaybackStateCompat.ACTION_SET_RATING
            // "seek" is the exception because it's the only action that
            // affects the appearance of the media notification, so we leave it
            // up to the plugin user whether to enable it (via systemActions).
            //| PlaybackStateCompat.ACTION_SEEK_TO
            | PlaybackStateCompat.ACTION_PLAY_PAUSE
            | PlaybackStateCompat.ACTION_PLAY_FROM_MEDIA_ID
            | PlaybackStateCompat.ACTION_PLAY_FROM_SEARCH
            | PlaybackStateCompat.ACTION_SKIP_TO_QUEUE_ITEM
            | PlaybackStateCompat.ACTION_PLAY_FROM_URI
            | PlaybackStateCompat.ACTION_PREPARE
            | PlaybackStateCompat.ACTION_PREPARE_FROM_MEDIA_ID
            | PlaybackStateCompat.ACTION_PREPARE_FROM_SEARCH
            | PlaybackStateCompat.ACTION_PREPARE_FROM_URI
            | PlaybackStateCompat.ACTION_SET_REPEAT_MODE
            | PlaybackStateCompat.ACTION_SET_SHUFFLE_MODE
            | PlaybackStateCompat.ACTION_SET_CAPTIONING_ENABLED;

    static AudioService instance;
    private static PendingIntent contentIntent;
    private static ServiceListener listener;

    private static boolean isFlutterConnected = false;

    private static long lastFlutterPing  = 0;
    private static final long FLUTTER_TIMEOUT_MS  = 5000;
    private static List<MediaSessionCompat.QueueItem> queue = new ArrayList<>();
    private static final Map<String, MediaMetadataCompat> mediaMetadataCache = new HashMap<>();

    public static void init(ServiceListener listener) {
        AudioService.listener = listener;
    }

    public static int toKeyCode(long action) {
        if (action == PlaybackStateCompat.ACTION_PLAY) {
            return KEYCODE_BYPASS_PLAY;
        } else if (action == PlaybackStateCompat.ACTION_PAUSE) {
            return KEYCODE_BYPASS_PAUSE;
        } else {
            return PlaybackStateCompat.toKeyCode(action);
        }
    }

    public static void updateFlutterConnection(boolean connected) {
        isFlutterConnected =  connected;
        lastFlutterPing = System.currentTimeMillis();
        Log.d("Flutter", "Flutterstate" +  isFlutterConnected);
    }

    public static boolean isIsFlutterConnected(){
        if (!isFlutterConnected) return false;
        long currentTime = System.currentTimeMillis();
        boolean isTimeOut = currentTime - lastFlutterPing > FLUTTER_TIMEOUT_MS;
        if (isTimeOut) {
            isFlutterConnected = false;
            Log.d("AudioService", "Flutter connection timed out");

        }
        return isFlutterConnected;
    }

    MediaMetadataCompat createMediaMetadata(String mediaId, String title, String album, String artist, String genre, Long duration, String artUri, Boolean playable, String displayTitle, String displaySubtitle, String displayDescription, RatingCompat rating, Map<?, ?> extras) {
        MediaMetadataCompat.Builder builder = new MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title);
        if (album != null)
            builder.putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album);
        if (artist != null)
            builder.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist);
        if (genre != null)
            builder.putString(MediaMetadataCompat.METADATA_KEY_GENRE, genre);
        if (duration != null)
            builder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration);
        if (artUri != null) {
            builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, artUri);
        }
        if (playable != null)
            builder.putLong("playable_long", playable ? 1 : 0);
        if (displayTitle != null)
            builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, displayTitle);
        if (displaySubtitle != null)
            builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, displaySubtitle);
        if (displayDescription != null)
            builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, displayDescription);
        if (rating != null) {
            builder.putRating(MediaMetadataCompat.METADATA_KEY_RATING, rating);
        }
        if (extras != null) {
            for (Object o : extras.keySet()) {
                String key = (String)o;
                Object value = extras.get(key);
                if (value instanceof Long) {
                    builder.putLong(key, (Long)value);
                } else if (value instanceof Integer) {
                    builder.putLong(key, (long)((Integer)value));
                } else if (value instanceof String) {
                    builder.putString(key, (String)value);
                } else if (value instanceof Boolean) {
                    builder.putLong(key, (Boolean)value ? 1 : 0);
                } else if (value instanceof Double) {
                    builder.putString(key, value.toString());
                }
            }
        }
        MediaMetadataCompat mediaMetadata = builder.build();
        mediaMetadataCache.put(mediaId, mediaMetadata);
        return mediaMetadata;
    }

    static MediaMetadataCompat getMediaMetadata(String mediaId) {
        return mediaMetadataCache.get(mediaId);
    }

    Bitmap loadArtBitmap(String artUriString, String loadThumbnailUri) {
        Bitmap bitmap = artBitmapCache.get(artUriString);
        if (bitmap != null) return bitmap;
        try {
            // There are 3 cases handled by this function:
            //   1. content URI with openFileDescriptor
            //   2. content URI with loadThumbnail (when Android >= Q and specified by the config)
            //   3. not content URI - loading from the file, or cache file created by the Dart side
            Uri artUri = Uri.parse(artUriString);
            boolean usesContentScheme = "content".equals(artUri.getScheme());
            FileDescriptor fileDescriptor = null;
            if (usesContentScheme) {
                try {
                    if (loadThumbnailUri != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        Size defaultSize = new Size(192, 192);
                        bitmap = getContentResolver().loadThumbnail(
                                artUri,
                                new Size(config.artDownscaleWidth == -1
                                                ? defaultSize.getWidth()
                                                : config.artDownscaleWidth,
                                        config.artDownscaleHeight == -1
                                                ? defaultSize.getHeight()
                                                : config.artDownscaleHeight),
                                null);
                        if (bitmap == null) {
                            return null;
                        }
                    } else {
                        ParcelFileDescriptor parcelFileDescriptor = getContentResolver().openFileDescriptor(artUri, "r");
                        if (parcelFileDescriptor != null) {
                            fileDescriptor = parcelFileDescriptor.getFileDescriptor();
                        } else {
                            return null;
                        }
                    }
                } catch (FileNotFoundException ex) {
                    return null;
                } catch (IOException ex) {
                    return null;
                }
            }
            // Decode the image ourselves for scenarios 1 and 3 (see the comment above).
            if (!usesContentScheme || fileDescriptor != null) {
                if (config.artDownscaleWidth != -1) {
                    BitmapFactory.Options options = new BitmapFactory.Options();
                    options.inJustDecodeBounds = true;
                    if (fileDescriptor != null) {
                        BitmapFactory.decodeFileDescriptor(fileDescriptor, null, options);
                    } else {
                        BitmapFactory.decodeFile(artUri.getPath(), options);
                    }
                    options.inSampleSize = calculateInSampleSize(options, config.artDownscaleWidth, config.artDownscaleHeight);
                    options.inJustDecodeBounds = false;

                    if (fileDescriptor != null) {
                        bitmap = BitmapFactory.decodeFileDescriptor(fileDescriptor, null, options);
                    } else {
                        bitmap = BitmapFactory.decodeFile(artUri.getPath(), options);
                    }
                } else {
                    if (fileDescriptor != null) {
                        bitmap = BitmapFactory.decodeFileDescriptor(fileDescriptor);
                    } else {
                        bitmap = BitmapFactory.decodeFile(artUri.getPath());
                    }
                }
            }
            artBitmapCache.put(artUriString, bitmap);
            return bitmap;
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    private static int calculateInSampleSize(BitmapFactory.Options options, int reqWidth, int reqHeight) {
        final int height = options.outHeight;
        final int width = options.outWidth;
        int inSampleSize = 1;

        if (height > reqHeight || width > reqWidth) {
            final int halfHeight = height / 2;
            final int halfWidth = width / 2;
            while ((halfHeight / inSampleSize) >= reqHeight
                    && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2;
            }
        }

        return inSampleSize;
    }

    private FlutterEngine flutterEngine;
    private AudioServiceConfig config;
    private PowerManager.WakeLock wakeLock;
    private MediaSessionCompat mediaSession;
    private MediaSessionCallback mediaSessionCallback;
    private List<MediaControl> controls = new ArrayList<>();
    private List<NotificationCompat.Action> nativeActions = new ArrayList<>();
    private List<PlaybackStateCompat.CustomAction> customActions = new ArrayList<>();
    private int[] compactActionIndices;
    private MediaMetadataCompat mediaMetadata;
    private Bitmap artBitmap;
    private String notificationChannelId;
    private LruCache<String, Bitmap> artBitmapCache;
    private boolean playing = false;
    private AudioProcessingState processingState = AudioProcessingState.idle;
    private int repeatMode;
    private int shuffleMode;
    private boolean notificationCreated;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private VolumeProviderCompat volumeProvider;

    public AudioProcessingState getProcessingState() {
        return processingState;
    }

    public boolean isPlaying() {
        return playing;
    }

    public int getRepeatMode() {
        return repeatMode;
    }

    public int getShuffleMode() {
        return shuffleMode;
    }

    @Override
    public void onCreate() {
        super.onCreate();
        instance = this;
        repeatMode = 0;
        shuffleMode = 0;
        notificationCreated = false;
        playing = false;
        processingState = AudioProcessingState.idle;
        mediaSession = new MediaSessionCompat(this, "media-session");

        configure(new AudioServiceConfig(getApplicationContext()));

        mediaSession.setFlags(MediaSessionCompat.FLAG_HANDLES_QUEUE_COMMANDS);
        PlaybackStateCompat.Builder stateBuilder = new PlaybackStateCompat.Builder()
                .setActions(AUTO_ENABLED_ACTIONS);
        mediaSession.setPlaybackState(stateBuilder.build());
        mediaSession.setCallback(mediaSessionCallback = new MediaSessionCallback());
        setSessionToken(mediaSession.getSessionToken());
        mediaSession.setQueue(queue);

        PowerManager pm = (PowerManager)getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, AudioService.class.getName());

        // Get max available VM memory, exceeding this amount will throw an
        // OutOfMemory exception. Stored in kilobytes as LruCache takes an
        // int in its constructor.
        final int maxMemory = (int)(Runtime.getRuntime().maxMemory() / 1024);

        // Use 1/8th of the available memory for this memory cache.
        final int cacheSize = maxMemory / 8;

        artBitmapCache = new LruCache<String, Bitmap>(cacheSize) {
            @Override
            protected int sizeOf(String key, Bitmap bitmap) {
                // The cache size will be measured in kilobytes rather than
                // number of items.
                return bitmap.getByteCount() / 1024;
            }
        };

        flutterEngine = AudioServicePlugin.getFlutterEngine(this);
        System.out.println("flutterEngine warmed up");
    }

    @Override
    public int onStartCommand(final Intent intent, int flags, int startId) {
        MediaButtonReceiver.handleIntent(mediaSession, intent);
        return START_NOT_STICKY;
    }

    public void stop() {
        deactivateMediaSession();
        stopSelf();
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        if (listener != null) {
            listener.onDestroy();
            listener = null;
        }
        mediaMetadata = null;
        artBitmap = null;
        queue.clear();
        mediaMetadataCache.clear();
        controls.clear();
        artBitmapCache.evictAll();
        compactActionIndices = null;
        releaseMediaSession();
        ServiceCompat.stopForeground(this, config.androidResumeOnClick ? STOP_FOREGROUND_DETACH : STOP_FOREGROUND_REMOVE);
        // This still does not solve the Android 11 problem.
        // if (notificationCreated) {
        //     NotificationManager notificationManager = getNotificationManager();
        //     notificationManager.cancel(NOTIFICATION_ID);
        // }
        releaseWakeLock();
        instance = null;
        notificationCreated = false;
    }

    public AudioServiceConfig getConfig() {
        return config;
    }

    public void configure(AudioServiceConfig config) {
        this.config = config;
        notificationChannelId = (config.androidNotificationChannelId != null)
            ? config.androidNotificationChannelId
            : getApplication().getPackageName() + ".channel";

        if (config.activityClassName != null) {
            Context context = getApplicationContext();
            Intent intent = new Intent((String)null);
            intent.setComponent(new ComponentName(context, config.activityClassName));
            //Intent intent = new Intent(context, config.activityClassName);
            intent.setAction(NOTIFICATION_CLICK_ACTION);
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= 23) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            contentIntent = PendingIntent.getActivity(context, REQUEST_CONTENT_INTENT, intent, flags);
        } else {
            contentIntent = null;
        }
        if (!config.androidResumeOnClick) {
            mediaSession.setMediaButtonReceiver(null);
        }
    }

    int getResourceId(String resource) {
        String[] parts = resource.split("/");
        String resourceType = parts[0];
        String resourceName = parts[1];
        return getResources().getIdentifier(resourceName, resourceType, getApplicationContext().getPackageName());
    }

    NotificationCompat.Action createAction(String resource, String label, long actionCode) {
        int iconId = getResourceId(resource);
        return new NotificationCompat.Action(iconId, label,
                buildMediaButtonPendingIntent(actionCode));
    }

    private boolean needCustomMediaControl(MediaControl control) {
        return control.customAction != null;
    }

    private Bundle mapToBundle(Map<?, ?> map) {
        if (map == null) {
            return null;
        }
        Bundle bundle = new Bundle();
        for (Map.Entry<?, ?> entry : map.entrySet()) {
            String key = entry.getKey().toString();
            Object value = entry.getValue();
            if (value instanceof Integer) {
                bundle.putInt(key, (Integer)value);
            } else if (value instanceof Long) {
                bundle.putLong(key, (Long)value);
            } else {
                bundle.putString(key, value.toString());
            }
        }
        return bundle;
    }

    PlaybackStateCompat.CustomAction createCustomAction(MediaControl control) {
        int iconId = getResourceId(control.icon);
        if (control.customAction != null) {
            return new PlaybackStateCompat.CustomAction.Builder(control.customAction.name, control.label, iconId)
                .setExtras(mapToBundle(control.customAction.extras))
                .build();
        } else if (Build.VERSION.SDK_INT >= 33) {
            // Android 13 changes MediaControl behavior as documented here:
            // https://developer.android.com/about/versions/13/behavior-changes-13
            // The below actions will be added to slots 1-3, if included.
            // 1 - ACTION_PLAY, ACTION_PLAY
            // 2 - ACTION_SKIP_TO_PREVIOUS
            // 3 - ACTION_SKIP_TO_NEXT
            // Custom actions will use slots 2-5 if included.
            // - ACTION_STOP
            // - ACTION_FAST_FORWARD
            // - ACTION_REWIND
            if (control.actionCode == PlaybackStateCompat.ACTION_STOP) {
                return new PlaybackStateCompat.CustomAction.Builder(CUSTOM_ACTION_STOP, control.label, iconId).build();
            } else if (control.actionCode == PlaybackStateCompat.ACTION_FAST_FORWARD) {
                return new PlaybackStateCompat.CustomAction.Builder(CUSTOM_ACTION_FAST_FORWARD, control.label, iconId).build();
            } else if (control.actionCode == PlaybackStateCompat.ACTION_REWIND) {
                return new PlaybackStateCompat.CustomAction.Builder(CUSTOM_ACTION_REWIND, control.label, iconId).build();
            }
        }
        return null;
    }

    PendingIntent buildMediaButtonPendingIntent(long action) {
        int keyCode = toKeyCode(action);
        if (keyCode == KeyEvent.KEYCODE_UNKNOWN)
            return null;
        Intent intent = new Intent(this, MediaButtonReceiver.class);
        intent.setAction(Intent.ACTION_MEDIA_BUTTON);
        intent.putExtra(Intent.EXTRA_KEY_EVENT, new KeyEvent(KeyEvent.ACTION_DOWN, keyCode));
        int flags = 0;
        if (Build.VERSION.SDK_INT >= 23) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getBroadcast(this, keyCode, intent, flags);
    }

    PendingIntent buildDeletePendingIntent() {
        Intent intent = new Intent(this, MediaButtonReceiver.class);
        intent.setAction(MediaButtonReceiver.ACTION_NOTIFICATION_DELETE);
        int flags = 0;
        if (Build.VERSION.SDK_INT >= 23) {
            flags |= PendingIntent.FLAG_IMMUTABLE;
        }
        return PendingIntent.getBroadcast(this, 0, intent, flags);
    }

    void setState(List<MediaControl> controls, long actionBits, int[] compactActionIndices, AudioProcessingState processingState, boolean playing, long position, long bufferedPosition, float speed, long updateTime, Integer errorCode, String errorMessage, int repeatMode, int shuffleMode, boolean captioningEnabled, Long queueIndex) {
        boolean notificationChanged = false;
        if (!Arrays.equals(compactActionIndices, this.compactActionIndices)) {
            notificationChanged = true;
        }
        if (!controls.equals(this.controls)) {
            notificationChanged = true;
        }
        this.controls = controls;
        this.nativeActions.clear();
        this.customActions.clear();
        for (MediaControl control : controls) {
            final PlaybackStateCompat.CustomAction customAction = createCustomAction(control);
            if (customAction != null) {
                customActions.add(customAction);
            } else {
                nativeActions.add(createAction(control.icon, control.label, control.actionCode));
            }
        }
        this.compactActionIndices = compactActionIndices;
        boolean wasPlaying = this.playing;
        AudioProcessingState oldProcessingState = this.processingState;
        this.processingState = processingState;
        this.playing = playing;
        this.repeatMode = repeatMode;
        this.shuffleMode = shuffleMode;

        PlaybackStateCompat.Builder stateBuilder = new PlaybackStateCompat.Builder()
                .setActions(AUTO_ENABLED_ACTIONS | actionBits)
                .setState(getPlaybackState(), position, speed, updateTime)
                .setBufferedPosition(bufferedPosition);

        for (PlaybackStateCompat.CustomAction action : this.customActions) {
            stateBuilder.addCustomAction(action);
        }

        if (queueIndex != null)
            stateBuilder.setActiveQueueItemId(queueIndex);
        if (errorCode != null && errorMessage != null)
            stateBuilder.setErrorMessage(errorCode, errorMessage);
        else if (errorMessage != null)
            stateBuilder.setErrorMessage(-987654, errorMessage);

        if (mediaMetadata != null) {
            // Update the progress bar in the browse view as content is playing as explained
            // here: https://developer.android.com/training/cars/media#browse-progress-bar
            Bundle extras = new Bundle();
            extras.putString(MediaConstants.PLAYBACK_STATE_EXTRAS_KEY_MEDIA_ID, mediaMetadata.getDescription().getMediaId());
            stateBuilder.setExtras(extras);
        }

        mediaSession.setPlaybackState(stateBuilder.build());
        mediaSession.setRepeatMode(repeatMode);
        mediaSession.setShuffleMode(shuffleMode);
        mediaSession.setCaptioningEnabled(captioningEnabled);

        if (!wasPlaying && playing) {
            enterPlayingState();
        } else if (wasPlaying && !playing) {
            exitPlayingState();
        }

        if (oldProcessingState != AudioProcessingState.idle && processingState == AudioProcessingState.idle) {
            // TODO: Handle completed state as well?
            stop();
        } else if (processingState != AudioProcessingState.idle && notificationChanged) {
            updateNotification();
        }
    }

    public void setPlaybackInfo(int playbackType, Integer volumeControlType, Integer maxVolume, Integer volume) {
        if (playbackType == MediaControllerCompat.PlaybackInfo.PLAYBACK_TYPE_LOCAL) {
            // We have to wait 'til media2 before we can use AudioAttributes.
            mediaSession.setPlaybackToLocal(AudioManager.STREAM_MUSIC);
            volumeProvider = null;
        } else if (playbackType == MediaControllerCompat.PlaybackInfo.PLAYBACK_TYPE_REMOTE) {
            if (volumeProvider == null || volumeControlType != volumeProvider.getVolumeControl() || maxVolume != volumeProvider.getMaxVolume()) {
                volumeProvider = new VolumeProviderCompat(volumeControlType, maxVolume, volume) {
                    @Override
                    public void onSetVolumeTo(int volumeIndex) {
                        if (listener == null) return;
                        listener.onSetVolumeTo(volumeIndex);
                    }
                    @Override
                    public void onAdjustVolume(int direction) {
                        if (listener == null) return;
                        listener.onAdjustVolume(direction);
                    }
                };
            } else {
                volumeProvider.setCurrentVolume(volume);
            }
            mediaSession.setPlaybackToRemote(volumeProvider);
        } else {
            // silently ignore
        }
    }

    public int getPlaybackState() {
        switch (processingState) {
        case idle: return PlaybackStateCompat.STATE_NONE;
        case loading: return PlaybackStateCompat.STATE_CONNECTING;
        case buffering: return PlaybackStateCompat.STATE_BUFFERING;
        case ready: return playing ? PlaybackStateCompat.STATE_PLAYING : PlaybackStateCompat.STATE_PAUSED;
        case completed: return playing ? PlaybackStateCompat.STATE_PLAYING : PlaybackStateCompat.STATE_PAUSED;
        case error: return PlaybackStateCompat.STATE_ERROR;
        default: return PlaybackStateCompat.STATE_NONE;
        }
    }

    private Notification buildNotification() {
        int[] compactActionIndices = this.compactActionIndices;
        if (compactActionIndices == null) {
            compactActionIndices = new int[Math.min(MAX_COMPACT_ACTIONS, nativeActions.size())];
            for (int i = 0; i < compactActionIndices.length; i++) compactActionIndices[i] = i;
        }
        NotificationCompat.Builder builder = getNotificationBuilder();
        if (mediaMetadata != null) {
            MediaDescriptionCompat description = mediaMetadata.getDescription();
            if (description.getTitle() != null)
                builder.setContentTitle(description.getTitle());
            if (description.getSubtitle() != null)
                builder.setContentText(description.getSubtitle());
            if (description.getDescription() != null)
                builder.setSubText(description.getDescription());
            synchronized (this) {
                if (artBitmap != null)
                    builder.setLargeIcon(artBitmap);
            }
        }
        if (config.androidNotificationClickStartsActivity)
            builder.setContentIntent(mediaSession.getController().getSessionActivity());
        // TODO: Look at setColorized
        if (config.notificationColor != -1)
            builder.setColor(config.notificationColor);
        for (NotificationCompat.Action action : nativeActions) {
            builder.addAction(action);
        }
        final MediaStyle style = new MediaStyle()
            .setMediaSession(mediaSession.getSessionToken());
        if (Build.VERSION.SDK_INT < 33) {
            style.setShowActionsInCompactView(compactActionIndices);
        }
        if (config.androidNotificationOngoing) {
            style.setShowCancelButton(true);
            style.setCancelButtonIntent(buildMediaButtonPendingIntent(PlaybackStateCompat.ACTION_STOP));
            builder.setOngoing(true);
        }
        builder.setStyle(style);
        return builder.build();
    }

    private NotificationManager getNotificationManager() {
        return (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
    }

    private /*synchronized*/ NotificationCompat.Builder getNotificationBuilder() {
        // This local variable could be commented out and replaced by an
        // instance variable if we want to reuse the builder instance. However,
        // there doesn't turn out to be much benefit to this since we don't
        // actually reuse any of the previous notification values when setting
        // a new notification.
        NotificationCompat.Builder notificationBuilder = null;
        if (notificationBuilder == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                createChannel();
            notificationBuilder = new NotificationCompat.Builder(this, notificationChannelId)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setShowWhen(false)
                    .setDeleteIntent(buildDeletePendingIntent())
            ;
        }
        int iconId = getResourceId(config.androidNotificationIcon);
        notificationBuilder.setSmallIcon(iconId);
        return notificationBuilder;
    }

    public void handleDeleteNotification() {
        if (listener == null) return;
        listener.onClose();
    }


    @RequiresApi(Build.VERSION_CODES.O)
    private void createChannel() {
        NotificationManager notificationManager = getNotificationManager();
        NotificationChannel channel = notificationManager.getNotificationChannel(notificationChannelId);
        if (channel == null) {
            channel = new NotificationChannel(notificationChannelId, config.androidNotificationChannelName, NotificationManager.IMPORTANCE_LOW);
            channel.setShowBadge(config.androidShowNotificationBadge);
            if (config.androidNotificationChannelDescription != null)
                channel.setDescription(config.androidNotificationChannelDescription);
            notificationManager.createNotificationChannel(channel);
        }
    }

    private void updateNotification() {
        if (notificationCreated) {
            getNotificationManager().notify(NOTIFICATION_ID, buildNotification());
        }
    }

    private void enterPlayingState() {
        ContextCompat.startForegroundService(this, new Intent(AudioService.this, AudioService.class));
        if (!mediaSession.isActive())
            mediaSession.setActive(true);

        acquireWakeLock();
        mediaSession.setSessionActivity(contentIntent);
        internalStartForeground();
    }

    private void exitPlayingState() {
        if (config.androidStopForegroundOnPause) {
            exitForegroundState();
        }
    }

    private void exitForegroundState() {
        ServiceCompat.stopForeground(this, STOP_FOREGROUND_DETACH);
        releaseWakeLock();
    }

    private void internalStartForeground() {
        startForeground(NOTIFICATION_ID, buildNotification());
        notificationCreated = true;
    }

    private void acquireWakeLock() {
        if (!wakeLock.isHeld())
            wakeLock.acquire();
    }

    private void releaseWakeLock() {
        if (wakeLock.isHeld())
            wakeLock.release();
    }

    private void activateMediaSession() {
        if (!mediaSession.isActive())
            mediaSession.setActive(true);
    }

    private void deactivateMediaSession() {
        if (mediaSession.isActive()) {
            mediaSession.setActive(false);
        }
        // Force cancellation of the notification
        getNotificationManager().cancel(NOTIFICATION_ID);
    }

    private void releaseMediaSession() {
        if (mediaSession == null) return;
        deactivateMediaSession();
        mediaSession.release();
        mediaSession = null;
    }

    /**
     * Updates queue.
     * Gets called from background thread.
     */
    synchronized void setQueue(List<MediaSessionCompat.QueueItem> queue) {
        AudioService.queue = queue;
        mediaSession.setQueue(queue);
    }

    void playMediaItem(MediaDescriptionCompat description) {
        mediaSessionCallback.onPlayMediaItem(description);
    }

    /**
     * Updates metadata, loads the art and updates the notification.
     * Gets called from background thread.
     * <p>
     * Also adds the loaded art bitmap to the MediaMetadata.
     * This is needed to display art in lock screen in versions
     * prior Android 11, in which this feature was removed.
     * <p>
     * See:
     *  - https://developer.android.com/guide/topics/media-apps/working-with-a-media-session#album_artwork
     *  - https://9to5google.com/2020/08/02/android-11-lockscreen-art/
     */
    synchronized void setMetadata(MediaMetadataCompat mediaMetadata) {
        String artCacheFilePath = mediaMetadata.getString("artCacheFile");
        if (artCacheFilePath != null) {
            // Load local files and network images, cached in files
            artBitmap = loadArtBitmap(artCacheFilePath, null);
            mediaMetadata = putArtToMetadata(mediaMetadata);
        } else {
            // Load content:// URIs
            String artUri = mediaMetadata.getString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI);
            if (artUri != null && artUri.startsWith("content:")) {
                String loadThumbnailUri = mediaMetadata.getString("loadThumbnailUri");
                artBitmap = loadArtBitmap(artUri, loadThumbnailUri);
                mediaMetadata = putArtToMetadata(mediaMetadata);
            } else {
                artBitmap = null;
            }
        }
        this.mediaMetadata = mediaMetadata;
        mediaSession.setMetadata(mediaMetadata);
        handler.removeCallbacksAndMessages(null);
        handler.post(this::updateNotification);
    }

    private MediaMetadataCompat putArtToMetadata(MediaMetadataCompat mediaMetadata) {
        return new MediaMetadataCompat.Builder(mediaMetadata)
                .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, artBitmap)
                .putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, artBitmap)
                .build();
    }

  
 @Override
public BrowserRoot onGetRoot(String clientPackageName, int clientUid, Bundle rootHints) {
    Boolean isRecentRequest = rootHints == null ? null : (Boolean)rootHints.getBoolean(BrowserRoot.EXTRA_RECENT);
    if (isRecentRequest == null) isRecentRequest = false;

     int maximumRootChildLimit = rootHints.getInt(
        MediaConstants.BROWSER_ROOT_HINTS_KEY_ROOT_CHILDREN_LIMIT, 4);
    int maxRootChildren = rootHints != null ?
        rootHints.getInt(MediaConstants.BROWSER_ROOT_HINTS_KEY_ROOT_CHILDREN_LIMIT, 4) : 4;

    Bundle extras = config.getBrowsableRootExtras();



    return new BrowserRoot(isRecentRequest ? RECENT_ROOT_ID : BROWSABLE_ROOT_ID, extras);
}

    @Override
    public void onLoadChildren(final String parentMediaId, final Result<List<MediaBrowserCompat.MediaItem>> result) {
        onLoadChildren(parentMediaId, result, null);
    }

    @Override
    public void onLoadChildren(final String parentMediaId, final Result<List<MediaBrowserCompat.MediaItem>> result, Bundle options) {
        // Handle 4 tabs for Android Auto
        if (BROWSABLE_ROOT_ID.equals(parentMediaId)) {
            result.sendResult(createFourTabs());
            return;
        }

        // Handle content for each tab
        if (TAB_HOME_ID.equals(parentMediaId)) {
            result.sendResult(createHomeContent());
            return;
        }

        if (TAB_RECENTS_ID.equals(parentMediaId)) {
            result.sendResult(createRecentsContent());
            return;
        }

        if (TAB_BROWSE_ID.equals(parentMediaId)) {
            result.sendResult(createBrowseContent());
            return;
        }

        if (TAB_LIBRARY_ID.equals(parentMediaId)) {
            result.sendResult(createLibraryContent());
            return;
        }

        // Handle sub-categories
        if (parentMediaId.startsWith("browse_")) {
            result.sendResult(createBrowseSubContent(parentMediaId));
            return;
        }

        if (parentMediaId.startsWith("library_")) {
            result.sendResult(createLibrarySubContent(parentMediaId));
            return;
        }

        if (listener == null) {
            result.sendResult(new ArrayList<>());
            return;
        }
        listener.onLoadChildren(parentMediaId, result, options);
    }

    private List<MediaBrowserCompat.MediaItem> createFourTabs() {
        List<MediaBrowserCompat.MediaItem> tabs = new ArrayList<>();

        // Tab 1: Home
        MediaDescriptionCompat homeDesc = new MediaDescriptionCompat.Builder()
            .setMediaId(TAB_HOME_ID)
            .setTitle("Home")
            .setIconUri(Uri.parse("android.resource://com.example.dr_play_app/drawable/ic_home"))   
            .setSubtitle("Your music home")
            .setExtras(createTabExtras())
            .build();
        tabs.add(new MediaBrowserCompat.MediaItem(homeDesc, MediaBrowserCompat.MediaItem.FLAG_BROWSABLE));

        // Tab 2: Recents
        MediaDescriptionCompat recentsDesc = new MediaDescriptionCompat.Builder()
            .setMediaId(TAB_RECENTS_ID)
            .setTitle("Recents")
              .setIconUri(Uri.parse("android.resource://com.example.dr_play_app/drawable/ic_recent"))   
            .setSubtitle("Recently played")
            .setExtras(createTabExtras())
            .build();
        tabs.add(new MediaBrowserCompat.MediaItem(recentsDesc, MediaBrowserCompat.MediaItem.FLAG_BROWSABLE));

        // Tab 3: Browse
        MediaDescriptionCompat browseDesc = new MediaDescriptionCompat.Builder()
            .setMediaId(TAB_BROWSE_ID)
            .setTitle("Browse")
               .setIconUri(Uri.parse("android.resource://com.example.dr_play_app/drawable/ic_collection"))   
            .setSubtitle("Explore music")
            .setExtras(createTabExtras())
            .build();
        tabs.add(new MediaBrowserCompat.MediaItem(browseDesc, MediaBrowserCompat.MediaItem.FLAG_BROWSABLE));

        // Tab 4: Library
        MediaDescriptionCompat libraryDesc = new MediaDescriptionCompat.Builder()
            .setMediaId(TAB_LIBRARY_ID)
            .setTitle("Library")
            .setIconUri(Uri.parse("android.resource://com.example.dr_play_app/drawable/ic_lib"))   
            .setSubtitle("Your collection")
            .setExtras(createTabExtras())
            .build();
        tabs.add(new MediaBrowserCompat.MediaItem(libraryDesc, MediaBrowserCompat.MediaItem.FLAG_BROWSABLE));

        return tabs;
    }

    private Bundle createTabExtras() {
        Bundle extras = new Bundle();
        extras.putInt(MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE,
                     MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM);
        extras.putInt(MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_PLAYABLE,
                     MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM);
        return extras;
    }



    // Thêm method override cho createHomeContent
private List<MediaBrowserCompat.MediaItem> createHomeContent() {
    List<MediaBrowserCompat.MediaItem> items = new ArrayList<>();
    Log.d("AudioService", config.getHomeVideoList() != null ? config.getHomeVideoList().toString() : "null");
    // Kiểm tra nếu có video list từ config
    if (config != null && config.getHomeVideoList() != null && !config.getHomeVideoList().isEmpty()) {
        for (Map<String, Object> videoData : config.getHomeVideoList()) {
            MediaBrowserCompat.MediaItem item = createMediaItemFromMap(videoData);
            if (item != null) {
                items.add(item);
            }
        }
    } else {
        // Fallback to default content
        items.add(createPlayableItem("home_quick_mix", "DEMO", "Mixed for you", ""));
        items.add(createPlayableItem("home_favorites", "DEMO", "Most played songs", ""));
        items.add(createPlayableItem("home_new_releases", "DEMO", "Latest additions", ""));
        items.add(createBrowsableItem("home_recent_section", "Recently Played", "Continue listening", ""));
    }
    
    return items;
}

// Helper method để convert Map thành MediaBrowserCompat.MediaItem
private MediaBrowserCompat.MediaItem createMediaItemFromMap(Map<String, Object> videoData) {
    try {
        String id = (String) videoData.get("id");
        String title = (String) videoData.get("title");
        String artist = (String) videoData.get("artist");
        String album = (String) videoData.get("album");
        String artUri = (String) videoData.get("artUri");
        Boolean playable = (Boolean) videoData.get("playable");
        
        if (id == null || title == null) {
            return null;
        }
        
        return createPlayableItem(id, title, artist != null ? artist : "", artUri != null ? artUri : "");
    } catch (Exception e) {
        e.printStackTrace();
        return null;
    }
}

    // RECENTS TAB CONTENT
    private List<MediaBrowserCompat.MediaItem> createRecentsContent() {
        // Load recent songs from SharedPreferences
        List<MediaBrowserCompat.MediaItem> items = loadRecentSongs();

        // If no recent songs, show default message
        if (items.isEmpty()) {
            items.add(createPlayableItem("recent_empty", "No recent songs", "Start playing music to see recent items", ""));
        }

        return items;
    }

    // BROWSE TAB CONTENT
    private List<MediaBrowserCompat.MediaItem> createBrowseContent() {
        List<MediaBrowserCompat.MediaItem> items = new ArrayList<>();

        // Browse categories
        items.add(createBrowsableItem("browse_genres", "Genres", "Browse by genre", ""));
        items.add(createBrowsableItem("browse_moods", "Moods", "Music for every mood", ""));
        items.add(createBrowsableItem("browse_charts", "Charts", "Top songs", ""));
        items.add(createBrowsableItem("browse_new", "New Music", "Latest releases", ""));
        items.add(createBrowsableItem("browse_radio", "Radio", "Live stations", ""));

        return items;
    }

    // LIBRARY TAB CONTENT
    private List<MediaBrowserCompat.MediaItem> createLibraryContent() {
        List<MediaBrowserCompat.MediaItem> items = new ArrayList<>();

        // Library sections
        items.add(createBrowsableItem("library_playlists", "Playlists", "Your playlists", ""));
        items.add(createBrowsableItem("library_artists", "Artists", "Browse artists", ""));
        items.add(createBrowsableItem("library_albums", "Albums", "Browse albums", ""));
        items.add(createBrowsableItem("library_songs", "Songs", "All your songs", ""));
        items.add(createBrowsableItem("library_downloads", "Downloads", "Offline music", ""));

        return items;
    }

    // Helper method to create browsable items
    private MediaBrowserCompat.MediaItem createBrowsableItem(String mediaId, String title, String subtitle, String iconUri) {
        MediaDescriptionCompat.Builder builder = new MediaDescriptionCompat.Builder()
            .setMediaId(mediaId)
            .setTitle(title)
            .setSubtitle(subtitle)
            .setExtras(createTabExtras());

        if (!iconUri.isEmpty()) {
            builder.setIconUri(Uri.parse(iconUri));
        }

        return new MediaBrowserCompat.MediaItem(builder.build(), MediaBrowserCompat.MediaItem.FLAG_BROWSABLE);
    }

    private void saveRecentSong(String mediaId, String title, String artist, String artUri) {
        try {
            SharedPreferences prefs = getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
            String existingData = prefs.getString(RECENT_PREFS_KEY, "[]");
            JSONArray recentsArray = new JSONArray(existingData);

            // Create new recent item
            JSONObject newItem = new JSONObject();
            newItem.put("mediaId", mediaId);
            newItem.put("title", title);
            newItem.put("artist", artist);
            newItem.put("artUri", artUri != null ? artUri : "");
            newItem.put("timestamp", System.currentTimeMillis());

            // Remove if already exists (to move to top)
            for (int i = 0; i < recentsArray.length(); i++) {
                JSONObject item = recentsArray.getJSONObject(i);
                if (mediaId.equals(item.getString("mediaId"))) {
                    recentsArray.remove(i);
                    break;
                }
            }

            // Add to beginning
            JSONArray newArray = new JSONArray();
            newArray.put(newItem);
            for (int i = 0; i < recentsArray.length() && i < MAX_RECENT_ITEMS - 1; i++) {
                newArray.put(recentsArray.getJSONObject(i));
            }

            // Save back to preferences
            prefs.edit().putString(RECENT_PREFS_KEY, newArray.toString()).apply();

        } catch (JSONException e) {
            Log.e("AudioService", "Error saving recent song", e);
        }
    }

    private List<MediaBrowserCompat.MediaItem> loadRecentSongs() {
        List<MediaBrowserCompat.MediaItem> items = new ArrayList<>();

        try {
            SharedPreferences prefs = getSharedPreferences(SHARED_PREFERENCES_NAME, Context.MODE_PRIVATE);
            String recentsData = prefs.getString(RECENT_PREFS_KEY, "[]");
            JSONArray recentsArray = new JSONArray(recentsData);

            for (int i = 0; i < recentsArray.length(); i++) {
                JSONObject item = recentsArray.getJSONObject(i);
                String mediaId = item.getString("mediaId");
                String title = item.getString("title");
                String artist = item.getString("artist");
                String artUri = item.optString("artUri", "");

                items.add(createPlayableItem(mediaId, title, artist, artUri));
            }

        } catch (JSONException e) {
            Log.e("AudioService", "Error loading recent songs", e);
            // Return default items if error
            items.add(createPlayableItem("recent_default_1", "No recent songs", "Start playing music", ""));
        }

        return items;
    }

    public MediaBrowserCompat.MediaItem createPlayableItem(String mediaId, String title, String artist, String iconUri) {
        Bundle extras = new Bundle();
        extras.putInt(MediaConstants.DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_PLAYABLE,
                     MediaConstants.DESCRIPTION_EXTRAS_VALUE_CONTENT_STYLE_GRID_ITEM);

        MediaDescriptionCompat.Builder builder = new MediaDescriptionCompat.Builder()
            .setMediaId(mediaId)
            .setTitle(title)
            .setSubtitle(artist)
            .setExtras(extras);

        if (!iconUri.isEmpty()) {
            builder.setIconUri(Uri.parse(iconUri));
        }

        return new MediaBrowserCompat.MediaItem(builder.build(), MediaBrowserCompat.MediaItem.FLAG_PLAYABLE);
    }


    private List<MediaBrowserCompat.MediaItem> createBrowseSubContent(String parentMediaId) {
        List<MediaBrowserCompat.MediaItem> items = new ArrayList<>();

        switch (parentMediaId) {
            case "browse_genres":
                items.add(createBrowsableItem("genre_pop", "Pop", "Popular music", ""));
                items.add(createBrowsableItem("genre_rock", "Rock", "Rock music", ""));
                items.add(createBrowsableItem("genre_jazz", "Jazz", "Jazz music", ""));
                items.add(createBrowsableItem("genre_classical", "Classical", "Classical music", ""));
                break;

            case "browse_moods":
                items.add(createBrowsableItem("mood_happy", "Happy", "Feel good music", ""));
                items.add(createBrowsableItem("mood_chill", "Chill", "Relaxing music", ""));
                items.add(createBrowsableItem("mood_workout", "Workout", "Energy music", ""));
                items.add(createBrowsableItem("mood_focus", "Focus", "Concentration music", ""));
                break;

            case "browse_charts":
                items.add(createPlayableItem("chart_1", "Top Song 1", "Artist 1", ""));
                items.add(createPlayableItem("chart_2", "Top Song 2", "Artist 2", ""));
                items.add(createPlayableItem("chart_3", "Top Song 3", "Artist 3", ""));
                break;

            default:
                // Default content for other browse categories
                items.add(createPlayableItem("default_1", "Sample Song 1", "Sample Artist", ""));
                items.add(createPlayableItem("default_2", "Sample Song 2", "Sample Artist", ""));
                break;
        }

        return items;
    }

    // Handle Library sub-content
    private List<MediaBrowserCompat.MediaItem> createLibrarySubContent(String parentMediaId) {
        List<MediaBrowserCompat.MediaItem> items = new ArrayList<>();

        switch (parentMediaId) {
            case "library_playlists":
                items.add(createBrowsableItem("playlist_1", "My Playlist 1", "25 songs", ""));
                items.add(createBrowsableItem("playlist_2", "My Playlist 2", "18 songs", ""));
                items.add(createBrowsableItem("playlist_3", "Favorites", "42 songs", ""));
                break;

            case "library_artists":
                items.add(createBrowsableItem("artist_1", "Artist 1", "12 songs", ""));
                items.add(createBrowsableItem("artist_2", "Artist 2", "8 songs", ""));
                items.add(createBrowsableItem("artist_3", "Artist 3", "15 songs", ""));
                break;

            case "library_albums":
                items.add(createBrowsableItem("album_1", "Album 1", "Artist 1 • 2023", ""));
                items.add(createBrowsableItem("album_2", "Album 2", "Artist 2 • 2023", ""));
                items.add(createBrowsableItem("album_3", "Album 3", "Artist 3 • 2022", ""));
                break;

            case "library_songs":
                items.add(createPlayableItem("song_1", "Song 1", "Artist 1", ""));
                items.add(createPlayableItem("song_2", "Song 2", "Artist 2", ""));
                items.add(createPlayableItem("song_3", "Song 3", "Artist 3", ""));
                items.add(createPlayableItem("song_4", "Song 4", "Artist 4", ""));
                break;

            default:
                items.add(createPlayableItem("lib_default_1", "Library Song 1", "Library Artist", ""));
                break;
        }

        return items;
    }

    @Override
    public void onLoadItem(String itemId, Result<MediaBrowserCompat.MediaItem> result) {
        if (listener == null) {
            result.sendResult(null);
            return;
        }
        listener.onLoadItem(itemId, result);
    }

    @Override
    public void onSearch(String query, Bundle extras, Result<List<MediaBrowserCompat.MediaItem>> result) {
        if (listener == null) {
            result.sendResult(new ArrayList<>());
            return;
        }
        listener.onSearch(query, extras, result);
    }

    @Override
    public void onTaskRemoved(Intent rootIntent) {
        if (listener != null) {
            listener.onTaskRemoved();
        }
        super.onTaskRemoved(rootIntent);
    }

    public class MediaSessionCallback extends MediaSessionCompat.Callback {
        @Override
        public void onAddQueueItem(MediaDescriptionCompat description) {
            if (listener == null) return;
            listener.onAddQueueItem(getMediaMetadata(description.getMediaId()));
        }

        @Override
        public void onAddQueueItem(MediaDescriptionCompat description, int index) {
            if (listener == null) return;
            listener.onAddQueueItemAt(getMediaMetadata(description.getMediaId()), index);
        }

        @Override
        public void onRemoveQueueItem(MediaDescriptionCompat description) {
            if (listener == null) return;
            listener.onRemoveQueueItem(getMediaMetadata(description.getMediaId()));
        }

        @Override
        public void onPrepare() {
            if (listener == null) return;
            if (!mediaSession.isActive())
                mediaSession.setActive(true);
            listener.onPrepare();
        }

        @Override
        public void onPrepareFromMediaId(String mediaId, Bundle extras) {
            if (listener == null) return;
            if (!mediaSession.isActive())
                mediaSession.setActive(true);
            listener.onPrepareFromMediaId(mediaId, extras);
        }

        @Override
        public void onPrepareFromSearch(String query, Bundle extras) {
            if (listener == null) return;
            if (!mediaSession.isActive())
                mediaSession.setActive(true);
            listener.onPrepareFromSearch(query, extras);
        }

        @Override
        public void onPrepareFromUri(Uri uri, Bundle extras) {
            if (listener == null) return;
            if (!mediaSession.isActive())
                mediaSession.setActive(true);
            listener.onPrepareFromUri(uri, extras);
        }

        @Override
        public void onPlay() {
            if (listener == null) return;
            listener.onPlay();
        }

        @Override
        public void onPlayFromMediaId(final String mediaId, final Bundle extras) {
            Log.d("AudioServiceX", "=== PLAYABLE ITEM CLICKED ===");
            Log.d("AudioServiceX", "MediaId: " + mediaId);
            Log.d("AudioServiceX", "This method ONLY called for FLAG_PLAYABLE items");

            boolean isValidPlayableItem = false;
            String itemTitle = "Unknown";
            String itemArtist = "Unknown";
            String itemArtUri = "";

            if (config != null && config.getHomeVideoList() != null) {
                List<Map<String, Object>> homeVideoList = config.getHomeVideoList();

                for (Map<String, Object> item : homeVideoList) {
                    String itemId = (String) item.get("id");
                    if (mediaId.equals(itemId)) {
                        isValidPlayableItem = true;
                        itemTitle = (String) item.get("title");
                        itemArtist = (String) item.get("artist");
                        itemArtUri = (String) item.get("artUri");
                        Log.d("AudioServiceX", "✅ FOUND ITEM: " + itemTitle + " - " + itemArtist);
                        break;
                    }
                }
            }

            if (isValidPlayableItem) {
                // *** NGAY LẬP TỨC cập nhật UI Android Auto ***
                Log.d("AudioServiceX", "🔄 UPDATING Android Auto UI immediately...");

                MediaMetadataCompat newMetadata = createMediaMetadata(
                    mediaId, itemTitle, "Dr Play App", itemArtist, null, null,
                    itemArtUri, true, null, null, null, null, null
                );

                // 2. Set metadata ngay lập tức
                setMetadata(newMetadata);

                // 3. Update playback state để hiển thị đang play
                setState(controls, AUTO_ENABLED_ACTIONS, compactActionIndices,
                       AudioProcessingState.ready, true, 0, 0, 1.0f,
                       System.currentTimeMillis(), null, null, repeatMode, shuffleMode, false, 0L);

                Log.d("AudioServiceX", "✅ Android Auto UI updated to: " + itemTitle);
            }

            if (listener == null) {
                Log.e("AudioServiceX", "❌ PROTOCOL ERROR: No listener to handle playback!");
                return;
            }

            // Gửi về Flutter để xử lý audio thực tế
            listener.onPlayFromMediaId(mediaId, extras);
        }

        @Override
        public void onPlayFromSearch(final String query, final Bundle extras) {
            if (listener == null) return;
            listener.onPlayFromSearch(query, extras);
        }

        @Override
        public void onPlayFromUri(final Uri uri, final Bundle extras) {
            if (listener == null) return;
            listener.onPlayFromUri(uri, extras);
        }

        @Override
        public boolean onMediaButtonEvent(Intent mediaButtonEvent) {
            if (listener == null) return false;
            // TODO: use typesafe version once SDK 33 is released.
            @SuppressWarnings("deprecation")
            final KeyEvent event = (KeyEvent)mediaButtonEvent.getExtras().getParcelable(Intent.EXTRA_KEY_EVENT);
            if (event.getAction() == KeyEvent.ACTION_DOWN) {
                switch (event.getKeyCode()) {
                case KEYCODE_BYPASS_PLAY:
                    onPlay();
                    break;
                case KEYCODE_BYPASS_PAUSE:
                    onPause();
                    break;
                case KeyEvent.KEYCODE_MEDIA_STOP:
                    onStop();
                    break;
                case KeyEvent.KEYCODE_MEDIA_FAST_FORWARD:
                    onFastForward();
                    break;
                case KeyEvent.KEYCODE_MEDIA_REWIND:
                    onRewind();
                    break;
                // Android unfortunately reroutes media button clicks to
                // KEYCODE_MEDIA_PLAY/PAUSE instead of the expected KEYCODE_HEADSETHOOK
                // or KEYCODE_MEDIA_PLAY_PAUSE. As a result, we can't genuinely tell if
                // onMediaButtonEvent was called because a media button was actually
                // pressed or because a PLAY/PAUSE action was pressed instead! To get
                // around this, we make PLAY and PAUSE actions use different keycodes:
                // KEYCODE_BYPASS_PLAY/PAUSE. Now if we get KEYCODE_MEDIA_PLAY/PUASE
                // we know it is actually a media button press.
                case KeyEvent.KEYCODE_MEDIA_NEXT:
                case KeyEvent.KEYCODE_MEDIA_PREVIOUS:
                case KeyEvent.KEYCODE_MEDIA_PLAY:
                case KeyEvent.KEYCODE_MEDIA_PAUSE:
                    // These are the "genuine" media button click events
                case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
                case KeyEvent.KEYCODE_HEADSETHOOK:
                    listener.onClick(eventToButton(event));
                    break;
                }
            }
            return true;
        }

        private MediaButton eventToButton(KeyEvent event) {
            switch (event.getKeyCode()) {
            case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
            case KeyEvent.KEYCODE_HEADSETHOOK:
                return MediaButton.media;
            case KeyEvent.KEYCODE_MEDIA_NEXT:
                return MediaButton.next;
            case KeyEvent.KEYCODE_MEDIA_PREVIOUS:
                return MediaButton.previous;
            default:
                return MediaButton.media;
            }
        }

        @Override
        public void onPause() {
            if (listener == null) return;
            listener.onPause();
        }

        @Override
        public void onStop() {
            if (listener == null) return;
            listener.onStop();
        }

        @Override
        public void onSkipToNext() {
            if (listener == null) return;
            listener.onSkipToNext();
        }

        @Override
        public void onSkipToPrevious() {
            if (listener == null) return;
            listener.onSkipToPrevious();
        }

        @Override
        public void onFastForward() {
            if (listener == null) return;
            listener.onFastForward();
        }

        @Override
        public void onRewind() {
            if (listener == null) return;
            listener.onRewind();
        }

        @Override
        public void onSkipToQueueItem(long id) {
            if (listener == null) return;
            listener.onSkipToQueueItem(id);
        }

        @Override
        public void onSeekTo(long pos) {
            if (listener == null) return;
            listener.onSeekTo(pos);
        }

        @Override
        public void onSetRating(RatingCompat rating) {
            if (listener == null) return;
            listener.onSetRating(rating);
        }

        @Override
        public void onSetPlaybackSpeed(float speed) {
            if (listener == null) return;
            listener.onSetPlaybackSpeed(speed);
        }

        @Override
        public void onSetCaptioningEnabled(boolean enabled) {
            if (listener == null) return;
            listener.onSetCaptioningEnabled(enabled);
        }

        @Override
        public void onSetRepeatMode(int repeatMode) {
            if (listener == null) return;
            listener.onSetRepeatMode(repeatMode);
        }

        @Override
        public void onSetShuffleMode(int shuffleMode) {
            if (listener == null) return;
            listener.onSetShuffleMode(shuffleMode);
        }

        @Override
        public void onCustomAction(String action, Bundle extras) {
            if (listener == null) return;
            if (CUSTOM_ACTION_STOP.equals(action)) {
                listener.onStop();
            } else if (CUSTOM_ACTION_FAST_FORWARD.equals(action)) {
                listener.onFastForward();
            } else if (CUSTOM_ACTION_REWIND.equals(action)) {
                listener.onRewind();
            } else {
                listener.onCustomAction(action, extras);
            }
        }

        @Override
        public void onSetRating(RatingCompat rating, Bundle extras) {
            if (listener == null) return;
            listener.onSetRating(rating, extras);
        }

        //
        // NON-STANDARD METHODS
        //

        public void onPlayMediaItem(final MediaDescriptionCompat description) {
            if (listener == null) return;
            listener.onPlayMediaItem(getMediaMetadata(description.getMediaId()));
        }
    }

    public interface ServiceListener {
        void onLoadChildren(String parentMediaId, Result<List<MediaBrowserCompat.MediaItem>> result, Bundle options);
        void onLoadItem(String itemId, Result<MediaBrowserCompat.MediaItem> result);
        void onSearch(String query, Bundle extras, Result<List<MediaBrowserCompat.MediaItem>> result);
        void onClick(MediaButton mediaButton);
        void onPrepare();
        void onPrepareFromMediaId(String mediaId, Bundle extras);
        void onPrepareFromSearch(String query, Bundle extras);
        void onPrepareFromUri(Uri uri, Bundle extras);
        void onPlay();
        void onPlayFromMediaId(String mediaId, Bundle extras);
        void onPlayFromSearch(String query, Bundle extras);
        void onPlayFromUri(Uri uri, Bundle extras);
        void onSkipToQueueItem(long id);
        void onPause();
        void onSkipToNext();
        void onSkipToPrevious();
        void onFastForward();
        void onRewind();
        void onStop();
        void onSeekTo(long pos);
        void onSetRating(RatingCompat rating);
        void onSetRating(RatingCompat rating, Bundle extras);
        void onSetRepeatMode(int repeatMode);
        void onSetShuffleMode(int shuffleMode);
        void onCustomAction(String action, Bundle extras);
        void onAddQueueItem(MediaMetadataCompat metadata);
        void onAddQueueItemAt(MediaMetadataCompat metadata, int index);
        void onRemoveQueueItem(MediaMetadataCompat metadata);
        void onRemoveQueueItemAt(int index);
        void onSetPlaybackSpeed(float speed);
        void onSetCaptioningEnabled(boolean enabled);
        void onSetVolumeTo(int volumeIndex);
        void onAdjustVolume(int direction);

        //
        // NON-STANDARD METHODS
        //

        void onPlayMediaItem(MediaMetadataCompat metadata);
        void onTaskRemoved();

        void onLoadHomeContent(Result<List<MediaBrowserCompat.MediaItem>> result);
        void onClose();
        void onDestroy();
    }
}
