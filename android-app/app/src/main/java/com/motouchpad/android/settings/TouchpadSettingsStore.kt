package com.motouchpad.android.settings

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

import android.content.Context
import com.motouchpad.android.model.TouchpadSettings

class TouchpadSettingsStore(context: Context) {
    private val preferences = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )

    fun load(): TouchpadSettings = TouchpadSettings(
        sensitivityPercent = preferences.getInt(KEY_SENSITIVITY, 100).coerceIn(50, 200),
        naturalScrolling = preferences.getBoolean(KEY_NATURAL_SCROLLING, false)
    )

    fun save(settings: TouchpadSettings) {
        preferences.edit()
            .putInt(KEY_SENSITIVITY, settings.sensitivityPercent.coerceIn(50, 200))
            .putBoolean(KEY_NATURAL_SCROLLING, settings.naturalScrolling)
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "touchpad_settings"
        const val KEY_SENSITIVITY = "sensitivity"
        const val KEY_NATURAL_SCROLLING = "natural_scrolling"
    }
}
