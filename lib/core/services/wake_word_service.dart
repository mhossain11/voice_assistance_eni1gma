import 'dart:async';

import 'package:flutter/services.dart';

abstract class WakeWordService {
  Future<void> initialize();
  Future<void> start();
  Future<void> stop();
  Stream<void> get wakeWordDetected;
  Stream<WakeWordServiceState> get serviceStates;
  Stream<String> get errors;
  Future<WakeWordServiceState> getServiceState();
  Future<void> dispose();
}

enum WakeWordServiceState { stopped, starting, listening, paused, stopping }

class WakeWordException implements Exception {
  const WakeWordException(this.message);
  final String message;
}

class NativeWakeWordService implements WakeWordService {
  static const _methods = MethodChannel('com.en1gma/wake_word');
  static const _events = EventChannel('com.en1gma/wake_word_events');
  final StreamController<void> _detections = StreamController.broadcast();
  final StreamController<WakeWordServiceState> _states =
      StreamController.broadcast();
  final StreamController<String> _errors = StreamController.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;
  bool _initialized = false;
  bool _pendingWake = false;
  WakeWordServiceState _state = WakeWordServiceState.stopped;

  NativeWakeWordService() {
    _detections.onListen = () {
      if (_pendingWake) {
        _pendingWake = false;
        scheduleMicrotask(() => _detections.add(null));
      }
    };
  }

  @override
  Stream<void> get wakeWordDetected => _detections.stream;
  @override
  Stream<WakeWordServiceState> get serviceStates => _states.stream;
  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final initialState = await _methods.invokeMethod<String>('initialize');
      _setState(_stateFromWire(initialState));
      _eventSubscription = _events.receiveBroadcastStream().listen((event) {
        if (event == 'enigma' || event == 'wake_word_detected') {
          if (_detections.hasListener) {
            _detections.add(null);
          } else {
            _pendingWake = true;
          }
        } else if (event is Map) {
          final type = event['event'];
          if (type == 'wake_word_detected') {
            if (_detections.hasListener) {
              _detections.add(null);
            } else {
              _pendingWake = true;
            }
          } else if (type == 'service_state_changed') {
            _setState(_stateFromWire(event['state'] as String?));
          } else if (type == 'service_error') {
            _errors.add(event['message'] as String? ?? 'Wake-word service error.');
          }
        }
      }, onError: (Object error) => _errors.add(error.toString()));
      _initialized = true;
    } on PlatformException catch (error) {
      throw WakeWordException(
        error.message ?? 'Wake-word initialization failed.',
      );
    }
  }

  @override
  Future<void> start() async {
    await initialize();
    try {
      await _methods.invokeMethod<void>('startWakeWord');
    } on PlatformException catch (error) {
      throw WakeWordException(
        error.message ?? 'Could not start microphone listening.',
      );
    }
  }

  @override
  Future<void> stop() async {
    if (_initialized) await _methods.invokeMethod<void>('pauseWakeWord');
  }

  @override
  Future<WakeWordServiceState> getServiceState() async {
    await initialize();
    try {
      final wire = await _methods.invokeMethod<String>('getWakeWordServiceState');
      _setState(_stateFromWire(wire));
      return _state;
    } on PlatformException catch (error) {
      throw WakeWordException(error.message ?? 'Could not read wake-word status.');
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _detections.close();
    await _states.close();
    await _errors.close();
  }

  WakeWordServiceState _stateFromWire(String? value) => switch (value) {
    'starting' => WakeWordServiceState.starting,
    'listening' => WakeWordServiceState.listening,
    'paused' => WakeWordServiceState.paused,
    'stopping' => WakeWordServiceState.stopping,
    _ => WakeWordServiceState.stopped,
  };

  void _setState(WakeWordServiceState value) {
    if (_state == value) return;
    _state = value;
    _states.add(value);
  }
}
