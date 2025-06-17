import Flutter
import UIKit
import MediaPipeTasksVision
import AVFoundation // Required for image conversion

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var handLandmarkerHelper: HandLandmarkerHelper?
  private let channelName = "com.powershell1.motion_kit/hand_landmarker"
  private var flutterResult: FlutterResult? // Store FlutterResult for async callback

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      fatalError("rootViewController is not type FlutterViewController")
    }

    let handChannel = FlutterMethodChannel(name: channelName,
                                           binaryMessenger: controller.binaryMessenger)

    // Initialize HandLandmarkerHelper for LIVE_STREAM mode
    // Ensure "hand_landmarker.task" is included in the Runner target and copied to the app bundle.
    HandLandmarkerHelper.create(modelPath: "hand_landmarker.task", runningMode: .liveStream, handLandmarkerLiveStreamDelegate: self) { [weak self] result in
        switch result {
        case .success(let landmarkerHelper):
            self?.handLandmarkerHelper = landmarkerHelper
            print("HandLandmarker (LiveStream) initialized successfully")
        case .failure(let error):
            print("Failed to initialize HandLandmarker (LiveStream): \(error.localizedDescription)")
            // Optionally, communicate this failure back to Flutter if needed at startup
        }
    }

    handChannel.setMethodCallHandler({ [weak self] (
      call: FlutterMethodCall,
      result: @escaping FlutterResult
    ) -> Void in
      guard let self = self else { return }

      guard call.method == "detect" else {
        result(FlutterMethodNotImplemented)
        return
      }

      self.flutterResult = result // Store for async response

      guard self.handLandmarkerHelper != nil else {
          self.flutterResult?(FlutterError(code: "LANDMARKER_NOT_INITIALIZED", message: "HandLandmarker is not initialized.", details: nil))
          self.flutterResult = nil
          return
      }

      guard let args = call.arguments as? [String: Any],
            let imageBytes = args["bytes"] as? FlutterStandardTypedData,
            let imageWidth = args["width"] as? Int,
            let imageHeight = args["height"] as? Int,
            let imageRotation = args["rotation"] as? Int else { // Degrees
          self.flutterResult?(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments for detect method", details: nil))
          self.flutterResult = nil
          return
      }

      // Convert image bytes to CVPixelBuffer, then to MPImage
      // This is a critical step and needs to be robust.
      guard let cvPixelBuffer = self.pixelBufferFromBytes(bytes: imageBytes.data, width: imageWidth, height: imageHeight, pixelFormat: kCVPixelFormatType_32BGRA) else {
          self.flutterResult?(FlutterError(code: "IMAGE_CONVERSION_ERROR", message: "Could not convert bytes to CVPixelBuffer", details: nil))
          self.flutterResult = nil
          return
      }

      // Determine the correct orientation for MPImage
      let imageOrientation = self.imageOrientation(fromDeviceRotation: imageRotation)

      // Create MPImage
      // For LIVE_STREAM, MPImage is often created from CVPixelBuffer.
      let mpImage = MPImage(pixelBuffer: cvPixelBuffer, orientation: imageOrientation)

      // Perform detection asynchronously
      // The result will be delivered via the HandLandmarkerLiveStreamDelegate methods.
      do {
          // Timestamp should be in milliseconds
          let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
          try self.handLandmarkerHelper?.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
      } catch {
          print("Failed to start async detection: \(error.localizedDescription)")
          self.flutterResult?(FlutterError(code: "DETECTION_ERROR", message: "Error starting hand landmark detection: \(error.localizedDescription)", details: nil))
          self.flutterResult = nil
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Helper to convert raw bytes (assumed BGRA) to CVPixelBuffer
  private func pixelBufferFromBytes(bytes: Data, width: Int, height: Int, pixelFormat: OSType) -> CVPixelBuffer? {
      var pixelBuffer: CVPixelBuffer?
      let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       width,
                                       height,
                                       pixelFormat,
                                       nil, // Attributes
                                       &pixelBuffer)
      guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
          print("Error: could not create CVPixelBuffer, status: \(status)")
          return nil
      }

      CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
      let pixelData = CVPixelBufferGetBaseAddress(buffer)

      // Assuming bytes are already in the correct format (e.g., BGRA)
      // and the correct length (width * height * 4 for BGRA)
      if bytes.count == width * height * 4 { // Basic check for BGRA
          bytes.withUnsafeBytes { (rawBufferPointer) in
              if let baseAddress = rawBufferPointer.baseAddress {
                  memcpy(pixelData, baseAddress, bytes.count)
              }
          }
      } else {
          print("Error: Byte count \(bytes.count) does not match expected for BGRA \(width*height*4 = \(width*height*4)")
          CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
          return nil // Or handle error appropriately
      }

      CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
      return buffer
  }

  // Convert device rotation (degrees from Flutter) to UIImage.Orientation for MPImage
  private func imageOrientation(fromDeviceRotation degrees: Int) -> UIImage.Orientation {
      // This mapping depends on how the camera sensor is mounted and how Flutter reports rotation.
      // MediaPipe generally expects images as if they are viewed upright.
      // Flutter's CameraImage rotation is the rotation to make the image upright.
      switch degrees {
          case 0: return .up
          case 90: return .right // Landscape right as viewed by user
          case 180: return .down
          case 270: return .left  // Landscape left as viewed by user
          default: return .up
      }
  }
}

// MARK: - HandLandmarkerLiveStreamDelegate
extension AppDelegate: HandLandmarkerLiveStreamDelegate {
    func handLandmarker(_ handLandmarker: HandLandmarker, didFinishDetection result: Result<HandLandmarkerResults, Error>?, timestampInMilliseconds: Int) {
        guard let currentFlutterResult = self.flutterResult else {
            print("Flutter result callback is nil, cannot send landmarks.")
            return
        }

        switch result {
        case .success(let handLandmarkerResults):
            let landmarksArray = handLandmarkerResults.landmarks.flatMap { handLandmarks in
                handLandmarks.map { landmark in
                    ["x": landmark.x, "y": landmark.y, "z": landmark.z]
                }
            }
            if !landmarksArray.isEmpty {
                // print("Hand landmarks detected (live): \(landmarksArray.count)")
            }
            currentFlutterResult(landmarksArray)
        case .failure(let error):
            print("Failed to detect hand landmarks (live): \(error.localizedDescription)")
            currentFlutterResult(FlutterError(code: "NATIVE_DETECTION_ERROR", message: "Error in live stream hand detection: \(error.localizedDescription)", details: nil))
        case .none:
            print("HandLandmarker live stream result is nil.")
            currentFlutterResult([]) // Or an appropriate error
        }
        self.flutterResult = nil // Clear after sending
    }
}


// Helper class for MediaPipe Hand Landmarker (adapted for Live Stream)
// Consider placing this in a separate Swift file.
class HandLandmarkerHelper {
    var handLandmarker: HandLandmarker?

    enum LandmarkerError: Error {
        case modelFileNotFound
        case initializationFailed(Error)
        case detectionFailed(Error)
        case liveStreamDelegateNotSet
    }

    private init() {}

    static func create(modelPath: String,
                       runningMode: RunningMode,
                       handLandmarkerLiveStreamDelegate: HandLandmarkerLiveStreamDelegate? = nil,
                       completion: @escaping (Result<HandLandmarkerHelper, LandmarkerError>) -> Void) {
        let helper = HandLandmarkerHelper()
        guard let modelUrl = Bundle.main.url(forResource: modelPath, withExtension: nil) else {
            completion(.failure(.modelFileNotFound))
            return
        }

        let baseOptions = BaseOptions(modelAssetPath: modelUrl.path)
        let options = HandLandmarkerOptions()
        options.baseOptions = baseOptions
        options.runningMode = runningMode
        options.numHands = 1 // Max number of hands
        // options.minHandDetectionConfidence = 0.5 // Default is 0.5
        // options.minHandPresenceConfidence = 0.5 // Default is 0.5
        // options.minTrackingConfidence = 0.5 // Default is 0.5

        if runningMode == .liveStream {
            guard let delegate = handLandmarkerLiveStreamDelegate else {
                completion(.failure(.liveStreamDelegateNotSet))
                return
            }
            options.handLandmarkerLiveStreamDelegate = delegate
        }

        do {
            helper.handLandmarker = try HandLandmarker(options: options)
            completion(.success(helper))
        } catch {
            completion(.failure(.initializationFailed(error)))
        }
    }

    // For LIVE_STREAM mode
    func detectAsync(image: MPImage, timestampInMilliseconds: Int) throws {
        guard let landmarker = handLandmarker else {
            throw LandmarkerError.initializationFailed(NSError(domain: "HandLandmarkerHelper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Landmarker not initialized."])) // Or a more specific error
        }
        try landmarker.detectAsync(image: image, timestampInMilliseconds: timestampInMilliseconds)
    }
    
    // For IMAGE or VIDEO mode (not used in this live stream setup but good to have)
    func detect(image: MPImage) throws -> HandLandmarkerResults? {
        guard let landmarker = handLandmarker else {
             throw LandmarkerError.initializationFailed(NSError(domain: "HandLandmarkerHelper", code: 0, userInfo: [NSLocalizedDescriptionKey: "Landmarker not initialized."])) 
        }
        return try landmarker.detect(image: image)
    }

    func close() {
        handLandmarker?.close()
        handLandmarker = nil
    }
}
