package xyz.depollsoft.monkeyssh

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "xyz.depollsoft.monkeyssh/ssh_service"
    private val notificationsPermissionRequestCode = 101

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        requestNotificationsIfNeeded()
                        val hostName = call.argument<String>("hostName") ?: "SSH server"
                        val intent = Intent(this, SshConnectionService::class.java).apply {
                            putExtra("hostName", hostName)
                        }
                        startForegroundService(intent)
                        result.success(null)
                    }
                    "stopService" -> {
                        val intent = Intent(this, SshConnectionService::class.java).apply {
                            action = SshConnectionService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationsIfNeeded() {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                notificationsPermissionRequestCode
            )
        }
    }
}
