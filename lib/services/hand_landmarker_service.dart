import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

enum LandmarksPoint {
  wrist,
  thumbCmc,
  thumbMcp,
  thumbIp,
  thumbTip,
  indexFingerMcp,
  indexFingerPip,
  indexFingerDip,
  indexFingerTip,
  middleFingerMcp,
  middleFingerPip,
  middleFingerDip,
  middleFingerTip,
  ringFingerMcp,
  ringFingerPip,
  ringFingerDip,
  ringFingerTip,
  pinkyMcp,
  pinkyPip,
  pinkyDip,
  pinkyTip,
}

class HandLandmark {
  final double x;
  final double y;
  final double z;

  const HandLandmark({
    required this.x,
    required this.y,
    required this.z,
  });

  factory HandLandmark.fromMap(Map<String, dynamic> map) {
    return HandLandmark(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      z: (map['z'] as num).toDouble(),
    );
  }

  factory HandLandmark.clone(HandLandmark landmark) {
    return HandLandmark(
      x: landmark.x,
      y: landmark.y,
      z: landmark.z,
    );
  }
}

enum Handedness {
  left,
  right,
  unknown,
}

// New class to hold landmarks and handedness for a single hand
class DetectedHand {
  final List<HandLandmark> landmarks;
  final Handedness handedness; // e.g., "Left", "Right", "Unknown"

  const DetectedHand({
    required this.landmarks,
    required this.handedness,
  });

  factory DetectedHand.fromMap(Map<String, dynamic> map) {
    final landmarksList = (map['landmarks'] as List<dynamic>?)
            ?.cast<Map<dynamic, dynamic>>()
            .map((landmarkMap) => HandLandmark.fromMap(Map<String, dynamic>.from(landmarkMap)))
            .toList() ??
        [];
    Handedness handedness = Handedness.unknown;
    if (map['handedness'] is String) {
      final handednessStr = map['handedness'].toLowerCase();
      if (handednessStr == 'left') {
        handedness = Handedness.left;
      } else if (handednessStr == 'right') {
        handedness = Handedness.right;
      }
    }
    return DetectedHand(
      landmarks: landmarksList,
      handedness: handedness,
    );
  }
}

class HandLandmarkerService {
  static const MethodChannel _channel = MethodChannel('com.powershell1.motion_kit/hand_landmarker');

  /// Detect hand landmarks and handedness from camera input image
  static Future<List<DetectedHand>> detectHandLandmarks(InputImage inputImage) async {
    try {
      // Convert InputImage to the format expected by native code
      final bytes = inputImage.bytes;
      if (bytes == null) {
        throw Exception('Image bytes are null');
      }

      final metadata = inputImage.metadata;
      if (metadata == null) {
        throw Exception('Image metadata is null');
      }

      // Get rotation in degrees
      final rotation = _getRotationDegrees(metadata.rotation);

      final result = await _channel.invokeMethod('detect', {
        'bytes': bytes,
        'width': metadata.size.width.toInt(),
        'height': metadata.size.height.toInt(),
        'rotation': rotation,
      });

      if (result is List) {
        final List<DetectedHand> listResult = result
            .cast<Map<dynamic, dynamic>>()
            .map((handDataMap) {
          final detectedHand = DetectedHand.fromMap(Map<String, dynamic>.from(handDataMap));
          final scaledLandmarks = detectedHand.landmarks.map((landmark) {
            return HandLandmark(
              x: landmark.x * metadata.size.height,
              y: landmark.y * metadata.size.width,
              z: landmark.z,
            );
          }).toList();
          return DetectedHand(
            landmarks: scaledLandmarks,
            handedness: detectedHand.handedness,
          );
        })
            .toList();
        return listResult;
      }

      return [];
    } catch (e) {
      print('Error detecting hand landmarks: $e');
      return [];
    }
  }

  static int _getRotationDegrees(InputImageRotation rotation) {
    switch (rotation) {
      case InputImageRotation.rotation0deg:
        return 0;
      case InputImageRotation.rotation90deg:
        return 90;
      case InputImageRotation.rotation180deg:
        return 180;
      case InputImageRotation.rotation270deg:
        return 270;
    }
  }
}
