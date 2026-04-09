package com.ospab.byteaway.service

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class ByteAwayTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    private fun updateTile() {
        val isCurrentlyRunning = ByteAwayForegroundService.isVpnRunning.get() || 
                                 ByteAwayForegroundService.isVpnConnecting.get()
        
        val tile = qsTile ?: return
        tile.state = if (isCurrentlyRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val isCurrentlyRunning = ByteAwayForegroundService.isVpnRunning.get() || 
                                 ByteAwayForegroundService.isVpnConnecting.get()
        
        val intent = Intent(this, ByteAwayForegroundService::class.java).apply {
            action = if (isCurrentlyRunning) {
                ByteAwayForegroundService.ACTION_STOP_VPN
            } else {
                ByteAwayForegroundService.ACTION_TOGGLE_VPN
            }
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        
        // Brief delay to allow state to start changing
        updateTile()
    }
    
    companion object {
        fun requestUpdate(context: android.content.Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                requestListeningState(context, android.content.ComponentName(context, ByteAwayTileService::class.java))
            }
        }
    }
}
