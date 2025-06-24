import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:motion_kit/services/gesture_classification.dart';
import 'dart:math';

import '../services/hand_landmarker_service.dart';
import 'detector_view.dart';
import 'painters/hand_painter.dart';

class HandDetectorView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _HandDetectorViewState();
}

int random(int min, int max) {
  return min + Random().nextInt(max - min);
}

class _HandDetectorViewState extends State<HandDetectorView> {
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  var _cameraLensDirection = CameraLensDirection.back;
  final GestureClassification _gestureClassification = GestureClassification();

  int m1 = 0;
  int m2 = 0;

  void generateRandomNumbers() {
    m1 = random(0, 10);
    m2 = random(0, 10 - m1);
  }

  @override
  void initState() {
    super.initState();
    _gestureClassification.initInterpreter();
    generateRandomNumbers();
  }

  @override
  void dispose() async {
    _canProcess = false;
    super.dispose();
  }

  int? gestureNumber;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DetectorView(
          title: 'Hand Detector',
          customPaint: _customPaint,
          text: _text,
          onImage: _processImage,
          initialCameraLensDirection: _cameraLensDirection,
          onCameraLensDirectionChanged: (value) => _cameraLensDirection = value,
        ),
        Positioned(
          top: 10,
          left: 40,
          child: GestureDetector(
            onTap: () {
              setState(generateRandomNumbers);
            },
            child: Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.white.withOpacity(0.7),
              child: Text(
                '$m1 + $m2',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      ],
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
              final gesture = _gestureClassification.checkGesture(hand);
              if (gesture.type.index < 11) {
                gestureNumber = gesture.type.index;
                if (gestureNumber == m1+m2) {
                  setState(generateRandomNumbers);
                }
              } else {
                gestureNumber = null; // Reset if gesture is not recognized
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
}
