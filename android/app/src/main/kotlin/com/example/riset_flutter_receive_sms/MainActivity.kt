package com.example.riset_flutter_receive_sms

import android.database.Cursor
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.riset_flutter_receive_sms/inbox"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readInbox" -> {
                        val after = call.argument<Number>("afterMillis")?.toLong() ?: 0L
                        try {
                            result.success(readInbox(after))
                        } catch (e: SecurityException) {
                            result.error("PERMISSION", e.message, null)
                        } catch (e: Exception) {
                            result.error("QUERY", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readInbox(afterMillis: Long): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )
        val selection = "${Telephony.Sms.DATE} > ?"
        val selectionArgs = arrayOf(afterMillis.toString())
        val cursor: Cursor? = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${Telephony.Sms.DATE} ASC"
        )
        cursor?.use {
            val addrIdx = it.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIdx = it.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIdx = it.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (it.moveToNext()) {
                messages.add(
                    mapOf(
                        "address" to it.getString(addrIdx),
                        "body" to it.getString(bodyIdx),
                        "date" to it.getLong(dateIdx)
                    )
                )
            }
        }
        return messages
    }
}
