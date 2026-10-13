package com.motouchpad.android.transport

// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

import com.motouchpad.android.model.FrameType
import com.motouchpad.android.model.TouchContact
import com.motouchpad.android.model.TouchFrame
import org.junit.Assert.*
import org.junit.Test

class TouchFrameOutboxTest {
    @Test fun movementBurstKeepsDownLatestMoveUpAndCancel() {
        val outbox = TouchFrameOutbox()
        outbox.begin(1)
        assertTrue(outbox.offer(packet(0, 0.1f)))
        for (index in 1..1000) assertTrue(outbox.offer(packet(index, 0.1f + index * 0.0005f)))
        assertTrue(outbox.offer(packet(1001, 0.6f, touching = false)))
        assertTrue(outbox.offer(TouchFrameOutbox.Packet(1, frame(1002, emptyList()))))
        assertEquals(0L, outbox.poll()!!.frame.sequence)
        assertEquals(1000L, outbox.poll()!!.frame.sequence)
        assertFalse(outbox.poll()!!.frame.contacts.first().touching)
        assertTrue(outbox.poll()!!.frame.contacts.isEmpty())
    }

    @Test fun reversalsAndSettingsChangesAreNotLost() {
        val outbox = TouchFrameOutbox()
        outbox.begin(1)
        assertTrue(outbox.offer(packet(0, 0.1f)))
        assertTrue(outbox.offer(packet(1, 0.7f)))
        assertTrue(outbox.offer(packet(2, 0.1f)))
        assertTrue(outbox.offer(TouchFrameOutbox.Packet(1, packet(3, 0.2f).frame.copy(naturalScrolling = true))))
        assertEquals(listOf(0L, 1L, 2L, 3L), (0..3).map { outbox.poll()!!.frame.sequence })
    }

    @Test fun overflowAndSessionReplacementNeverReplayOldFrames() {
        val outbox = TouchFrameOutbox(capacity = 2)
        outbox.begin(1)
        assertTrue(outbox.offer(packet(0, 0.1f)))
        assertTrue(outbox.offer(packet(1, 0.1f, touching = false)))
        assertFalse(outbox.offer(packet(2, 0.2f)))
        outbox.begin(2)
        assertTrue(outbox.offer(packet(3, 0.3f))) // stale session is ignored
        assertTrue(outbox.offer(TouchFrameOutbox.Packet(2, packet(4, 0.4f).frame)))
        assertEquals(2L, outbox.poll()!!.session)
    }

    private fun packet(sequence: Int, x: Float, touching: Boolean = true) =
        TouchFrameOutbox.Packet(1, frame(sequence, listOf(TouchContact(1, touching, x, 0.5f, 0f, 0f, 0f))))

    private fun frame(sequence: Int, contacts: List<TouchContact>) =
        TouchFrame(FrameType.TOUCH, sequence.toLong(), sequence.toLong(), 0, 100, false, contacts)
}
