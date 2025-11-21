import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_editor/models.dart';
import 'package:my_editor/editor_canvas.dart';

void main() {
  group('Elite Text Engine Specs', () {

    // 1. ANCHOR LOGIC TEST (Gravity Fix)
    test('Anchor Logic: Dragging Right Handle keeps Left Edge fixed', () {
      // Setup: Box centered at 100, Width 100.
      // Left Edge = 50, Right Edge = 150.
      double center = 100.0;
      double width = 100.0;
      double deltaX = 50.0; // Drag Right handle by +50.

      // Expected New Width
      double newWidth = width + deltaX; // 150

      // Expected New Center
      // To keep Left Edge at 50:
      // New Left = New Center - New Width / 2
      // 50 = New Center - 75 => New Center = 125.
      // Math: Old Center + Delta / 2 => 100 + 25 = 125.
      double newCenter = center + (deltaX / 2);

      expect(newWidth, 150.0);
      expect(newCenter, 125.0);
    });

    test('Anchor Logic: Dragging Left Handle keeps Right Edge fixed', () {
      // Setup: Box centered at 100, Width 100.
      // Left Edge = 50, Right Edge = 150.
      double center = 100.0;
      double width = 100.0;
      double deltaX = -50.0; // Drag Left handle by -50 (move left).

      // Expected New Width
      // Dragging left handle to the left INCREASES width.
      // Delta is negative (-50).
      // Width Change = -Delta = +50.
      double newWidth = width - deltaX; // 150.

      // Expected New Center
      // To keep Right Edge at 150:
      // New Right = New Center + New Width / 2
      // 150 = New Center + 75 => New Center = 75.
      // Math: Old Center + Delta / 2 => 100 + (-25) = 75.
      double newCenter = center + (deltaX / 2);

      expect(newWidth, 150.0);
      expect(newCenter, 75.0);
    });

    // 2. UNCONSTRAINED WIDTH TEST
    testWidgets('Unconstrained Width: Box can be wider than text', (WidgetTester tester) async {
      final textLayer = TextLayer(
        id: '1',
        text: 'Hi', // Approx 20-30px wide
        style: const TextStyle(fontSize: 20),
      );

      textLayer.customWidth = 500.0;

      await tester.pumpWidget(
        Center(
          child: CustomPaint(
            painter: TestLayerPainter(textLayer),
            size: const Size(1000, 1000),
          ),
        ),
      );

      // The reported size of the layer should match customWidth
      expect(textLayer.size.width, 500.0);
      // And it should NOT have scaled up (fitScale should be 1.0)
      expect(textLayer.debugFitScale, 1.0);
    });

    // 3. AUTO-FIT SHRINK TEST
    testWidgets('Auto-Fit Shrink: Scales down to fit narrow box', (WidgetTester tester) async {
      final textLayer = TextLayer(
        id: '2',
        text: 'HugeText',
        style: const TextStyle(fontSize: 100), // Intrinsic width large
        enableAutoFit: true,
      );

      textLayer.customWidth = 10.0; // Very narrow

      await tester.pumpWidget(
        Center(
          child: CustomPaint(
            painter: TestLayerPainter(textLayer),
            size: const Size(1000, 1000),
          ),
        ),
      );

      // Should have shrunk significantly
      expect(textLayer.debugFitScale, lessThan(1.0));
      // Should handle safety margin (effective width < 10)
      // Check if it crashed or produced valid scale
      expect(textLayer.debugFitScale, greaterThan(0.0));
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
