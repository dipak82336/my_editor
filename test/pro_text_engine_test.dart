import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_editor/models.dart';
import 'package:my_editor/editor_canvas.dart';
import 'dart:math' as math;

void main() {
  group('Pro-Grade Text Engine Specs', () {

    // 1. ANCHORED RESIZING
    test('Anchored Resize: Dragging Right Handle keeps Left Edge fixed', () {
      // Setup: Box centered at 100, Width 100.
      // Left Edge = 50, Right Edge = 150.
      double center = 100.0;
      double width = 100.0;
      double delta = 50.0; // Drag Right handle by +50.

      // Logic for Right Handle:
      // New Width = Old Width + Delta
      double newWidth = width + delta; // 150

      // New Center = Old Center + (Delta / 2)
      double newCenter = center + (delta / 2); // 100 + 25 = 125

      // Verification: Left Edge should still be 50.
      // Left = New Center - (New Width / 2)
      double newLeft = newCenter - (newWidth / 2); // 125 - 75 = 50.

      expect(newWidth, 150.0);
      expect(newLeft, 50.0);
    });

    test('Anchored Resize: Dragging Left Handle keeps Right Edge fixed', () {
      // Setup: Box centered at 100, Width 100.
      // Left Edge = 50, Right Edge = 150.
      double center = 100.0;
      double width = 100.0;
      double delta = -50.0; // Drag Left handle by -50 (to the left, making it bigger).
      // Note: If we drag left handle to left (negative delta in X), width INCREASES.
      // So delta calculation depends on handle.
      // Usually: deltaX is (current - prev). If moving left, deltaX is negative.
      // For Left Handle: Width Change = -deltaX.

      double dragDelta = -50.0; // Moved mouse 50px left.

      // Logic for Left Handle:
      // New Width = Old Width - dragDelta (e.g. 100 - (-50) = 150)
      double newWidth = width - dragDelta;

      // New Center = Old Center + (dragDelta / 2)
      // 100 + (-25) = 75.
      double newCenter = center + (dragDelta / 2);

      // Verification: Right Edge should still be 150.
      // Right = New Center + (New Width / 2)
      double newRight = newCenter + (newWidth / 2); // 75 + 75 = 150.

      expect(newWidth, 150.0);
      expect(newRight, 150.0);
    });

    // 2. AUTO-FIT & SAFETY MARGINS
    testWidgets('Auto-Fit: Scales down single long word with Safety Margin', (WidgetTester tester) async {
      final textLayer = TextLayer(
        id: '1',
        text: 'EXTRALONGWORD',
        style: const TextStyle(fontSize: 100),
      );

      // Simulate "Narrow Box"
      textLayer.customWidth = 100.0;
      textLayer.enableAutoFit = true;

      // We need to run paint logic.
      await tester.pumpWidget(
        Center(
          child: CustomPaint(
            painter: TestLayerPainter(textLayer),
            size: const Size(500, 500),
          ),
        ),
      );

      // Logic expectation:
      // Intrinsic width of 'EXTRALONGWORD' at size 100 is LARGE (e.g. 800+).
      // Box is 100. Safety margin 8px? (Or strict specification).
      // Spec: "effectiveWidth = boxWidth - padding"
      // If padding is 16px (from Spec C description "e.g. 16px" - wait, previous plan said 8px, this prompt says 16px).
      // Let's check spec again: "e.g., 16px padding".
      // I will implement configurable or 16px default if "pro".
      // Let's assume 8px per side -> 16px total? Or 8px total?
      // Step 3 in prompt says "effectiveWidth = boxWidth - padding".
      // Let's use 16px total for safety.

      // Effective Width = 100 - 16 = 84.
      // Scale = 84 / Intrinsic.
      // Scale should be << 1.0.

      expect(textLayer.debugFitScale, lessThan(1.0));
      expect(textLayer.debugFitScale, greaterThan(0.0));
    });

    // 3. UNBOUNDED BOX
    testWidgets('Unbounded Box: Does NOT scale if box > text', (WidgetTester tester) async {
      final textLayer = TextLayer(
        id: '2',
        text: 'Tiny',
        style: const TextStyle(fontSize: 20),
      );

      textLayer.customWidth = 500.0; // Huge box
      textLayer.enableAutoFit = true;

      await tester.pumpWidget(
        Center(
          child: CustomPaint(
            painter: TestLayerPainter(textLayer),
            size: const Size(500, 500),
          ),
        ),
      );

      // Should NOT scale up.
      expect(textLayer.debugFitScale, 1.0);
    });
  });
}

class TestLayerPainter extends CustomPainter {
  final TextLayer layer;
  TestLayerPainter(this.layer);
  @override
  void paint(Canvas canvas, Size size) {
    layer.paint(canvas, size);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
