package com.example.captions_app

import android.graphics.*
import android.media.*
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
// import android.os.Environment 
import java.util.concurrent.ConcurrentHashMap
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.io.IOException


class NativeEncoderPlugin: FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var events: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Media state
    private var extractor: MediaExtractor? = null
    private var videoTrackIdx = -1
    private var audioTrackIdx = -1
    private var decoder: MediaCodec? = null
    private var encoder: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var outVideoTrack = -1
    private var muxerStarted = false

    private var outputPath: String = ""
    private var width = 0
    private var height = 0
    private var fps = 30.0
    private var keepAudio = true

    // Overlay delivery (thread-safe)
    private val pendingOverlays = ConcurrentHashMap<Long, Bitmap>()   // exact tMs
    private var lastOverlay: Bitmap? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "native_encoder")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "native_encoder/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onListen(args: Any?, sink: EventChannel.EventSink?) { events = sink }
    override fun onCancel(args: Any?) { events = null }

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                outputPath = call.argument<String>("outputPath")!!
                val input = call.argument<String>("inputVideoPath")!!
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
                    lastOverlay?.recycle()
                    lastOverlay = bmp.copy(Bitmap.Config.ARGB_8888, false)
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
        extractor = MediaExtractor().apply { setDataSource(inputVideo) }

        // Pick tracks
        val ex = extractor!!
        for (i in 0 until ex.trackCount) {
            val fmt = ex.getTrackFormat(i)
            val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith("video/") && videoTrackIdx == -1) {
                videoTrackIdx = i
                if (fmt.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                    fps = fmt.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble().coerceAtLeast(1.0)
                }
            } else if (mime.startsWith("audio/") && audioTrackIdx == -1) {
                audioTrackIdx = i
            }
        }

        // Decoder (to images)
        ex.selectTrack(videoTrackIdx)
        val vFormat = ex.getTrackFormat(videoTrackIdx)
        val mime = vFormat.getString(MediaFormat.KEY_MIME)!!
        decoder = MediaCodec.createDecoderByType(mime).apply {
            configure(vFormat, /*surface*/ null, null, 0)
            start()
        }

        // Encoder (surface input)
        val targetMime = "video/avc"
        val bitRate = (width * height * 2.0 * fps).toInt()  // ~2 bpp * fps baseline
        val eFormat = MediaFormat.createVideoFormat(targetMime, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps.toInt().coerceAtLeast(1))
        }
        encoder = MediaCodec.createEncoderByType(targetMime)
        encoder!!.configure(eFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = encoder!!.createInputSurface()
        encoder!!.start()

        muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        muxerStarted = false
        outVideoTrack = -1

        Thread { processLoop(inputSurface) }.start()
    }


        private fun processLoop(inputSurface: Surface) {
        val d = decoder!!
        val ex = extractor!!
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)

        val decIn = d.inputBuffers
        var sawInputEOS = false
        var sawOutputEOS = false

        while (!sawOutputEOS) {
            if (!sawInputEOS) {
                val inIdx = d.dequeueInputBuffer(10000)
                if (inIdx >= 0) {
                    val buf = decIn[inIdx]
                    val sampleSize = ex.readSampleData(buf, 0)
                    if (sampleSize < 0) {
                        d.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        sawInputEOS = true
                    } else {
                        val ptsUs = ex.sampleTime
                        d.queueInputBuffer(inIdx, 0, sampleSize, ptsUs, 0)
                        ex.advance()
                    }
                }
            }

            val info = MediaCodec.BufferInfo()
            val outIdx = d.dequeueOutputBuffer(info, 10000)
            if (outIdx >= 0) {
                val image = d.getOutputImage(outIdx)
                if (image != null) {
                    val bmp = yuv420ToBitmap(image, width, height)
                    image.close()

                    val tMs = info.presentationTimeUs / 1000
                    // Ask Flutter for overlay on main thread (EventChannel requirement)
                    mainHandler.post {
                        events?.success(mapOf("type" to "requestOverlay", "tMs" to tMs))
                    }

                    // Bounded wait ~80ms for this exact tMs
                    val startWait = System.currentTimeMillis()
                    var overlay: Bitmap? = null
                    while (System.currentTimeMillis() - startWait < 80) {
                        overlay = pendingOverlays.remove(tMs)
                        if (overlay != null) break
                        Thread.sleep(2)
                    }
                    // Fallback to last overlay to keep cadence
                    if (overlay == null) overlay = lastOverlay

                    val c = inputSurface.lockCanvas(null)
                    val dst = Rect(0, 0, width, height)
                    c.drawBitmap(bmp, null, dst, paint)
                    overlay?.let { c.drawBitmap(it, null, dst, paint) }
                    inputSurface.unlockCanvasAndPost(c)

                    bmp.recycle()
                    // DO NOT recycle overlay here (might be reused)
                }

                d.releaseOutputBuffer(outIdx, false)
                if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                    sawOutputEOS = true
                }
            }

            drainEncoder()
        }

        finishEncoding()
    }

        private fun drainEncoder() {
        val e = encoder ?: return
        val m = muxer ?: return
        val info = MediaCodec.BufferInfo()

        while (true) {
            val outIdx = e.dequeueOutputBuffer(info, 0)
            if (outIdx == MediaCodec.INFO_TRY_AGAIN_LATER) break
            if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (muxerStarted) continue
                outVideoTrack = m.addTrack(e.outputFormat)
                m.start()
                muxerStarted = true
            } else if (outIdx >= 0) {
                val encoded = e.getOutputBuffer(outIdx)!!
                if (info.size > 0 && muxerStarted && outVideoTrack >= 0) {
                    encoded.position(info.offset)
                    encoded.limit(info.offset + info.size)
                    m.writeSampleData(outVideoTrack, encoded, info)
                }
                e.releaseOutputBuffer(outIdx, false)
                if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break
            }
        }
    }

    private fun finishEncoding() {
        try { drainEncoder() } catch (_: Throwable) {}
        try { encoder?.signalEndOfInputStream() } catch (_: Throwable) {}

        try { encoder?.stop() } catch (_: Throwable) {}
        try { encoder?.release() } catch (_: Throwable) {}
        encoder = null

        try { decoder?.stop() } catch (_: Throwable) {}
        try { decoder?.release() } catch (_: Throwable) {}
        decoder = null

        try {
            if (muxerStarted) muxer?.stop()
        } catch (_: Throwable) {}
        try { muxer?.release() } catch (_: Throwable) {}
        muxer = null

        try { extractor?.release() } catch (_: Throwable) {}
        extractor = null

        // recycle cache
        pendingOverlays.values.forEach { it.recycle() }
        pendingOverlays.clear()
        lastOverlay?.recycle()
        lastOverlay = null
    }

    private fun releaseAll() {
        try { encoder?.release() } catch (_: Throwable) {}
        encoder = null
        try { decoder?.release() } catch (_: Throwable) {}
        decoder = null
        try { muxer?.release() } catch (_: Throwable) {}
        muxer = null
        try { extractor?.release() } catch (_: Throwable) {}
        extractor = null
        pendingOverlays.clear()
        lastOverlay?.recycle()
        lastOverlay = null
    }

    // --- Utility: convert YUV_420_888 Image -> NV21 byte[] -> Bitmap (simple MVP)
        private fun yuv420ToBitmap(image: Image, w: Int, h: Int): Bitmap {
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val ySize = yPlane.buffer.remaining()
        val uSize = uPlane.buffer.remaining()
        val vSize = vPlane.buffer.remaining()

        val nv21 = ByteArray(w * h + (w * h) / 2)

        // Copy Y taking rowStride into account
        var pos = 0
        val yRowStride = yPlane.rowStride
        val yPixelStride = yPlane.pixelStride
        val yBuffer = yPlane.buffer
        for (row in 0 until h) {
            var col = 0
            var yIdx = row * yRowStride
            while (col < w) {
                nv21[pos++] = yBuffer.get(yIdx)
                yIdx += yPixelStride
                col++
            }
        }

        // Interleave V and U (NV21 = Y + VU)
        val uvRowStride = uPlane.rowStride
        val uvPixelStride = uPlane.pixelStride
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer

        val chromaHeight = h / 2
        val chromaWidth = w / 2

        var offset = w * h
        for (row in 0 until chromaHeight) {
            var col = 0
            var uIdx = row * uvRowStride
            var vIdx = row * vPlane.rowStride
            while (col < chromaWidth) {
                val vVal = vBuffer.get(vIdx)
                val uVal = uBuffer.get(uIdx)
                nv21[offset++] = vVal
                nv21[offset++] = uVal
                uIdx += uvPixelStride
                vIdx += vPlane.pixelStride
                col++
            }
        }

        val yuvImage = YuvImage(nv21, ImageFormat.NV21, w, h, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, w, h), 100, out)
        val jpegBytes = out.toByteArray()
        return BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
    }



}
