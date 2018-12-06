package com.ryanheise.audioservice;

import android.content.Intent;
import android.os.IBinder;
import android.content.Context;
import android.media.AudioManager;
import android.os.PowerManager;
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
import android.support.annotation.RequiresApi;

// TODO:
// - deep link to a specified route when user clicks on the notification
public class AudioService extends MediaBrowserServiceCompat implements AudioManager.OnAudioFocusChangeListener {
	private static final int NOTIFICATION_ID = 1124;
	private static final String MEDIA_ROOT_ID = "root";
	public static final int KEYCODE_BYPASS_PLAY = KeyEvent.KEYCODE_MUTE;
	public static final int KEYCODE_BYPASS_PAUSE = KeyEvent.KEYCODE_MEDIA_RECORD;

	private static volatile boolean running;
	static AudioService instance;
	private static boolean resumeOnClick;
	private static ServiceListener listener;
	static String notificationChannelName;
	static Integer notificationColor;
	static String notificationAndroidIcon;
	private static List<MediaSessionCompat.QueueItem> queue = new ArrayList<MediaSessionCompat.QueueItem>();
	private static int queueIndex = -1;
	private static Map<String,MediaMetadataCompat> mediaMetadataCache = new HashMap<>();

	public static synchronized void init(Context context, boolean resumeOnClick, String notificationChannelName, Integer notificationColor, String notificationAndroidIcon, List<MediaSessionCompat.QueueItem> queue, ServiceListener listener) {
		if (running)
			throw new IllegalStateException("AudioService already running");
		running = true;
		AudioService.listener = listener;
		AudioService.resumeOnClick = resumeOnClick;
		AudioService.notificationChannelName = notificationChannelName;
		AudioService.notificationColor = notificationColor;
		AudioService.notificationAndroidIcon = notificationAndroidIcon;
		AudioService.queue = queue;
		queueIndex = queue.isEmpty() ? -1 : 0;
	}

	public void stop() {
		queue.clear();
		queueIndex = -1;
		mediaSession.setQueue(queue);
		instance.abandonAudioFocus();
		unregisterNoisyReceiver();
		mediaSession.setActive(false);
		if (wakeLock.isHeld()) wakeLock.release();
		stopForeground(true);
		stopSelf();
		running = false;
	}

	public void pause() {
		unregisterNoisyReceiver();
		stopForeground(false);
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

	void setState(List<NotificationCompat.Action> actions, int actionBits, int playbackState, long position, float speed, long updateTime) {
		this.actions = actions;
		updateNotification();

		PlaybackStateCompat.Builder stateBuilder = new PlaybackStateCompat.Builder()
			.setActions(PlaybackStateCompat.ACTION_PLAY_PAUSE|actionBits)
			.setState(playbackState, position, speed, updateTime);
		mediaSession.setPlaybackState(stateBuilder.build());
	}

	private Notification buildNotification() {
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
			createChannel();
		int iconId = getResourceId(notificationAndroidIcon);
		int[] actionIndices = new int[Math.min(3, actions.size())];
		for (int i = 0; i < actionIndices.length; i++) actionIndices[i] = i;
		MediaControllerCompat controller = mediaSession.getController();
		String contentTitle = "";
		String contentText = "";
		if (mediaMetadata != null) {
			MediaDescriptionCompat description = mediaMetadata.getDescription();
			contentTitle = description.getTitle().toString();
			contentText = description.getSubtitle().toString();
		}
		NotificationCompat.Builder builder = new NotificationCompat.Builder(AudioService.this, notificationChannelId)
				.setSmallIcon(iconId)
				.setContentTitle(contentTitle)
				.setContentText(contentText)
				.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
				//.setContentIntent(controller.getSessionActivity())

				.setDeleteIntent(buildMediaButtonPendingIntent(PlaybackStateCompat.ACTION_STOP))
				;
		if (notificationColor != null)
			builder.setColor(notificationColor);
		for (NotificationCompat.Action action : actions) {
			builder.addAction(action);
		}
		builder.setStyle(new MediaStyle()
				.setMediaSession(mediaSession.getSessionToken())
				.setShowActionsInCompactView(actionIndices)
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
			channel = new NotificationChannel(notificationChannelId, notificationChannelName, NotificationManager.IMPORTANCE_LOW);
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

	static MediaMetadataCompat createMediaMetadata(Map<?,?> rawMediaItem) {
		return createMediaMetadata((String)rawMediaItem.get("id"), (String)rawMediaItem.get("album"), (String)rawMediaItem.get("title"));
	}

	static MediaMetadataCompat createMediaMetadata(String mediaId, String album, String title) {
		MediaMetadataCompat mediaMetadata = new MediaMetadataCompat.Builder()
			.putString(MediaMetadataCompat.METADATA_KEY_MEDIA_ID, mediaId)
			.putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
			// TODO: Support the following metadata
			//.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
			//.putLong(MediaMetadataCompat.METADATA_KEY_DURATION,
			//		TimeUnit.MILLISECONDS.convert(duration, durationUnit))
			//.putString(MediaMetadataCompat.METADATA_KEY_GENRE, genre)
			//.putString(
			//		MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI,
			//		getAlbumArtUri(albumArtResName))
			//.putString(
			//		MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI,
			//		getAlbumArtUri(albumArtResName))
			.putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
			.build();
		mediaMetadataCache.put(mediaId, mediaMetadata);
		return mediaMetadata;
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

	void setQueue(List<MediaSessionCompat.QueueItem> queue) {
		this.queue = queue;
		mediaSession.setQueue(queue);
	}

	void setMetadata(MediaMetadataCompat mediaMetadata) {
		this.mediaMetadata = mediaMetadata;
		mediaSession.setMetadata(mediaMetadata);
	}

	@Override
	public BrowserRoot onGetRoot(String clientPackageName, int clientUid, Bundle rootHints) {
		return new BrowserRoot(MEDIA_ROOT_ID, null);
	}

	@Override
	public void onLoadChildren(final String parentMediaId, final Result<List<MediaBrowserCompat.MediaItem>> result) {
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
			listener.onAddQueueItem(description.getMediaId());
		}

		@Override
		public void onAddQueueItem(MediaDescriptionCompat description, int index) {
			listener.onAddQueueItemAt(description.getMediaId(), index);
		}

		@Override
		public void onRemoveQueueItem(MediaDescriptionCompat description) {
			listener.onRemoveQueueItem(description.getMediaId());
		}

		@Override
		public void onPrepare() {
			if (!mediaSession.isActive())
				mediaSession.setActive(true);
			listener.onPrepare();
		}

		@Override
		public void onPlay() {
			play(new Runnable() {
				public void run() {
					listener.doTask(AudioService.this);
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
			startForeground(NOTIFICATION_ID, buildNotification());
		}

		@Override
		public void onPrepareFromMediaId(String mediaId, Bundle extras) {
			if (!mediaSession.isActive())
				mediaSession.setActive(true);
			listener.onPrepareFromMediaId(mediaId);
		}

		@Override
		public void onPlayFromMediaId(final String mediaId, final Bundle extras) {
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
			listener.onPause();
		}

		@Override
		public void onStop() {
			listener.onStop();
		}

		@Override
		public void onSkipToNext() {
			listener.onSkipToNext();
		}

		@Override
		public void onSkipToPrevious() {
			listener.onSkipToPrevious();
		}

		@Override
		public void onSkipToQueueItem(long id) {
			listener.onSkipToQueueItem(id);
		}

		@Override
		public void onSeekTo(long pos) {
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

		void doTask(Context context);
		void onClick(MediaControl mediaControl);
		void onPrepare();
		void onPrepareFromMediaId(String mediaId);
		//void onPrepareFromSearch(String query);
		//void onPrepareFromUri(String uri);
		void onPlayFromMediaId(String mediaId);
		//void onPlayFromSearch(String query, Map<?,?> extras);
		//void onPlayFromUri(String uri, Map<?,?> extras);
		void onSkipToQueueItem(long id);
		void onPause();
		void onSkipToNext();
		void onSkipToPrevious();
		//void onFastForward();
		//void onRewind();
		void onStop();
		void onSeekTo(long pos);
		//void onSetRating(RatingCompat rating);
		//void onSetRepeatMode(@PlaybackStateCompat.RepeatMode int repeatMode)
		//void onSetShuffleModeEnabled(boolean enabled);
		//void onSetShuffleMode(@PlaybackStateCompat.ShuffleMode int shuffleMode);
		//void onCustomAction(String action, Bundle extras);
		void onAddQueueItem(String mediaId);
		void onAddQueueItemAt(String mediaId, int index);
		void onRemoveQueueItem(String mediaId);
	}
}
