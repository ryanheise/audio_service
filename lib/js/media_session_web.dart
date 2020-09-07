@JS('navigator.mediaSession')
library media_session_web;

import 'package:js/js.dart';
import 'media_metadata.dart';

@JS('setActionHandler')
external void setActionHandler(String action, Function(ActionResult) callback);

@JS('setPositionState')
external void setPositionState(PositionState state);

@JS()
@anonymous
class ActionResult {
  external String get action;
  external double get seekTime;

  external factory ActionResult({String action, double seekTime});
}

@JS()
@anonymous
class PositionState {
  external double get duration;
  external double get playbackRate;
  external double get position;
  external factory PositionState({
    double duration,
    double playbackRate,
    double position,
  });
}

@JS('metadata')
external set metadata(MediaMetadata metadata);
