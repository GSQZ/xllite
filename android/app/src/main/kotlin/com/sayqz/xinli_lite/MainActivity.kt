package com.sayqz.xinli_lite

import android.content.res.Configuration
import android.content.res.Resources
import com.sayqz.xinli_lite.widget.ClassWidgetProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var densityResources: Resources? = null
    private var sourceConfiguration: Configuration? = null
    private var sourceWidth = 0
    private var sourceHeight = 0

    override fun getResources(): Resources {
        val original = super.getResources()
        val config = original.configuration
        val metrics = original.displayMetrics
        val dpi = AppDisplayDensity.densityDpi(
            metrics.widthPixels,
            metrics.heightPixels,
            config.densityDpi,
            config.smallestScreenWidthDp,
            config.screenWidthDp,
        )
        if (dpi == config.densityDpi) return original
        if (sourceConfiguration != config || sourceWidth != metrics.widthPixels ||
            sourceHeight != metrics.heightPixels || densityResources == null
        ) {
            sourceConfiguration = Configuration(config)
            sourceWidth = metrics.widthPixels
            sourceHeight = metrics.heightPixels
            // A separate resource context changes only this Activity. Flutter
            // reads its DPR here, so rendering, insets, taps and platform views
            // share a real coordinate system. Leave fontScale/locales intact.
            val override = Configuration(config).apply { densityDpi = dpi }
            densityResources = baseContext.createConfigurationContext(override).resources
        }
        return densityResources!!
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        densityResources = null
        sourceConfiguration = null
        super.onConfigurationChanged(newConfig)
    }

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
