part of 'package:audio_service_platform_interface/audio_service_platform_interface.dart';

/// Casts `Map<dynamic, dynamic>` into `Map<String, dynamic>`.
/// 
/// Used mostly to unwrap [MethodCall.arguments] which in case with maps
/// is always `Map<Object?, Object?>`.
@pragma('vm:prefer-inline')
Map<String, dynamic>? _castMap(Map? map) => map?.cast<String, dynamic>();
