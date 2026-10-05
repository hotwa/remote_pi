package dev.pimic.addons

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** One cancellable, bounded import. Opening a blocking provider keeps its operation busy. */
internal class WavImportReader {
    val cancelled = AtomicBoolean(false)
    private val activeStream = AtomicReference<InputStream?>()

    fun requestCancellation(): InputStream? {
        cancelled.set(true)
        return activeStream.getAndSet(null)
    }

    private fun checkCancellation() {
        if (cancelled.get() || Thread.currentThread().isInterrupted) throw CancellationException()
    }

    fun read(open: () -> InputStream?): ByteArray {
        checkCancellation()
        val input = open() ?: throw IOException("Unable to open WAV.")
        activeStream.set(input)
        try {
            checkCancellation()
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                checkCancellation()
                val count = input.read(buffer)
                checkCancellation()
                if (count < 0) break
                require(output.size() + count <= WavCodec.MAX_IMPORT_BYTES) { "WAV must be at most 2 MB." }
                output.write(buffer, 0, count)
            }
            return output.toByteArray()
        } finally {
            // A cancelling thread may already own the close. Close exactly once.
            if (activeStream.compareAndSet(input, null)) input.close()
        }
    }
}
