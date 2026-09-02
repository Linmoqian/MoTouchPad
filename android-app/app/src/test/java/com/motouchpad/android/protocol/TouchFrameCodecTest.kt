package com.motouchpad.android.protocol

import com.motouchpad.android.model.FrameType
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

class TouchFrameCodecTest {
    @Test
    fun decodesAndReencodesGoldenFrames() {
        validFixtures
            .filterNot { it == "stream-two-frames.hex" }
            .forEach { name ->
                val bytes = fixture(name)
                val frame = TouchFrameCodec.decode(bytes)
                assertArrayEquals(name, bytes, TouchFrameCodec.encode(frame))
            }
    }

    @Test
    fun rejectsInvalidGoldenFrames() {
        invalidFixtures.forEach { name ->
            val result = runCatching { TouchFrameCodec.decode(fixture(name)) }
            assertTrue("$name was accepted", result.isFailure)
        }
    }

    @Test
    fun handlesFragmentedAndCoalescedStream() {
        val source = fixture("stream-two-frames.hex")
        val chunks = listOf(source.copyOfRange(0, 1), source.copyOfRange(1, 7),
            source.copyOfRange(7, 31), source.copyOfRange(31, source.size))
        val merged = ByteArrayOutputStream()
        chunks.forEach(merged::write)

        val frames = splitFrames(merged.toByteArray())
        assertEquals(2, frames.size)
        assertEquals(FrameType.HELLO, TouchFrameCodec.decode(frames[0]).type)
        assertEquals(FrameType.TOUCH, TouchFrameCodec.decode(frames[1]).type)
    }

    @Test
    fun mapsWireSensitivityZeroToOneHundred() {
        val bytes = fixture("empty-touch.hex")
        bytes[22] = 0
        assertEquals(100, TouchFrameCodec.decode(bytes).sensitivityPercent)
    }

    private fun fixture(name: String): ByteArray {
        val loader = checkNotNull(Thread.currentThread().contextClassLoader)
        val stream = loader.getResourceAsStream(name)
            ?: error("Missing fixture $name")
        return stream.use {
            it.bufferedReader().readText().trim().split(" ")
                .filter(String::isNotEmpty)
                .map { it.toInt(16).toByte() }
                .toByteArray()
        }
    }

    private fun splitFrames(bytes: ByteArray): List<ByteArray> {
        val frames = mutableListOf<ByteArray>()
        var offset = 0
        while (offset < bytes.size) {
            val count = bytes[offset + 20].toInt() and 0xFF
            val length = TouchProtocol.HEADER_SIZE + count * TouchProtocol.CONTACT_SIZE
            frames += bytes.copyOfRange(offset, offset + length)
            offset += length
        }
        return frames
    }

    private companion object {
        val validFixtures = listOf(
            "hello-empty.hex",
            "empty-touch.hex",
            "single-down.hex",
            "single-move.hex",
            "single-up.hex",
            "two-scroll-start.hex",
            "two-scroll-move.hex",
            "two-pinch-start.hex",
            "two-pinch-move.hex",
            "five-finger-max.hex"
        )
        val invalidFixtures = listOf(
            "invalid-version.hex",
            "invalid-type.hex",
            "invalid-count.hex",
            "invalid-float.hex",
            "invalid-length.hex",
            "invalid-flags.hex",
            "invalid-state.hex"
        )
    }
}
