package com.sayqz.xinli_lite.widget

import org.json.JSONObject

/**
 * Everything the widget draws, already formatted by the app.
 *
 * Kotlin never parses the school's timetable: it renders this, so Android and
 * iOS cannot drift apart and a change on the server never needs a native fix.
 */
data class WidgetSnapshotData(
    val status: String,
    val title: String,
    val subtitle: String,
    val room: String,
    val teacher: String,
    val label: String,
    val trailing: String,
    val metaTexts: List<String>,
    val timeRange: String,
    val progress: Float?,
    val minutes: Int?,
    val week: Int?,
    val accent: Int,
) {
    /** True when there is no course to show (free day, term over, signed out). */
    val isEmpty: Boolean
        get() = title.isEmpty()

    /** The pill's label: 正在上课 / 下一节. */
    val pillLabel: String
        get() = label.ifEmpty {
            when (status) {
                "in_class" -> "正在上课"
                "upcoming" -> "下一节"
                else -> statusLabel(status)
            }
        }

    /** "12 周" or null. */
    val weekLabel: String?
        get() = week?.let { "第 $it 周" }

    /** The room on its own, falling back to the combined line. */
    val roomLabel: String
        get() = room.ifEmpty { subtitle }

    companion object {
        const val PREFS = "xinli_widget"
        const val KEY = "xinli.widget.snapshot"
        const val DEFAULT_ACCENT = -14848040 // 0xFF1D6FD8

        fun parse(raw: String?, now: Long = System.currentTimeMillis()): WidgetSnapshotData? {
            if (raw.isNullOrBlank()) return null
            return try {
                val envelope = JSONObject(raw)
                if (envelope.optInt("v") != 2 || now >= envelope.optLong("expiresAt")) return null
                val entries = envelope.optJSONArray("entries") ?: return null
                var selected: JSONObject? = null
                for (i in 0 until entries.length()) {
                    val entry = entries.getJSONObject(i)
                    if (entry.optLong("at") <= now) selected = entry else break
                }
                val json = selected ?: return null
                val status = json.optString("status", "idle")
                val start = json.optLong("startsAt")
                val end = json.optLong("endsAt")
                val remaining = when (status) {
                    "in_class" -> ((end - now).coerceAtLeast(0) / 60000).toInt()
                    "upcoming" -> ((start - now).coerceAtLeast(0) / 60000).toInt()
                    else -> null
                }
                WidgetSnapshotData(
                    status = json.optString("status", "idle"),
                    title = json.optString("title"),
                    subtitle = json.optString("subtitle"),
                    room = json.optString("where"),
                    teacher = json.optString("teacher"),
                    label = json.optString("label"),
                    trailing = json.optString("trailing"),
                    metaTexts = json.optJSONArray("metaTexts")?.let { array ->
                        (0 until array.length()).map { array.optString(it) }
                    } ?: emptyList(),
                    timeRange = json.optString("timeRange"),
                    progress = if (status == "in_class" && end > start) {
                        ((now - start).toFloat() / (end - start)).coerceIn(0f, 1f)
                    } else null,
                    minutes = remaining,
                    week = if (json.isNull("week")) null else json.optInt("week"),
                    accent = json.optInt("accent", DEFAULT_ACCENT),
                )
            } catch (_: Exception) {
                null
            }
        }
    }
}

/** The row's leading label. */
fun statusLabel(status: String): String = when (status) {
    "in_class" -> "正在上课"
    "upcoming" -> "下一节课"
    "free" -> "今天没课"
    "done" -> "今日课程已结束"
    else -> "课表待同步"
}

/**
 * The countdown shown at the top right: how long is left, or how long until
 * it starts. Empty when there is nothing to count, so the row never shows
 * the time range twice.
 */
fun timeHint(snapshot: WidgetSnapshotData): String {
    val minutes = snapshot.minutes ?: return ""
    return when (snapshot.status) {
        "in_class" -> "还有 $minutes 分钟"
        "upcoming" -> when {
            minutes < 60 -> "$minutes 分钟后"
            minutes < 24 * 60 -> "${minutes / 60} 小时后"
            else -> "${minutes / (24 * 60)} 天后"
        }
        else -> ""
    }
}
