package com.example.captions_app

import android.graphics.*
import android.media.*
import android.util.Log
import android.view.Surface
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import android.os.Environment   // ✅ FIXED - Required for Downloads path
import java.util.concurrent.ConcurrentHashMap


class NativeEncoderPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var events: EventChannel.EventSink? = null

    // State
    private lateinit var extractor: MediaExtractor
    private var videoTrackIdx = -1
    private var audioTrackIdx = -1
    private lateinit var decoder: MediaCodec
    private lateinit var encoder: MediaCodec
    private lateinit var muxer: MediaMuxer
    private var outAudioTrack = -1
    private var outVideoTrack = -1
    private var outputPath: String = ""
    private var width = 0
    private var height = 0
    private var fps = 30.0
    private var keepAudio = true

    // overlay bitmaps keyed by tMs (concurrent since producer/consumer threads)
    private val pendingOverlays = ConcurrentHashMap<Long, Bitmap>()

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "native_encoder")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "native_encoder/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.events = events
    }

    override fun onCancel(arguments: Any?) {
        this.events = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val input = call.argument<String>("inputVideoPath")!!
                outputPath = call.argument<String>("outputPath")!!
                width = call.argument<Int>("width")!!
                height = call.argument<Int>("height")!!
                fps = call.argument<Double>("fps") ?: 30.0
                keepAudio = call.argument<Boolean>("keepAudio") ?: true
                startEncoding(input)
                result.success(null)
            }
            "deliverOverlay" -> {
                val tMs = (call.argument<Int>("tMs")!!).toLong()
                val png = call.argument<ByteArray>("png")!!
                val bmp = BitmapFactory.decodeByteArray(png, 0, png.size)
                if (bmp != null) {
                    pendingOverlays[tMs] = bmp
                }
                result.success(null)
            }
            "finish" -> {
                finishEncoding()
                result.success(outputPath)
            }
            "cancel" -> {
                releaseAll()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startEncoding(inputVideo: String) {
        // Create a subfolder inside Downloads
        //val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val downloadsDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "CaptionsApp"
        )
        val appFolder = File(downloadsDir, "CaptionsApp")
        if (!appFolder.exists()) {
            appFolder.mkdirs()
        }

        // Generate a unique file name
        val fileName = "exported_video_${System.currentTimeMillis()}.mp4"

        // Set final export path
        outputPath = File(appFolder, fileName).absolutePath

        Log.d("NativeEncoder", "Saving video to: $outputPath")

        extractor = MediaExtractor()
        extractor.setDataSource(inputVideo)

        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("video/") && videoTrackIdx == -1) {
                videoTrackIdx = i
            } else if (mime.startsWith("audio/") && audioTrackIdx == -1) {
                audioTrackIdx = i
            }
        }

        extractor.selectTrack(videoTrackIdx)
        val vFormat = extractor.getTrackFormat(videoTrackIdx)
        val mime = vFormat.getString(MediaFormat.KEY_MIME)!!
        decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(vFormat, null, null, 0)
        decoder.start()

        val eFormat = MediaFormat.createVideoFormat("video/avc", width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            //setInteger(MediaFormat.KEY_BIT_RATE, width * height * 5)
            //setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            //setInteger(MediaFormat.KEY_FRAME_RATE, fps.toInt())
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.toInt())
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setInteger(MediaFormat.KEY_BIT_RATE, width * height * 8) // Higher bitrate = smoother video
        }
        encoder = MediaCodec.createEncoderByType("video/avc")
        encoder.configure(eFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = encoder.createInputSurface()
        encoder.start()

        // ✅ Create CaptionsApp folder inside Downloads if not exists
        //val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
         
        val captionsDir = File(downloadsDir, "CaptionsApp")
        if (!captionsDir.exists()) {
            captionsDir.mkdirs()
        }

        outputPath = File(captionsDir, "exported_${System.currentTimeMillis()}.mp4").absolutePath
        muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                Thread { processLoop(inputSurface) }.start()
            }


    private fun processLoop(inputSurface: Surface) {
        val canvasPaint = Paint(Paint.FILTER_BITMAP_FLAG)
        val overlayPaint = Paint().apply { isFilterBitmap = true }

        var sawInputEOS = false
        var sawOutputEOS = false

        while (!sawOutputEOS) {
            // Feed decoder
            if (!sawInputEOS) {
                val inIndex = decoder.dequeueInputBuffer(10_000)
                if (inIndex >= 0) {
                    val buffer = decoder.getInputBuffer(inIndex)!!
                    val sampleSize = extractor.readSampleData(buffer, 0)
                    if (sampleSize < 0) {
                        decoder.queueInputBuffer(
                            inIndex, 0, 0, 0,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM
                        )
                        sawInputEOS = true
                    } else {
                        val ptsUs = extractor.sampleTime
                        decoder.queueInputBuffer(inIndex, 0, sampleSize, ptsUs, 0)
                        extractor.advance()
                    }
                }
            }

            // Get decoded output
            val info = MediaCodec.BufferInfo()
            val outIndex = decoder.dequeueOutputBuffer(info, 10_000)
            if (outIndex >= 0) {
                decoder.getOutputImage(outIndex)?.let { image ->
                    val bmp = yuv420ToBitmap(image, width, height)
                    image.close()

                    val tMs = info.presentationTimeUs / 1000
                    // Ask Flutter for overlay at this timestamp
                    //events?.success(mapOf("type" to "requestOverlay", "tMs" to tMs))
                    // Ask Flutter for overlay at this timestamp (tMs)
                    val payload = mapOf("type" to "requestOverlay", "tMs" to tMs)
                    // Post to main thread before calling EventChannel
                    android.os.Handler(android.os.Looper.getMainLooper()).post {
                        events?.success(payload)
                    }


                    // Wait up to 5s for overlay delivery
                    var overlay: Bitmap? = null
                    val startWait = System.currentTimeMillis()
                    while (overlay == null && System.currentTimeMillis() - startWait < 5000) {
                        overlay = pendingOverlays.remove(tMs)
                        if (overlay == null) Thread.sleep(2)
                    }

                    // Composite into encoder surface
                    val canvas = inputSurface.lockCanvas(null)
                    val dst = Rect(0, 0, width, height)
                    canvas.drawBitmap(bmp, null, dst, canvasPaint)
                    overlay?.let { canvas.drawBitmap(it, null, dst, overlayPaint) }
                    inputSurface.unlockCanvasAndPost(canvas)

                    bmp.recycle()
                    overlay?.recycle()
                }

                decoder.releaseOutputBuffer(outIndex, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    sawOutputEOS = true
                }
            }

            // Drain encoder to muxer
            drainEncoder()
        }

        finishEncoding()
    }

    private fun drainEncoder(endOfStream: Boolean = false) {
        if (endOfStream) {
            encoder.signalEndOfInputStream()
        }

        val bufferInfo = MediaCodec.BufferInfo()
        while (true) {
            val outputBufferIndex = encoder.dequeueOutputBuffer(bufferInfo, 10000)

            when {
                outputBufferIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) break
                }

                outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (outVideoTrack != -1) {
                        throw RuntimeException("Format changed twice!")
                    }
                    outVideoTrack = muxer.addTrack(encoder.outputFormat)

                    // Add audio track if needed
                    if (keepAudio && audioTrackIdx >= 0) {
                        extractor.selectTrack(audioTrackIdx)
                        outAudioTrack = muxer.addTrack(extractor.getTrackFormat(audioTrackIdx))
                    }

                    muxer.start()
                }

                outputBufferIndex >= 0 -> {
                    val encodedData = encoder.getOutputBuffer(outputBufferIndex)
                        ?: throw RuntimeException("Encoder output buffer $outputBufferIndex was null")

                    if (bufferInfo.size > 0 && outVideoTrack != -1) {
                        encodedData.position(bufferInfo.offset)
                        encodedData.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(outVideoTrack, encodedData, bufferInfo)
                    }

                    encoder.releaseOutputBuffer(outputBufferIndex, false)

                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break
                    }
                }
            }
        }
    }

    private fun finishEncoding() {
        try {
            encoder.signalEndOfInputStream()
        } catch (_: Throwable) {}

        try { drainEncoder() } catch (_: Throwable) {}
        try { encoder.stop(); encoder.release() } catch (_: Throwable) {}
        try { decoder.stop(); decoder.release() } catch (_: Throwable) {}
        try { muxer.stop(); muxer.release() } catch (_: Throwable) {}

        Log.d("NativeEncoder", "Encoding finished successfully.")
    }

    private fun releaseAll() {
        try { encoder.release() } catch (_: Throwable) {}
        try { decoder.release() } catch (_: Throwable) {}
        try { muxer.release() } catch (_: Throwable) {}
    }

    // --- Utility: convert YUV_420_888 Image -> NV21 byte[] -> Bitmap (simple MVP)
    private fun yuv420ToBitmap(image: Image, w: Int, h: Int): Bitmap {
    try {
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val yBuffer = yPlane.buffer
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer

        val ySize = yBuffer.remaining()
        val uSize = uBuffer.remaining()
        val vSize = vBuffer.remaining()

        // If buffer is inaccessible or corrupted → return blank bitmap
        if (ySize <= 0 || uSize <= 0 || vSize <= 0) {
            Log.e("NativeEncoder", "Empty YUV buffers, returning blank frame.")
            return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        }

        // Copy YUV planes into NV21 format
        val nv21 = ByteArray(ySize + uSize + vSize)
        yBuffer.get(nv21, 0, ySize)
        vBuffer.get(nv21, ySize, vSize)
        uBuffer.get(nv21, ySize + vSize, uSize)

        // Convert NV21 → Bitmap
        val yuvImage = YuvImage(nv21, ImageFormat.NV21, w, h, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, w, h), 100, out)
        val jpegBytes = out.toByteArray()

        return BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
    } catch (e: Exception) {
        Log.e("NativeEncoder", "yuv420ToBitmap failed: ${e.message}")
        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    }
}


}
