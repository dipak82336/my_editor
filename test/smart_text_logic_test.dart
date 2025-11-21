import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_editor/models.dart';
import 'package:my_editor/editor_canvas.dart';
import 'package:my_editor/logic_helper.dart'; // Import the helper

void main() {
  test('Unconstrained Width Test', () {
    // 2. Unconstrained Width Test:
    // Set text "Hi" (approx 20px wide).
    // Manually set customWidth to 500.
    // Assert that the layer's reported size width is 500, NOT 20.

    final layer = TextLayer(
      id: '2',
      text: 'Hi',
      style: const TextStyle(fontSize: 20),
      customWidth: 500,
    );

    // Trigger paint to calculate size
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    layer.paint(canvas, Size.infinite);

    expect(layer.size.width, 500.0);
    expect(layer.size.height, greaterThan(0));
  });

  test('Auto-Fit Shrink Test', () {
    // 3. Auto-Fit Shrink Test:
    // Set text "Huge Text String". Set customWidth to 10px.
    // Assert that the calculated paint scale is < 1.0 (meaning it shrunk to fit).

    final layer = TextLayer(
      id: '3',
      text: 'Huge Text String',
      style: const TextStyle(fontSize: 50),
      customWidth: 10,
    );

    // Get intrinsic size
    final intrinsicLayer = TextLayer(
      id: 'temp',
      text: 'Huge Text String',
      style: const TextStyle(fontSize: 50),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    intrinsicLayer.paint(canvas, Size.infinite);
    final intrinsicHeight = intrinsicLayer.size.height;

    layer.paint(canvas, Size.infinite);

    expect(layer.size.width, 10.0);
    expect(layer.size.height, lessThan(intrinsicHeight));
  });

  test('Anchor Logic Test (Unit Test)', () {
    // 1. Anchor Logic Test (The "Gravity" Fix):
    // Replaced integration test with Unit Test for LogicHelper.
    // Create a layer at position: Offset(100, 100) with width: 100.
    // Simulate dragging the Right Handle by +50px.
    // Expectation: New width 150, New position (center) Offset(125, 100).

    final layer = TextLayer(
      id: '1',
      text: 'Test',
      position: const Offset(100, 100),
      customWidth: 100,
    );

    // Drag Right Handle +50.
    final result = LogicHelper.calculateTextResize(
      layer: layer,
      localDelta: const Offset(50, 0),
      isRightHandle: true,
      isLeftHandle: false,
    );

    expect(result.newWidth, 150.0);
    expect(result.newPosition, const Offset(125, 100));

    // Additional Test: Drag Left Handle -50 (move left by 50).
    // Current width 150. Drag Left Handle -50.
    // Width should increase by 50 -> 200.
    // Center should shift Left by 25.
    // Current pos (125, 100). New pos (100, 100).

    // Setup modified layer
    final layer2 = TextLayer(
      id: '1',
      text: 'Test',
      position: const Offset(125, 100),
      customWidth: 150,
    );

    final result2 = LogicHelper.calculateTextResize(
      layer: layer2,
      localDelta: const Offset(-50, 0), // Moving Left Handle to Left (negative X)
      isRightHandle: false,
      isLeftHandle: true,
    );

    // If moving left handle to left (negative delta), width INCREASES.
    // deltaWidth = -(-50) = 50.
    // newWidth = 150 + 50 = 200.
    // centerXShift = -50 / 2 = -25.
    // newPosition = 125 - 25 = 100.

    expect(result2.newWidth, 200.0);
    expect(result2.newPosition, const Offset(100, 100));
  });
}
