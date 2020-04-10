#import "AudioServicePlugin.h"
#if __has_include(<audio_service/audio_service-Swift.h>)
#import <audio_service/audio_service-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "audio_service-Swift.h"
#endif

@implementation AudioServicePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftAudioServicePlugin registerWithRegistrar:registrar];
}
@end
