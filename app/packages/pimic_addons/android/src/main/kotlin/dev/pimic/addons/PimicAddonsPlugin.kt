package dev.pimic.addons

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.Future
import java.util.concurrent.CancellationException
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.sqrt

/** Idle attachment only registers channels. No microphone, network, or permission work. */
class PimicAddonsPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener, Application.ActivityLifecycleCallbacks {
    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private val executor = ThreadPoolExecutor(2, 2, 0L, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue<Runnable>(2))
    private var binding: ActivityPluginBinding? = null
    private var sink: EventChannel.EventSink? = null
    private var sinkOwner: String? = null
    private var generation = 0L
    private var session: Session? = null
    private var pendingStart: MethodChannel.Result? = null
    private var pendingStartOwner: String? = null
    private var permissionOutstanding = false
    private var pendingInput: Int? = null
    private var importing: ImportOperation? = null
    private var pickerOutstanding = false
    private var attached = false

    private class Session(val generation: Long, val owner: String) {
        val stopped = AtomicBoolean(false)
        val cancelled = AtomicBoolean(false)
        val pcm = ByteArrayOutputStream()
        @Volatile var recorder: AudioRecord? = null
        @Volatile var input: Map<String, Any>? = null
        @Volatile var frames = 0
        @Volatile var limitReached = false
        @Volatile var complete = false
        @Volatile var wav: ByteArray? = null
        @Volatile var failure: String? = null
        var stopResult: MethodChannel.Result? = null
        val eventQueued = AtomicBoolean(false)
        @Volatile var lastEventDelivered = 0L
        @Volatile var latestLevel: Map<String, Any?>? = null
    }

    private class ImportOperation(val owner: String, var result: MethodChannel.Result?) {
        val reader = WavImportReader()
        var future: Future<*>? = null
        var started = false
        @Volatile var readerFinished = false
        @Volatile var closeFinished = true
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "pimic_addons/audio")
        events = EventChannel(binding.binaryMessenger, "pimic_addons/levels")
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        attached = true
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        cancelAll()
        detachActivity()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        sinkOwner = null
        executor.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
        binding.activity.application.registerActivityLifecycleCallbacks(this)
    }

    private fun detachActivity() {
        cancelAll()
        binding?.let {
            it.removeRequestPermissionsResultListener(this)
            it.removeActivityResultListener(this)
            it.activity.application.unregisterActivityLifecycleCallbacks(this)
        }
        binding = null
    }

    override fun onDetachedFromActivity() = detachActivity()
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val owner = (arguments as? Map<*, *>)?.get("owner") as? String
        if (owner.isNullOrBlank()) {
            events.error("invalid_owner", "Audio subscription requires an owner.", null)
            return
        }
        sinkOwner = owner
        sink = events
    }
    override fun onCancel(arguments: Any?) {
        val owner = (arguments as? Map<*, *>)?.get("owner") as? String
        if (owner != null && owner == sinkOwner) { sink = null; sinkOwner = null }
    }

    private fun allowed(device: AudioDeviceInfo) = device.isSource && device.type in setOf(
        AudioDeviceInfo.TYPE_BUILTIN_MIC, AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_ACCESSORY,
    )

    private fun inputMap(device: AudioDeviceInfo): Map<String, Any> = mapOf(
        "id" to device.id,
        "type" to when (device.type) {
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "builtIn"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wiredHeadset"
            AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "usb"
            else -> "unsupported"
        },
        "label" to device.productName.toString(),
    )

    private fun devices() = (context.getSystemService(Context.AUDIO_SERVICE) as AudioManager)
        .getDevices(AudioManager.GET_DEVICES_INPUTS).filter(::allowed)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "discoverInputs") {
            result.success(devices().map(::inputMap))
            return
        }
        val owner = call.argument<String>("owner")
        if (owner.isNullOrBlank()) {
            result.error("invalid_owner", "Audio operations require an owner.", null)
            return
        }
        when (call.method) {
            "startRecording" -> start(owner, call.argument<Number>("preferredInputId")?.toInt(), result)
            "stopRecording" -> stop(owner, result)
            "cancel", "dispose" -> { cancelAll(owner); result.success(null) }
            "importWav" -> importWav(owner, result)
            else -> result.notImplemented()
        }
    }

    private fun start(owner: String, preferredInput: Int?, result: MethodChannel.Result) {
        if (session != null || pendingStart != null || importing != null || pickerOutstanding || permissionOutstanding) {
            busyError(result)
            return
        }
        val activity = binding?.activity
        if (activity == null) {
            result.error("unavailable", "Recording requires a foreground Android activity.", null)
            return
        }
        if (preferredInput != null && devices().none { it.id == preferredInput }) {
            result.error("unavailable", "The selected microphone is no longer available.", null)
            return
        }
        pendingStart = result
        pendingStartOwner = owner
        pendingInput = preferredInput
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            permissionOutstanding = true
            activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST)
        } else {
            beginRecording()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        permissionOutstanding = false
        if (pendingStart == null) return true
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            beginRecording()
        } else {
            pendingStart?.error("permission_denied", "Microphone permission was denied.", null)
            pendingStart = null
            pendingStartOwner = null
            pendingInput = null
        }
        return true
    }

    private fun beginRecording() {
        val result = pendingStart ?: return
        val preferredInput = pendingInput
        val current = Session(++generation, pendingStartOwner ?: return)
        session = current
        executor.purge()
        try { executor.execute {
            try {
                val minimum = AudioRecord.getMinBufferSize(WavCodec.SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                check(minimum > 0) { "This device cannot record mono PCM16 at 16000 Hz." }
                val recorder = AudioRecord.Builder()
                    .setAudioSource(MediaRecorder.AudioSource.VOICE_RECOGNITION)
                    .setAudioFormat(AudioFormat.Builder().setSampleRate(WavCodec.SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
                    .setBufferSizeInBytes(maxOf(minimum * 2, 3200)).build()
                // Coordinate creation with cancellation so a late builder cannot reopen the mic.
                synchronized(current) {
                    if (current.cancelled.get()) { recorder.release(); return@execute }
                    current.recorder = recorder
                }
                check(recorder.state == AudioRecord.STATE_INITIALIZED) { "Microphone initialization failed." }
                if (preferredInput != null) {
                    val preferred = devices().firstOrNull { it.id == preferredInput }
                    check(preferred != null && recorder.setPreferredDevice(preferred)) {
                        "The selected microphone is no longer available."
                    }
                }
                synchronized(current) {
                    if (current.cancelled.get()) return@execute
                    recorder.startRecording()
                }
                main.post {
                    if (session === current && !current.cancelled.get() && pendingStart === result) {
                        pendingStart = null
                        pendingStartOwner = null
                        pendingInput = null
                        result.success(null)
                    }
                }
                val samples = ShortArray(800) // 50 ms: at most 20 level updates per second.
                var lastEvent = 0L
                while (!current.stopped.get() && !current.cancelled.get()) {
                    val read = recorder.read(samples, 0,
                        minOf(samples.size, WavCodec.MAX_FRAMES - current.frames), AudioRecord.READ_BLOCKING)
                    if (current.stopped.get() || current.cancelled.get()) break
                    check(read >= 0) { "The microphone became unavailable. Try reconnecting it." }
                    if (read == 0) continue
                    var squares = 0.0
                    for (index in 0 until read) {
                        val sample = samples[index].toInt()
                        current.pcm.write(sample and 0xff)
                        current.pcm.write((sample shr 8) and 0xff)
                        val normalized = sample / 32768.0
                        squares += normalized * normalized
                    }
                    current.frames += read
                    current.input = recorder.routedDevice?.let { device ->
                        check(allowed(device)) { "Choose a built-in, wired headset, or USB microphone." }
                        inputMap(device)
                    }
                    current.limitReached = current.frames >= WavCodec.MAX_FRAMES
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastEvent >= 50 || current.limitReached) {
                        lastEvent = now
                        queueLevel(current, sqrt(squares / read))
                    }
                    if (current.limitReached) break
                }
            } catch (_: SecurityException) {
                current.failure = "Microphone permission is unavailable."
            } catch (error: IllegalStateException) {
                if (!current.cancelled.get() && !current.stopped.get()) current.failure = error.message ?: "Recording failed."
            } catch (_: IllegalArgumentException) {
                current.failure = "The microphone does not support this recording format."
            } finally {
                release(current)
                if (!current.cancelled.get() && current.failure == null && current.frames > 0) {
                    current.wav = WavCodec.encode(current.pcm.toByteArray())
                }
                current.complete = true
                main.post {
                    if (session === current) {
                        if (current.cancelled.get()) { session = null; return@post }
                        if (pendingStart === result) {
                            pendingStart = null
                            pendingStartOwner = null
                            pendingInput = null
                            result.error("recording_failed", current.failure ?: "Recording was cancelled.", null)
                            session = null
                        }
                        if (current.failure != null && current.stopResult == null) {
                            if (sinkOwner == current.owner) sink?.error("recording_failed", current.failure, null)
                        }
                        current.stopResult?.let { finish(current, it) }
                    }
                }
            }
        } } catch (_: RejectedExecutionException) {
            session = null
            pendingStart = null
            pendingStartOwner = null
            pendingInput = null
            result.error("busy", "Previous audio resources are still closing. Try again shortly.", null)
        }
    }

    private fun queueLevel(current: Session, rms: Double) {
        current.latestLevel = mapOf("owner" to current.owner, "rms" to rms.coerceIn(0.0, 1.0), "input" to current.input,
            "frames" to current.frames, "durationMs" to current.frames * 1000L / WavCodec.SAMPLE_RATE,
            "limitReached" to current.limitReached)
        if (current.eventQueued.compareAndSet(false, true)) main.postDelayed({
            current.lastEventDelivered = SystemClock.elapsedRealtime()
            current.eventQueued.set(false)
            if (session === current && !current.cancelled.get() && sinkOwner == current.owner) sink?.success(current.latestLevel)
        }, maxOf(0L, 50L - (SystemClock.elapsedRealtime() - current.lastEventDelivered)))
    }

    private fun stop(owner: String, result: MethodChannel.Result) {
        val current = session
        if (current == null || current.owner != owner || current.cancelled.get() || pendingStart != null) {
            result.error("unavailable", "No active recording is ready to stop.", null)
            return
        }
        if (current.stopResult != null) {
            result.error("busy", "Recording is already stopping.", null)
            return
        }
        current.stopResult = result
        current.stopped.set(true)
        release(current)
        if (current.complete) finish(current, result)
    }

    private fun finish(current: Session, result: MethodChannel.Result) {
        current.stopResult = null
        session = null
        if (current.failure != null || current.frames == 0) {
            result.error("recording_failed", current.failure ?: "No audio was captured.", null)
            return
        }
        result.success(mapOf("wav" to current.wav,
            "frames" to current.frames, "durationMs" to current.frames * 1000L / WavCodec.SAMPLE_RATE,
            "input" to current.input))
    }

    private fun release(current: Session) {
        synchronized(current) {
            val recorder = current.recorder ?: return
            current.recorder = null
            try { recorder.stop() } catch (_: IllegalStateException) { /* Already stopped. */ }
            recorder.release()
        }
    }

    private fun cancelRecording(owner: String? = null) {
        ++generation
        session?.let {
            if (owner != null && owner != it.owner) return@let
            it.cancelled.set(true)
            it.stopped.set(true)
            release(it)
            it.stopResult?.error("cancelled", "Recording was cancelled.", null)
            it.stopResult = null
            // Keep the global busy guard until creation/read/final release finishes.
            if (it.complete) session = null
        }
        if (owner == null || pendingStartOwner == owner) {
            pendingStart?.error("cancelled", "Recording was cancelled.", null)
            pendingStart = null
            pendingStartOwner = null
            pendingInput = null
        }
    }

    private fun cancelAll(owner: String? = null) {
        cancelRecording(owner)
        cancelImport(owner)
    }

    private fun importWav(owner: String, result: MethodChannel.Result) {
        if (session != null || pendingStart != null || importing != null || pickerOutstanding || permissionOutstanding) {
            busyError(result)
            return
        }
        val activity = binding?.activity
        if (activity == null) {
            result.error("unavailable", "File import requires a foreground Android activity.", null)
            return
        }
        importing = ImportOperation(owner, result)
        pickerOutstanding = true
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/wav", "audio/x-wav", "audio/wave"))
            }, IMPORT_REQUEST)
        } catch (_: android.content.ActivityNotFoundException) {
            importing = null
            pickerOutstanding = false
            result.error("unavailable", "No document picker is available.", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != IMPORT_REQUEST) return false
        pickerOutstanding = false
        val operation = importing ?: return true
        val result = operation.result
        if (operation.reader.cancelled.get() || result == null) {
            importing = null
            return true
        }
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            importing = null
            result.success(null)
            return true
        }
        val uri = data.data!!
        executor.purge()
        try {
            operation.future = executor.submit {
                var audio: Map<String, Any?>? = null
                var failure: String? = null
                try {
                    synchronized(operation) {
                        if (operation.reader.cancelled.get()) throw CancellationException()
                        operation.started = true
                    }
                    val bytes = operation.reader.read { context.contentResolver.openInputStream(uri) }
                    val frames = WavCodec.validate(bytes)
                    audio = mapOf("wav" to bytes, "frames" to frames,
                        "durationMs" to frames * 1000L / WavCodec.SAMPLE_RATE, "input" to null)
                } catch (_: CancellationException) {
                    // Cancellation already completed the Dart result; discard every byte.
                } catch (error: IllegalArgumentException) {
                    failure = error.message ?: "Invalid WAV file."
                } catch (_: IOException) {
                    failure = "Unable to read the selected WAV file."
                } catch (_: SecurityException) {
                    failure = "Access to the selected file was denied."
                } finally {
                    operation.readerFinished = true
                    main.post {
                        if (importing === operation && attached && !operation.reader.cancelled.get()) {
                            operation.result = null
                            if (audio != null) result.success(audio)
                            else result.error("invalid_wav", failure ?: "Unable to import WAV.", null)
                        }
                        clearFinishedImport(operation)
                    }
                }
            }
        } catch (_: RejectedExecutionException) {
            importing = null
            result.error("busy", "Previous audio resources are still closing. Try again shortly.", null)
        }
        return true
    }

    private fun cancelImport(owner: String? = null) {
        val operation = importing ?: return
        if (owner != null && owner != operation.owner) return
        operation.result?.error("cancelled", "File import was cancelled.", null)
        operation.result = null
        synchronized(operation) {
            val input = operation.reader.requestCancellation()
            if (input != null) {
                operation.closeFinished = false
                executor.purge()
                // Provider close may block too. Keep one bounded operation busy until
                // both read/open and close finish; never enqueue repeated imports.
                executor.execute {
                    try { input.close() } catch (_: IOException) { /* Already closing. */ }
                    finally {
                        operation.closeFinished = true
                        main.post { clearFinishedImport(operation) }
                    }
                }
            }
            operation.future?.cancel(true)
            if (!operation.started && operation.future != null) operation.readerFinished = true
        }
        clearFinishedImport(operation)
    }

    private fun clearFinishedImport(operation: ImportOperation) {
        if (importing === operation && !pickerOutstanding && operation.readerFinished && operation.closeFinished) {
            importing = null
        }
    }

    private fun busyError(result: MethodChannel.Result) {
        val closing = session?.cancelled?.get() == true || importing?.reader?.cancelled?.get() == true
        result.error("busy", if (closing) "Previous audio resources are still closing. Try again shortly."
            else "Finish or cancel the current audio operation first.", null)
    }

    override fun onActivityStopped(activity: Activity) {
        // The document picker is intentionally allowed to cover the host activity.
        if (activity === binding?.activity) cancelRecording()
    }
    override fun onActivityCreated(activity: Activity, state: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityResumed(activity: Activity) {}
    override fun onActivityPaused(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {
        if (activity === binding?.activity) cancelAll()
    }

    companion object {
        private const val PERMISSION_REQUEST = 51621
        private const val IMPORT_REQUEST = 51622
    }
}
