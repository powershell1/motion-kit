package com.powershell1.motion_kit

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity: FlutterActivity(), HandLandmarkerHelper.LandmarkerListener {
    private val CHANNEL = "com.powershell1.motion_kit/hand_landmarker"
    private lateinit var handLandmarkerHelper: HandLandmarkerHelper
    private var flutterResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        handLandmarkerHelper = HandLandmarkerHelper(
            context = applicationContext,
            landmarkerListener = this
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "detect") {
                this.flutterResult = result // Store the result callback

                val imageBytes: ByteArray? = call.argument("bytes")
                val imageWidth: Int? = call.argument("width")
                val imageHeight: Int? = call.argument("height")
                val imageRotation: Int? = call.argument("rotation") // degrees

                if (imageBytes != null && imageWidth != null && imageHeight != null && imageRotation != null) {
                    try {
                        val bitmap = convertYuvToBitmap(imageBytes, imageWidth, imageHeight, imageRotation)
                        val mpImage = BitmapImageBuilder(bitmap).build()
                        // Use SystemClock.uptimeMillis() for timestamp as per MediaPipe examples for LIVE_STREAM
                        handLandmarkerHelper.detectAsync(mpImage, SystemClock.uptimeMillis())
                        // Result will be sent back via the LandmarkerListener callbacks
                    } catch (e: Exception) {
                        Log.e("HandLandmarker", "Error processing image for detection: ${e.message}", e)
                        result.error("IMAGE_PROCESSING_ERROR", "Error processing image: ${e.message}", null)
                    }
                } else {
                    result.error("INVALID_ARGUMENTS", "Missing image data, width, height, or rotation", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun convertYuvToBitmap(yuvBytes: ByteArray, width: Int, height: Int, rotationDegrees: Int): Bitmap {
        // This conversion assumes the input yuvBytes are in NV21 format.
        // Flutter's CameraImage usually provides data in YUV_420_888 format.
        // YUV_420_888 can have different plane orderings and strides.
        // The `planes[0].bytes` from Flutter's InputImage might just be the Y plane.
        // A full YUV_420_888 to Bitmap conversion requires all Y, U, V planes.
        // For simplicity, this example continues with a basic NV21 assumption.
        // THIS IS A CRITICAL PART: Ensure this conversion matches your actual InputImage format.
        // Log.d("HandLandmarker", "Attempting to convert YUV to Bitmap. Width: $width, Height: $height, Rotation: $rotationDegrees")

        val yuvImage = YuvImage(yuvBytes, ImageFormat.NV21, width, height, null)
        val out = ByteArrayOutputStream()
        yuvImage.compressToJpeg(Rect(0, 0, width, height), 90, out) // Use 90 for quality
        val imageBytes = out.toByteArray()
        var bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)

        if (rotationDegrees != 0) {
            val matrix = Matrix()
            matrix.postRotate(rotationDegrees.toFloat())
            bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            // Log.d("HandLandmarker", "Bitmap rotated by $rotationDegrees degrees.")
        }
        // Log.d("HandLandmarker", "Bitmap conversion successful. New Width: ${bitmap.width}, New Height: ${bitmap.height}")
        return bitmap
    }

    override fun onError(error: String, errorCode: Int) {
        Log.e("HandLandmarker", "HandLandmarkerHelper Error: $error (Code: $errorCode)")
        flutterResult?.error("NATIVE_ERROR", error, errorCode)
        flutterResult = null // Clear to avoid reuse
    }

    override fun onResults(resultBundle: HandLandmarkerHelper.ResultBundle) {
        val handsDataList = mutableListOf<Map<String, Any>>()
        resultBundle.results.firstOrNull()?.let { handLandmarkerResult ->
            for (i in 0 until handLandmarkerResult.landmarks().size) {
                val landmarks = handLandmarkerResult.landmarks()[i]
                val handedness = handLandmarkerResult.handednesses()[i] // Get handedness for this hand

                val landmarksMapList = mutableListOf<Map<String, Double>>()
                landmarks.forEach { landmark ->
                    landmarksMapList.add(mapOf("x" to landmark.x().toDouble(), "y" to landmark.y().toDouble(), "z" to landmark.z().toDouble()))
                }

                val handData = mutableMapOf<String, Any>()
                handData["landmarks"] = landmarksMapList
                // Assuming handedness list is not empty and we take the first one (highest score)
                if (handedness.isNotEmpty()) {
                    handData["handedness"] = handedness[0].categoryName()
                    handData["handednessScore"] = handedness[0].score().toDouble()
                } else {
                    handData["handedness"] = "Unknown"
                    handData["handednessScore"] = 0.0
                }
                handsDataList.add(handData)
            }
        }

        if (handsDataList.isNotEmpty()) {
            // Log.d("HandLandmarker", "Hands data detected: ${handsDataList.size}")
        } else {
            // Log.d("HandLandmarker", "No hands detected in this frame.")
        }
        flutterResult?.success(handsDataList)
        flutterResult = null // Clear to avoid reuse
    }

    override fun onDestroy() {
        super.onDestroy()
        handLandmarkerHelper.clearHandLandmarker()
    }
}

// Helper class for MediaPipe Hand Landmarker
// Based on official MediaPipe examples
class HandLandmarkerHelper(
    val context: Context,
    var landmarkerListener: LandmarkerListener? = null
) {
    private var handLandmarker: HandLandmarker? = null
    private var executorService: ExecutorService? = null

    init {
        setupHandLandmarker()
    }

    fun setupHandLandmarker() {
        if (executorService == null) {
            executorService = Executors.newSingleThreadExecutor()
        }

        try {
            val baseOptionsBuilder = BaseOptions.builder().setModelAssetPath(MODEL_PATH)
            // TODO: Ensure "hand_landmarker.task" is in app/src/main/assets/
            // Download from: https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/index#models

            val baseOptions = baseOptionsBuilder.build()
            val optionsBuilder =
                HandLandmarker.HandLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setRunningMode(RunningMode.LIVE_STREAM) // Use LIVE_STREAM for camera input
                    .setNumHands(MAX_NUM_HANDS)
                    .setMinHandDetectionConfidence(MIN_HAND_DETECTION_CONFIDENCE)
                    .setMinHandPresenceConfidence(MIN_HAND_PRESENCE_CONFIDENCE)
                    .setMinTrackingConfidence(MIN_TRACKING_CONFIDENCE)
                    .setResultListener(this::returnLivestreamResult)
                    .setErrorListener(this::returnLivestreamError)

            val options = optionsBuilder.build()
            handLandmarker = HandLandmarker.createFromOptions(context, options)
            Log.d(TAG, "HandLandmarker initialized successfully.")
        } catch (e: Exception) {
            landmarkerListener?.onError("Hand Landmarker failed to initialize. See error logs for details.", ERROR_INIT_FAILED)
            Log.e(TAG, "MediaPipe failed to load the task with error: ${e.message}", e)
        }
    }

    fun detectAsync(mpImage: MPImage, frameTime: Long) {
        if (handLandmarker == null) {
            landmarkerListener?.onError("HandLandmarker is not initialized.", ERROR_NOT_INITIALIZED)
            return
        }
        executorService?.execute {
            handLandmarker?.detectAsync(mpImage, frameTime)
        }
    }

    private fun returnLivestreamResult(result: HandLandmarkerResult, input: MPImage) {
        val finishTimeMs = SystemClock.uptimeMillis()
        val inferenceTime = finishTimeMs - result.timestampMs() // result.timestampMs() is the frameTime passed to detectAsync

        landmarkerListener?.onResults(
            ResultBundle(
                listOf(result),
                inferenceTime,
                input.height,
                input.width
            )
        )
    }

    private fun returnLivestreamError(error: RuntimeException) {
        landmarkerListener?.onError(error.message ?: "An unknown error has occurred", ERROR_RUNTIME)
        Log.e(TAG, "HandLandmarker encountered an error: ${error.message}", error)
    }

    fun clearHandLandmarker() {
        executorService?.shutdown()
        try {
            if (executorService?.awaitTermination(500, TimeUnit.MILLISECONDS) == false) {
                executorService?.shutdownNow()
            }
        } catch (e: InterruptedException) {
             Thread.currentThread().interrupt()
        } finally {
            executorService = null
        }
        handLandmarker?.close()
        handLandmarker = null
        Log.d(TAG, "HandLandmarker closed.")
    }

    interface LandmarkerListener {
        fun onError(error: String, errorCode: Int = 0)
        fun onResults(resultBundle: ResultBundle)
    }

    data class ResultBundle(
        val results: List<HandLandmarkerResult>,
        val inferenceTime: Long,
        val inputImageHeight: Int,
        val inputImageWidth: Int
    )

    companion object {
        const val TAG = "HandLandmarkerHelper"
        private const val MODEL_PATH = "hand_landmarker.task" // Lite or Full model

        const val MAX_NUM_HANDS = 2
        const val MIN_HAND_DETECTION_CONFIDENCE = 0.5f
        const val MIN_HAND_PRESENCE_CONFIDENCE = 0.5f
        const val MIN_TRACKING_CONFIDENCE = 0.5f

        const val ERROR_INIT_FAILED = -1
        const val ERROR_NOT_INITIALIZED = -2
        const val ERROR_RUNTIME = -3
    }
}
