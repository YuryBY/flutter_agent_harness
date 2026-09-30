// Copyright (c) 2026, the Flutter Agent Harness authors.
// Use of this source code is governed by a MIT license that can be found
// in the LICENSE file.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'package:fa_ui/fa_ui.dart' show FaChatVoiceInput;

/// Whether the Android Voice channel is available on this platform.
bool get androidSttSupported => !kIsWeb && Platform.isAndroid;

/// [FaChatVoiceInput] backed by the native Android SpeechRecognizer
/// (`dev.fa1.app/voice` MethodChannel + `dev.fa1.app/voice_events`
/// EventChannel).
///
/// The composer calls [start] → user speaks → [stopAndTranscribe] returns
/// the recognised text directly from Android STT — no Whisper endpoint needed.
///
/// On non-Android platforms [isAvailable] is false so the composer hides
/// the mic button via the normal [FaChatVoiceInput] contract.
final class AndroidSttVoiceInput implements FaChatVoiceInput {
  static const _method = MethodChannel('dev.fa1.app/voice');
  static const _events = EventChannel('dev.fa1.app/voice_events');

  Completer<String?>? _resultCompleter;
  StreamSubscription<dynamic>? _sub;

  @override
  bool get isAvailable => androidSttSupported;

  @override
  String? get unavailableReason => null;

  @override
  Future<bool> start() async {
    if (!androidSttSupported) return false;

    // Enable the channel and start a single-utterance listen.
    await _method.invokeMethod<void>('setVoiceEnabled', {'enabled': true});
    final ok = await _method.invokeMethod<bool>('startListening') ?? false;
    if (!ok) return false;

    // Wire up the event stream — the completer resolves on the first
    // result (or error) and the subscription is cancelled in cancel().
    _resultCompleter = Completer<String?>();
    _sub = _events.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) return;
        final type = raw['type']?.toString() ?? '';
        final text = raw['text']?.toString() ?? '';
        switch (type) {
          case 'result':
            if (!(_resultCompleter?.isCompleted ?? true)) {
              _resultCompleter!.complete(text.isEmpty ? null : text);
            }
          case 'error':
            if (!(_resultCompleter?.isCompleted ?? true)) {
              _resultCompleter!.complete(null);
            }
          default:
            break;
        }
      },
      onError: (Object _) {
        if (!(_resultCompleter?.isCompleted ?? true)) {
          _resultCompleter!.complete(null);
        }
      },
    );
    return true;
  }

  @override
  Future<String?> stopAndTranscribe() async {
    if (!androidSttSupported) return null;
    // Stop the recognizer — the native side fires a final 'result' event.
    await _method.invokeMethod<void>('stopListening');
    await _method.invokeMethod<void>('setVoiceEnabled', {'enabled': false});
    // Wait up to 5 s for the result event; timeout → null.
    final result = await _resultCompleter?.future
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    await _cleanup();
    return result;
  }

  @override
  Future<void> cancel() async {
    if (!androidSttSupported) return;
    await _method.invokeMethod<void>('stopListening').catchError((_) {});
    await _method.invokeMethod<void>('setVoiceEnabled', {'enabled': false})
        .catchError((_) {});
    if (!(_resultCompleter?.isCompleted ?? true)) {
      _resultCompleter!.complete(null);
    }
    await _cleanup();
  }

  Future<void> _cleanup() async {
    await _sub?.cancel();
    _sub = null;
    _resultCompleter = null;
  }
}
