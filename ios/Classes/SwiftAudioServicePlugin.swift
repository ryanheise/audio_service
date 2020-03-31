import Flutter
import UIKit
import AVFoundation
import MediaPlayer

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

public class SwiftAudioServicePlugin: NSObject, FlutterPlugin, PlayerActions {
    static var channel: FlutterMethodChannel?
    static var backgroundChannel: FlutterMethodChannel?
    static var startResult: FlutterResult?
    static private var running = false
    static var commandCenter: MPRemoteCommandCenter?
    static var queue:NSArray?
    static var mediaItem: [String: Any]?
    static var artwork:MPMediaItemArtwork?
    static var state: PlaybackState?
    static let audioSession = AVAudioSession.sharedInstance()
    static var remoteCommandController: RemoteCommandController?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        // TODO: Need a reliable way to detect whether this is the client
        // or background.
        if channel == nil {
            channel = FlutterMethodChannel(name: "ryanheise.com/audioService", binaryMessenger: registrar.messenger())
            let instance = SwiftAudioServicePlugin(registrar: registrar)
            registrar.addMethodCallDelegate(instance, channel: channel!)
        } else {
            backgroundChannel = FlutterMethodChannel(name: "ryanheise.com/audioServiceBackground", binaryMessenger: registrar.messenger())
            let instance = SwiftAudioServicePlugin(registrar: registrar)
            registrar.addMethodCallDelegate(instance, channel: backgroundChannel!)
        }
    }
    
    init(registrar: FlutterPluginRegistrar) {
        super.init()
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // TODO:
        // - Restructure this so that we have a separate method call delegate
        //   for the client instance and the background instance so that methods
        //   can't be called on the wrong instance.
        switch call.method {
        case "connect":
            connect()
            result(nil)
        case "disconnect":
            result(nil)
        case "start":
            start(result: result)
        case "ready":
            result(true)
            if let startResult = SwiftAudioServicePlugin.startResult {
                startResult(true)
            }
            SwiftAudioServicePlugin.startResult = nil
        case "stopped":
            stopped()
            result(true)
        case "isRunning":
            result(SwiftAudioServicePlugin.running)
        case "play":
            play()
            result(true)
        case "pause":
            pause()
            result(true)
        case "setState":
            setState(arguments: call.arguments)
            result(true)
        case "setQueue":
            setQueue(arguments: call.arguments)
            result(true)
        case "setMediaItem":
            setMediaItem(arguments: call.arguments)
            result(true)
            
        case "setRating":
            invokeOn(callMthod: call.method, arguments: [call.arguments,nil])
            result(true)
            
        case
        "addQueueItemAt":
            invokeOn(callMthod: call.method, arguments: call.arguments)
            result(true)
            
        case "addQueueItem",
             "removeQueueItem",
             "click",
             "prepareFromMediaId",
             "playFromMediaId",
             "skipToQueueItem":
            invokeOn(callMthod: call.method, arguments: [call.arguments])
            result(true)
            
        case "stop",
             "seekTo",
             "skipToNext",
             "skipToPrevious",
             "fastForward",
             "rewind",
             "prepare":
            invokeOn(callMthod: call.method, arguments: nil)
            result(true)
            
        case "notifyChildrenChanged",
             "androidForceEnableMediaButtons",
             "setBrowseMediaParent":
            result(true)
            
        default:
            SwiftAudioServicePlugin.backgroundChannel?.invokeMethod(call.method, arguments: call.arguments, result: result)
        }
    }
    
    func invokeOn(callMthod:String, arguments: Any?){
        var callMthod = callMthod
        let onMethod = ("on" + callMthod.removeFirst().uppercased() + callMthod);
        print(onMethod)
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod(onMethod, arguments: arguments)
    }
    
    func connect() {
        if SwiftAudioServicePlugin.state == nil {
            SwiftAudioServicePlugin.state = PlaybackState()
        }
        SwiftAudioServicePlugin.channel?.invokeMethod("onPlaybackStateChanged", arguments: SwiftAudioServicePlugin.state?.toArguments())
        SwiftAudioServicePlugin.channel?.invokeMethod("onMediaChanged", arguments: [SwiftAudioServicePlugin.mediaItem])
        SwiftAudioServicePlugin.channel?.invokeMethod("onQueueChanged", arguments: [SwiftAudioServicePlugin.queue])
    }
    
    func start(result: @escaping FlutterResult) {
        if SwiftAudioServicePlugin.running == true {
            result(false)
            return
        }
        SwiftAudioServicePlugin.running = true
        // The result will be sent after the background task actually starts.
        // See the "ready" case below.
        SwiftAudioServicePlugin.startResult = result
        do{
            try SwiftAudioServicePlugin.audioSession.setCategory(.playback)
            try SwiftAudioServicePlugin.audioSession.setActive(true)
            SwiftAudioServicePlugin.remoteCommandController = RemoteCommandController(playerActions: self)
        } catch {
            print(error)
        }
    }

    func stopped() {
        SwiftAudioServicePlugin.running = false
        SwiftAudioServicePlugin.channel?.invokeMethod("onStopped", arguments: nil)
        SwiftAudioServicePlugin.remoteCommandController?.disable(commands: RemoteCommand.all())
        SwiftAudioServicePlugin.remoteCommandController = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        do {
            try SwiftAudioServicePlugin.audioSession.setActive(false)
        } catch {
            print(error)
        }
    }

    func setState(arguments: Any?) {
        SwiftAudioServicePlugin.state = PlaybackState.init(arguments: arguments)
        SwiftAudioServicePlugin.remoteCommandController?.enable(commands: SwiftAudioServicePlugin.state?.controls ?? [])
        SwiftAudioServicePlugin.channel?.invokeMethod("onPlaybackStateChanged", arguments: SwiftAudioServicePlugin.state?.toArguments())
        updateNowPlayingInfo()
    }

    func setQueue(arguments: Any?){
        SwiftAudioServicePlugin.queue = arguments as? NSArray
        SwiftAudioServicePlugin.channel?.invokeMethod("onQueueChanged", arguments: [SwiftAudioServicePlugin.queue])
    }

    func setMediaItem(arguments: Any?) {
        SwiftAudioServicePlugin.mediaItem = arguments as? [String: Any]
        let artUri: String? = SwiftAudioServicePlugin.mediaItem?["artUri"] as? String
        if let stringUrl = artUri?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)  {
            if let url = URL(string: stringUrl) {
                DispatchQueue.global().async {
                    if let data = try? Data(contentsOf: url) {
                        if let artImage = UIImage(data: data) {
                            SwiftAudioServicePlugin.artwork = MPMediaItemArtwork(image: artImage)
                            self.updateNowPlayingInfo()
                        }
                    }
                }
            }
        }
        SwiftAudioServicePlugin.channel?.invokeMethod("onMediaChanged", arguments: [arguments])
    }
    
    func updateNowPlayingInfo(){
        var nowPlayingInfo: [String: Any] = [String: Any]()
        if let mediaItem = SwiftAudioServicePlugin.mediaItem {
            nowPlayingInfo[MPMediaItemPropertyTitle] = mediaItem["title"]
            nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = mediaItem["album"]
            if let duration = mediaItem["duration"] as? UInt64 {
                nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration / 1000
            }
            if let artwork = SwiftAudioServicePlugin.artwork {
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = (SwiftAudioServicePlugin.state?.position ?? 0) / 1000;
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = SwiftAudioServicePlugin.state?.state == .playing ? 1.0 : 0.0;
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    func play() {
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onPlay", arguments: nil)
    }
    
    func pause() {
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onPause", arguments: nil)
    }
    
    func stop() {
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onStop", arguments: nil)
    }
    
    func togglePlaying() {
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onClick", arguments: nil)
        
    }
    
    func seek(to position: Double) {
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onSeekTo", arguments: [UInt64(position)])
        
    }
    
    func nextTrack() {
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onSkipToNext", arguments: nil)
        
    }
    
    func previousTrack() {
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onSkipToPrevious", arguments: nil)
    }
    
    
    func skipForward(interval: Double) {
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onFastForward", arguments: nil)
    }
    
    func skipBackward(interval: Double){
        SwiftAudioServicePlugin.backgroundChannel?.invokeMethod("onRewind", arguments: nil)
    }
}
