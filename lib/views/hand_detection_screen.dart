import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../services/hand_landmarker_service.dart';
import 'detector_view.dart';
import 'painters/hand_painter.dart';

class HandDetectorView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _HandDetectorViewState();
}

class _HandDetectorViewState extends State<HandDetectorView> {
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  var _cameraLensDirection = CameraLensDirection.back;

  @override
  void dispose() async {
    _canProcess = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DetectorView(
      title: 'Hand Detector',
      customPaint: _customPaint,
      text: _text,
      onImage: _processImage,
      initialCameraLensDirection: _cameraLensDirection,
      onCameraLensDirectionChanged: (value) => _cameraLensDirection = value,
    );
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;
    
    setState(() {
      _text = '';
    });

    try {
      // landmarks is now List<DetectedHand>
      final detectedHands = await HandLandmarkerService.detectHandLandmarks(inputImage);

      if (inputImage.metadata?.size != null &&
          inputImage.metadata?.rotation != null) {

        final painter = HandPainter(
          detectedHands, // Pass the flattened list of landmarks
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
          _cameraLensDirection,
          showLandmarkNumbers: true, // Set to true to show landmark indices
        );
        _customPaint = CustomPaint(painter: painter);
        
        // Update text with detection info
        if (detectedHands.isNotEmpty) {
          String handsText = '';
          for (int i = 0; i < detectedHands.length; i++) {
            final hand = detectedHands[i];
            handsText += 'Hand ${i + 1}: ${hand.handedness} (${hand.landmarks.length} landmarks)\\n';
            // Analyze gesture for each hand
            if (hand.landmarks.length >= 21) { // Ensure enough landmarks for gesture analysis
              final gesture = _analyzeHandGesture(hand.landmarks);
              if (gesture != null) {
                handsText += 'Gesture: $gesture\\n';
              }
            }
          }
          _text = handsText.trim();
        } else {
          _text = 'No hand detected';
        }
      } else {
        // Handle case where metadata is null, though less likely if image processing started
        if (detectedHands.isNotEmpty) {
          _text = 'Detected ${detectedHands.length} hand(s), but image metadata is missing.';
        } else {
          _text = 'No hand detected and image metadata is missing.';
        }
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

  // Returns a string describing the gesture, or null if no specific gesture is detected
  String? _analyzeHandGesture(List<HandLandmark> landmarks) {
    if (landmarks.length < 21) return null;

    // Example: Simple gesture detection
    // You can implement more sophisticated gesture recognition here
    
    // Check if pointing (index finger extended, others folded)
    final indexTip = landmarks[8];
    final indexPip = landmarks[6];
    final middleTip = landmarks[12];
    final middlePip = landmarks[10];
    final ringTip = landmarks[16];
    final ringPip = landmarks[14];
    final pinkyTip = landmarks[20];
    final pinkyPip = landmarks[18];
    
    // Simple pointing detection (index finger up, others down)
    bool isPointing = indexTip.y < indexPip.y && // Index finger extended
                     middleTip.y > middlePip.y && // Middle finger folded
                     ringTip.y > ringPip.y &&    // Ring finger folded
                     pinkyTip.y > pinkyPip.y;    // Pinky folded
    
    if (isPointing) {
      return 'Pointing 👉';
    }
    
    // You can add more gesture detection logic here
    // For example: thumbs up, peace sign, fist, etc.
    return null; // No specific gesture detected
  }
}
