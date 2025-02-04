#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'audio_service'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin to play audio in the background while the screen is off.'
  s.description      = <<-DESC
Flutter plugin to play audio in the background while the screen is off.
                       DESC
  s.homepage         = 'https://github.com/ryanheise/audio_service'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ryan Heise' => 'ryan@ryanheise.com' }
  s.source           = { :path => '.' }
  s.source_files = 'audio_service/Sources/audio_service/**/*.{h,m}'
  s.public_header_files = 'audio_service/Sources/audio_service/include/**/*.h'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end

