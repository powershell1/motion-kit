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

  // Rotation tracking variables
  int _rotationCount = 0;
  double? _previousAngle;
  double _totalRotation = 0.0;
  bool _isHandInRadius = false;
  Vector3? _previousHandPosition;
  
  // Hand landmark indices for center calculation
  static const int _wristIndex = 0;
  static const int _middleFingerMcpIndex = 9;
  static const int _indexFingerMcpIndex = 5;
  static const int _ringFingerMcpIndex = 13;
  static const int _pinkyMcpIndex = 17;

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
      ),      body: Stack(
        children: [
          DetectorView(
            title: 'Hand & Pose Detector',
            customPaint: _customPaint,
            text: _text,
            onImage: _processImage,
            initialCameraLensDirection: _cameraLensDirection,
            onCameraLensDirectionChanged: (value) => _cameraLensDirection = value,
          ),
          // Control buttons
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  onPressed: () {
                    setState(() {
                      switchingSide();
                      _resetRotationTracking();
                    });
                  },
                  label: Text('Target: ${side == Handedness.left ? "Left" : "Right"}'),
                  icon: Icon(Icons.swap_horiz),
                  heroTag: "switch_hand",
                ),
                SizedBox(height: 10),
                FloatingActionButton.extended(
                  onPressed: () {
                    setState(() {
                      _resetRotationTracking();
                    });
                  },
                  label: Text('Reset Count'),
                  icon: Icon(Icons.refresh),
                  heroTag: "reset_count",
                ),
              ],
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
        _customPaint = CustomPaint(painter: painter);        // Build text output
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
        
        // Add rotation tracking information
        outputText += '\n--- Rotation Tracking ---\n';
        outputText += 'Target Hand: ${side == Handedness.left ? "Left" : "Right"}\n';
        outputText += 'Hand in Radius: ${_isHandInRadius ? "YES" : "NO"}\n';
        outputText += 'Rotation Count: $_rotationCount\n';
        outputText += 'Current Rotation: ${(_totalRotation * 180 / math.pi).toStringAsFixed(1)}°\n';
        
        _text = outputText.trim();

        // The circle drawing logic seems specific to pose landmarks,
        // ensure it still makes sense or adjust as needed.
        if (poses.isNotEmpty && poses[0].landmarks.isNotEmpty) {
          final landmarks = poses[0].landmarks;
          PoseLandmark? rightShoulder = landmarks[PoseLandmarkType.rightShoulder];
          PoseLandmark? leftShoulder = landmarks[PoseLandmarkType.leftShoulder];

          if (rightShoulder != null && leftShoulder != null) {
            Vector3 centerShoulder = Vector3(
              (rightShoulder.x + leftShoulder.x) / 2,
              (rightShoulder.y + leftShoulder.y) / 2 + 10,
              (rightShoulder.z + leftShoulder.z) / 2,
            );
            Vector3 rightCollarbone = Vector3(
                (centerShoulder.x + rightShoulder.x) / 2,
                (centerShoulder.y + rightShoulder.y) / 2 + 10, // Adjusted for better visibility
                (centerShoulder.z + rightShoulder.z) / 2
            );
            Vector3 leftCollarbone = Vector3(
                (centerShoulder.x + leftShoulder.x) / 2,
                (centerShoulder.y + leftShoulder.y) / 2 + 10, // Adjusted for better visibility
                (centerShoulder.z + leftShoulder.z) / 2
            );
            Vector3 targetCollarbone = side == Handedness.left
                ? leftCollarbone
                : rightCollarbone;            double distance = (rightShoulder.x - leftShoulder.x).abs();
            double radius = distance / 10 * 1.75; // Adjust radius based on distance

            if (targetHandLandmarks != null) {
              // Calculate hand center position
              Vector3 handCenter = _getHandCenter(targetHandLandmarks.landmarks);
              
              // Check if hand is within the target circle radius
              double handToTargetDistance = _calculateDistance(handCenter, targetCollarbone);
              _isHandInRadius = handToTargetDistance <= radius;
              
              if (_isHandInRadius) {
                // Update rotation tracking only when hand is in radius
                _updateRotationTracking(targetHandLandmarks.landmarks);
              } else {
                // Reset rotation tracking when hand leaves radius
                if (_previousAngle != null) {
                  _resetRotationTracking();
                }
              }
            } else {
              // No hand detected, reset tracking
              _isHandInRadius = false;
              if (_previousAngle != null) {
                _resetRotationTracking();
              }
            }            painter.drawCircle(targetCollarbone.x, targetCollarbone.y, radius, isActive: _isHandInRadius);
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

  // Utility methods for hand tracking
  Vector3 _getHandCenter(List<HandLandmark> landmarks) {
    if (landmarks.length < 21) return Vector3.zero();
    
    // Calculate center using wrist and MCP joints
    final wrist = landmarks[_wristIndex];
    final indexMcp = landmarks[_indexFingerMcpIndex];
    final middleMcp = landmarks[_middleFingerMcpIndex];
    final ringMcp = landmarks[_ringFingerMcpIndex];
    final pinkyMcp = landmarks[_pinkyMcpIndex];
    
    return Vector3(
      (wrist.x + indexMcp.x + middleMcp.x + ringMcp.x + pinkyMcp.x) / 5,
      (wrist.y + indexMcp.y + middleMcp.y + ringMcp.y + pinkyMcp.y) / 5,
      (wrist.z + indexMcp.z + middleMcp.z + ringMcp.z + pinkyMcp.z) / 5,
    );
  }
  
  double _calculateHandAngle(List<HandLandmark> landmarks) {
    if (landmarks.length < 21) return 0.0;
    
    // Use wrist to middle finger MCP for angle calculation
    final wrist = landmarks[_wristIndex];
    final middleMcp = landmarks[_middleFingerMcpIndex];
    
    return math.atan2(
      middleMcp.y - wrist.y,
      middleMcp.x - wrist.x,
    );
  }
  
  double _calculateDistance(Vector3 point1, Vector3 point2) {
    return math.sqrt(
      math.pow(point1.x - point2.x, 2) +
      math.pow(point1.y - point2.y, 2) +
      math.pow(point1.z - point2.z, 2)
    );
  }
  
  void _updateRotationTracking(List<HandLandmark> landmarks) {
    final currentAngle = _calculateHandAngle(landmarks);
    
    if (_previousAngle != null) {
      double angleDifference = currentAngle - _previousAngle!;
      
      // Normalize angle difference to [-π, π]
      while (angleDifference > math.pi) angleDifference -= 2 * math.pi;
      while (angleDifference < -math.pi) angleDifference += 2 * math.pi;
      
      _totalRotation += angleDifference;
      
      // Count full rotations (360 degrees = 2π radians)
      if (_totalRotation.abs() >= 2 * math.pi) {
        _rotationCount += (_totalRotation > 0) ? 1 : -1;
        _totalRotation = _totalRotation % (2 * math.pi);
      }
    }
    
    _previousAngle = currentAngle;
  }
  
  void _resetRotationTracking() {
    _rotationCount = 0;
    _previousAngle = null;
    _totalRotation = 0.0;
    _previousHandPosition = null;
  }
}
