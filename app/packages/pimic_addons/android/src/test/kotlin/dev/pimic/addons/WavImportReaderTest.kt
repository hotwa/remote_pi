package dev.pimic.addons

import java.io.ByteArrayInputStream
import java.io.InputStream
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class WavImportReaderTest {
    @Test fun readsWavAndClosesStream() {
        val bytes = WavCodec.encode(byteArrayOf(0, 0))
        var closed = false
        val input = object : ByteArrayInputStream(bytes) {
            override fun close() { closed = true; super.close() }
        }
        assertArrayEquals(bytes, WavImportReader().read { input })
        assertTrue(closed)
    }

    @Test(expected = IllegalArgumentException::class)
    fun capsReadEvenForUnknownProviderLength() {
        WavImportReader().read { ByteArrayInputStream(ByteArray(WavCodec.MAX_IMPORT_BYTES + 1)) }
    }

    @Test fun cancellationBeforeOpeningNeverContactsProvider() {
        val reader = WavImportReader()
        reader.requestCancellation()
        var opened = false
        try { reader.read { opened = true; ByteArrayInputStream(byteArrayOf(1)) }; fail() }
        catch (_: CancellationException) { assertFalse(opened) }
    }

    @Test fun cancellationDuringOpenClosesReturnedStreamAndDiscardsBytes() {
        val reader = WavImportReader()
        var closed = false
        val input = object : ByteArrayInputStream(byteArrayOf(1)) {
            override fun close() { closed = true }
        }
        try { reader.read { reader.requestCancellation(); input }; fail() }
        catch (_: CancellationException) { assertTrue(closed) }
    }

    @Test fun closeUnblocksReadAndCancelledAudioNeverReturns() {
        val reading = CountDownLatch(1)
        val closed = CountDownLatch(1)
        val input = object : InputStream() {
            override fun read(): Int { reading.countDown(); closed.await(); return 1 }
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int = read()
            override fun close() { closed.countDown() }
        }
        val reader = WavImportReader()
        val pool = Executors.newSingleThreadExecutor()
        try {
            val result = pool.submit<Boolean> {
                try { reader.read { input }; false }
                catch (_: CancellationException) { true }
            }
            assertTrue(reading.await(1, TimeUnit.SECONDS))
            reader.requestCancellation()?.close()
            assertTrue(result.get(1, TimeUnit.SECONDS))
        } finally { pool.shutdownNow() }
    }
}
