package com.example.mosmobile

import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "mosco_mobile/file_reader"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "readFile") {
                    val uriString = call.argument<String>("uri")
                    if (uriString == null) {
                        result.error("NULL_URI", "URI was null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriString)
                        val inputStream = contentResolver.openInputStream(uri)
                        if (inputStream == null) {
                            result.error("NULL_STREAM", "Could not open input stream", null)
                            return@setMethodCallHandler
                        }
                        val buffer = ByteArrayOutputStream()
                        val chunk = ByteArray(8192)
                        var bytesRead: Int
                        while (inputStream.read(chunk).also { bytesRead = it } != -1) {
                            buffer.write(chunk, 0, bytesRead)
                        }
                        inputStream.close()
                        val bytes = buffer.toByteArray()
                        result.success(bytes)
                    } catch (e: Exception) {
                        result.error("READ_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
