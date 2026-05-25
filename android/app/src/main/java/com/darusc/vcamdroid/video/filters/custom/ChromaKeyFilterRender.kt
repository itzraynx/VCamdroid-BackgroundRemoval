package com.darusc.vcamdroid.video.filters.custom

import android.content.Context
import android.opengl.GLES20
import android.opengl.Matrix
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder

class ChromaKeyFilterRender : BaseFilterRender() {

    companion object {
        private const val FLOAT_SIZE_BYTES = 4
        private const val SQUARE_VERTEX_DATA_STRIDE_BYTES = 32
        private const val SQUARE_VERTEX_DATA_POS_OFFSET = 0
        private const val SQUARE_VERTEX_DATA_UV_OFFSET = 3
    }

    private val squareVertexDataFilter = floatArrayOf(
        -1f, -1f, 0f, 0f, 0f,
        1f, -1f, 0f, 1f, 0f,
        -1f, 1f, 0f, 0f, 1f,
        1f, 1f, 0f, 1f, 1f
    )

    private var program = -1
    private var aPositionHandle = -1
    private var aTextureHandle = -1
    private var uMVPMatrixHandle = -1
    private var uSTMatrixHandle = -1
    private var uSamplerHandle = -1
    private var uKeyColorHandle = -1
    private var uToleranceHandle = -1

    var keyColorR: Float = 0.0f
    var keyColorG: Float = 1.0f
    var keyColorB: Float = 0.0f
    var tolerance: Float = 0.3f

    override fun initGlFilter(context: Context) {
        val vertexShader = GlUtil.getStringFromRaw(context, com.pedro.encoder.R.raw.simple_vertex)
        val fragmentShader = createFragmentShader()
        program = GlUtil.createProgram(vertexShader, fragmentShader)
        if (program < 0) return

        aPositionHandle = GLES20.glGetAttribLocation(program, "aPosition")
        aTextureHandle = GLES20.glGetAttribLocation(program, "aTextureCoord")
        uMVPMatrixHandle = GLES20.glGetUniformLocation(program, "uMVPMatrix")
        uSTMatrixHandle = GLES20.glGetUniformLocation(program, "uSTMatrix")
        uSamplerHandle = GLES20.glGetUniformLocation(program, "uSampler")
        uKeyColorHandle = GLES20.glGetUniformLocation(program, "uKeyColor")
        uToleranceHandle = GLES20.glGetUniformLocation(program, "uTolerance")

        squareVertex = ByteBuffer.allocateDirect(squareVertexDataFilter.size * FLOAT_SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
        squareVertex.put(squareVertexDataFilter).position(0)
        Matrix.setIdentityM(MVPMatrix, 0)
        Matrix.setIdentityM(STMatrix, 0)
    }

    override fun drawFilter() {
        if (program < 0) return

        GLES20.glUseProgram(program)
        squareVertex.position(SQUARE_VERTEX_DATA_POS_OFFSET)
        GLES20.glVertexAttribPointer(aPositionHandle, 3, GLES20.GL_FLOAT, false,
            SQUARE_VERTEX_DATA_STRIDE_BYTES, squareVertex)
        GLES20.glEnableVertexAttribArray(aPositionHandle)
        squareVertex.position(SQUARE_VERTEX_DATA_UV_OFFSET)
        GLES20.glVertexAttribPointer(aTextureHandle, 2, GLES20.GL_FLOAT, false,
            SQUARE_VERTEX_DATA_STRIDE_BYTES, squareVertex)
        GLES20.glEnableVertexAttribArray(aTextureHandle)
        GLES20.glUniformMatrix4fv(uMVPMatrixHandle, 1, false, MVPMatrix, 0)
        GLES20.glUniformMatrix4fv(uSTMatrixHandle, 1, false, STMatrix, 0)
        GLES20.glUniform1i(uSamplerHandle, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, previousTexId)
        GLES20.glUniform3f(uKeyColorHandle, keyColorR, keyColorG, keyColorB)
        GLES20.glUniform1f(uToleranceHandle, tolerance)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    override fun disableResources() {
        if (aPositionHandle >= 0) GLES20.glDisableVertexAttribArray(aPositionHandle)
        if (aTextureHandle >= 0) GLES20.glDisableVertexAttribArray(aTextureHandle)
    }

    override fun release() {
        GLES20.glDeleteProgram(program)
    }

    private fun createFragmentShader(): String {
        return """
precision mediump float;
varying vec2 vTexCoord;
uniform sampler2D uSampler;
uniform vec3 uKeyColor;
uniform float uTolerance;

void main() {
    vec4 color = texture2D(uSampler, vTexCoord);
    float dist = distance(color.rgb, uKeyColor);
    if (dist < uTolerance) {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        gl_FragColor = color;
    }
}
""".trimIndent()
    }
}
