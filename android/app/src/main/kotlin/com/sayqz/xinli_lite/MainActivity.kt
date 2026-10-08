package com.sayqz.xinli_lite

import com.sayqz.xinli_lite.widget.ClassWidgetProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingRoute = intent?.getStringExtra(EXTRA_ROUTE)
        // The timetable widget is drawn by native code from a snapshot the
        // app pushes; this channel is that one-way hand-off.
        widgetChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        )
        widgetChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "sync" -> {
                    val payload = call.arguments as? Map<*, *>
                    ClassWidgetProvider.store(this, payload?.get("raw") as? String)
                    result.success(null)
                }
                "clear" -> {
                    ClassWidgetProvider.store(this, null)
                    result.success(null)
                }
                // Which tab the launch asked for (a widget tap), consumed
                // once so a later launch from the launcher starts normally.
                "initialRoute" -> {
                    result.success(pendingRoute)
                    pendingRoute = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingRoute = intent.getStringExtra(EXTRA_ROUTE) ?: pendingRoute
        if (pendingRoute != null) widgetChannel?.invokeMethod("routeAvailable", null)
    }

    private var widgetChannel: MethodChannel? = null
    private var pendingRoute: String? = null

    companion object {
        private const val CHANNEL = "xinli_lite/widgets"
        private const val EXTRA_ROUTE = "xinli.route"
    }
}
