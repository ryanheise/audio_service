import Flutter
import UIKit

public class SwiftAudioServicePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "audio_service", binaryMessenger: registrar.messenger())
    let instance = SwiftAudioServicePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
protocol PlayerActions {
    func play()
    func pause()
    func stop()
    func togglePlaying()
    func seek(to position: Double)
    func nextTrack()
    func previousTrack()
    func skipForward(interval: Double)
    func skipBackward(interval: Double)
}

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result("iOS " + UIDevice.current.systemVersion)
  }
}
