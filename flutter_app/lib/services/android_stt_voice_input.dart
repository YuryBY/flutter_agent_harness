// Copyright (c) 2026, the Flutter Agent Harness authors.
// Use of this source code is governed by a MIT license that can be found
// in the LICENSE file.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';

import 'package:fa_ui/fa_ui.dart' show FaChatVoiceInput;

bool get androidSttSupported => !kIsWeb && Platform.isAndroid;

final class AndroidSttVoiceInput implements FaChatVoiceInput {
  static const _method = MethodChannel('dev.fa1.app/voice');
  static const _events = EventChannel('dev.fa1.app/voice_events');

  Completer<String?>? _resultCompleter;
  StreamSubscription<dynamic>? _sub;
  String? _lastPartial;
  String? _finalText;

  @override
  bool get isAvailable => androidSttSupported;

  @override
  String? get unavailableReason => null;

  @override
  Future<bool> start() async {
    if (!androidSttSupported) return false;
    _lastPartial = null;
    _finalText = null;

    await _method.invokeMethod<void>('setVoiceEnabled', {'enabled': true});
    final ok = await _method.invokeMethod<bool>('startListening') ?? false;
    if (!ok) return false;

    _resultCompleter = Completer<String?>();
    _sub = _events.receiveBroadcastStream().listen(
      (dynamic raw) {
        if (raw is! Map) return;
        final type = raw['type']?.toString() ?? '';
        final text = raw['text']?.toString() ?? '';
        debugPrint('[AndroidSTT] type=$type text=$text');
        switch (type) {
          case 'partial':
            if (text.isNotEmpty) _lastPartial = text;
          case 'result':
            final best = text.isNotEmpty ? text : _lastPartial;
            if (best != null) _finalText = best;
            if (!(_resultCompleter?.isCompleted ?? true)) {
              _resultCompleter!.complete(best);
            }
          case 'error':
            if (!(_resultCompleter?.isCompleted ?? true)) {
              _resultCompleter!.complete(_lastPartial);
            }
          default:
            break;
        }
      },
      onError: (Object _) {
        if (!(_resultCompleter?.isCompleted ?? true)) {
          _resultCompleter!.complete(_lastPartial);
        }
      },
    );
    return true;
  }

  @override
  Future<String?> stopAndTranscribe() async {
    if (!androidSttSupported) return null;
    // Resolve immediately if we already have a final or partial result
    final best = _finalText ?? _lastPartial;
    if (best != null && !(_resultCompleter?.isCompleted ?? true)) {
      _resultCompleter!.complete(best);
    }
    await _method.invokeMethod<void>('stopListening');
    await _method.invokeMethod<void>('setVoiceEnabled', {'enabled': false});
    final result = await _resultCompleter?.future
        .timeout(const Duration(seconds: 5), onTimeout: () => _finalText ?? _lastPartial);
    debugPrint('[AndroidSTT] stopAndTranscribe → $result');
    await _cleanup();
    return result;
  }

  @override
  Future<void> cancel() async {
    if (!androidSttSupported) return;
    await _method.invokeMethod<void>('stopListening').catchError((_) {});
    await _method.invokeMethod<void>('setVoiceEnabled', {'enabled': false}).catchError((_) {});
    if (!(_resultCompleter?.isCompleted ?? true)) _resultCompleter!.complete(null);
    await _cleanup();
  }

  Future<void> _cleanup() async {
    await _sub?.cancel();
    _sub = null;
    _resultCompleter = null;
    _lastPartial = null;
    _finalText = null;
  }
}
