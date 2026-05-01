package com.ospab.byteaway.tile

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.content.Intent
import android.os.Build
import com.ospab.byteaway.service.ByteAwayForegroundService
import com.ospab.byteaway.service.ServiceBridge

class VpnTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        
        val currentState = qsTile.state
        val isVpnRunning = ByteAwayForegroundService.isVpnRunning.get()
        
        if (isVpnRunning) {
            // Stop VPN
            val intent = Intent(this, ByteAwayForegroundService::class.java).apply {
                action = ByteAwayForegroundService.ACTION_STOP_VPN
            }
            startService(intent)
        } else {
            // Start VPN - need to get config from Flutter
            // Trigger VPN start through Flutter
            ServiceBridge.sendEvent(mapOf(
                "action" to "toggle_vpn",
                "vpnConnected" to false
            ))
        }
        
        // Update tile state immediately
        qsTile.state = if (isVpnRunning) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        qsTile.updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
    }

    private fun updateTile() {
        val isVpnRunning = ByteAwayForegroundService.isVpnRunning.get()
        val isVpnConnecting = ByteAwayForegroundService.isVpnConnecting.get()
        
        qsTile.state = when {
            isVpnRunning -> Tile.STATE_ACTIVE
            isVpnConnecting -> Tile.STATE_UNAVAILABLE
            else -> Tile.STATE_INACTIVE
        }
        
        qsTile.label = if (isVpnRunning) "VPN Вкл" else "VPN Выкл"
        qsTile.updateTile()
    }
}
