package io.github.saimadhav10.coc_tracker

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReminderEngineTest {
    @Test fun overnightQuietHoursRespectBothBoundaries() {
        assertFalse(ReminderEngine.isQuiet(21, 22, 8))
        assertTrue(ReminderEngine.isQuiet(22, 22, 8))
        assertTrue(ReminderEngine.isQuiet(0, 22, 8))
        assertTrue(ReminderEngine.isQuiet(7, 22, 8))
        assertFalse(ReminderEngine.isQuiet(8, 22, 8))
    }
    @Test fun daytimeAndDisabledQuietHours() {
        assertFalse(ReminderEngine.isQuiet(8, 9, 17))
        assertTrue(ReminderEngine.isQuiet(9, 9, 17))
        assertFalse(ReminderEngine.isQuiet(17, 9, 17))
        for (hour in 0..23) assertFalse(ReminderEngine.isQuiet(hour, 8, 8))
    }
    @Test fun remindersWaitForInactivityAndRepeatInterval() {
        val hour = 3600000L
        val clock = 100 * hour
        assertFalse(ReminderEngine.inactivityDue(clock, clock - 23 * hour, 0))
        assertTrue(ReminderEngine.inactivityDue(clock, clock - 24 * hour, 0))
        assertFalse(ReminderEngine.inactivityDue(clock, clock - 25 * hour, clock - 2 * hour))
        assertTrue(ReminderEngine.inactivityDue(clock, clock - 25 * hour, clock - 3 * hour))
        assertFalse(ReminderEngine.inactivityDue(clock, clock - hour, clock - 3 * hour))
    }
}
