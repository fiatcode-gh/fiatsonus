package dev.fiatcode.fiatsonus

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Cancels audio_service's notification after a stop (PLAN 4.6).
 *
 * audio_service leaves the foreground with STOP_FOREGROUND_DETACH and then
 * cancels the notification. system_server strips the notification's
 * FLAG_FOREGROUND_SERVICE through two handler hops, and drops an app's cancel
 * while that flag is set, so the cancel can arrive too early and the
 * notification stays. This polls the app's own active notifications and
 * cancels the notification once the flag is gone. While the service is in
 * the foreground the flag stays set, so a playing notification is never
 * cancelled.
 */
class PlaybackNotification(context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val handler = Handler(Looper.getMainLooper())

    fun clear() {
        handler.removeCallbacksAndMessages(null)
        poll(MAX_POLLS)
    }

    private fun poll(left: Int) {
        val posted = manager.activeNotifications.firstOrNull { it.id == ID } ?: return
        if (posted.notification.flags and Notification.FLAG_FOREGROUND_SERVICE == 0) {
            Log.i(TAG, "cancelling notification $ID left after its service stopped")
            manager.cancel(ID)
        }
        if (left > 1) handler.postDelayed({ poll(left - 1) }, POLL_MS)
    }

    private companion object {
        const val TAG = "fiatsonus"

        /** audio_service's NOTIFICATION_ID. */
        const val ID = 1124
        const val POLL_MS = 50L

        /** Gives up after 5 s, e.g. when playback has started again. */
        const val MAX_POLLS = 100
    }
}
