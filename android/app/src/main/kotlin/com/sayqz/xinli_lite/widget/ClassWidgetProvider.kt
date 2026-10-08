package com.sayqz.xinli_lite.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Bundle
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import com.sayqz.xinli_lite.MainActivity
import com.sayqz.xinli_lite.R

/**
 * The horizontal timetable widget.
 *
 * It only draws [WidgetSnapshotData]: one row, one course, one hint. The app
 * pushes a new snapshot through the widget bridge whenever the timetable
 * changes, and a cheap repeated alarm keeps the countdown honest while the
 * widget sits on the home screen.
 */
class ClassWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        ids.forEach { render(context, manager, it) }
        scheduleRefresh(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in listOf(REFRESH, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED)) {
            refreshAll(context)
            scheduleRefresh(context)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        render(context, manager, id)
    }

    override fun onDisabled(context: Context) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            ?: return
        alarm.cancel(refreshIntent(context))
    }

    companion object {
        private const val REFRESH = "com.sayqz.xinli_lite.WIDGET_REFRESH"
        private const val PREFS = WidgetSnapshotData.PREFS
        private const val REFRESH_MS = 15L * 60L * 1000L

        /** Writes a snapshot (null clears it) and repaints every widget. */
        fun store(context: Context, raw: String?) {
            val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            if (raw == null) {
                editor.remove(WidgetSnapshotData.KEY)
            } else {
                editor.putString(WidgetSnapshotData.KEY, raw)
            }
            editor.apply()
            refreshAll(context)
        }

        private fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(
                ComponentName(context, ClassWidgetProvider::class.java),
            )
            ids.forEach { render(context, manager, it) }
        }

        private fun snapshotOf(context: Context): WidgetSnapshotData? =
            WidgetSnapshotData.parse(
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    .getString(WidgetSnapshotData.KEY, null),
            )

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
        ) {
            val night = isNight(context)
            val snapshot = snapshotOf(context)
            val hasCourse = snapshot != null && !snapshot.isEmpty
            val accent = snapshot?.accent ?: DEFAULT_ACCENT
            val views = RemoteViews(context.packageName, R.layout.widget_class)

            // The card's own quiet surface, the same one the app's cards use.
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                if (night) R.drawable.widget_card_dark else R.drawable.widget_card_light,
            )

            // The pill is the skin colour at 14% with the skin colour as ink;
            // Android tints rather than alpha-blends, so the drawable is
            // painted at full strength and the text carries the contrast.
            views.setColorStateList(
                R.id.widget_pill,
                "setBackgroundTintList",
                ColorStateList.valueOf(withAlpha(accent, 0x24)),
            )
            views.setColorStateList(
                R.id.widget_pill_dot,
                "setBackgroundTintList",
                ColorStateList.valueOf(accent),
            )
            views.setTextColor(R.id.widget_pill_label, accent)
            views.setTextViewText(
                R.id.widget_pill_label,
                snapshot?.pillLabel ?: statusLabel("idle"),
            )
            views.setTextViewText(R.id.widget_trailing, snapshot?.trailing ?: "")
            views.setViewVisibility(
                R.id.widget_trailing,
                if (snapshot?.trailing.isNullOrEmpty()) View.GONE else View.VISIBLE,
            )
            views.setTextColor(R.id.widget_trailing, mutedColor(night))

            views.setViewVisibility(
                R.id.widget_body,
                if (hasCourse) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_empty,
                if (hasCourse) View.GONE else View.VISIBLE,
            )
            views.setTextColor(R.id.widget_empty_title, titleColor(night))
            views.setTextColor(R.id.widget_empty_hint, mutedColor(night))
            views.setTextViewText(
                R.id.widget_empty_title,
                when (snapshot?.status) {
                    "done" -> "今天的课都上完啦"
                    "free" -> "今天没有课程"
                    else -> "课表还没同步"
                },
            )
            views.setTextViewText(
                R.id.widget_empty_hint,
                if (snapshot?.status in listOf("done", "free")) {
                    "好好享受课余时光"
                } else {
                    "打开新理Lite 看一眼课表"
                },
            )

            if (hasCourse) {
                val course = snapshot!!
                val progress = course.progress
                views.setTextViewText(R.id.widget_title, course.title)
                views.setTextColor(R.id.widget_title, titleColor(night))

                // Meta line: time and teacher. RemoteViews cannot lay out
                // per-item glyphs reliably across launchers, so the values
                // are separated by a middot instead of an icon each.
                views.setTextViewText(
                    R.id.widget_meta,
                    course.metaTexts.joinToString("  ·  "),
                )
                views.setTextColor(R.id.widget_meta, mutedColor(night))

                // The room owns the last line, where nothing competes with it.
                val room = course.roomLabel
                views.setTextViewText(R.id.widget_room, room)
                views.setTextColor(R.id.widget_room, mutedColor(night))
                views.setViewVisibility(
                    R.id.widget_room,
                    if (room.isEmpty()) View.GONE else View.VISIBLE,
                )

                val showProgress = progress != null
                views.setViewVisibility(
                    R.id.widget_progress_track,
                    if (showProgress) View.VISIBLE else View.GONE,
                )
                if (showProgress) {
                    views.setImageViewBitmap(
                        R.id.widget_progress_track,
                        progressTrack(progress!!, accent),
                    )
                }
            }

            views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
            manager.updateAppWidget(id, views)
        }

        /**
         * The progress track, drawn once and scaled by the ImageView.
         * RemoteViews has no cheap way to clip a rounded bar, so it is
         * painted at a fixed size and stretched.
         */
        private fun progressTrack(progress: Float, accent: Int): Bitmap {
            val width = 600
            val height = 12
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.color = accent
            paint.alpha = 40
            canvas.drawRoundRect(0f, 0f, width.toFloat(), height.toFloat(), 6f, 6f, paint)
            paint.alpha = 255
            val filled = (progress.coerceIn(0f, 1f) * width).coerceAtLeast(12f)
            canvas.drawRoundRect(0f, 0f, filled, height.toFloat(), 6f, 6f, paint)
            return bitmap
        }

        /** Tapping the widget opens the timetable. */
        private fun openApp(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("xinli.route", "schedule")
            }
            return PendingIntent.getActivity(context, 0, intent, pendingFlags())
        }

        private fun refreshIntent(context: Context): PendingIntent {
            val intent = Intent(context, ClassWidgetProvider::class.java).apply {
                action = REFRESH
            }
            return PendingIntent.getBroadcast(context, 1, intent, pendingFlags())
        }

        private fun pendingFlags(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

        /**
         * Rebuilds the hint every quarter hour. Inexact on purpose: being a
         * minute off is invisible here, and this must never wake the device.
         */
        private fun scheduleRefresh(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            if (manager.getAppWidgetIds(ComponentName(context, ClassWidgetProvider::class.java)).isEmpty()) return
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                ?: return
            alarm.setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + REFRESH_MS,
                REFRESH_MS,
                refreshIntent(context),
            )
        }

        private fun isNight(context: Context): Boolean =
            (
                context.resources.configuration.uiMode and
                    Configuration.UI_MODE_NIGHT_MASK
                ) == Configuration.UI_MODE_NIGHT_YES

        private fun titleColor(night: Boolean): Int =
            Color.parseColor(if (night) "#F0F2F6" else "#14161B")

        private fun mutedColor(night: Boolean): Int =
            Color.parseColor(if (night) "#9AA1B1" else "#6B7280")

        private fun withAlpha(color: Int, alpha: Int): Int =
            Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color))

        /** Campus blue, used until the app has ever synced a skin. */
        private const val DEFAULT_ACCENT = -14848040 // 0xFF1D6FD8
    }
}
