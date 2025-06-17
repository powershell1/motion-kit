import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'coordinates_translator.dart';

class Circle {
  Circle(this.x, this.y, this.radius);

  final double x;
  final double y;
  final double radius;
}

class PosePainter extends CustomPainter {
  PosePainter(
      this.poses,
      this.imageSize,
      this.rotation,
      this.cameraLensDirection,
      {
        this.debugLandmarks = false,
      }
  );

  final bool debugLandmarks;
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final List<Circle> circles = [];

  void drawCircle(double x, double y, double radius) {
    circles.add(Circle(x, y, radius));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.green;

    final leftPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.yellow;

    final rightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.blueAccent;

    if (this.debugLandmarks) {
      for (final pose in poses) {
        pose.landmarks.forEach((_, landmark) {
          canvas.drawCircle(
              Offset(
                translateX(
                  landmark.x,
                  size,
                  imageSize,
                  rotation,
                  cameraLensDirection,
                ),
                translateY(
                  landmark.y,
                  size,
                  imageSize,
                  rotation,
                  cameraLensDirection,
                ),
              ),
              1,
              paint);
        });

        void paintLine(PoseLandmarkType type1, PoseLandmarkType type2,
            Paint paintType) {
          final PoseLandmark joint1 = pose.landmarks[type1]!;
          final PoseLandmark joint2 = pose.landmarks[type2]!;
          canvas.drawLine(
              Offset(
                  translateX(
                    joint1.x,
                    size,
                    imageSize,
                    rotation,
                    cameraLensDirection,
                  ),
                  translateY(
                    joint1.y,
                    size,
                    imageSize,
                    rotation,
                    cameraLensDirection,
                  )),
              Offset(
                  translateX(
                    joint2.x,
                    size,
                    imageSize,
                    rotation,
                    cameraLensDirection,
                  ),
                  translateY(
                    joint2.y,
                    size,
                    imageSize,
                    rotation,
                    cameraLensDirection,
                  )),
              paintType);
        }

        // Draw collarbones
        paintLine(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
            paint);

        //Draw arms
        paintLine(
            PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow,
            leftPaint);
        paintLine(
            PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, leftPaint);
        paintLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow,
            rightPaint);
        paintLine(
            PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist,
            rightPaint);

        //Draw Body
        paintLine(
            PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, leftPaint);
        paintLine(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip,
            rightPaint);

        //Draw legs
        paintLine(
            PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, leftPaint);
        paintLine(
            PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, leftPaint);
        paintLine(
            PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, rightPaint);
        paintLine(
            PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle,
            rightPaint);
      }
    }

    // Draw circles for each landmark
    for (final circle in circles) {
      canvas.drawCircle(
        Offset(
          translateX(circle.x, size, imageSize, rotation, cameraLensDirection),
          translateY(circle.y, size, imageSize, rotation, cameraLensDirection),
        ),
        circle.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.imageSize != imageSize || oldDelegate.poses != poses;
  }
}