package com.ospab.byteaway.tile

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.content.Intent
import com.ospab.byteaway.service.ByteAwayForegroundService
import com.ospab.byteaway.service.ServiceBridge

class NodeTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTile()
    }

    override fun onClick() {
        super.onClick()
        
        val isNodeActive = ByteAwayForegroundService.isNodeActive.get()
        
        if (isNodeActive) {
            // Stop node
            val intent = Intent(this, ByteAwayForegroundService::class.java).apply {
                action = ByteAwayForegroundService.ACTION_STOP_NODE
            }
            startService(intent)
        } else {
            // Start node - trigger through Flutter
            ServiceBridge.sendEvent(mapOf(
                "action" to "toggle_node",
                "nodeActive" to false
            ))
        }
        
        // Update tile state immediately
        qsTile.state = if (isNodeActive) Tile.STATE_INACTIVE else Tile.STATE_ACTIVE
        qsTile.updateTile()
    }

    override fun onStopListening() {
        super.onStopListening()
    }

    private fun updateTile() {
        val isNodeActive = ByteAwayForegroundService.isNodeActive.get()
        val isNodeConnecting = ByteAwayForegroundService.isNodeConnecting.get()
        
        qsTile.state = when {
            isNodeActive -> Tile.STATE_ACTIVE
            isNodeConnecting -> Tile.STATE_UNAVAILABLE
            else -> Tile.STATE_INACTIVE
        }
        
        qsTile.label = if (isNodeActive) "Узел Вкл" else "Узел Выкл"
        qsTile.updateTile()
    }
}
