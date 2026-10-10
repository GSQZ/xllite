package com.sayqz.xinli_lite

import kotlin.math.min
import kotlin.math.roundToInt

/** Phone content uses the same width budget as the iPhone 17 Pro (402 points).
 * The value is per window, not a fixed DPI copied between different screens.
 */
internal object AppDisplayDensity {
    private const val PHONE_WIDTH_DP = 402f
    private const val BASE_DPI = 160f
    private const val TABLET_WIDTH_DP = 600
    private const val NARROW_WINDOW_DP = 240

    fun densityDpi(
        widthPixels: Int,
        heightPixels: Int,
        systemDensityDpi: Int,
        smallestWidthDp: Int,
        windowWidthDp: Int,
    ): Int {
        if (widthPixels <= 0 || heightPixels <= 0 || systemDensityDpi <= 0 ||
            smallestWidthDp >= TABLET_WIDTH_DP ||
            windowWidthDp in 1 until NARROW_WINDOW_DP
        ) {
            return systemDensityDpi
        }
        // Keep the scale through rotation; do not stretch a landscape phone
        // to the portrait design width. Unfolded tablets retain system density.
        return (min(widthPixels, heightPixels) / PHONE_WIDTH_DP * BASE_DPI)
            .roundToInt().coerceAtLeast(1)
    }
}
