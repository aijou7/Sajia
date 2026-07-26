package id.aksaldev.sajia

import android.bluetooth.BluetoothAdapter
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "sajia/system"
    private var integrityManager: StandardIntegrityManager? = null
    private var tokenProvider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private var preparedCloudProjectNumber: Long? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openBluetoothPanel" -> {
                    openBluetoothPanel()
                    result.success(null)
                }
                "preparePlayIntegrity" -> {
                    val projectNumber = (call.argument<Number>("cloudProjectNumber"))?.toLong()
                    if (projectNumber == null || projectNumber <= 0L) {
                        result.error(
                            "PLAY_INTEGRITY_NOT_CONFIGURED",
                            "Cloud project number Play Integrity belum dikonfigurasi",
                            null
                        )
                    } else {
                        preparePlayIntegrity(projectNumber, result)
                    }
                }
                "requestPlayIntegrityToken" -> {
                    val requestHash = call.argument<String>("requestHash")
                    if (requestHash.isNullOrBlank()) {
                        result.error(
                            "PLAY_INTEGRITY_BAD_REQUEST",
                            "Request hash kosong",
                            null
                        )
                    } else {
                        requestPlayIntegrityToken(requestHash, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun preparePlayIntegrity(
        cloudProjectNumber: Long,
        result: MethodChannel.Result
    ) {
        val existingProvider = tokenProvider
        if (
            existingProvider != null &&
            preparedCloudProjectNumber == cloudProjectNumber
        ) {
            result.success(true)
            return
        }

        val manager = integrityManager
            ?: IntegrityManagerFactory.createStandard(applicationContext)
                .also { integrityManager = it }

        manager.prepareIntegrityToken(
            PrepareIntegrityTokenRequest.builder()
                .setCloudProjectNumber(cloudProjectNumber)
                .build()
        ).addOnSuccessListener { provider ->
            tokenProvider = provider
            preparedCloudProjectNumber = cloudProjectNumber
            result.success(true)
        }.addOnFailureListener { exception ->
            result.error(
                "PLAY_INTEGRITY_PREPARE_FAILED",
                exception.localizedMessage ?: "Gagal menyiapkan Play Integrity",
                null
            )
        }
    }

    private fun requestPlayIntegrityToken(
        requestHash: String,
        result: MethodChannel.Result
    ) {
        val provider = tokenProvider
        if (provider == null) {
            result.error(
                "PLAY_INTEGRITY_NOT_PREPARED",
                "Play Integrity belum disiapkan",
                null
            )
            return
        }

        provider.request(
            StandardIntegrityTokenRequest.builder()
                .setRequestHash(requestHash)
                .build()
        ).addOnSuccessListener { response ->
            result.success(response.token())
        }.addOnFailureListener { exception ->
            result.error(
                "PLAY_INTEGRITY_TOKEN_FAILED",
                exception.localizedMessage ?: "Gagal mengambil token Play Integrity",
                null
            )
        }
    }

    private fun openBluetoothPanel() {
        try {
            @Suppress("DEPRECATION")
            startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
        } catch (_: ActivityNotFoundException) {
            openBluetoothSettings()
        } catch (_: SecurityException) {
            openBluetoothSettings()
        }
    }

    private fun openBluetoothSettings() {
        try {
            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
        } catch (_: ActivityNotFoundException) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }
}
