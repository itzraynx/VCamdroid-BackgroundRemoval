package com.darusc.vcamdroid.video

import android.content.Context
import android.graphics.Bitmap
import com.darusc.vcamdroid.util.Logger
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import java.nio.ByteBuffer
import java.nio.ByteOrder

object SelfieSegmenterHelper {
    private const val TAG = "SEG_HELPER"
    private var segmenter: ImageSegmenter? = null
    private var initialized = false
    private var reusableBitmap: Bitmap? = null
    private var maskWidth = 0
    private var maskHeight = 0

    fun initialize(context: Context) {
        if (initialized) return
        try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("selfie_segmenter.tflite")
                .setDelegate(Delegate.CPU)
                .build()
            val options = ImageSegmenter.ImageSegmenterOptions.builder()
                .setBaseOptions(baseOptions)
                .build()
            segmenter = ImageSegmenter.createFromOptions(context, options)
            initialized = true
            Logger.log(TAG, "ImageSegmenter initialized (CPU)")
        } catch (e: Exception) {
            Logger.log(TAG, "Failed to init segmenter: ${e.message}")
        }
    }

    fun segment(pixelBuffer: ByteBuffer, width: Int, height: Int): ByteBuffer? {
        if (!initialized || segmenter == null) return null
        try {
            pixelBuffer.position(0)

            if (reusableBitmap == null || reusableBitmap!!.width != width || reusableBitmap!!.height != height) {
                reusableBitmap?.recycle()
                reusableBitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            }
            reusableBitmap!!.copyPixelsFromBuffer(pixelBuffer)

            val mpImage = BitmapImageBuilder(reusableBitmap!!).build()
            val result = segmenter!!.segment(mpImage)
            val masks = result.confidenceMasks().orElse(null) ?: return null
            if (masks.size < 2) return null

            val personMask = masks[1]
            maskWidth = personMask.width
            maskHeight = personMask.height

            val maskBuf = personMask.getBuffer()
            maskBuf.order(ByteOrder.nativeOrder())
            val floatBuf = maskBuf.asFloatBuffer()
            val numPixels = maskWidth * maskHeight
            val byteMask = ByteBuffer.allocateDirect(numPixels).order(ByteOrder.nativeOrder())
            for (i in 0 until numPixels) {
                val f = floatBuf.get(i)
                val b = (f * 255.0f).toInt().coerceIn(0, 255)
                byteMask.put(b.toByte())
            }
            byteMask.position(0)
            return byteMask
        } catch (e: Exception) {
            Logger.log(TAG, "Segmentation failed: ${e.message}")
            return null
        }
    }

    fun getMaskWidth(): Int = maskWidth
    fun getMaskHeight(): Int = maskHeight

    fun close() {
        segmenter?.close()
        segmenter = null
        initialized = false
        reusableBitmap?.recycle()
        reusableBitmap = null
    }
}
