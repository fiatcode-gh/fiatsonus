package dev.fiatcode.fiatsonus

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel(flutterEngine).setMethodCallHandler { call, result ->
            if (call.method == "request") requestNotifications(result) else result.notImplemented()
        }
        // Holds only the application context, so it stays registered after
        // this activity is gone: a notification Stop can come without it.
        val notification = PlaybackNotification(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "clear") {
                    notification.clear()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // The engine is cached by audio_service and outlives this activity.
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel(flutterEngine).setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun channel(flutterEngine: FlutterEngine) =
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

    private fun requestNotifications(result: MethodChannel.Result) {
        when {
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU -> result.success(true)
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED -> result.success(true)
            pending != null -> result.error("busy", "A permission request is already pending", null)
            else -> {
                pending = result
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_CODE)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE) return
        val result = pending ?: return
        pending = null
        result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
    }

    private companion object {
        const val CHANNEL = "fiatsonus/notification_permission"
        const val NOTIFICATION_CHANNEL = "fiatsonus/playback_notification"
        const val REQUEST_CODE = 1001
    }
}
