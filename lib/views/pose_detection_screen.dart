import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:vector_math/vector_math.dart';

import 'detector_view.dart';
import 'painters/pose_painter.dart';

class PoseDetectorView extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _PoseDetectorViewState();
}

class _PoseDetectorViewState extends State<PoseDetectorView> {
  final PoseDetector _poseDetector =
  PoseDetector(options: PoseDetectorOptions(
    mode: PoseDetectionMode.stream,
    model: PoseDetectionModel.base,
  ));
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  var _cameraLensDirection = CameraLensDirection.back;

  @override
  void dispose() async {
    _canProcess = false;
    _poseDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DetectorView(
      title: 'Pose Detector',
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
    final poses = await _poseDetector.processImage(inputImage);
    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null) {
      final painter = PosePainter(
        poses,
        inputImage.metadata!.size,
        inputImage.metadata!.rotation,
        _cameraLensDirection,
        debugLandmarks: true,
      );
      _customPaint = CustomPaint(painter: painter);
      if (poses.isNotEmpty) {
        final landmarks = poses[0].landmarks;
        PoseLandmark rightShoulder = landmarks[PoseLandmarkType.rightShoulder]!;
        PoseLandmark leftShoulder = landmarks[PoseLandmarkType.leftShoulder]!;
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

        double distance = (rightShoulder.x - leftShoulder.x).abs();
        double radius = distance / 10; // Adjust radius based on distance

        painter.drawCircle(rightCollarbone.x, rightCollarbone.y, radius);
        painter.drawCircle(leftCollarbone.x, leftCollarbone.y, radius);
      }
    } else {
      _text = 'Poses found: ${poses.length}\n\n';
      // TODO: set _customPaint to draw landmarks on top of image
      _customPaint = null;
    }
    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }
}