// Copyright (c) 2026, the Flutter Agent Harness authors.
// Use of this source code is governed by a MIT license that can be found
// in the LICENSE file.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';

import 'package:fa/services/voice_service.dart';

/// Whether this platform has the Android Voice channel wired in.
bool get voicePlatformSupported => !kIsWeb && Platform.isAndroid;

/// Creates the Android-backed [VoiceService].
VoiceService createVoiceService() => AndroidVoiceService();

/// [VoiceService] over `dev.fa1.app/voice` (MethodChannel) and
/// `dev.fa1.app/voice_events` (EventChannel).
///
/// Recognised utterances are forwarded to the DAP Hub at
/// `ws://127.0.0.1:8787` as plain-text user messages so the on-device
/// Fa agent can process them immediately.
///
/// Stop phrases ("стоп голос" / "выключи голос") are handled natively in
/// [VoiceChannel.kt]; the Dart side surfaces them as [VoiceEventKind.disabled].
final class AndroidVoiceService implements VoiceService {
  static const _method = MethodChannel('dev.fa1.app/voice');
  static const _events = EventChannel('dev.fa1.app/voice_events');

  /// DAP Hub WebSocket endpoint — ADB reverse-forwarded port 8787.
  static const _dapWs = 'ws://127.0.0.1:8787';

  final _controller = StreamController<VoiceEvent>.broadcast();

  IOWebSocketChannel? _ws;
  StreamSubscription<dynamic>? _eventSub;

  AndroidVoiceService() {
    _eventSub = _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (Object e) =>
          _controller.add(VoiceEvent(VoiceEventKind.error, e.toString())),
    );
  }

  @override
  bool get isSupported => voicePlatformSupported;

  @override
  Stream<VoiceEvent> get events => _controller.stream;

  @override
  Future<void> setEnabled({required bool enabled}) async {
    await _method.invokeMethod<void>('setVoiceEnabled', {'enabled': enabled});
    if (enabled) await _method.invokeMethod<void>('startListening');
  }

  @override
  Future<void> speak(String text) =>
      _method.invokeMethod<void>('speak', {'text': text});

  // ── private ──────────────────────────────────────────────────────────

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type']?.toString() ?? '';
    final text = raw['text']?.toString() ?? '';

    final kind = switch (type) {
      'result'   => VoiceEventKind.result,
      'partial'  => VoiceEventKind.partial,
      'disabled' => VoiceEventKind.disabled,
      'error'    => VoiceEventKind.error,
      _          => VoiceEventKind.status,
    };
    _controller.add(VoiceEvent(kind, text));

    // Forward final results to the DAP Hub
    if (kind == VoiceEventKind.result && text.isNotEmpty) {
      _sendToDap(text);
    }
  }

  Future<void> _sendToDap(String text) async {
    try {
      _ws ??= IOWebSocketChannel.connect(Uri.parse(_dapWs));
      _ws!.sink.add(text);
    } catch (_) {
      // Hub not reachable — drop silently; the agent is local anyway
      _ws = null;
    }
  }

  /// Call when the service is no longer needed (app shutdown / test teardown).
  Future<void> dispose() async {
    await _eventSub?.cancel();
    await _ws?.sink.close();
    await _controller.close();
  }
}
