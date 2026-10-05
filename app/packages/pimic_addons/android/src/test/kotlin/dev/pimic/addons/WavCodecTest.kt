package dev.pimic.addons

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

class WavCodecTest {
    @Test fun roundTripPreservesLittleEndianSamples() {
        val pcm = byteArrayOf(0, 0, -1, 127, 0, -128, -1, -1)
        val wav = WavCodec.encode(pcm)
        assertEquals(4, WavCodec.validate(wav))
        assertArrayEquals(pcm, wav.copyOfRange(44, wav.size))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsStereo() {
        val wav = WavCodec.encode(byteArrayOf(0, 0))
        wav[22] = 2
        WavCodec.validate(wav)
    }

    @Test fun acceptsExactSixtySecondImport() {
        assertEquals(WavCodec.MAX_FRAMES,
            WavCodec.validate(WavCodec.encode(ByteArray(WavCodec.MAX_PCM_BYTES))))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsTruncatedChunk() {
        WavCodec.validate(WavCodec.encode(byteArrayOf(0, 0)).copyOf(45))
    }

    @Test(expected = IllegalArgumentException::class)
    fun refusesCapturePastBound() {
        WavCodec.encode(ByteArray(WavCodec.MAX_PCM_BYTES + 2))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsWrongRateEvenWhenHeaderIsConsistent() {
        val wav = WavCodec.encode(byteArrayOf(0, 0))
        java.nio.ByteBuffer.wrap(wav).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            .putInt(24, 8000).putInt(28, 16000)
        WavCodec.validate(wav)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsChunkLengthOverflow() {
        val wav = WavCodec.encode(byteArrayOf(0, 0))
        java.nio.ByteBuffer.wrap(wav).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            .putInt(40, -1)
        WavCodec.validate(wav)
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsCompressedAudio() {
        val wav = WavCodec.encode(byteArrayOf(0, 0))
        wav[20] = 3 // IEEE float, not PCM16.
        WavCodec.validate(wav)
    }

    @Test fun acceptsLastFrameBelowImportLimit() {
        assertEquals(WavCodec.MAX_FRAMES - 1,
            WavCodec.validate(WavCodec.encode(ByteArray(WavCodec.MAX_PCM_BYTES - 2))))
    }

    @Test fun acceptsSixtySecondsWithAncillaryMetadataWithinFileCap() {
        val wav = WavCodec.encode(ByteArray(WavCodec.MAX_PCM_BYTES))
        val buffer = java.nio.ByteBuffer.allocate(wav.size + 12)
            .order(java.nio.ByteOrder.LITTLE_ENDIAN)
        buffer.put(wav).put("LIST".toByteArray(Charsets.US_ASCII)).putInt(4).putInt(0)
        buffer.putInt(4, buffer.capacity() - 8)
        assertEquals(WavCodec.MAX_FRAMES, WavCodec.validate(buffer.array()))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsSixtySecondsPlusOneFrameEvenBelowFileCap() {
        val wav = WavCodec.encode(ByteArray(WavCodec.MAX_PCM_BYTES)).copyOf(44 + WavCodec.MAX_PCM_BYTES + 2)
        java.nio.ByteBuffer.wrap(wav).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            .putInt(4, wav.size - 8).putInt(40, WavCodec.MAX_PCM_BYTES + 2)
        WavCodec.validate(wav)
    }
}
