// ...existing utility code...
// import 'package:movemind/service/vectorOperation.dart';
import 'package:motion_kit/services/hand_landmarker_service.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:vector_math/vector_math_64.dart';
import 'dart:typed_data';

enum GestureType {
  zero,
  one,
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  jeep,
  pinky,
}

class VectorOperation {
  static const double TARGET_SCALE = 0.2;

  static double vectorNorm(Vector3 v) => v.length;

  static List<Vector3> cloneVectors(List<Vector3> vectors) =>
      vectors.map((v) => Vector3.copy(v)).toList();

  static Vector3 crossProduct(Vector3 a, Vector3 b) => a.cross(b);

  static Vector3 safeNormalize(Vector3 v) {
    double len = vectorNorm(v);
    return (len > 0) ? v / len : v;
  }

  static List<Vector3> landmarkNormalization(List<Vector3> landmarks) {
    // Get key landmark positions
    final Vector3 wrist = landmarks[LandmarksPoint.wrist.index];
    final Vector3 middleMcp = landmarks[LandmarksPoint.middleFingerMcp.index];
    final Vector3 pinkyMcp = landmarks[LandmarksPoint.pinkyMcp.index];

    // Define the coordinate system based on hand anatomy
    Vector3 yAxis = middleMcp - wrist;
    final double referenceLength = yAxis.length;
    final double scaleFactor = referenceLength > 0 ? TARGET_SCALE / referenceLength : 1.0;

    // Normalize axes to create orthogonal coordinate system
    yAxis = safeNormalize(yAxis);

    Vector3 tempVector = pinkyMcp - wrist;
    Vector3 zAxis = crossProduct(yAxis, tempVector);
    zAxis = safeNormalize(zAxis);

    Vector3 xAxis = crossProduct(yAxis, zAxis);
    xAxis = safeNormalize(xAxis);

    // Ensure z-axis is perfectly orthogonal
    zAxis = crossProduct(xAxis, yAxis);
    zAxis = safeNormalize(zAxis);

    // Create transformation matrix from hand coordinate system
    final Matrix3 transformMatrix = Matrix3(
        xAxis.x, yAxis.x, zAxis.x,
        xAxis.y, yAxis.y, zAxis.y,
        xAxis.z, yAxis.z, zAxis.z
    );

    // Apply normalization to all landmarks
    return landmarks.map((landmark) {
      // Translate landmark to origin at wrist
      Vector3 centered = landmark - wrist;

      // Apply rotation to align with canonical axes
      Vector3 rotated = transformMatrix * centered;

      // Scale to target size
      return rotated * scaleFactor;
    }).toList();
  }
}

class GestureClassified {
  final GestureType type;
  final double confidence;
  GestureClassified(this.type, this.confidence);
}

class GestureClassification {
  static const int inputSize = 63;
  static const int outputSize = 12;

  late Interpreter interpreter;

  GestureClassification() {
    initInterpreter();
  }

  Future<void> initInterpreter() async {
    try {
      interpreter = await Interpreter.fromAsset('assets/models/gestured_detection.tflite');
      print('Interpreter loaded: ${interpreter.getInputTensors()[0].shape} -> ${interpreter.getOutputTensors()[0].shape}');
    } catch (err) {
      print('Interpreter error: $err');
    }
  }

  GestureClassified checkGesture(DetectedHand hand) {
    if (interpreter.isAllocated == false) {
      throw Exception('Interpreter is not initialized');
    }
    List<Vector3> keyPoints = hand.landmarks
        .map((lm) => Vector3(lm.x, lm.y, lm.z))
        .toList();
    // HandLandmarks.values.map((lm) => landmarks[lm]!.position).toList();
    keyPoints = VectorOperation.landmarkNormalization(keyPoints);
    List<double> inputData = [];
    for (var pt in keyPoints) {
      inputData.addAll([pt.x, pt.y, pt.z]);
    }
    Float32List inputTensor = Float32List.fromList(inputData);
    List<List<double>> outputTensor = List.generate(1, (_) => List.filled(outputSize, 0.0));
    interpreter.run(inputTensor, outputTensor);
    List<double> outputs = outputTensor[0];
    int maxIndex = outputs.indexOf(outputs.reduce((a, b) => a > b ? a : b));
    return GestureClassified(GestureType.values[maxIndex], outputs[maxIndex]);
  }
}