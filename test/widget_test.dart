import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // For kDoubleTapTimeout
import 'package:flutter_test/flutter_test.dart';
import 'package:my_editor/main.dart';
import 'package:my_editor/editor_canvas.dart';
import 'package:my_editor/models.dart';

void main() {
  testWidgets('Editor Core Interaction Test', (WidgetTester tester) async {
    // 1. Load the MyApp
    await tester.pumpWidget(const MyApp());
    await tester.pump(); // Frame

    // 2. Find the CustomPaint
    final gestureDetectorFinder = find.descendant(
      of: find.byType(EditorCanvas),
      matching: find.byType(GestureDetector),
    );
    expect(gestureDetectorFinder, findsOneWidget);

    final customPaintFinder = find.descendant(
      of: gestureDetectorFinder,
      matching: find.byType(CustomPaint),
    );
    expect(customPaintFinder, findsOneWidget);

    // 3. Access the state
    final editorPageFinder = find.byType(EditorPage);
    expect(editorPageFinder, findsOneWidget);
    final EditorPageState editorPageState = tester.state(editorPageFinder);
    final composition = editorPageState.composition;

    // Verify initial state
    expect(composition.layers.length, 2);
    final textLayer1 = composition.layers[0] as TextLayer;

    // 4. Simulate a Tap to select the layer
    await tester.tap(customPaintFinder);
    await tester.pump(); // Process the tap event

    // Because onDoubleTapDown is present, GestureDetector waits to ensure it's not a double tap.
    await tester.pump(kDoubleTapTimeout);

    // Verify that tapping on a layer selects it
    expect(
      textLayer1.isSelected,
      true,
      reason: "Layer should be selected after tap",
    );

    // 5. Simulate a Drag
    // Use tester.drag which is higher level and reliable
    await tester.drag(customPaintFinder, const Offset(50, 50));
    await tester.pump();

    // Pump enough time for any pending double-tap timers from the drag start to expire
    await tester.pump(kDoubleTapTimeout);

    // 6. Verify via logic/math that the layer's position has indeed updated
    // Initial position was Offset.zero
    // We expect the position to have changed significantly in the direction of drag.
    // Exact pixel value depends on scaling, so we check it's > 0.
    expect(
      textLayer1.position.dx,
      greaterThan(1.0),
      reason: "Layer X position should update after drag",
    );
    expect(
      textLayer1.position.dy,
      greaterThan(1.0),
      reason: "Layer Y position should update after drag",
    );
  });
}
