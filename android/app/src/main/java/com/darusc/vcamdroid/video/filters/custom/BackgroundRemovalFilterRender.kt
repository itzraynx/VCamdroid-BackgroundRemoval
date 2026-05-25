package com.darusc.vcamdroid.video.filters.custom

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLES30
import android.opengl.Matrix
import com.darusc.vcamdroid.util.Logger
import com.darusc.vcamdroid.video.SelfieSegmenterHelper
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder

class BackgroundRemovalFilterRender : BaseFilterRender() {

    companion object {
        private const val TAG = "BG_REMOVE"
        const val MODE_REMOVE = 0
        const val MODE_BLUR = 1
        private const val INFERENCE_SIZE = 256
        private const val INFERENCE_INTERVAL = 2
        private const val THRESHOLD = 0.5f
        private const val FLOAT_SIZE_BYTES = 4
        private const val SQUARE_VERTEX_DATA_STRIDE_BYTES = 32
        private const val SQUARE_VERTEX_DATA_POS_OFFSET = 0
        private const val SQUARE_VERTEX_DATA_UV_OFFSET = 3
    }

    var mode: Int = MODE_REMOVE

    private val squareVertexDataFilter = floatArrayOf(
        -1f, -1f, 0f, 0f, 0f,
        1f, -1f, 0f, 1f, 0f,
        -1f, 1f, 0f, 0f, 1f,
        1f, 1f, 0f, 1f, 1f
    )

    private var readbackProgram = -1
    private var maskProgram = -1

    private var readbackFbo = IntArray(1)
    private var readbackTex = IntArray(1)

    private var maskTextureId = IntArray(1)

    private var aPositionHandleRb = -1
    private var aTextureHandleRb = -1
    private var uMVPMatrixHandleRb = -1
    private var uSTMatrixHandleRb = -1
    private var uSamplerHandleRb = -1

    private var aPositionHandleMk = -1
    private var aTextureHandleMk = -1
    private var uMVPMatrixHandleMk = -1
    private var uSTMatrixHandleMk = -1
    private var uSamplerHandleMk = -1
    private var uMaskSamplerHandle = -1
    private var uThresholdHandle = -1
    private var uModeHandle = -1
    private var uPixelSizeHandle = -1

    private var readbackBuffer: ByteBuffer? = null
    private var frameCount = 0
    private var lastMaskBuffer: ByteBuffer? = null

    override fun initGlFilter(context: Context) {
        SelfieSegmenterHelper.initialize(context.applicationContext)

        val vertexShader = GlUtil.getStringFromRaw(context, com.pedro.encoder.R.raw.simple_vertex)
        val fragmentShader = GlUtil.getStringFromRaw(context, com.pedro.encoder.R.raw.simple_fragment)
        readbackProgram = GlUtil.createProgram(vertexShader, fragmentShader)
        if (readbackProgram < 0) {
            Logger.log(TAG, "Failed to create readback program")
            return
        }
        aPositionHandleRb = GLES20.glGetAttribLocation(readbackProgram, "aPosition")
        aTextureHandleRb = GLES20.glGetAttribLocation(readbackProgram, "aTextureCoord")
        uMVPMatrixHandleRb = GLES20.glGetUniformLocation(readbackProgram, "uMVPMatrix")
        uSTMatrixHandleRb = GLES20.glGetUniformLocation(readbackProgram, "uSTMatrix")
        uSamplerHandleRb = GLES20.glGetUniformLocation(readbackProgram, "uSampler")

        val maskFragShader = createMaskFragmentShader()
        maskProgram = GlUtil.createProgram(vertexShader, maskFragShader)
        if (maskProgram < 0) {
            Logger.log(TAG, "Failed to create mask program")
            return
        }
        aPositionHandleMk = GLES20.glGetAttribLocation(maskProgram, "aPosition")
        aTextureHandleMk = GLES20.glGetAttribLocation(maskProgram, "aTextureCoord")
        uMVPMatrixHandleMk = GLES20.glGetUniformLocation(maskProgram, "uMVPMatrix")
        uSTMatrixHandleMk = GLES20.glGetUniformLocation(maskProgram, "uSTMatrix")
        uSamplerHandleMk = GLES20.glGetUniformLocation(maskProgram, "uSampler")
        uMaskSamplerHandle = GLES20.glGetUniformLocation(maskProgram, "uMaskTexture")
        uThresholdHandle = GLES20.glGetUniformLocation(maskProgram, "uThreshold")
        uModeHandle = GLES20.glGetUniformLocation(maskProgram, "uMode")
        uPixelSizeHandle = GLES20.glGetUniformLocation(maskProgram, "uPixelSize")

        GLES20.glGenFramebuffers(1, readbackFbo, 0)
        GLES20.glGenTextures(1, readbackTex, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, readbackTex[0])
        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, INFERENCE_SIZE, INFERENCE_SIZE,
            0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, readbackFbo[0])
        GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
            GLES20.GL_TEXTURE_2D, readbackTex[0], 0)
        if (GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER) != GLES20.GL_FRAMEBUFFER_COMPLETE) {
            Logger.log(TAG, "Readback FBO not complete")
        }
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)

        GLES20.glGenTextures(1, maskTextureId, 0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTextureId[0])
        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES30.GL_R8, INFERENCE_SIZE, INFERENCE_SIZE,
            0, GLES30.GL_RED, GLES20.GL_UNSIGNED_BYTE, null)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        squareVertex = ByteBuffer.allocateDirect(squareVertexDataFilter.size * FLOAT_SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        squareVertex.put(squareVertexDataFilter).position(0)
        Matrix.setIdentityM(MVPMatrix, 0)
        Matrix.setIdentityM(STMatrix, 0)

        readbackBuffer = ByteBuffer.allocateDirect(INFERENCE_SIZE * INFERENCE_SIZE * 4)
            .order(ByteOrder.nativeOrder())

        Logger.log(TAG, "Filter initialized, mode=$mode")
    }

    override fun drawFilter() {
        if (readbackProgram < 0 || maskProgram < 0) return

        val fw = width
        val fh = height
        if (fw <= 0 || fh <= 0) return

        val prevFbo = IntArray(1)
        GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, prevFbo, 0)

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, readbackFbo[0])
        GLES20.glViewport(0, 0, INFERENCE_SIZE, INFERENCE_SIZE)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        GLES20.glUseProgram(readbackProgram)
        squareVertex.position(SQUARE_VERTEX_DATA_POS_OFFSET)
        GLES20.glVertexAttribPointer(aPositionHandleRb, 3, GLES20.GL_FLOAT, false,
            SQUARE_VERTEX_DATA_STRIDE_BYTES, squareVertex)
        GLES20.glEnableVertexAttribArray(aPositionHandleRb)
        squareVertex.position(SQUARE_VERTEX_DATA_UV_OFFSET)
        GLES20.glVertexAttribPointer(aTextureHandleRb, 2, GLES20.GL_FLOAT, false,
            SQUARE_VERTEX_DATA_STRIDE_BYTES, squareVertex)
        GLES20.glEnableVertexAttribArray(aTextureHandleRb)
        GLES20.glUniformMatrix4fv(uMVPMatrixHandleRb, 1, false, MVPMatrix, 0)
        GLES20.glUniformMatrix4fv(uSTMatrixHandleRb, 1, false, STMatrix, 0)
        GLES20.glUniform1i(uSamplerHandleRb, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, previousTexId)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glFinish()

        readbackBuffer?.let { rb ->
            rb.position(0)
            GLES20.glReadPixels(0, 0, INFERENCE_SIZE, INFERENCE_SIZE,
                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, rb)

            frameCount++
            if (frameCount % INFERENCE_INTERVAL == 0) {
                val t0 = System.nanoTime()
                val mask = SelfieSegmenterHelper.segment(rb, INFERENCE_SIZE, INFERENCE_SIZE)
                val elapsed = (System.nanoTime() - t0) / 1_000_000L
                if (elapsed > 20) Logger.log(TAG, "Seg inference: ${elapsed}ms")
                if (mask != null) {
                    lastMaskBuffer = mask
                }
            }
        }

        lastMaskBuffer?.let { maskBuf ->
            maskBuf.position(0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTextureId[0])
            GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0,
                INFERENCE_SIZE, INFERENCE_SIZE, GLES30.GL_RED, GLES20.GL_UNSIGNED_BYTE, maskBuf)
        }

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, prevFbo[0])
        GLES20.glViewport(0, 0, fw, fh)

        GLES20.glUseProgram(maskProgram)
        squareVertex.position(SQUARE_VERTEX_DATA_POS_OFFSET)
        GLES20.glVertexAttribPointer(aPositionHandleMk, 3, GLES20.GL_FLOAT, false,
            SQUARE_VERTEX_DATA_STRIDE_BYTES, squareVertex)
        GLES20.glEnableVertexAttribArray(aPositionHandleMk)
        squareVertex.position(SQUARE_VERTEX_DATA_UV_OFFSET)
        GLES20.glVertexAttribPointer(aTextureHandleMk, 2, GLES20.GL_FLOAT, false,
            SQUARE_VERTEX_DATA_STRIDE_BYTES, squareVertex)
        GLES20.glEnableVertexAttribArray(aTextureHandleMk)
        GLES20.glUniformMatrix4fv(uMVPMatrixHandleMk, 1, false, MVPMatrix, 0)
        GLES20.glUniformMatrix4fv(uSTMatrixHandleMk, 1, false, STMatrix, 0)
        GLES20.glUniform1i(uSamplerHandleMk, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, previousTexId)
        GLES20.glUniform1i(uMaskSamplerHandle, 1)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE1)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTextureId[0])
        GLES20.glUniform1f(uThresholdHandle, THRESHOLD)
        GLES20.glUniform1i(uModeHandle, mode)
        GLES20.glUniform2f(uPixelSizeHandle, 1f / fw, 1f / fh)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    override fun disableResources() {
        if (aPositionHandleRb >= 0) GLES20.glDisableVertexAttribArray(aPositionHandleRb)
        if (aTextureHandleRb >= 0) GLES20.glDisableVertexAttribArray(aTextureHandleRb)
        if (aPositionHandleMk >= 0) GLES20.glDisableVertexAttribArray(aPositionHandleMk)
        if (aTextureHandleMk >= 0) GLES20.glDisableVertexAttribArray(aTextureHandleMk)
    }

    override fun release() {
        GLES20.glDeleteProgram(readbackProgram)
        GLES20.glDeleteProgram(maskProgram)
        if (readbackFbo[0] > 0) GLES20.glDeleteFramebuffers(1, readbackFbo, 0)
        if (readbackTex[0] > 0) GLES20.glDeleteTextures(1, readbackTex, 0)
        if (maskTextureId[0] > 0) GLES20.glDeleteTextures(1, maskTextureId, 0)
        SelfieSegmenterHelper.close()
    }

    private fun createMaskFragmentShader(): String {
        return """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uSampler;
uniform sampler2D uMaskTexture;
uniform float uThreshold;
uniform int uMode;
uniform vec2 uPixelSize;

void main() {
    vec4 color = texture2D(uSampler, vTexCoord);
    float mask = texture2D(uMaskTexture, vTexCoord).r;
    if (mask > uThreshold) {
        gl_FragColor = color;
    } else if (uMode == 0) {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        vec4 blur = vec4(0.0);
        for (int x = -2; x <= 2; x++) {
            for (int y = -2; y <= 2; y++) {
                vec2 off = vec2(float(x), float(y)) * uPixelSize;
                blur += texture2D(uSampler, vTexCoord + off);
            }
        }
        gl_FragColor = blur / 25.0;
    }
}
""".trimIndent()
    }
}
