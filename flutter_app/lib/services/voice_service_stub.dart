// Copyright (c) 2026, the Flutter Agent Harness authors.
// Use of this source code is governed by a MIT license that can be found
// in the LICENSE file.

import 'package:fa/services/voice_service.dart';

/// No-op stub for non-Android platforms.
VoiceService createVoiceService() => const _StubVoiceService();

final class _StubVoiceService implements VoiceService {
  const _StubVoiceService();

  @override
  bool get isSupported => false;

  @override
  Future<void> setEnabled({required bool enabled}) async {}

  @override
  Future<void> speak(String text) async {}

  @override
  Stream<VoiceEvent> get events => const Stream.empty();
}
