package com.ryanheise.audioservice;

import android.content.Intent;
import android.os.IBinder;
import android.content.Context;
import android.media.AudioManager;
import android.os.PowerManager;
import android.app.Activity;
import android.app.PendingIntent;
import android.app.TaskStackBuilder;
import android.app.Notification;
import android.app.NotificationChannel;
import android.support.v4.app.NotificationCompat;
import android.support.v4.media.app.NotificationCompat.MediaStyle;
import android.support.v4.media.session.MediaControllerCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.MediaBrowserServiceCompat;
import android.support.v4.media.MediaBrowserServiceCompat.BrowserRoot;
import android.support.v4.media.session.PlaybackStateCompat;
import android.support.v4.media.MediaBrowserCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.MediaDescriptionCompat;
import android.support.v4.media.session.MediaButtonReceiver;
import android.content.ComponentName;
import android.R;
import io.flutter.app.FlutterApplication;
import android.app.Service;
import android.os.Build;
import android.os.SystemClock;
import android.app.IntentService;
import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;
import java.util.List;
import java.util.ArrayList;
import android.os.Bundle;
import android.view.KeyEvent;
import java.util.HashMap;
import java.util.Map;
import android.media.AudioFocusRequest;
import android.media.AudioAttributes;
import android.net.Uri;
import java.io.InputStream;
import java.net.URL;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import java.io.IOException;
import android.support.annotation.RequiresApi;

public class AudioService extends MediaBrowserServiceCompat implements AudioManager.OnAudioFocusChangeListener {
	private static final int NOTIFICATION_ID = 1124;
	private static final int REQUEST_CONTENT_INTENT = 1000;
	private static final String MEDIA_ROOT_ID = "root";
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
	private static List<MediaSessionCompat.QueueItem> queue = new ArrayList<MediaSessionCompat.QueueItem>();
	private static int queueIndex = -1;
	private static Map<String,MediaMetadataCompat> mediaMetadataCache = new HashMap<>();

	public static synchronized void init(Activity activity, boolean resumeOnClick, String androidNotificationChannelName, String androidNotificationChannelDescription, Integer notificationColor, String androidNotificationIcon, boolean androidNotificationClickStartsActivity, ServiceListener listener) {
		if (running)
			throw new IllegalStateException("AudioService already running");
		running = true;

		Context context = activity.getApplicationContext();
		Intent intent = new Intent(context, activity.getClass());
		contentIntent = PendingIntent.getActivity(context, REQUEST_CONTENT_INTENT, intent, PendingIntent.FLAG_UPDATE_CURRENT);
		AudioService.listener = listener;
		AudioService.resumeOnClick = resumeOnClick;
		AudioService.androidNotificationChannelName = androidNotificationChannelName;
		AudioService.androidNotificationChannelDescription = androidNotificationChannelDescription;
		AudioService.notificationColor = notificationColor;
		AudioService.androidNotificationIcon = androidNotificationIcon;
		AudioService.androidNotificationClickStartsActivity = androidNotificationClickStartsActivity;
	}

	public void stop() {
		running = false;
		resumeOnClick = false;
		listener = null;
		androidNotificationChannelName = null;
		androidNotificationChannelDescription = null;
		notificationColor = null;
		androidNotificationIcon = null;
		queue.clear();
		queueIndex = -1;
		mediaMetadataCache.clear();
		actions.clear();
		compactActionIndices = null;

		mediaSession.setQueue(queue);
		instance.abandonAudioFocus();
		unregisterNoisyReceiver();
		mediaSession.setActive(false);
		if (wakeLock.isHeld()) wakeLock.release();
		stopForeground(true);
		stopSelf();
	}

	public static synchronized boolean isRunning() {
		return running;
	}

	private PowerManager.WakeLock wakeLock;
	private BroadcastReceiver noisyReceiver;
	private MediaSessionCompat mediaSession;
	private MediaSessionCallback mediaSessionCallback;
	private AudioManager audioManager;
	private MediaMetadataCompat preparedMedia;
	private List<NotificationCompat.Action> actions = new ArrayList<NotificationCompat.Action>();
	private int[] compactActionIndices;
	private MediaMetadataCompat mediaMetadata;
	private Object audioFocusRequest;
	private String notificationChannelId;

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
		ComponentName component = new ComponentName(getPackageName(), "android.support.v4.media.session.MediaButtonReceiver");
		return buildMediaButtonPendingIntent(component, action);
	}

	PendingIntent buildMediaButtonPendingIntent(ComponentName component, long action) {
		int keyCode = toKeyCode(action);
		if (keyCode == KeyEvent.KEYCODE_UNKNOWN)
			return null;
		Intent intent = new Intent(Intent.ACTION_MEDIA_BUTTON);
		intent.setComponent(component);
		intent.putExtra(Intent.EXTRA_KEY_EVENT, new KeyEvent(KeyEvent.ACTION_DOWN, keyCode));
		return PendingIntent.getBroadcast(this, keyCode, intent, 0);
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

	void setState(List<NotificationCompat.Action> actions, int actionBits, int[] compactActionIndices, int playbackState, long position, float speed, long updateTime) {
		this.actions = actions;
		this.compactActionIndices = compactActionIndices;

		PlaybackStateCompat.Builder stateBuilder = new PlaybackStateCompat.Builder()
			.setActions(PlaybackStateCompat.ACTION_PLAY_PAUSE|actionBits)
			.setState(playbackState, position, speed, updateTime);
		mediaSession.setPlaybackState(stateBuilder.build());

		updateNotification();
	}

	private Notification buildNotification() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			createChannel();
		int iconId = getResourceId(androidNotificationIcon);
		int[] compactActionIndices = this.compactActionIndices;
		if (compactActionIndices == null) {
			compactActionIndices = new int[Math.min(MAX_COMPACT_ACTIONS, actions.size())];
			for (int i = 0; i < compactActionIndices.length; i++) compactActionIndices[i] = i;
		}
		MediaControllerCompat controller = mediaSession.getController();
		String contentTitle = "";
		String contentText = "";
		Bitmap artBitmap = null;
		if (mediaMetadata != null) {
			MediaDescriptionCompat description = mediaMetadata.getDescription();
			contentTitle = description.getTitle().toString();
			contentText = description.getSubtitle().toString();
			artBitmap = description.getIconBitmap();
		}
		NotificationCompat.Builder builder = new NotificationCompat.Builder(AudioService.this, notificationChannelId)
				.setSmallIcon(iconId)
				.setContentTitle(contentTitle)
				.setContentText(contentText)
				.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
				.setShowWhen(false)
				.setDeleteIntent(buildMediaButtonPendingIntent(PlaybackStateCompat.ACTION_STOP))
				;
		if (androidNotificationClickStartsActivity)
			builder.setContentIntent(controller.getSessionActivity());
		if (notificationColor != null)
			builder.setColor(notificationColor);
		for (NotificationCompat.Action action : actions) {
			builder.addAction(action);
		}
		if (artBitmap != null)
			builder.setLargeIcon(artBitmap);
		builder.setStyle(new MediaStyle()
				.setMediaSession(mediaSession.getSessionToken())
				.setShowActionsInCompactView(compactActionIndices)
				.setShowCancelButton(true)
				.setCancelButtonIntent(buildMediaButtonPendingIntent(PlaybackStateCompat.ACTION_STOP))
				);
		Notification notification = builder.build();
		return notification;
	}

	private int requestAudioFocus() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			return requestAudioFocusO();
		else
			return audioManager.requestAudioFocus(this,
					AudioManager.STREAM_MUSIC,
					AudioManager.AUDIOFOCUS_GAIN);
	}

	@RequiresApi(Build.VERSION_CODES.O)
	private int requestAudioFocusO() {
		AudioAttributes audioAttributes = new AudioAttributes.Builder()
				.setUsage(AudioAttributes.USAGE_MEDIA)
				.setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
				.build();
		audioFocusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
				.setAudioAttributes(audioAttributes)
				.setWillPauseWhenDucked(true)
				.setOnAudioFocusChangeListener(this)
				.build();
		return audioManager.requestAudioFocus((AudioFocusRequest)audioFocusRequest);
	}

	private void abandonAudioFocus() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			abandonAudioFocusO();
		else
			audioManager.abandonAudioFocus(this);
	}

	@RequiresApi(Build.VERSION_CODES.O)
	private void abandonAudioFocusO() {
		audioManager.abandonAudioFocusRequest((AudioFocusRequest)audioFocusRequest);
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
		NotificationManager notificationManager = (NotificationManager)getSystemService(Context.NOTIFICATION_SERVICE);
		notificationManager.notify(NOTIFICATION_ID, buildNotification());
	}

	private void registerNoisyReceiver() {
		if (noisyReceiver != null) return;
		noisyReceiver = new BroadcastReceiver() {
			@Override
			public void onReceive(Context context, Intent intent) {
				if (AudioManager.ACTION_AUDIO_BECOMING_NOISY.equals(intent.getAction())) {
					listener.onAudioBecomingNoisy();
				}
			}
		};
		registerReceiver(noisyReceiver, new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY));
	}

	private void unregisterNoisyReceiver() {
		if (noisyReceiver == null) return;
		unregisterReceiver(noisyReceiver);
		noisyReceiver = null;
	}

	static MediaMetadataCompat createMediaMetadata(String mediaId, String album, String title, String artist, String genre, Long duration, String artUri, String displayTitle, String displaySubtitle, String displayDescription) {
		MediaMetadataCompat mediaMetadata = mediaMetadataCache.get(mediaId);
		if (mediaMetadata == null) {
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
			if (artUri != null)
				builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, artUri);
			if (displayTitle != null)
				builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE, displayTitle);
			if (displaySubtitle != null)
				builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE, displaySubtitle);
			if (displayDescription != null)
				builder.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_DESCRIPTION, displayDescription);
			mediaMetadata = builder.build();
			mediaMetadataCache.put(mediaId, mediaMetadata);
		}
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
		audioManager = (AudioManager)getSystemService(Context.AUDIO_SERVICE);

		mediaSession = new MediaSessionCompat(this, "media-session");
		mediaSession.setMediaButtonReceiver(null); // TODO: Make this configurable
		mediaSession.setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS | MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS);
		PlaybackStateCompat.Builder stateBuilder = new PlaybackStateCompat.Builder()
				.setActions(PlaybackStateCompat.ACTION_PLAY);
		mediaSession.setPlaybackState(stateBuilder.build());
		mediaSession.setCallback(mediaSessionCallback = new MediaSessionCallback());
		setSessionToken(mediaSession.getSessionToken());
		mediaSession.setQueue(queue);

		PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
		wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, AudioService.class.getName());
	}

	void enableQueue() {
		mediaSession.setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS | MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS | MediaSessionCompat.FLAG_HANDLES_QUEUE_COMMANDS);
	}

	void setQueue(List<MediaSessionCompat.QueueItem> queue) {
		this.queue = queue;
		mediaSession.setQueue(queue);
	}

	synchronized void setMetadata(final MediaMetadataCompat mediaMetadata) {
		this.mediaMetadata = mediaMetadata;
		mediaSession.setMetadata(mediaMetadata);
		updateNotification();

		final MediaDescriptionCompat description = mediaMetadata.getDescription();
		final Uri artUri = description.getIconUri();
		if (description.getIconBitmap() == null && artUri != null) {
			new Thread() {
				@Override public void run() {
					try (InputStream in = new URL(artUri.toString()).openConnection().getInputStream()) {
						Bitmap bitmap = BitmapFactory.decodeStream(in);
						updateArtBitmap(mediaMetadata, bitmap);
					}
					catch (IOException e) {
						e.printStackTrace();
					}
				}
			}.start();
		}
	}

	synchronized void updateArtBitmap(MediaMetadataCompat mediaMetadata, Bitmap bitmap) {
		if (mediaMetadata.getDescription().getMediaId().equals(this.mediaMetadata.getDescription().getMediaId())) {
			String mediaId = mediaMetadata.getDescription().getMediaId();
			mediaMetadata = new MediaMetadataCompat.Builder(mediaMetadata)
				.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
				.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, bitmap) 
				.build();
			mediaMetadataCache.put(mediaId, mediaMetadata);
			setMetadata(mediaMetadata);
		}
	}

	@Override
	public BrowserRoot onGetRoot(String clientPackageName, int clientUid, Bundle rootHints) {
		return new BrowserRoot(MEDIA_ROOT_ID, null);
	}

	@Override
	public void onLoadChildren(final String parentMediaId, final Result<List<MediaBrowserCompat.MediaItem>> result) {
		if (listener == null) return;
		listener.onLoadChildren(parentMediaId, result);
	}

	@Override
	public int onStartCommand(final Intent intent, int flags, int startId) {
		MediaButtonReceiver.handleIntent(mediaSession, intent);
		return super.onStartCommand(intent, flags, startId);
	}

	@Override
	public void onDestroy() {
		instance = null;
		super.onDestroy();
	}

	@Override
	public void onAudioFocusChange(int focusChange) {
		switch (focusChange) {
			case AudioManager.AUDIOFOCUS_GAIN:
				listener.onAudioFocusGained();
				break;
			case AudioManager.AUDIOFOCUS_LOSS:
				listener.onAudioFocusLost();
				break;
			case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
				listener.onAudioFocusLostTransient();
				break;
			case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
				listener.onAudioFocusLostTransientCanDuck();
				break;
			default:
				break;
		}
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
			play(new Runnable() {
				public void run() {
					listener.onPlay();
				}
			});
		}

		private void play(Runnable runner) {
			int result = requestAudioFocus();
			if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
				throw new RuntimeException("Failed to gain audio focus");
			}

			startService(new Intent(AudioService.this, AudioService.class));
			if (!mediaSession.isActive())
				mediaSession.setActive(true);

			runner.run();

			acquireWakeLock();
			registerNoisyReceiver();
			mediaSession.setSessionActivity(contentIntent);
			startForeground(NOTIFICATION_ID, buildNotification());
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
			play(new Runnable() {
				public void run() {
					listener.onPlayFromMediaId(mediaId);
				}
			});
		}

		private void acquireWakeLock() {
			if (!wakeLock.isHeld())
				wakeLock.acquire();
		}

		@Override
		public boolean onMediaButtonEvent(Intent mediaButtonEvent) {
			if (listener == null) return false;
			KeyEvent event = (KeyEvent)mediaButtonEvent.getExtras().get(Intent.EXTRA_KEY_EVENT);
			if (event.getAction() == KeyEvent.ACTION_DOWN) {
				switch (event.getKeyCode()) {
				case KEYCODE_BYPASS_PLAY:
					onPlay();
					break;
				case KEYCODE_BYPASS_PAUSE:
					onPause();
					break;
				case KeyEvent.KEYCODE_MEDIA_NEXT:
					onSkipToNext();
					break;
				case KeyEvent.KEYCODE_MEDIA_PREVIOUS:
					onSkipToPrevious();
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
				// The remaining cases are for media button clicks.
				// Unfortunately Android reroutes media button clicks to PLAY/PAUSE
				// events making them indistinguishable from from play/pause button presses.
				// We do our best to distinguish...
				case KeyEvent.KEYCODE_MEDIA_PLAY:
					// If you press the media button while in the pause state, it resumes.
					MediaControllerCompat controller = mediaSession.getController();
					if (resumeOnClick && controller.getPlaybackState().getState() == PlaybackStateCompat.STATE_PAUSED) {
						onPlay();
						break;
					}
					// Otherwise fall through and pass it to onClick
				case KeyEvent.KEYCODE_MEDIA_PAUSE:
				// These are the "genuine" media button click events
				case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
				case KeyEvent.KEYCODE_HEADSETHOOK:
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
			unregisterNoisyReceiver();
			stopForeground(false);
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
	}

	public static interface ServiceListener {
		// Use a null parentMediaId to get the children of root
		void onLoadChildren(String parentMediaId, Result<List<MediaBrowserCompat.MediaItem>> result);

		void onAudioFocusGained();
		void onAudioFocusLost();
		void onAudioFocusLostTransient();
		void onAudioFocusLostTransientCanDuck();
		void onAudioBecomingNoisy();

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
		void onSeekTo(long pos);
		//void onSetRating(RatingCompat rating);
		//void onSetRepeatMode(@PlaybackStateCompat.RepeatMode int repeatMode)
		//void onSetShuffleModeEnabled(boolean enabled);
		//void onSetShuffleMode(@PlaybackStateCompat.ShuffleMode int shuffleMode);
		//void onCustomAction(String action, Bundle extras);
		void onAddQueueItem(MediaMetadataCompat metadata);
		void onAddQueueItemAt(MediaMetadataCompat metadata, int index);
		void onRemoveQueueItem(MediaMetadataCompat metadata);
	}
}
