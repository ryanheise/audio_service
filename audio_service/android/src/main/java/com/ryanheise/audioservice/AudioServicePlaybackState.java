package com.ryanheise.audioservice;

import android.support.v4.media.session.PlaybackStateCompat;

import androidx.core.app.NotificationCompat;

import java.util.ArrayList;
import java.util.List;

class AudioServicePlaybackState {
    AudioProcessingState processingState = AudioProcessingState.idle;
    long actionBits;
    boolean playing = false;
    List<NotificationCompat.Action> actions = new ArrayList<>();
    int[] compactActionIndices;
    long position;
    long bufferedPosition;
    float speed;
    long updateTime;
    Integer errorCode;
    String errorMessage;
    int repeatMode = 0;
    int shuffleMode = 0;
    boolean captioningEnabled;
    Long queueIndex = -1L;

    int getPlaybackState() {
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
}
