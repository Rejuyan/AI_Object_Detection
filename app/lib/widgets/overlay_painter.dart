import 'package:flutter/material.dart';

class DetectedObject {
  final String className;
  final int id;
  final List<double> box; // [x1, y1, x2, y2]

  DetectedObject({
    required this.className,
    required this.id,
    required this.box,
  });

  factory DetectedObject.fromJson(Map<String, dynamic> json) {
    return DetectedObject(
      className: json['class'] as String,
      id: json['id'] as int,
      box: List<double>.from(json['box'].map((x) => (x as num).toDouble())),
    );
  }
}

class DetectedHand {
  final Map<String, double> fingertip; // {"x": x, "y": y}
  final List<Map<String, double>> landmarks; // List of {"x": x, "y": y, "z": z}

  DetectedHand({
    required this.fingertip,
    required this.landmarks,
  });

  factory DetectedHand.fromJson(Map<String, dynamic> json) {
    var fingertipJson = json['fingertip'] as Map<String, dynamic>;
    var landmarksJson = json['landmarks'] as List<dynamic>;

    return DetectedHand(
      fingertip: {
        'x': (fingertipJson['x'] as num).toDouble(),
        'y': (fingertipJson['y'] as num).toDouble(),
      },
      landmarks: landmarksJson.map((lm) {
        var lmMap = lm as Map<String, dynamic>;
        return {
          'x': (lmMap['x'] as num).toDouble(),
          'y': (lmMap['y'] as num).toDouble(),
          'z': (lmMap['z'] as num).toDouble(),
        };
      }).toList(),
    );
  }
}

class DetectionOverlayPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final List<DetectedHand> hands;
  final double frameWidth;
  final double frameHeight;

  DetectionOverlayPainter({
    required this.objects,
    required this.hands,
    required this.frameWidth,
    required this.frameHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / frameWidth;
    final double scaleY = size.height / frameHeight;

    // 1. Paint YOLOv8 Detections (Bounding Boxes and labels)
    final boxPaint = Paint()
      ..color = const Color(0xFF00A8E8) // Amazon Vibrant Teal/Blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var obj in objects) {
      if (obj.box.length < 4) continue;
      final x1 = obj.box[0] * scaleX;
      final y1 = obj.box[1] * scaleY;
      final x2 = obj.box[2] * scaleX;
      final y2 = obj.box[3] * scaleY;

      // Draw bounding box
      final rect = Rect.fromPoints(Offset(x1, y1), Offset(x2, y2));
      canvas.drawRect(rect, boxPaint);

      // Draw class and tracker ID label background
      final label = "${obj.className} #${obj.id}";
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.0,
          fontWeight: FontWeight.bold,
          backgroundColor: Color(0xFF232F3E), // Amazon Navy
        ),
      );
      textPainter.layout();

      // Label background rectangle
      final bgPaint = Paint()..color = const Color(0xFF232F3E); // Amazon Navy
      canvas.drawRect(
        Rect.fromLTWH(
          x1,
          (y1 - textPainter.height - 8).clamp(0, size.height),
          textPainter.width + 10,
          textPainter.height + 6,
        ),
        bgPaint,
      );

      // Draw text
      textPainter.paint(
        canvas,
        Offset(x1 + 5, (y1 - textPainter.height - 5).clamp(0, size.height)),
      );
    }

    // 2. Paint MediaPipe Hands (Fingertip circles, joint connections)
    final handJointPaint = Paint()
      ..color = const Color(0xFFD93838) // Amazon Red
      ..style = PaintingStyle.fill;

    final handConnectionPaint = Paint()
      ..color = const Color(0xFFFF9900) // Amazon Gold/Orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // MediaPipe Hand Landmark Connections Map
    const List<List<int>> handConnections = [
      [0, 1], [1, 2], [2, 3], [3, 4], // Thumb
      [0, 5], [5, 6], [6, 7], [7, 8], // Index
      [9, 10], [10, 11], [11, 12], // Middle
      [13, 14], [14, 15], [15, 16], // Ring
      [0, 17], [17, 18], [18, 19], [19, 20], // Pinky
      [5, 9], [9, 13], [13, 17] // Palm joints
    ];

    for (var hand in hands) {
      if (hand.landmarks.isEmpty) continue;

      // Draw connections
      for (var conn in handConnections) {
        if (conn[0] < hand.landmarks.length && conn[1] < hand.landmarks.length) {
          final pt1 = hand.landmarks[conn[0]];
          final pt2 = hand.landmarks[conn[1]];

          // MediaPipe hand landmarks are normalized [0.0 - 1.0]
          canvas.drawLine(
            Offset(pt1['x']! * size.width, pt1['y']! * size.height),
            Offset(pt2['x']! * size.width, pt2['y']! * size.height),
            handConnectionPaint,
          );
        }
      }

      // Draw landmark points
      for (int i = 0; i < hand.landmarks.length; i++) {
        final lm = hand.landmarks[i];
        final x = lm['x']! * size.width;
        final y = lm['y']! * size.height;

        // Make fingertip (index fingertip landmark 8) larger and teal/blue
        if (i == 8) {
          canvas.drawCircle(
            Offset(x, y),
            10.0,
            Paint()
              ..color = const Color(0xFF007185) // Amazon Deep Teal
              ..style = PaintingStyle.fill,
          );
        } else {
          canvas.drawCircle(
            Offset(x, y),
            4.0,
            handJointPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.objects != objects || oldDelegate.hands != hands;
  }
}
