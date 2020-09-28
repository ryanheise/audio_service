package com.ryanheise.audioservice;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.support.v4.media.MediaBrowserCompat;
import android.support.v4.media.MediaDescriptionCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.RatingCompat;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;
import android.util.LruCache;
import android.view.KeyEvent;

import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;
import androidx.media.MediaBrowserServiceCompat;
import androidx.media.app.NotificationCompat.MediaStyle;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class AudioService extends MediaBrowserServiceCompat {
	private static final int NOTIFICATION_ID = 1124;
	private static final int REQUEST_CONTENT_INTENT = 1000;
	private static final String MEDIA_ROOT_ID = "root";
	// See the comment in onMediaButtonEvent to understand how the BYPASS keycodes work.
	// We hijack KEYCODE_MUTE and KEYCODE_MEDIA_RECORD since the media session subsystem
	// considers these keycodes relevant to media playback and will pass them on to us.
	public static final int KEYCODE_BYPASS_PLAY = KeyEvent.KEYCODE_MUTE;
	public static final int KEYCODE_BYPASS_PAUSE = KeyEvent.KEYCODE_MEDIA_RECORD;
	public static final int MAX_COMPACT_ACTIONS = 3;

	private static volatile boolean running;
	static AudioService instance;
	private static PendingIntent contentIntent;
	private static boolean resumeOnClick;
	private static ServiceListener listener;
	static String androidNotificationChannelName;
	static String androidNotificationChannelDescription;
	static Integer notificationColor;
	static String androidNotificationIcon;
	static boolean androidNotificationClickStartsActivity;
	static boolean androidNotificationOngoing;
	static boolean androidStopForegroundOnPause;
	private static List<MediaSessionCompat.QueueItem> queue = new ArrayList<MediaSessionCompat.QueueItem>();
	private static int queueIndex = -1;
	private static Map<String, MediaMetadataCompat> mediaMetadataCache = new HashMap<>();
	private static Set<String> artUriBlacklist = new HashSet<>();
	private static LruCache<String, Bitmap> artBitmapCache;
	private static Size artDownscaleSize;
	private static boolean playing = false;
	private static AudioProcessingState processingState = AudioProcessingState.none;
	private static int repeatMode;
	private static int shuffleMode;
	private static boolean notificationCreated;

	public static void init(Activity activity, boolean resumeOnClick, String androidNotificationChannelName, String androidNotificationChannelDescription, String action, Integer notificationColor, String androidNotificationIcon, boolean androidNotificationClickStartsActivity, boolean androidNotificationOngoing, boolean androidStopForegroundOnPause, Size artDownscaleSize, ServiceListener listener) {
		if (running)
			throw new IllegalStateException("AudioService already running");
		running = true;

		Context context = activity.getApplicationContext();
		Intent intent = new Intent(context, activity.getClass());
		intent.setAction(action);
		contentIntent = PendingIntent.getActivity(context, REQUEST_CONTENT_INTENT, intent, PendingIntent.FLAG_UPDATE_CURRENT);
		AudioService.listener = listener;
		AudioService.resumeOnClick = resumeOnClick;
		AudioService.androidNotificationChannelName = androidNotificationChannelName;
		AudioService.androidNotificationChannelDescription = androidNotificationChannelDescription;
		AudioService.notificationColor = notificationColor;
		AudioService.androidNotificationIcon = androidNotificationIcon;
		AudioService.androidNotificationClickStartsActivity = androidNotificationClickStartsActivity;
		AudioService.androidNotificationOngoing = androidNotificationOngoing;
		AudioService.androidStopForegroundOnPause = androidStopForegroundOnPause;
		AudioService.artDownscaleSize = artDownscaleSize;

		notificationCreated = false;
		playing = false;
		processingState = AudioProcessingState.none;
		repeatMode = 0;
		shuffleMode = 0;

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
	}

	public static AudioProcessingState getProcessingState() {
		return processingState;
	}

	public static boolean isPlaying() {
		return playing;
	}

	public static int getRepeatMode() {
		return repeatMode;
	}

	public static int getShuffleMode() {
		return shuffleMode;
	}

	public void stop() {
		running = false;
		mediaMetadata = null;
		resumeOnClick = false;
		listener = null;
		androidNotificationChannelName = null;
		androidNotificationChannelDescription = null;
		notificationColor = null;
		androidNotificationIcon = null;
		artDownscaleSize = null;
		queue.clear();
		queueIndex = -1;
		mediaMetadataCache.clear();
		actions.clear();
		artBitmapCache.evictAll();
		compactActionIndices = null;

		mediaSession.setQueue(queue);
		mediaSession.setActive(false);
		releaseWakeLock();
		stopForeground(true);
		stopSelf();
		// This still does not solve the Android 11 problem.
		// if (notificationCreated) {
		// 	NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
		// 	notificationManager.cancel(NOTIFICATION_ID);
		// }
		notificationCreated = false;
	}

	public static boolean isRunning() {
		return running;
	}

	private PowerManager.WakeLock wakeLock;
	private MediaSessionCompat mediaSession;
	private MediaSessionCallback mediaSessionCallback;
	private MediaMetadataCompat preparedMedia;
	private List<NotificationCompat.Action> actions = new ArrayList<NotificationCompat.Action>();
	private int[] compactActionIndices;
	private MediaMetadataCompat mediaMetadata;
	private Object audioFocusRequest;
	private String notificationChannelId;
	private Handler handler = new Handler(Looper.getMainLooper());

	int getResourceId(String resource) {
		String[] parts = resource.split("/");
		String resourceType = parts[0];
		String resourceName = parts[1];
		return getResources().getIdentifier(resourceName, resourceType, getApplicationContext().getPackageName());
	}

	NotificationCompat.Action action(String resource, String label, long actionCode) {
		int iconId = getResourceId(resource);
		return new NotificationCompat.Action(iconId, label,
				buildMediaButtonPendingIntent(actionCode));
	}

	PendingIntent buildMediaButtonPendingIntent(long action) {
		int keyCode = toKeyCode(action);
		if (keyCode == KeyEvent.KEYCODE_UNKNOWN)
			return null;
		Intent intent = new Intent(this, MediaButtonReceiver.class);
		intent.setAction(Intent.ACTION_MEDIA_BUTTON);
		intent.putExtra(Intent.EXTRA_KEY_EVENT, new KeyEvent(KeyEvent.ACTION_DOWN, keyCode));
		return PendingIntent.getBroadcast(this, keyCode, intent, 0);
	}

	PendingIntent buildDeletePendingIntent() {
		Intent intent = new Intent(this, MediaButtonReceiver.class);
		intent.setAction(MediaButtonReceiver.ACTION_NOTIFICATION_DELETE);
		return PendingIntent.getBroadcast(this, 0, intent, 0);
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

	void setState(List<NotificationCompat.Action> actions, int actionBits, int[] compactActionIndices, AudioProcessingState processingState, boolean playing, long position, long bufferedPosition, float speed, long updateTime, int repeatMode, int shuffleMode) {
		this.actions = actions;
		this.compactActionIndices = compactActionIndices;
		boolean wasPlaying = AudioService.playing;
		AudioService.processingState = processingState;
		AudioService.playing = playing;
		AudioService.repeatMode = repeatMode;
		AudioService.shuffleMode = shuffleMode;

		PlaybackStateCompat.Builder stateBuilder = new PlaybackStateCompat.Builder()
				.setActions(PlaybackStateCompat.ACTION_PLAY_PAUSE | actionBits)
				.setState(getPlaybackState(), position, speed, updateTime)
				.setBufferedPosition(bufferedPosition);
		mediaSession.setPlaybackState(stateBuilder.build());

		if (!running) return;

		if (!wasPlaying && playing) {
			enterPlayingState();
		} else if (wasPlaying && !playing) {
			exitPlayingState();
		}

		updateNotification();
	}

	public int getPlaybackState() {
		switch (processingState) {
		case none: return PlaybackStateCompat.STATE_NONE;
		case connecting: return PlaybackStateCompat.STATE_CONNECTING;
		case ready: return playing ? PlaybackStateCompat.STATE_PLAYING : PlaybackStateCompat.STATE_PAUSED;
		case buffering: return PlaybackStateCompat.STATE_BUFFERING;
		case fastForwarding: return PlaybackStateCompat.STATE_FAST_FORWARDING;
		case rewinding: return PlaybackStateCompat.STATE_REWINDING;
		case skippingToPrevious: return PlaybackStateCompat.STATE_SKIPPING_TO_PREVIOUS;
		case skippingToNext: return PlaybackStateCompat.STATE_SKIPPING_TO_NEXT;
		case skippingToQueueItem: return PlaybackStateCompat.STATE_SKIPPING_TO_QUEUE_ITEM;
		case completed: return playing ? PlaybackStateCompat.STATE_PLAYING : PlaybackStateCompat.STATE_PAUSED;
		case stopped: return PlaybackStateCompat.STATE_STOPPED;
		case error: return PlaybackStateCompat.STATE_ERROR;
		default: return PlaybackStateCompat.STATE_NONE;
		}
	}

	private Notification buildNotification() {
		int[] compactActionIndices = this.compactActionIndices;
		if (compactActionIndices == null) {
			compactActionIndices = new int[Math.min(MAX_COMPACT_ACTIONS, actions.size())];
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
			if (description.getIconBitmap() != null)
				builder.setLargeIcon(description.getIconBitmap());
		}
		if (androidNotificationClickStartsActivity)
			builder.setContentIntent(mediaSession.getController().getSessionActivity());
		if (notificationColor != null)
			builder.setColor(notificationColor);
		for (NotificationCompat.Action action : actions) {
			builder.addAction(action);
		}
		builder.setStyle(new MediaStyle()
				.setMediaSession(mediaSession.getSessionToken())
				.setShowActionsInCompactView(compactActionIndices)
				.setShowCancelButton(true)
				.setCancelButtonIntent(buildMediaButtonPendingIntent(PlaybackStateCompat.ACTION_STOP))
		);
		if (androidNotificationOngoing)
			builder.setOngoing(true);
		Notification notification = builder.build();
		return notification;
	}

	private NotificationCompat.Builder getNotificationBuilder() {
		NotificationCompat.Builder notificationBuilder = null;
		if (notificationBuilder == null) {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
				createChannel();
			int iconId = getResourceId(androidNotificationIcon);
			notificationBuilder = new NotificationCompat.Builder(this, notificationChannelId)
					.setSmallIcon(iconId)
					.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
					.setShowWhen(false)
					.setDeleteIntent(buildDeletePendingIntent())
			;
		}
		return notificationBuilder;
	}

	public void handleDeleteNotification() {
		if (listener == null) return;
		listener.onClose();
	}


	@RequiresApi(Build.VERSION_CODES.O)
	private void createChannel() {
		NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
		NotificationChannel channel = notificationManager.getNotificationChannel(notificationChannelId);
		if (channel == null) {
			channel = new NotificationChannel(notificationChannelId, androidNotificationChannelName, NotificationManager.IMPORTANCE_LOW);
			if (androidNotificationChannelDescription != null)
				channel.setDescription(androidNotificationChannelDescription);
			notificationManager.createNotificationChannel(channel);
		}
	}

	private void updateNotification() {
		if (!notificationCreated) return;
		NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
		notificationManager.notify(NOTIFICATION_ID, buildNotification());
	}

	private boolean enterPlayingState() {
		startService(new Intent(AudioService.this, AudioService.class));
		if (!mediaSession.isActive())
			mediaSession.setActive(true);

		acquireWakeLock();
		mediaSession.setSessionActivity(contentIntent);
		internalStartForeground();
		return true;
	}

	private void exitPlayingState() {
		if (androidStopForegroundOnPause) {
			exitForegroundState();
		}
	}

	private void exitForegroundState() {
		stopForeground(false);
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

	static MediaMetadataCompat createMediaMetadata(String mediaId, String album, String title, String artist, String genre, Long duration, String artUri, Boolean playable, String displayTitle, String displaySubtitle, String displayDescription, RatingCompat rating, Map<?, ?> extras) {
		MediaMetadataCompat.Builder builder = new MediaMetadataCompat.Builder()
				.putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
				.putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
				.putString(MediaMetadataCompat.METADATA_KEY_TITLE, title);
		if (artist != null)
			builder.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist);
		if (genre != null)
			builder.putString(MediaMetadataCompat.METADATA_KEY_GENRE, genre);
		if (duration != null)
			builder.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, duration);
		if (artUri != null) {
			builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, artUri);
			String artCacheFilePath = null;
			if (extras != null) {
				artCacheFilePath = (String)extras.get("artCacheFile");
			}
			if (artCacheFilePath != null) {
				Bitmap bitmap = loadArtBitmapFromFile(artCacheFilePath);
				if (bitmap != null) {
					builder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap);
					builder.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, bitmap);
				}
			}
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
					builder.putLong("extra_long_" + key, (Long)value);
				} else if (value instanceof Integer) {
					builder.putLong("extra_long_" + key, (Integer)value);
				} else if (value instanceof String) {
					builder.putString("extra_string_" + key, (String)value);
				} else if (value instanceof Boolean) {
					builder.putLong("extra_boolean_" + key, (Boolean)value ? 1 : 0);
				} else if (value instanceof Double) {
					builder.putString("extra_double_" + key, value.toString());
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

	@Override
	public void onCreate() {
		super.onCreate();
		instance = this;
		notificationChannelId = getApplication().getPackageName() + ".channel";

		mediaSession = new MediaSessionCompat(this, "media-session");
		mediaSession.setMediaButtonReceiver(null); // TODO: Make this configurable
		mediaSession.setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS | MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS);
		PlaybackStateCompat.Builder stateBuilder = new PlaybackStateCompat.Builder()
				.setActions(PlaybackStateCompat.ACTION_PLAY);
		mediaSession.setPlaybackState(stateBuilder.build());
		mediaSession.setCallback(mediaSessionCallback = new MediaSessionCallback());
		setSessionToken(mediaSession.getSessionToken());
		mediaSession.setQueue(queue);

		PowerManager pm = (PowerManager)getSystemService(Context.POWER_SERVICE);
		wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, AudioService.class.getName());
	}

	void enableQueue() {
		mediaSession.setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS | MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS | MediaSessionCompat.FLAG_HANDLES_QUEUE_COMMANDS);
	}

	void setQueue(List<MediaSessionCompat.QueueItem> queue) {
		this.queue = queue;
		mediaSession.setQueue(queue);
	}

	void playMediaItem(MediaDescriptionCompat description) {
		mediaSessionCallback.onPlayMediaItem(description);
	}

	void setMetadata(final MediaMetadataCompat mediaMetadata) {
		this.mediaMetadata = mediaMetadata;
		mediaSession.setMetadata(mediaMetadata);
		updateNotification();
	}

	static Bitmap loadArtBitmapFromFile(String path) {
		Bitmap bitmap = artBitmapCache.get(path);
		if (bitmap != null) return bitmap;
		try {
			if (artDownscaleSize != null) {
				BitmapFactory.Options options = new BitmapFactory.Options();
				options.inJustDecodeBounds = true;
				BitmapFactory.decodeFile(path, options);
				int imageHeight = options.outHeight;
				int imageWidth = options.outWidth;
				options.inSampleSize = calculateInSampleSize(options, artDownscaleSize.width, artDownscaleSize.height);
				options.inJustDecodeBounds = false;

				bitmap = BitmapFactory.decodeFile(path, options);
			} else {
				bitmap = BitmapFactory.decodeFile(path);
			}
			artBitmapCache.put(path, bitmap);
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

	@Override
	public BrowserRoot onGetRoot(String clientPackageName, int clientUid, Bundle rootHints) {
		return new BrowserRoot(MEDIA_ROOT_ID, null);
	}

	@Override
	public void onLoadChildren(final String parentMediaId, final Result<List<MediaBrowserCompat.MediaItem>> result) {
		if (listener == null) {
			result.sendResult(new ArrayList<MediaBrowserCompat.MediaItem>());
			return;
		}
		listener.onLoadChildren(parentMediaId, result);
	}

	@Override
	public int onStartCommand(final Intent intent, int flags, int startId) {
		MediaButtonReceiver.handleIntent(mediaSession, intent);
		return START_NOT_STICKY;
	}

	@Override
	public void onDestroy() {
		super.onDestroy();
		if (listener != null) {
			listener.onDestroy();
		}
		mediaSession.release();
		instance = null;
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
		public void onPlay() {
			if (listener == null) return;
			listener.onPlay();
		}

		@Override
		public void onPrepareFromMediaId(String mediaId, Bundle extras) {
			if (listener == null) return;
			if (!mediaSession.isActive())
				mediaSession.setActive(true);
			listener.onPrepareFromMediaId(mediaId);
		}

		@Override
		public void onPlayFromMediaId(final String mediaId, final Bundle extras) {
			if (listener == null) return;
			listener.onPlayFromMediaId(mediaId);
		}

		@Override
		public boolean onMediaButtonEvent(Intent mediaButtonEvent) {
			if (listener == null) return false;
			final KeyEvent event = (KeyEvent)mediaButtonEvent.getExtras().get(Intent.EXTRA_KEY_EVENT);
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
					MediaControllerCompat controller = mediaSession.getController();
					listener.onClick(mediaControl(event));
					break;
				}
			}
			return true;
		}

		private MediaControl mediaControl(KeyEvent event) {
			switch (event.getKeyCode()) {
			case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
			case KeyEvent.KEYCODE_HEADSETHOOK:
				return MediaControl.media;
			case KeyEvent.KEYCODE_MEDIA_NEXT:
				return MediaControl.next;
			case KeyEvent.KEYCODE_MEDIA_PREVIOUS:
				return MediaControl.previous;
			default:
				return MediaControl.media;
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

	public static interface ServiceListener {
		void onLoadChildren(String parentMediaId, Result<List<MediaBrowserCompat.MediaItem>> result);

		void onClick(MediaControl mediaControl);

		void onPrepare();

		void onPrepareFromMediaId(String mediaId);

		//void onPrepareFromSearch(String query);
		//void onPrepareFromUri(String uri);
		void onPlay();

		void onPlayFromMediaId(String mediaId);

		//void onPlayFromSearch(String query, Map<?,?> extras);
		//void onPlayFromUri(String uri, Map<?,?> extras);
		void onSkipToQueueItem(long id);

		void onPause();

		void onSkipToNext();

		void onSkipToPrevious();

		void onFastForward();

		void onRewind();

		void onStop();

		void onDestroy();

		void onSeekTo(long pos);

		void onSetRating(RatingCompat rating);

		void onSetRating(RatingCompat rating, Bundle extras);

		void onSetRepeatMode(int repeatMode);

		//void onSetShuffleModeEnabled(boolean enabled);

		void onSetShuffleMode(int shuffleMode);

		//void onCustomAction(String action, Bundle extras);

		void onAddQueueItem(MediaMetadataCompat metadata);

		void onAddQueueItemAt(MediaMetadataCompat metadata, int index);

		void onRemoveQueueItem(MediaMetadataCompat metadata);

		//
		// NON-STANDARD METHODS
		//

		void onPlayMediaItem(MediaMetadataCompat metadata);

		void onTaskRemoved();

		void onClose();
	}
}
