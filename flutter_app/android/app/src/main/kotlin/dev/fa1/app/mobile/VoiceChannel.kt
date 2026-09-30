package dev.fa1.app.mobile

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

object VoiceChannel {
    private const val METHOD_CH = "dev.fa1.app/voice"
    private const val EVENT_CH  = "dev.fa1.app/voice_events"
    private const val MIC_REQUEST_CODE = 4242

    private var tts: TextToSpeech? = null
    private var stt: SpeechRecognizer? = null
    private var eventSink: EventChannel.EventSink? = null
    @Volatile private var voiceEnabled = false
    private var activity: Activity? = null

    fun register(messenger: BinaryMessenger, context: Context, activity: Activity) {
        this.activity = activity

        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val ruRU = Locale("ru", "RU")
                tts?.language = if (
                    tts?.isLanguageAvailable(ruRU) == TextToSpeech.LANG_AVAILABLE ||
                    tts?.isLanguageAvailable(ruRU) == TextToSpeech.LANG_COUNTRY_AVAILABLE
                ) ruRU else Locale.getDefault()
            }
        }

        EventChannel(messenger, EVENT_CH).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) { eventSink = sink }
                override fun onCancel(args: Any?) { eventSink = null }
            }
        )

        MethodChannel(messenger, METHOD_CH).setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    if (!voiceEnabled) { result.success(false); return@setMethodCallHandler }
                    if (!hasMicPermission(context)) {
                        requestMicPermission()
                        send("permission_required", "")
                        result.success(false)
                        return@setMethodCallHandler
                    }
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
        activity = null
    }

    private fun hasMicPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestMicPermission() {
        val act = activity ?: return
        ActivityCompat.requestPermissions(
            act,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            MIC_REQUEST_CODE,
        )
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
                    // ERROR_INSUFFICIENT_PERMISSIONS (9) — stop the loop immediately
                    if (errorCode == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ||
                        !hasMicPermission(context)
                    ) {
                        voiceEnabled = false
                        send("permission_required", errorCode.toString())
                        requestMicPermission()
                        return
                    }
                    send("error", errorCode.toString())
                    // auto-restart only for transient errors while still enabled
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
