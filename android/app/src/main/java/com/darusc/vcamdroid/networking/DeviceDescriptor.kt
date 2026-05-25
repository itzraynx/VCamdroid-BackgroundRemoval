package com.darusc.vcamdroid.networking

import com.darusc.vcamdroid.video.filters.FilterRepository
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets

data class DeviceDescriptor(
    val name: String,
    val urls: List<String>,
    val backResolutions: List<Pair<Int, Int>>,
    val frontResolutions: List<Pair<Int, Int>>,
    val filterInfos: List<FilterRepository.FilterInfo>
) {

    fun serialize(): ByteArray {
        var requiredSize = 0

        requiredSize += 2 + name.toByteArray(StandardCharsets.UTF_8).size
        requiredSize += 2
        requiredSize += urls.sumOf { 2 + it.toByteArray(StandardCharsets.UTF_8).size }

        requiredSize += 2 + frontResolutions.size * 4
        requiredSize += 2 + backResolutions.size * 4

        requiredSize += 2
        requiredSize += filterInfos.sumOf { 2 + it.name.toByteArray(StandardCharsets.UTF_8).size + 1 }

        val buffer = ByteBuffer.allocate(requiredSize)
        buffer.order(ByteOrder.BIG_ENDIAN)

        fun putString(s: String) {
            val bytes = s.toByteArray(StandardCharsets.UTF_8)
            buffer.putShort(bytes.size.toShort())
            buffer.put(bytes)
        }

        putString(name)
        buffer.putShort(urls.size.toShort())
        urls.forEach { putString(it) }

        buffer.putShort(frontResolutions.size.toShort())
        frontResolutions.forEach { (w, h) ->
            buffer.putShort(w.toShort())
            buffer.putShort(h.toShort())
        }

        buffer.putShort(backResolutions.size.toShort())
        backResolutions.forEach { (w, h) ->
            buffer.putShort(w.toShort())
            buffer.putShort(h.toShort())
        }

        buffer.putShort(filterInfos.size.toShort())
        filterInfos.forEach { (name, _, category) ->
            putString(name)
            buffer.put(category.ordinal.toByte())
        }

        return buffer.array()
    }
}
