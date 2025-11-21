import 'package:flutter/material.dart';
import 'package:my_editor/models.dart';
import 'dart:math' as math;

class TextResizeResult {
  final double newWidth;
  final Offset newPosition;

  TextResizeResult(this.newWidth, this.newPosition);
}

class LogicHelper {
  static TextResizeResult calculateTextResize({
    required TextLayer layer,
    required Offset localDelta,
    required bool isRightHandle,
    required bool isLeftHandle,
  }) {
    // 3. Apply Anchor Rules based on Handle
    double deltaWidth = 0.0;
    double centerXShift = 0.0;

    // Ensure customWidth is initialized
    double currentWidth = layer.customWidth ?? layer.size.width;

    if (isRightHandle) {
      // Dragging Right Handle
      // Positive deltaX -> Increase Width
      deltaWidth = localDelta.dx;
      // Shift Center Right by half delta
      centerXShift = localDelta.dx / 2;
    } else if (isLeftHandle) {
      // Dragging Left Handle
      // Positive deltaX -> Decrease Width (because handle is at negative X)
      // Wait, localDeltaX is positive if moving right.
      // If dragging Left handle to Right -> Width Decreases.
      deltaWidth = -localDelta.dx;
      // Shift Center Right by half delta
      centerXShift = localDelta.dx / 2;
    }

    double newWidth = currentWidth + deltaWidth;

    // 4. Enforce Min Width
    if (newWidth < 50.0) {
      final actualDeltaWidth = 50.0 - currentWidth;
      newWidth = 50.0;

      if (isRightHandle) {
        centerXShift = actualDeltaWidth / 2;
      } else {
        // center shift should be half of (negative) width change.
        centerXShift = -actualDeltaWidth / 2;
      }
    }

    // 5. Apply Center Shift (Rotate back to global)
    // We shifted center by (centerXShift, 0) in local space.
    // Convert (centerXShift, 0) back to global delta.
    final globalShiftX = centerXShift * math.cos(layer.rotation);
    final globalShiftY = centerXShift * math.sin(layer.rotation);

    final newPosition = layer.position + Offset(globalShiftX, globalShiftY);

    return TextResizeResult(newWidth, newPosition);
  }
}
