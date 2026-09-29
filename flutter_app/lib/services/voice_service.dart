// Copyright (c) 2026, the Flutter Agent Harness authors.
// Use of this source code is governed by a MIT license that can be found
// in the LICENSE file.

export 'voice_service_stub.dart'
    if (dart.library.io) 'voice_service_android.dart';

/// Event kinds emitted by [VoiceService.events].
enum VoiceEventKind {
  /// A final STT result ready to be sent to the agent.
  result,

  /// Interim/partial hypothesis (for UI feedback).
  partial,

  /// Voice input was disabled by a stop phrase or [VoiceService.setEnabled].
  disabled,

  /// Recogniser error (text = error code string).
  error,

  /// Any other status update from the native side (ready, begin, end, …).
  status,
}

/// One event from the voice pipeline.
final class VoiceEvent {
  const VoiceEvent(this.kind, this.text);

  final VoiceEventKind kind;

  /// The transcript (or error code string for [VoiceEventKind.error]).
  final String text;

  @override
  String toString() => 'VoiceEvent($kind, "$text")';
}

/// Platform-independent voice service contract.
///
/// Platform implementations:
///   Android → [AndroidVoiceService] in `voice_service_android.dart`
///   others  → no-op stub in `voice_service_stub.dart`
abstract interface class VoiceService {
  /// Whether this platform can do STT/TTS at all.
  bool get isSupported;

  /// Stream of voice events (results, partials, errors, status).
  Stream<VoiceEvent> get events;

  /// Enable or disable continuous listening.
  Future<void> setEnabled({required bool enabled});

  /// Speak [text] via TTS.
  Future<void> speak(String text);
}
