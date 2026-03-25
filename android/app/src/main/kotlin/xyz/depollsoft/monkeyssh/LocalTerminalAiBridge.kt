package xyz.depollsoft.monkeyssh

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Method-channel bridge for Android's built-in on-device GenAI runtime status.
 *
 * The currently published Google on-device prompt SDK requires a higher app
 * minSdk than MonkeySSH currently ships with, so Android reports that callers
 * should use the configured fallback model file for now.
 */
class LocalTerminalAiBridge(binaryMessenger: BinaryMessenger) {
    companion object {
        private const val CHANNEL_NAME = "xyz.depollsoft.monkeyssh/local_terminal_ai"
        private const val PROVIDER_NAME = "androidAiCore"
    }

    private val methodChannel = MethodChannel(binaryMessenger, CHANNEL_NAME)

    fun start() {
        methodChannel.setMethodCallHandler(::handleMethodCall)
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getRuntimeInfo" -> result.success(buildRuntimeInfo())
            "generateText" -> handleGenerateText(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleGenerateText(call: MethodCall, result: MethodChannel.Result) {
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

        result.error(
            "fallback_required",
            "Android built-in prompt generation is unavailable in this build. Configure a fallback local model file instead.",
            null,
        )
    }

    private fun buildRuntimeInfo(): Map<String, Any?> = runtimeInfo(
        supportedPlatform = false,
        available = false,
        statusMessage =
            "Android's current built-in prompt SDK requires a higher app minSdk than MonkeySSH currently targets, so use a fallback local model file on Android for now.",
    )

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

}
