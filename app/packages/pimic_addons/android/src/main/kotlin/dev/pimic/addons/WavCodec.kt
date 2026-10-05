package dev.pimic.addons

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Deliberately narrow format: uncompressed, mono, 16-bit PCM at 16 kHz. */
internal object WavCodec {
    const val SAMPLE_RATE = 16_000
    const val MAX_FRAMES = SAMPLE_RATE * 60
    const val MAX_PCM_BYTES = MAX_FRAMES * 2
    const val MAX_IMPORT_BYTES = 2_000_000

    fun encode(pcm: ByteArray): ByteArray {
        require(pcm.isNotEmpty() && pcm.size % 2 == 0 && pcm.size <= MAX_PCM_BYTES)
        val buffer = ByteBuffer.allocate(44 + pcm.size).order(ByteOrder.LITTLE_ENDIAN)
        buffer.put("RIFF".toByteArray(Charsets.US_ASCII)).putInt(36 + pcm.size)
        buffer.put("WAVEfmt ".toByteArray(Charsets.US_ASCII)).putInt(16)
        buffer.putShort(1).putShort(1).putInt(SAMPLE_RATE).putInt(SAMPLE_RATE * 2)
        buffer.putShort(2).putShort(16)
        buffer.put("data".toByteArray(Charsets.US_ASCII)).putInt(pcm.size).put(pcm)
        return buffer.array()
    }

    fun validate(bytes: ByteArray): Int {
        require(bytes.size in 44..MAX_IMPORT_BYTES) { "WAV must be at most 2 MB." }
        val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        fun tag(offset: Int) = String(bytes, offset, 4, Charsets.US_ASCII)
        fun uint(offset: Int) = buffer.getInt(offset).toLong() and 0xffffffffL
        require(tag(0) == "RIFF" && tag(8) == "WAVE" && uint(4) + 8 == bytes.size.toLong()) {
            "Select a complete RIFF/WAVE file."
        }
        var offset = 12
        var foundFormat = false
        var frames: Int? = null
        while (offset < bytes.size) {
            require(offset + 8 <= bytes.size) { "Truncated WAV chunk." }
            val length = uint(offset + 4)
            val end = offset.toLong() + 8 + length
            require(end <= bytes.size) { "Truncated WAV data." }
            when (tag(offset)) {
                "fmt " -> {
                    require(!foundFormat && length >= 16) { "Invalid WAV format chunk." }
                    val start = offset + 8
                    require(buffer.getShort(start).toInt() == 1 &&
                        buffer.getShort(start + 2).toInt() == 1 &&
                        buffer.getInt(start + 4) == SAMPLE_RATE &&
                        buffer.getInt(start + 8) == SAMPLE_RATE * 2 &&
                        buffer.getShort(start + 12).toInt() == 2 &&
                        buffer.getShort(start + 14).toInt() == 16) {
                        "WAV must be mono PCM16 at 16000 Hz. Compressed audio is unsupported."
                    }
                    foundFormat = true
                }
                "data" -> {
                    require(frames == null && length > 0 && length % 2 == 0L &&
                        length <= MAX_PCM_BYTES) { "WAV must contain audio no longer than 60 seconds." }
                    frames = (length / 2).toInt()
                }
            }
            val next = end + (length and 1L)
            require(next <= bytes.size) { "Missing WAV chunk padding." }
            offset = next.toInt()
        }
        require(foundFormat && frames != null) { "WAV needs PCM format and audio data chunks." }
        return frames
    }
}
