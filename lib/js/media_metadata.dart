@JS()
library media_metadata;

import 'package:js/js.dart';

@JS('MediaMetadata')
class MediaMetadata {
  external MediaMetadata(MetadataLiteral md);
}

@JS()
@anonymous
class MetadataLiteral {
  external String get title;
  external String get album;
  external String get artist;
  external List<MetadataArtwork> get artwork;
  external factory MetadataLiteral(
      {String title,
      String album,
      String artist,
      List<MetadataArtwork> artwork});
}

@JS()
@anonymous
class MetadataArtwork {
  external String get src;
  external String get sizes;
  external String get type;
  external factory MetadataArtwork({String src, String sizes, String type});
}
