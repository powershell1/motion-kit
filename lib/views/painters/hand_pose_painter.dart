import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import '../../services/hand_landmarker_service.dart';
import 'coordinates_translator.dart';

class Circle {
  Circle(this.x, this.y, this.radius);

  final double x;
  final double y;
  final double radius;
}

class HandPosePainter extends CustomPainter {
  HandPosePainter(
    this.poses,
    this.hands,
    this.imageSize,
    this.rotation,
    this.cameraLensDirection, {
    this.showHandNumbers = false,
    this.showPoseNumbers = false,
    this.showConnections = true,
  });

  final List<Pose> poses;
  final List<DetectedHand> hands;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final bool showHandNumbers;
  final bool showPoseNumbers;
  final bool showConnections;
  final List<Circle> circles = [];

  void drawCircle(double x, double y, double radius) {
    circles.add(Circle(x, y, radius));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Paint configurations
    final poseLandmarkPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 3.0
      ..color = Colors.green;

    final handLandmarkPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2.0
      ..color = Colors.red;

    final poseConnectionPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.blue;

    final handConnectionPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.orange;

    final leftSidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.yellow;

    final rightSidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.cyan;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw pose landmarks and connections
    for (final pose in poses) {
      _drawPoseLandmarks(canvas, pose, size, poseLandmarkPaint, textPainter);
      if (showConnections) {
        _drawPoseConnections(canvas, pose, size, poseConnectionPaint, leftSidePaint, rightSidePaint);
      }
    }

    // Draw hand landmarks and connections
    if (hands.isNotEmpty && showConnections) {
      for (final hand in hands) {
        if (hand.landmarks.isEmpty) continue;
        final handLandmarks = hand.landmarks;
        _drawHandLandmarks(canvas, handLandmarks, size, handLandmarkPaint, textPainter);
        _drawHandConnections(canvas, handLandmarks, size, handConnectionPaint);
      }
    }

    // Draw circles if any
    for (final circle in circles) {
      canvas.drawCircle(
        Offset(
          translateX(circle.x, size, imageSize, rotation, cameraLensDirection),
          translateY(circle.y, size, imageSize, rotation, cameraLensDirection),
        ),
        circle.radius,
        Paint()
          ..color = Colors.red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0,
      );
    }
  }

  void _drawPoseLandmarks(Canvas canvas, Pose pose, Size size, Paint paint, TextPainter textPainter) {
    pose.landmarks.forEach((type, landmark) {
      final x = translateX(
        landmark.x,
        size,
        imageSize,
        rotation,
        cameraLensDirection,
      );
      final y = translateY(
        landmark.y,
        size,
        imageSize,
        rotation,
        cameraLensDirection,
      );

      canvas.drawCircle(Offset(x, y), 5, paint);

      if (showPoseNumbers) {
        textPainter.text = TextSpan(
          text: type.name.substring(0, 3).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - 12, y - 25));
      }
    });
  }

  void _drawPoseConnections(Canvas canvas, Pose pose, Size size, Paint centerPaint, Paint leftPaint, Paint rightPaint) {
    final landmarks = pose.landmarks;

    void drawConnection(PoseLandmarkType from, PoseLandmarkType to, Paint paint) {
      final fromLandmark = landmarks[from];
      final toLandmark = landmarks[to];
      
      if (fromLandmark != null && toLandmark != null) {
        final x1 = translateX(fromLandmark.x, size, imageSize, rotation, cameraLensDirection);
        final y1 = translateY(fromLandmark.y, size, imageSize, rotation, cameraLensDirection);
        final x2 = translateX(toLandmark.x, size, imageSize, rotation, cameraLensDirection);
        final y2 = translateY(toLandmark.y, size, imageSize, rotation, cameraLensDirection);
        
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
      }
    }

    // Face connections
    drawConnection(PoseLandmarkType.leftEar, PoseLandmarkType.leftEyeOuter, leftPaint);
    drawConnection(PoseLandmarkType.leftEyeOuter, PoseLandmarkType.leftEye, leftPaint);
    drawConnection(PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeInner, leftPaint);
    drawConnection(PoseLandmarkType.leftEyeInner, PoseLandmarkType.nose, centerPaint);
    drawConnection(PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner, centerPaint);
    drawConnection(PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye, rightPaint);
    drawConnection(PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter, rightPaint);
    drawConnection(PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar, rightPaint);

    // Torso connections
    drawConnection(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, centerPaint);
    drawConnection(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, leftPaint);
    drawConnection(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, rightPaint);
    drawConnection(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip, centerPaint);

    // Left arm connections
    drawConnection(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, leftPaint);
    drawConnection(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, leftPaint);

    // Right arm connections
    drawConnection(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, rightPaint);
    drawConnection(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, rightPaint);

    // Left leg connections
    drawConnection(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, leftPaint);
    drawConnection(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, leftPaint);

    // Right leg connections
    drawConnection(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, rightPaint);
    drawConnection(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, rightPaint);
  }

  void _drawHandLandmarks(Canvas canvas, List<HandLandmark> landmarks, Size size, Paint paint, TextPainter textPainter) {
    for (int i = 0; i < landmarks.length; i++) {
      final landmark = landmarks[i];
      final x = translateX(
        landmark.x,
        size,
        imageSize, // Hand landmarks are normalized
        rotation,
        cameraLensDirection,
      );
      final y = translateY(
        landmark.y,
        size,
        imageSize, // Hand landmarks are normalized
        rotation,
        cameraLensDirection,
      );

      canvas.drawCircle(Offset(x, y), 4, paint);

      if (showHandNumbers) {
        textPainter.text = TextSpan(
          text: i.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(x - 6, y - 18));
      }
    }
  }

  void _drawHandConnections(Canvas canvas, List<HandLandmark> landmarks, Size size, Paint paint) {
    if (landmarks.length < 21) return;

    // Define hand landmark connections
    final connections = [
      // Thumb
      [0, 1], [1, 2], [2, 3], [3, 4],
      // Index finger
      [0, 5], [5, 6], [6, 7], [7, 8],
      // Middle finger
      [0, 9], [9, 10], [10, 11], [11, 12],
      // Ring finger
      [0, 13], [13, 14], [14, 15], [15, 16],
      // Pinky
      [0, 17], [17, 18], [18, 19], [19, 20],
    ];

    for (final connection in connections) {
      if (connection[0] < landmarks.length && connection[1] < landmarks.length) {
        final landmark1 = landmarks[connection[0]];
        final landmark2 = landmarks[connection[1]];
        
        final x1 = translateX(landmark1.x, size, imageSize, rotation, cameraLensDirection);
        final y1 = translateY(landmark1.y, size, imageSize, rotation, cameraLensDirection);
        final x2 = translateX(landmark2.x, size, imageSize, rotation, cameraLensDirection);
        final y2 = translateY(landmark2.y, size, imageSize, rotation, cameraLensDirection);
        
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
