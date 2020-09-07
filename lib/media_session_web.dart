@JS('navigator.mediaSession')
library media_session_web;

import 'package:js/js.dart';
import './media_metadata.dart';

@JS('setActionHandler')
external void setActionHandler(String action, Function(ActionResult) callback);

@JS('setPositionState')
external void setPositionState(PositionState state);

@JS()
@anonymous
class ActionResult {
  external String get action;
  external int get seekTime;

  external factory ActionResult({String action, int seekTime});
}

@JS()
@anonymous
class PositionState {
  external int get duration;
  external int get playbackRate;
  external int get position;
  external factory PositionState({
    int duration,
    int playbackRate,
    int position,
  });
}

@JS('metadata')
external set metadata(MediaMetadata metadata);
