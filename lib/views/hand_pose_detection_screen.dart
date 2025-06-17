import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:motion_kit/views/painters/coordinates_translator.dart';
import 'package:vector_math/vector_math.dart';

import '../services/hand_landmarker_service.dart';
import 'detector_view.dart';
import 'painters/hand_pose_painter.dart';

class HandPoseDetectorView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _HandPoseDetectorViewState();
}

class _HandPoseDetectorViewState extends State<HandPoseDetectorView> {
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );
  
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  var _cameraLensDirection = CameraLensDirection.back;
  
  // Display options
  bool _showHandNumbers = false;
  bool _showPoseNumbers = false;
  bool _showConnections = true;

  // Variables for circle interaction
  bool _isHandInCircle = false;
  DateTime? _handInCircleStartTime;

  // New state variables for gesture detection
  String _rpmText = "RPM: 0";
  int _rotationCount = 0;
  DateTime? _lastRotationCompleteTime;

  // Variables for circular gesture calculation
  double _accumulatedAngle = 0.0;
  double? _previousAngleRad; // Angle in radians

  // Helper function for angle difference
  double _calculateAngleDifference(double angle1Rad, double angle2Rad) {
    double diff = angle2Rad - angle1Rad;
    while (diff <= -math.pi) {
      diff += 2 * math.pi;
    }
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    return diff;
  }

  @override
  void dispose() async {
    _canProcess = false;
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hand & Pose Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'hand_numbers':
                    _showHandNumbers = !_showHandNumbers;
                    break;
                  case 'pose_numbers':
                    _showPoseNumbers = !_showPoseNumbers;
                    break;
                  case 'connections':
                    _showConnections = !_showConnections;
                    break;
                }
              });
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem<String>(
                value: 'hand_numbers',
                child: Row(
                  children: [
                    Icon(_showHandNumbers ? Icons.check_box : Icons.check_box_outline_blank),
                    const SizedBox(width: 8),
                    const Text('Show Hand Numbers'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'pose_numbers',
                child: Row(
                  children: [
                    Icon(_showPoseNumbers ? Icons.check_box : Icons.check_box_outline_blank),
                    const SizedBox(width: 8),
                    const Text('Show Pose Numbers'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'connections',
                child: Row(
                  children: [
                    Icon(_showConnections ? Icons.check_box : Icons.check_box_outline_blank),
                    const SizedBox(width: 8),
                    const Text('Show Connections'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          DetectorView(
            title: 'Hand & Pose Detector',
            customPaint: _customPaint,
            text: _text,
            onImage: _processImage,
            initialCameraLensDirection: _cameraLensDirection,
            onCameraLensDirectionChanged: (value) => _cameraLensDirection = value,
          ),
          Positioned(
            top: 20,
            left: 20,
            child: ElevatedButton(
              onPressed: () {
                setState(switchingSide);
              },
              child: Text(_rpmText),
            ),
          ),
        ],
      )
    );
  }

  Handedness side = Handedness.left;

  void switchingSide() {
    if (side == Handedness.left) {
      side = Handedness.right;
    } else {
      side = Handedness.left;
    }
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    
    setState(() {
      _text = '';
    });
    
    try {
      // Process both pose and hand detection simultaneously
      final futures = await Future.wait([
        _poseDetector.processImage(inputImage),
        HandLandmarkerService.detectHandLandmarks(inputImage), // This now returns List<DetectedHand>
      ]);
      
      final poses = futures[0] as List<Pose>;
      // handLandmarks is now List<DetectedHand>
      final detectedHands = futures[1] as List<DetectedHand>;

      DetectedHand? leftHandLandmarks = detectedHands
          .where((hand) => hand.handedness == Handedness.left).firstOrNull;
      DetectedHand? rightHandLandmarks = detectedHands
          .where((hand) => hand.handedness == Handedness.right).firstOrNull;
      DetectedHand? targetHandLandmarks = side == Handedness.left
          ? leftHandLandmarks
          : rightHandLandmarks;


      if (inputImage.metadata?.size != null &&
          inputImage.metadata?.rotation != null) {
        final painter = HandPosePainter(
          poses,
          detectedHands, // Pass the flattened list of hand landmarks
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
          _cameraLensDirection,
          showHandNumbers: _showHandNumbers,
          showPoseNumbers: _showPoseNumbers,
          showConnections: _showConnections,
        );
        _customPaint = CustomPaint(painter: painter);

        // Build text output
        String outputText = 'Poses: ${poses.length}\n';
        if (detectedHands.isNotEmpty) {
          for (int i = 0; i < detectedHands.length; i++) {
            final hand = detectedHands[i];
            outputText += 'Hand ${i + 1}: ${hand.handedness} (${hand.landmarks.length} landmarks)\n';
            // Optionally, add gesture analysis text here if you implement it for HandPoseDetectorView
          }
        } else {
          outputText += 'No hands detected\n';
        }
        _text = outputText.trim();
        _text = (_text ?? "") + "\\n$_rpmText"; // Append RPM text

        // The circle drawing logic seems specific to pose landmarks,
        // ensure it still makes sense or adjust as needed.
        if (poses.isNotEmpty && poses[0].landmarks.isNotEmpty) {
          final landmarks = poses[0].landmarks;
          PoseLandmark? rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
          PoseLandmark? leftShoulder = landmarks[PoseLandmarkType.leftShoulder];

          if (rightShoulder != null && leftShoulder != null) {
            Vector3 centerShoulder = Vector3(
              (rightShoulder.x + leftShoulder.x) / 2,
              (rightShoulder.y + leftShoulder.y) / 2,
              (rightShoulder.z + leftShoulder.z) / 2,
            );
            Vector3 rightCollarbone = Vector3(
                (centerShoulder.x + rightShoulder.x) / 2,
                (centerShoulder.y + rightShoulder.y) / 2 - 1, // Adjusted for better visibility
                (centerShoulder.z + rightShoulder.z) / 2
            );
            Vector3 leftCollarbone = Vector3(
                (centerShoulder.x + leftShoulder.x) / 2,
                (centerShoulder.y + leftShoulder.y) / 2 - 1, // Adjusted for better visibility
                (centerShoulder.z + leftShoulder.z) / 2
            );
            Vector3 targetCollarbone = side == Handedness.left
                ? leftCollarbone
                : rightCollarbone;

            double distance = (rightShoulder.x - leftShoulder.x).abs();
            double radius = distance / 10; // Adjust radius based on distance

            if (targetHandLandmarks != null) {
              HandLandmark targetLandmark = targetHandLandmarks.landmarks[10]; // Assuming landmark 10 is a fingertip or palm center
              double currentHandX = targetLandmark.x;
              double currentHandY = targetLandmark.y;

              // Calculate distance for the 10-second hold logic (existing)
              double distanceTo = distanceCalculation(
                targetCollarbone.x,
                targetCollarbone.y,
                currentHandX,
                currentHandY,
              );

              if (distanceTo < radius) {
                // Existing 10-second hold logic
                if (!_isHandInCircle) {
                  _isHandInCircle = true;
                  _handInCircleStartTime = DateTime.now();
                } else {
                  if (_handInCircleStartTime != null &&
                      DateTime.now().difference(_handInCircleStartTime!).inSeconds >= 10) {
                    setState(switchingSide);
                    _isHandInCircle = false;
                    _handInCircleStartTime = null;
                  }
                }

                // New RPM Calculation Logic
                // Use targetCollarbone as the center of rotation
                double centerX = targetCollarbone.x;
                double centerY = targetCollarbone.y;

                double currentAngleRad = math.atan2(currentHandY - centerY, currentHandX - centerX);

                if (_previousAngleRad != null) {
                  double deltaAngle = _calculateAngleDifference(_previousAngleRad!, currentAngleRad);
                  _accumulatedAngle += deltaAngle;

                  if (_accumulatedAngle.abs() >= 2 * math.pi) { // Full circle completed
                    _rotationCount++;
                    DateTime now = DateTime.now();
                    if (_lastRotationCompleteTime != null) {
                      double timeDiffSeconds = now.difference(_lastRotationCompleteTime!).inMilliseconds / 1000.0;
                      if (timeDiffSeconds > 0) { // Avoid division by zero if frames are too fast
                        double rpm = (1.0 / timeDiffSeconds) * 60.0;
                        print(rpm);
                        _rpmText = "RPM: ${rpm.toStringAsFixed(1)}";
                      }
                    }
                    _lastRotationCompleteTime = now;
                    _accumulatedAngle -= (2 * math.pi * _accumulatedAngle.sign); // Reset accumulated angle for the next circle
                  }
                }
                _previousAngleRad = currentAngleRad;
                // if (_gesturePoints.length > 50) _gesturePoints.removeAt(0); // Optional: manage gesture points list size
                // _gesturePoints.add(Offset(currentHandX, currentHandY)); // Optional: for drawing

              } else {
                // Hand is out of the circle, reset the 10-second timer (existing)
                _isHandInCircle = false;
                _handInCircleStartTime = null;

                // Reset RPM calculation variables
                _previousAngleRad = null;
                _accumulatedAngle = 0.0;
                _rotationCount = 0; // Reset count if hand leaves area
                _lastRotationCompleteTime = null;
                _rpmText = "RPM: 0";
                // _gesturePoints.clear(); // Optional: clear path
              }
            } else {
              // No target hand landmarks, reset the 10-second timer (existing)
              _isHandInCircle = false;
              _handInCircleStartTime = null;

              // Reset RPM calculation variables
              _previousAngleRad = null;
              _accumulatedAngle = 0.0;
              _rotationCount = 0;
              _lastRotationCompleteTime = null;
              _rpmText = "RPM: 0";
              // _gesturePoints.clear(); // Optional: clear path
            }

            painter.drawCircle(targetCollarbone.x, targetCollarbone.y, radius);
            // painter.drawCircle(leftCollarbone.x, leftCollarbone.y, radius);
          }
        }
      } else {
        _text = 'Poses: ${poses.length}, Detected Hands: ${detectedHands.length}';
        _customPaint = null;
      }
    } catch (e) {
      _text = 'Error: $e';
      _customPaint = null;
    }
    
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }
}
