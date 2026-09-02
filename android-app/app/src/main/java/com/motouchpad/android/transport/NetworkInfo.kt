package com.motouchpad.android.transport

// Created on 2026-09-02; updated 2026-09-02.
// @author: https://github.com/Linmoqian

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.Inet4Address

fun wifiIpv4Address(context: Context): String {
    return try {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val network = connectivity.activeNetwork ?: return "Wi-Fi 未连接"
        val capabilities = connectivity.getNetworkCapabilities(network)
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true) {
            return "Wi-Fi 未连接"
        }
        connectivity.getLinkProperties(network)
            ?.linkAddresses
            ?.firstOrNull { it.address is Inet4Address && !it.address.isLoopbackAddress }
            ?.address
            ?.hostAddress
            ?: "Wi-Fi 未连接"
    } catch (_: Exception) {
        "Wi-Fi 未连接"
    }
}
