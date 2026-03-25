package xyz.depollsoft.monkeyssh

import android.os.Build
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Method-channel bridge for Android's built-in on-device GenAI runtime.
 */
class LocalTerminalAiBridge(binaryMessenger: BinaryMessenger) {
    companion object {
        private const val CHANNEL_NAME = "xyz.depollsoft.monkeyssh/local_terminal_ai"
        private const val PROVIDER_NAME = "androidAiCore"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val methodChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)
    private var generativeModel: GenerativeModel? = null

    fun start() {
        methodChannel.setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        generativeModel?.close()
        generativeModel = null
        scope.cancel()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getRuntimeInfo" -> {
                scope.launch {
                    result.success(buildRuntimeInfo())
                }
            }
            "generateText" -> {
                scope.launch {
                    handleGenerateText(call, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    private suspend fun handleGenerateText(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val prompt = arguments?.get("prompt") as? String
        val maxTokens = arguments?.get("maxTokens") as? Int
        if (prompt == null || prompt.isBlank() || maxTokens == null || maxTokens <= 0) {
            result.error(
                "invalid_args",
                "Missing Android AI Core prompt arguments.",
                null,
            )
            return
        }

        try {
            val model = getGenerativeModel()
            ensureModelReady(model)
            val response = model.generateContent(
                generateContentRequest(TextPart(prompt)) {
                    temperature = 0.2f
                    maxOutputTokens = maxTokens
                    candidateCount = 1
                },
            )
            val text = response.candidates.firstOrNull()?.text?.trim()
            if (text.isNullOrEmpty()) {
                result.error(
                    "empty_response",
                    "Android AI Core returned an empty response.",
                    null,
                )
                return
            }
            result.success(text)
        } catch (error: Exception) {
            result.error(
                "generation_error",
                error.message ?: "Android AI Core generation failed.",
                null,
            )
        }
    }

    private suspend fun buildRuntimeInfo(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return runtimeInfo(
                supportedPlatform = false,
                available = false,
                statusMessage = "Android AI Core requires Android 12 or newer.",
            )
        }

        return try {
            val model = getGenerativeModel()
            val status = model.checkStatus()
            val baseModelName = runCatching { model.getBaseModelName() }.getOrNull()
            when (status) {
                FeatureStatus.AVAILABLE -> runtimeInfo(
                    supportedPlatform = true,
                    available = true,
                    statusMessage = "Gemini Nano is ready on this device.",
                    modelName = baseModelName,
                )
                FeatureStatus.UNAVAILABLE -> runtimeInfo(
                    supportedPlatform = false,
                    available = false,
                    statusMessage =
                        "Android AI Core prompt generation is unavailable on this device.",
                    modelName = baseModelName,
                )
                else -> runtimeInfo(
                    supportedPlatform = true,
                    available = false,
                    statusMessage =
                        "Gemini Nano is supported here but still downloading or preparing.",
                    modelName = baseModelName,
                )
            }
        } catch (error: Exception) {
            runtimeInfo(
                supportedPlatform = true,
                available = false,
                statusMessage =
                    error.message ?: "Failed to query Android AI Core availability.",
            )
        }
    }

    private fun runtimeInfo(
        supportedPlatform: Boolean,
        available: Boolean,
        statusMessage: String,
        modelName: String? = null,
    ): Map<String, Any?> = buildMap {
        put("provider", PROVIDER_NAME)
        put("supportedPlatform", supportedPlatform)
        put("available", available)
        put("statusMessage", statusMessage)
        if (!modelName.isNullOrBlank()) {
            put("modelName", modelName)
        }
    }

    private fun getGenerativeModel(): GenerativeModel {
        val currentModel = generativeModel
        if (currentModel != null) {
            return currentModel
        }

        val createdModel = Generation.getClient()
        generativeModel = createdModel
        return createdModel
    }

    private suspend fun ensureModelReady(model: GenerativeModel) {
        when (model.checkStatus()) {
            FeatureStatus.AVAILABLE -> return
            FeatureStatus.UNAVAILABLE -> {
                throw IllegalStateException(
                    "Android AI Core prompt generation is unavailable on this device.",
                )
            }
            else -> {
                model.download().collect { status ->
                    if (status is DownloadStatus.DownloadFailed) {
                        throw status.e
                    }
                }
            }
        }
    }
}
