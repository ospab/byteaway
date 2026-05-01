package com.ospab.byteaway.service

object OstpJni {
    init {
        System.loadLibrary("ostp_android_jni")
    }

    external fun createClient(
        serverAddr: String,
        sessionId: Int,
        privateKey: ByteArray,
        token: String,
        country: String,
        connType: String,
        hwid: String
    ): Long

    external fun startClient(clientId: Long): Boolean

    external fun sendData(clientId: Long, streamId: Int, data: ByteArray): Boolean

    external fun receiveData(clientId: Long, data: ByteArray): Boolean

    external fun getSendData(clientId: Long): ByteArray

    external fun closeClient(clientId: Long)
}
