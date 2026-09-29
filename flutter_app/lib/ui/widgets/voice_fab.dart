// Copyright (c) 2026, the Flutter Agent Harness authors.
// Use of this source code is governed by a MIT license that can be found
// in the LICENSE file.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:fa/services/voice_service.dart';

/// Whether this platform should show the voice FAB.
bool get _voiceSupported => !kIsWeb && Platform.isAndroid;

/// Floating mic button (🎤 / stop) for Android — activates the native
/// Android [VoiceService] (SpeechRecognizer + TextToSpeech).
///
/// * Tapping once starts continuous listening (green pulsing mic).
/// * Tapping again (or speaking "стоп голос") stops it (grey mic).
/// * Recognised speech is forwarded to the DAP Hub ws://127.0.0.1:8787.
///
/// Returns [SizedBox.shrink] on non-Android platforms (iOS, macOS, web).
class VoiceFab extends StatefulWidget {
  const VoiceFab({super.key});

  @override
  State<VoiceFab> createState() => _VoiceFabState();
}

class _VoiceFabState extends State<VoiceFab>
    with SingleTickerProviderStateMixin {
  late final VoiceService _voice;
  StreamSubscription<VoiceEvent>? _sub;
  bool _listening = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    if (_voiceSupported) {
      _voice = createVoiceService();
      _sub = _voice.events.listen(_onEvent);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _onEvent(VoiceEvent e) {
    if (!mounted) return;
    switch (e.kind) {
      case VoiceEventKind.disabled:
        setState(() => _listening = false);
        _pulse.stop();
        _showSnack('🎤 Voice disabled');
      case VoiceEventKind.result:
        // Show a brief snack with the recognised text
        _showSnack('🎤 "${e.text}"');
      case VoiceEventKind.error:
        if (_listening) {
          // SpeechRecognizer auto-restarts on error — keep UI consistent
        }
      default:
        break;
    }
  }

  void _showSnack(String msg) {
    final ctx = context;
    if (!ctx.mounted) return;
    ScaffoldMessenger.maybeOf(ctx)
        ?.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _toggle() async {
    if (!_voiceSupported) return;
    final next = !_listening;
    setState(() => _listening = next);
    if (next) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
    await _voice.setEnabled(enabled: next);
  }

  @override
  Widget build(BuildContext context) {
    if (!_voiceSupported) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = colorScheme.primary;
    final idleColor = colorScheme.onSurface.withValues(alpha: 0.5);

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final scale = _listening ? (1.0 + _pulse.value * 0.12) : 1.0;
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: FloatingActionButton(
        heroTag: 'voice_fab',
        tooltip: _listening ? 'Stop voice' : 'Start voice',
        backgroundColor: _listening
            ? activeColor
            : colorScheme.surfaceContainerHighest,
        foregroundColor: _listening ? colorScheme.onPrimary : idleColor,
        onPressed: _toggle,
        child: Icon(_listening ? Icons.mic : Icons.mic_none),
      ),
    );
  }
}
