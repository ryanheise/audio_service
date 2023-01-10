import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SwitchAudioHandler:', () {
    test('Can forward errors from inner audio handlers', () {
      InnerAudioHandlerA innerAudioHandlerA = InnerAudioHandlerA();
      InnerAudioHandlerB innerAudioHandlerB = InnerAudioHandlerB();

      _TestSwitchAudioHandler switchAudioHandler =
          _TestSwitchAudioHandler(innerAudioHandlerA, innerAudioHandlerB);

      DateTime updateTime = DateTime.now();

      switchAudioHandler.customAction('switchToHandler',
          <String, dynamic>{'handlerId': InnerAudioHandlerB.handlerId});

      innerAudioHandlerB.playbackState.add(PlaybackState(
        processingState: AudioProcessingState.loading,
        updateTime: updateTime,
      ));

      innerAudioHandlerB.playbackState.addError('Error occurred');

      expectLater(
        switchAudioHandler.playbackState,
        emitsInOrder(<dynamic>[
          emits(anything),
          PlaybackState(
            processingState: AudioProcessingState.loading,
            updateTime: updateTime,
          ),
          emitsError('Error occurred'),
        ]),
      );
    });
  });
}

class _TestSwitchAudioHandler extends SwitchAudioHandler {
  final InnerAudioHandlerA _innerAudioHandlerA;
  final InnerAudioHandlerB _innerAudioHandlerB;

  _TestSwitchAudioHandler(this._innerAudioHandlerA, this._innerAudioHandlerB)
      : super(_innerAudioHandlerA);

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'switchToHandler':
        stop();

        String handlerId = extras!['handlerId'] as String;

        if (handlerId == InnerAudioHandlerA.handlerId) {
          inner = _innerAudioHandlerA;
        }

        if (handlerId == InnerAudioHandlerB.handlerId) {
          inner = _innerAudioHandlerB;
        }

        return null;
      default:
        return super.customAction(name, extras);
    }
  }
}

class InnerAudioHandlerA extends BaseAudioHandler {
  static const handlerId = 'A';
}

class InnerAudioHandlerB extends BaseAudioHandler {
  static const handlerId = 'B';
}
