package com.motouchpad.android.transport

// Created on 2026-10-13.
// @author: https://github.com/Linmoqian

import com.motouchpad.android.model.FrameType
import com.motouchpad.android.model.TouchFrame
import java.util.ArrayDeque

/** Only adjacent movement snapshots are replaceable; transitions always remain ordered. */
class TouchFrameOutbox(private val capacity: Int = 32) {
    data class Packet(val session: Long, val frame: TouchFrame)
    private data class Entry(val packet: Packet, val anchor: TouchFrame?)
    private val lock = Object()
    private val entries = ArrayDeque<Entry>()
    private var session = 0L
    private var accepting = false
    private var previous: TouchFrame? = null

    fun begin(session: Long) = synchronized(lock) {
        entries.clear()
        previous = null
        this.session = session
        accepting = true
    }

    fun clear() = synchronized(lock) {
        entries.clear()
        previous = null
        accepting = false
        lock.notifyAll()
    }

    /** False on critical-frame overflow; caller disconnects rather than dropping a release. */
    fun offer(packet: Packet): Boolean = synchronized(lock) {
        if (!accepting || packet.session != session) return true
        val replaceable = previous?.let { sameMotionSession(it, packet.frame) } ?: false
        val tail = entries.peekLast()
        val replaceTail = replaceable && tail?.anchor != null &&
            movementContinues(tail.anchor, tail.packet.frame, packet.frame)
        if (replaceTail) {
            entries.removeLast()
        } else if (entries.size >= capacity) {
            return false
        }
        entries.addLast(Entry(packet, if (replaceTail) tail?.anchor else if (replaceable) previous else null))
        previous = packet.frame
        lock.notifyAll()
        true
    }

    fun poll(): Packet? = synchronized(lock) {
        if (entries.isEmpty()) lock.wait(500)
        entries.pollFirst()?.packet
    }

    private fun sameMotionSession(first: TouchFrame, second: TouchFrame): Boolean {
        if (first.type != FrameType.TOUCH || second.type != FrameType.TOUCH ||
            first.contacts.isEmpty() || first.contacts.size != second.contacts.size ||
            first.buttons != second.buttons || first.sensitivityPercent != second.sensitivityPercent ||
            first.naturalScrolling != second.naturalScrolling) return false
        return first.contacts.all { contact ->
            contact.touching && second.contacts.any { it.touching && it.id == contact.id }
        }
    }

    private fun movementContinues(anchor: TouchFrame, current: TouchFrame, next: TouchFrame): Boolean {
        return current.contacts.all { point ->
            val start = anchor.contacts.first { it.id == point.id }
            val end = next.contacts.first { it.id == point.id }
            val ax = point.x - start.x
            val ay = point.y - start.y
            val bx = end.x - point.x
            val by = end.y - point.y
            val dot = ax * bx + ay * by
            val magnitude = (ax * ax + ay * ay) * (bx * bx + by * by)
            magnitude == 0f || (dot >= 0f && dot * dot >= 0.7225f * magnitude)
        }
    }
}
