import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:rxdart/rxdart.dart';

/// A stub wrapper that ensures that the [value] was called
/// only once and only once during the tests, until the new value is set.
///
/// Automatically disposes stream controllers and subjects.
class _Stub<T> {
  int _count = 0;

  T? _value;
  T get value {
    assert(_count != 0, "Stub was not set");
    assert(
      _count == 1,
      "Stub value was used more than once"
      "Update the stub value if you want to use it once more",
    );
    _count += 1;
    return _value!;
  }

  T get exposeValue {
    assert(_count != 0, "Stub was not set");
    return _value!;
  }

  set value(T newValue) {
    _value = newValue;
    _count = 1;
  }

  void reset() {
    _count = 0;
    _value = null;
    final value = _value;
    if (value is StreamController) {
      value.close();
    }
  }
}

class MockBaseAudioHandler implements BaseAudioHandler {
  final List<String> log = [];
  final List<Object?> argumentsLog = [];

  final _Stub<BehaviorSubject<PlaybackState>> _stubPlaybackState = _Stub();
  BehaviorSubject<PlaybackState> get stubPlaybackState =>
      _stubPlaybackState.exposeValue;
  set stubPlaybackState(BehaviorSubject<PlaybackState> value) {
    _stubPlaybackState.value = value;
  }

  final _Stub<BehaviorSubject<List<MediaItem>>> _stubQueue = _Stub();
  BehaviorSubject<List<MediaItem>> get stubQueue => _stubQueue.exposeValue;
  set stubQueue(BehaviorSubject<List<MediaItem>> value) {
    _stubQueue.value = value;
  }

  final _Stub<BehaviorSubject<String>> _stubQueueTitle = _Stub();
  BehaviorSubject<String> get stubQueueTitle => _stubQueueTitle.exposeValue;
  set stubQueueTitle(BehaviorSubject<String> value) {
    _stubQueueTitle.value = value;
  }

  final _Stub<BehaviorSubject<MediaItem?>> _stubMediaItem = _Stub();
  BehaviorSubject<MediaItem?> get stubMediaItem => _stubMediaItem.exposeValue;
  set stubMediaItem(BehaviorSubject<MediaItem?> value) {
    _stubMediaItem.value = value;
  }

  final _Stub<BehaviorSubject<RatingStyle>> _stubRatingStyle = _Stub();
  BehaviorSubject<RatingStyle> get stubRatingStyle =>
      _stubRatingStyle.exposeValue;
  set stubRatingStyle(BehaviorSubject<RatingStyle> value) {
    _stubRatingStyle.value = value;
  }

  final _Stub<BehaviorSubject<AndroidPlaybackInfo>> _stubAndroidPlaybackInfo =
      _Stub();
  BehaviorSubject<AndroidPlaybackInfo> get stubAndroidPlaybackInfo =>
      _stubAndroidPlaybackInfo.exposeValue;
  set stubAndroidPlaybackInfo(BehaviorSubject<AndroidPlaybackInfo> value) {
    _stubAndroidPlaybackInfo.value = value;
  }

  final _Stub<PublishSubject<Object?>> _stubCustomEvent = _Stub();
  PublishSubject<Object?> get stubCustomEvent => _stubCustomEvent.exposeValue;
  set stubCustomEvent(PublishSubject<Object?> value) {
    _stubCustomEvent.value = value;
  }

  final _Stub<BehaviorSubject<Object?>> _stubCustomState = _Stub();
  BehaviorSubject<Object?> get stubCustomState => _stubCustomState.exposeValue;
  set stubCustomState(BehaviorSubject<Object?> value) {
    _stubCustomState.value = value;
  }

  final _Stub<Object?> _stubCustomAction = _Stub();
  Object? get stubCustomAction => _stubCustomAction.exposeValue;
  set stubCustomAction(Object? value) {
    _stubCustomAction.value = value;
  }

  final _Stub<List<MediaItem>> _stubGetChildren = _Stub();
  List<MediaItem> get stubGetChildren => _stubGetChildren.exposeValue;
  set stubGetChildren(List<MediaItem> value) {
    _stubGetChildren.value = value;
  }

  final _Stub<BehaviorSubject<Map<String, dynamic>>> _stubSubscribeToChildren =
      _Stub();
  BehaviorSubject<Map<String, dynamic>> get stubSubscribeToChildren =>
      _stubSubscribeToChildren.exposeValue;
  set stubSubscribeToChildren(BehaviorSubject<Map<String, dynamic>> value) {
    _stubSubscribeToChildren.value = value;
  }

  final _Stub<MediaItem?> _stubGetMediaItem = _Stub();
  MediaItem? get stubGetMediaItem => _stubGetMediaItem.exposeValue;
  set stubGetMediaItem(MediaItem? value) {
    _stubGetMediaItem.value = value;
  }

  final _Stub<List<MediaItem>> _stubSearch = _Stub();
  List<MediaItem> get stubSearch => _stubSearch.exposeValue;
  set stubSearch(List<MediaItem> value) {
    _stubSearch.value = value;
  }

  void reset() {
    _stubPlaybackState.reset();
    _stubQueue.reset();
    _stubQueueTitle.reset();
    _stubMediaItem.reset();
    _stubRatingStyle.reset();
    _stubAndroidPlaybackInfo.reset();
    _stubCustomEvent.reset();
    _stubCustomState.reset();
    _stubCustomAction.reset();
    _stubGetChildren.reset();
    _stubSubscribeToChildren.reset();
    _stubGetMediaItem.reset();
    _stubSearch.reset();
    log.clear();
    argumentsLog.clear();
  }

  void _log(String method, [List<Object?> arguments = const [null]]) {
    log.add(method);
    argumentsLog.add(arguments);
  }

  @override
  BehaviorSubject<PlaybackState> get playbackState {
    _log('playbackState');
    return _stubPlaybackState.value;
  }

  @override
  BehaviorSubject<List<MediaItem>> get queue {
    _log('queue');
    return _stubQueue.value;
  }

  @override
  BehaviorSubject<String> get queueTitle {
    _log('queueTitle');
    return _stubQueueTitle.value;
  }

  @override
  BehaviorSubject<MediaItem?> get mediaItem {
    _log('mediaItem');
    return _stubMediaItem.value;
  }

  @override
  BehaviorSubject<RatingStyle> get ratingStyle {
    _log('ratingStyle');
    return _stubRatingStyle.value;
  }

  @override
  BehaviorSubject<AndroidPlaybackInfo> get androidPlaybackInfo {
    _log('androidPlaybackInfo');
    return _stubAndroidPlaybackInfo.value;
  }

  @override
  PublishSubject<dynamic> get customEvent {
    _log('customEvent');
    return _stubCustomEvent.value;
  }

  @override
  BehaviorSubject<dynamic> get customState {
    _log('customState');
    return _stubCustomState.value;
  }

  @override
  Future<void> prepare() async {
    _log('prepare');
  }

  @override
  Future<void> prepareFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    _log('prepareFromMediaId', [mediaId, extras]);
  }

  @override
  Future<void> prepareFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    _log('prepareFromSearch', [query, extras]);
  }

  @override
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic>? extras]) async {
    _log('prepareFromUri', [uri, extras]);
  }

  @override
  Future<void> play() async {
    _log('play');
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    _log('playFromMediaId', [mediaId, extras]);
  }

  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    _log('playFromSearch', [query, extras]);
  }

  @override
  Future<void> playFromUri(Uri uri, [Map<String, dynamic>? extras]) async {
    _log('playFromUri', [uri, extras]);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    _log('playMediaItem', [mediaItem]);
  }

  @override
  Future<void> pause() async {
    _log('pause');
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    _log('click', [button]);
  }

  @override
  Future<void> stop() async {
    _log('stop');
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    _log('addQueueItem', [mediaItem]);
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    _log('addQueueItems', [mediaItems]);
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    _log('insertQueueItem', [index, mediaItem]);
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    _log('updateQueue', [queue]);
  }

  @override
  Future<void> updateMediaItem(MediaItem mediaItem) async {
    _log('updateMediaItem', [mediaItem]);
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    _log('removeQueueItem', [mediaItem]);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    _log('removeQueueItemAt', [index]);
  }

  @override
  Future<void> skipToNext() async {
    _log('skipToNext');
  }

  @override
  Future<void> skipToPrevious() async {
    _log('skipToPrevious');
  }

  @override
  Future<void> fastForward() async {
    _log('fastForward');
  }

  @override
  Future<void> rewind() async {
    _log('rewind');
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _log('skipToQueueItem', [index]);
  }

  @override
  Future<void> seek(Duration position) async {
    _log('seek', [position]);
  }

  @override
  Future<void> setRating(Rating rating, [Map<String, dynamic>? extras]) async {
    _log('setRating', [rating, extras]);
  }

  @override
  Future<void> setCaptioningEnabled(bool enabled) async {
    _log('setCaptioningEnabled', [enabled]);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _log('setRepeatMode', [repeatMode]);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _log('setShuffleMode', [shuffleMode]);
  }

  @override
  Future<void> seekBackward(bool begin) async {
    _log('seekBackward', [begin]);
  }

  @override
  Future<void> seekForward(bool begin) async {
    _log('seekForward', [begin]);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _log('setSpeed', [speed]);
  }

  @override
  Future<dynamic> customAction(
      String name, [Map<String, dynamic>? extras]) async {
    _log('customAction', [name, extras]);
    return _stubCustomAction.value;
  }

  @override
  Future<void> onTaskRemoved() async {
    _log('onTaskRemoved');
  }

  @override
  Future<void> onNotificationDeleted() async {
    _log('onNotificationDeleted');
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    _log('getChildren', [parentMediaId, options]);
    return _stubGetChildren.value;
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    _log('subscribeToChildren', [parentMediaId]);
    return _stubSubscribeToChildren.value;
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    _log('getMediaItem', [mediaId]);
    return _stubGetMediaItem.value;
  }

  @override
  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    _log('search', [query, extras]);
    return _stubSearch.value;
  }

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) async {
    _log('androidSetRemoteVolume', [volumeIndex]);
  }

  @override
  Future<void> androidAdjustRemoteVolume(
      AndroidVolumeDirection direction) async {
    _log('androidAdjustRemoteVolume', [direction]);
  }
}
