import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import '../../services/hand_landmarker_service.dart';
import 'coordinates_translator.dart';

class HandPainter extends CustomPainter {
  HandPainter(
    this.hands,
    this.imageSize,
    this.rotation,
    this.cameraLensDirection, {
    this.showLandmarkNumbers = false,
  });

  final List<DetectedHand> hands;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final bool showLandmarkNumbers;

  @override
  void paint(Canvas canvas, Size size) {
    if (hands.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2.0
      ..color = Colors.red;

    final connectionPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.blue;

    final textPaint = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final hand in hands) {
      final landmarks = hand.landmarks;
      // Draw hand landmarks
      for (int i = 0; i < landmarks.length; i++) {
        final landmark = landmarks[i];
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

        // Draw landmark point
        canvas.drawCircle(Offset(x, y), 4, paint);

        // Optionally show landmark numbers
        if (showLandmarkNumbers) {
          textPaint.text = TextSpan(
            text: i.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          );
          textPaint.layout();
          textPaint.paint(canvas, Offset(x + 5, y - 10));
        }
      }

      // Draw hand connections (MediaPipe hand model has 21 landmarks)
      if (landmarks.length >= 21) {
        _drawHandConnections(canvas, size, connectionPaint);
      }
    }
  }

  void _drawHandConnections(Canvas canvas, Size size, Paint paint) {
    // MediaPipe hand landmark connections
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
      // Palm connections
      [5, 9], [9, 13], [13, 17],
    ];


    for (final hand in hands) {
      final landmarks = hand.landmarks;
      for (final connection in connections) {
        if (connection[0] < landmarks.length &&
            connection[1] < landmarks.length) {
          final start = landmarks[connection[0]];
          final end = landmarks[connection[1]];

          final startX = translateX(
              start.x, size, imageSize, rotation, cameraLensDirection);
          final startY = translateY(
              start.y, size, imageSize, rotation, cameraLensDirection);
          final endX =
              translateX(end.x, size, imageSize, rotation, cameraLensDirection);
          final endY =
              translateY(end.y, size, imageSize, rotation, cameraLensDirection);

          canvas.drawLine(
            Offset(startX, startY),
            Offset(endX, endY),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant HandPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize ||
        oldDelegate.hands != hands;
  }
}
