package dev.fa1.app.mobile

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/// Voice channel: Android SpeechRecognizer (STT) + TextToSpeech (TTS)
/// MethodChannel  : dev.fa1.app/voice
/// EventChannel   : dev.fa1.app/voice_events  → {type, text} maps
///
/// Stop phrases: "стоп голос" / "выключи голос" disable listening without
/// a Dart round-trip.
object VoiceChannel {
    private const val METHOD_CH = "dev.fa1.app/voice"
    private const val EVENT_CH  = "dev.fa1.app/voice_events"

    private var tts: TextToSpeech? = null
    private var stt: SpeechRecognizer? = null
    private var eventSink: EventChannel.EventSink? = null
    @Volatile private var voiceEnabled = false

    fun register(messenger: BinaryMessenger, context: Context) {
        // TTS — initialise once; prefer Russian locale, fall back to default
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val ruRU = Locale("ru", "RU")
                tts?.language = if (tts?.isLanguageAvailable(ruRU) == TextToSpeech.LANG_AVAILABLE
                        || tts?.isLanguageAvailable(ruRU) == TextToSpeech.LANG_COUNTRY_AVAILABLE)
                    ruRU else Locale.getDefault()
            }
        }

        // Event stream — STT results flow here
        EventChannel(messenger, EVENT_CH).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                }
                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            }
        )

        // Method channel — control surface
        MethodChannel(messenger, METHOD_CH).setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    if (!voiceEnabled) { result.success(false); return@setMethodCallHandler }
                    startStt(context)
                    result.success(true)
                }
                "stopListening" -> {
                    stt?.stopListening()
                    result.success(null)
                }
                "speak" -> {
                    val text = call.argument<String>("text") ?: ""
                    tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "fa_tts")
                    result.success(null)
                }
                "setVoiceEnabled" -> {
                    voiceEnabled = call.argument<Boolean>("enabled") ?: true
                    if (!voiceEnabled) stt?.stopListening()
                    result.success(null)
                }
                "isAvailable" ->
                    result.success(SpeechRecognizer.isRecognitionAvailable(context))
                else -> result.notImplemented()
            }
        }
    }

    fun destroy() {
        stt?.destroy();  stt = null
        tts?.shutdown(); tts = null
    }

    private fun startStt(context: Context) {
        stt?.destroy()
        stt = SpeechRecognizer.createSpeechRecognizer(context).also { sr ->
            sr.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(p: Bundle?) = send("ready", "")
                override fun onBeginningOfSpeech()        = send("begin", "")
                override fun onEndOfSpeech()              = send("end", "")
                override fun onRmsChanged(v: Float)       {}
                override fun onBufferReceived(b: ByteArray?) {}
                override fun onEvent(type: Int, p: Bundle?) {}

                override fun onError(errorCode: Int) {
                    send("error", errorCode.toString())
                    // auto-restart on recognizer errors if still enabled
                    if (voiceEnabled) startStt(context)
                }

                override fun onPartialResults(b: Bundle?) {
                    val text = b?.getStringArrayList(
                        SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
                    send("partial", text)
                }

                override fun onResults(b: Bundle?) {
                    val text = b?.getStringArrayList(
                        SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
                    val lower = text.lowercase()
                    if (lower.contains("стоп голос") || lower.contains("выключи голос")) {
                        voiceEnabled = false
                        stt?.stopListening()
                        send("disabled", text)
                        return
                    }
                    send("result", text)
                    // continuous mode: restart for next utterance
                    if (voiceEnabled) startStt(context)
                }
            })

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }
            sr.startListening(intent)
        }
    }

    private fun send(type: String, text: String) {
        eventSink?.success(mapOf("type" to type, "text" to text))
    }
}
