@JS('navigator.mediaSession')
library media_session_web;

import 'dart:html' as html;

import 'package:js/js.dart';

@JS('setActionHandler')
external void setActionHandler(String action, Function(ActionResult) callback);

@JS('setPositionState')
external void setPositionState(PositionState state);

@JS()
@anonymous
class ActionResult {
  external String get action;
  external double get seekTime;

  external factory ActionResult({String? action, double? seekTime});
}

@JS()
@anonymous
class PositionState {
  external double get duration;
  external double get playbackRate;
  external double get position;
  external factory PositionState({
    double? duration,
    double? playbackRate,
    double? position,
  });
}

@JS('metadata')
external set metadata(html.MediaMetadata metadata);

// TODO: document this also create a library-level doc comment (dartdoc shows a warning related to this)
