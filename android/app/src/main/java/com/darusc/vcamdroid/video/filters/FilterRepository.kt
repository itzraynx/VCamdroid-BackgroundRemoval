package com.darusc.vcamdroid.video.filters

import com.darusc.vcamdroid.video.filters.custom.BackgroundRemovalFilterRender
import com.darusc.vcamdroid.video.filters.custom.ChromaKeyFilterRender
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.input.gl.render.filters.*

object FilterRepository {

    enum class Category {
        NONE, CORRECTION, EFFECT, DISTORTION, ARTISTIC
    }

    data class FilterInfo(
        val name: String,
        val filterClass: Class<out BaseFilterRender>,
        val category: Category,
        val configure: ((BaseFilterRender) -> Unit)? = null
    ) {
        override fun toString() = name
    }

    fun getCategory(filterName: String): Category =
        filters.find { it.name.equals(filterName, ignoreCase = true) }?.let {
            it.category
        } ?: Category.NONE

    fun getClass(filterName: String): Class<out BaseFilterRender>? =
        filters.find { it.name.equals(filterName, ignoreCase = true) }?.filterClass

    fun create(filterName: String): BaseFilterRender? =
        filters.find { it.name.equals(filterName, ignoreCase = true) }?.let { create(it) }

    fun create(filterInfo: FilterInfo): BaseFilterRender? {
        return try {
            val filter = filterInfo.filterClass.getDeclaredConstructor().newInstance()
            filterInfo.configure?.invoke(filter)
            filter
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    val filters: List<FilterInfo> = listOf(
        // --- Default ---
        FilterInfo("None", NoFilterRender::class.java, Category.NONE),

        // --- Background Processing (MediaPipe) ---
        FilterInfo("Background Removal", BackgroundRemovalFilterRender::class.java, Category.EFFECT),
        FilterInfo("Background Blur", BackgroundRemovalFilterRender::class.java, Category.EFFECT) {
            (it as BackgroundRemovalFilterRender).mode = BackgroundRemovalFilterRender.MODE_BLUR
        },

        // --- Chroma Key ---
        FilterInfo("Chroma Key", ChromaKeyFilterRender::class.java, Category.EFFECT),

        // --- Corrections ---
        FilterInfo("Brightness", BrightnessFilterRender::class.java, Category.CORRECTION),
        FilterInfo("Contrast", ContrastFilterRender::class.java, Category.CORRECTION),
        FilterInfo("Exposure", ExposureFilterRender::class.java, Category.CORRECTION),
        FilterInfo("Gamma", GammaFilterRender::class.java, Category.CORRECTION),
        FilterInfo("Saturation", SaturationFilterRender::class.java, Category.CORRECTION),
        FilterInfo("Temperature", TemperatureFilterRender::class.java, Category.CORRECTION),
        FilterInfo("Sharpness", SharpnessFilterRender::class.java, Category.CORRECTION),

        // --- Classic Effects ---
        FilterInfo("Grey Scale", GreyScaleFilterRender::class.java, Category.EFFECT),
        FilterInfo("Sepia", SepiaFilterRender::class.java, Category.EFFECT),
        FilterInfo("Negative", NegativeFilterRender::class.java, Category.EFFECT),
        FilterInfo("Early Bird", EarlyBirdFilterRender::class.java, Category.EFFECT),
        FilterInfo("70s Style", Image70sFilterRender::class.java, Category.EFFECT),
        FilterInfo("Lamoish", LamoishFilterRender::class.java, Category.EFFECT),

        // --- Artistic ---
        FilterInfo("Cartoon", CartoonFilterRender::class.java, Category.ARTISTIC),
        FilterInfo("Duotone", DuotoneFilterRender::class.java, Category.ARTISTIC),
        FilterInfo("Halftone Lines", HalftoneLinesFilterRender::class.java, Category.ARTISTIC),
        FilterInfo("Pixelated", PixelatedFilterRender::class.java, Category.ARTISTIC),
        FilterInfo("Polygonization", PolygonizationFilterRender::class.java, Category.ARTISTIC),
        FilterInfo("Rainbow", RainbowFilterRender::class.java, Category.ARTISTIC),
        FilterInfo("Money", MoneyFilterRender::class.java, Category.ARTISTIC),
        FilterInfo("Zebra", ZebraFilterRender::class.java, Category.ARTISTIC),
        FilterInfo("Edge Detection", EdgeDetectionFilterRender::class.java, Category.ARTISTIC),

        // --- Distortion & FX ---
        FilterInfo("Blur", BlurFilterRender::class.java, Category.DISTORTION),
        FilterInfo("Glitch", GlitchFilterRender::class.java, Category.DISTORTION),
        FilterInfo("Noise", NoiseFilterRender::class.java, Category.DISTORTION),
        FilterInfo("Analog TV", AnalogTVFilterRender::class.java, Category.DISTORTION),
        FilterInfo("Swirl", SwirlFilterRender::class.java, Category.DISTORTION),
        FilterInfo("Ripple", RippleFilterRender::class.java, Category.DISTORTION),
        FilterInfo("Fire", FireFilterRender::class.java, Category.DISTORTION),
        FilterInfo("Snow", SnowFilterRender::class.java, Category.DISTORTION),
    )
}
