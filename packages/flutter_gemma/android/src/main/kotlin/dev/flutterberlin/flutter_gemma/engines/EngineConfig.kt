package dev.flutterberlin.flutter_gemma.engines

import android.content.Context
import dev.flutterberlin.flutter_gemma.PreferredBackend
import dev.flutterberlin.flutter_gemma.engines.litertlm.LiteRtLmEngine
import dev.flutterberlin.flutter_gemma.engines.mediapipe.MediaPipeEngine
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

/**
 * Engine initialization configuration.
 */
data class EngineConfig(
    val modelPath: String,
    val maxTokens: Int,
    val supportedLoraRanks: List<Int>? = null,
    val preferredBackend: PreferredBackend? = null,
    val maxNumImages: Int? = null,
    val supportAudio: Boolean? = null,
)

/**
 * Session-level configuration (sampling parameters).
 */
data class SessionConfig(
    val temperature: Float = 1.0f,
    val randomSeed: Int = 0,
    val topK: Int = 40,
    val topP: Float? = null,
    val loraPath: String? = null,
    val enableVisionModality: Boolean? = null,
    val enableAudioModality: Boolean? = null,
    val systemInstruction: String? = null,
)

/**
 * Helper to create SharedFlow instances with consistent configuration.
 */
object FlowFactory {
    fun <T> createSharedFlow(): MutableSharedFlow<T> = MutableSharedFlow(
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )
}

/**
 * Abstraction for inference engines (MediaPipe, LiteRT-LM, future engines).
 *
 * Lifecycle:
 * 1. initialize(config) - Load model, setup backend
 * 2. createSession(config) - Create conversation/session
 * 3. close() - Release resources
 */
interface InferenceEngine {
    /** Whether engine has been initialized successfully */
    val isInitialized: Boolean

    /** Engine capabilities (vision, audio, function calls) */
    val capabilities: EngineCapabilities

    /** Streaming outputs (partial results + errors) */
    val partialResults: SharedFlow<Pair<String, Boolean>>
    val errors: SharedFlow<Throwable>

    /**
     * Initialize engine with model file.
     * MUST be called on background thread (can take 10+ seconds).
     */
    suspend fun initialize(config: EngineConfig)

    /**
     * Create a new inference session.
     * Throws IllegalStateException if engine not initialized.
     */
    fun createSession(config: SessionConfig): InferenceSession

    /** Release all resources */
    fun close()
}

/**
 * Engine capabilities descriptor.
 */
data class EngineCapabilities(
    val supportsVision: Boolean = false,
    val supportsAudio: Boolean = false,
    val supportsFunctionCalls: Boolean = false,
    val supportsStreaming: Boolean = true,
    val supportsTokenCounting: Boolean = false,
    val maxTokenLimit: Int = 2048,
)

/**
 * Factory for creating inference engines.
 *
 * Engine selection strategy:
 * - MEDIAPIPE: .task, .bin, .tflite files
 * - LITERTLM: .litertlm files
 */
object EngineFactory {

    /**
     * Create engine based on file extension.
     *
     * @param modelPath Path to model file
     * @param context Android context
     * @return Appropriate engine instance
     * @throws IllegalArgumentException if file extension not recognized
     */
    fun createFromModelPath(modelPath: String, context: Context): InferenceEngine {
        return when {
            modelPath.endsWith(".litertlm", ignoreCase = true) -> LiteRtLmEngine(context)
            modelPath.endsWith(".task", ignoreCase = true) -> MediaPipeEngine(context)
            modelPath.endsWith(".bin", ignoreCase = true) -> MediaPipeEngine(context)
            modelPath.endsWith(".tflite", ignoreCase = true) -> MediaPipeEngine(context)
            else -> {
                val extension = if (modelPath.contains('.')) {
                    modelPath.substringAfterLast('.')
                } else {
                    "<no extension>"
                }
                throw IllegalArgumentException(
                    "Unsupported model format: .$extension. " +
                        "Supported: .litertlm (LiteRT-LM), .task/.bin/.tflite (MediaPipe)"
                )
            }
        }
    }

    /**
     * Create engine explicitly by type (for testing or advanced use cases).
     *
     * @param engineType Type of engine to create
     * @param context Android context
     * @return Engine instance of specified type
     */
    fun create(engineType: EngineType, context: Context): InferenceEngine {
        return when (engineType) {
            EngineType.MEDIAPIPE -> MediaPipeEngine(context)
            EngineType.LITERTLM -> LiteRtLmEngine(context)
        }
    }

    /**
     * Detect engine type from model path.
     *
     * @param modelPath Path to model file
     * @return Engine type for the given model
     * @throws IllegalArgumentException if extension not recognized
     */
    fun detectEngineType(modelPath: String): EngineType {
        return when {
            modelPath.endsWith(".litertlm", ignoreCase = true) -> EngineType.LITERTLM
            modelPath.endsWith(".task", ignoreCase = true) -> EngineType.MEDIAPIPE
            modelPath.endsWith(".bin", ignoreCase = true) -> EngineType.MEDIAPIPE
            modelPath.endsWith(".tflite", ignoreCase = true) -> EngineType.MEDIAPIPE
            else -> throw IllegalArgumentException(
                "Unsupported model format: ${modelPath.substringAfterLast('.')}"
            )
        }
    }
}

/**
 * Engine type enumeration.
 */
enum class EngineType {
    MEDIAPIPE,  // .task, .bin, .tflite
    LITERTLM, // .litertlm
}
