#import "Camera2Plugin.h"
#if __has_include(<camera2/camera2-Swift.h>)
#import <camera2/camera2-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "camera2-Swift.h"
#endif

@implementation Camera2Plugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftCamera2Plugin registerWithRegistrar:registrar];
}
@end
