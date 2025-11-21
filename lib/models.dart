import 'package:flutter/material.dart';
import 'dart:ui' as ui;

// Constants
const double handleRadius = 9.0;
const double rotationHandleDistance = 30.0;

class EditorComposition {
  Size dimension;
  Color backgroundColor;
  List<BaseLayer> layers;

  EditorComposition({
    required this.dimension,
    this.backgroundColor = Colors.white,
    List<BaseLayer>? layers,
  }) : layers = layers ?? [];
}

abstract class BaseLayer {
  String id;
  Offset position;
  double rotation;
  double scale;
  bool isSelected;
  bool isEditing;

  BaseLayer({
    required this.id,
    this.position = Offset.zero,
    this.rotation = 0.0,
    this.scale = 1.0,
    this.isSelected = false,
    this.isEditing = false,
  });

  Matrix4 get matrix {
    final mat = Matrix4.identity();
    mat.setTranslationRaw(position.dx, position.dy, 0);
    mat.rotateZ(rotation);
    mat.scale(scale, scale, 1.0);
    return mat;
  }

  void paint(Canvas canvas, Size size);
  Size get size;
}

class TextLayer extends BaseLayer {
  String text;
  TextStyle style;
  Size _cachedSize = Size.zero;

  TextSelection selection;
  bool showCursor;

  double? customWidth;
  bool enableAutoFit;

  // Exposed for testing
  double debugFitScale = 1.0;

  TextLayer({
    required super.id,
    required this.text,
    super.position,
    super.rotation,
    super.scale,
    this.style = const TextStyle(fontSize: 30, color: Colors.black),
    this.selection = const TextSelection.collapsed(offset: 0),
    this.showCursor = false,
    this.customWidth,
    this.enableAutoFit = true,
  });

  @override
  Size get size => _cachedSize;

  @override
  void paint(Canvas canvas, Size size) {
    // Pre-calculate intrinsic width to decide logic
    final intrinsicPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    intrinsicPainter.layout();
    final maxIntrinsicWidth = intrinsicPainter.width;

    double fitScale = 1.0;
    double? layoutWidth;

    if (customWidth != null) {
      final hasSpaces = text.contains(' ');

      // Scenario A (Sentence): If spaces exist, use standard wrapping
      if (hasSpaces) {
        layoutWidth = customWidth;
      }
      // Scenario B (Long Word): If NO spaces and textWidth > customWidth, auto-fit
      else if (enableAutoFit && maxIntrinsicWidth > customWidth!) {
        fitScale = customWidth! / maxIntrinsicWidth;
      } else {
        // Fallback for single word that fits or auto-fit disabled
        // Just center it, maybe restrict width if you want clipping,
        // but typically single words overflow if not scaled.
        // Here we act like standard text unless scaled.
      }
    }

    debugFitScale = fitScale;

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );

    // Apply layout width if wrapping
    if (layoutWidth != null) {
       textPainter.layout(maxWidth: layoutWidth);
    } else {
       textPainter.layout();
    }

    _cachedSize = textPainter.size;

    // If we are scaling down a single word, the visual size is effectively smaller
    // but the painter reports original size. We need to adjust drawing.

    canvas.save();

    if (fitScale != 1.0) {
      // Scale around center
      canvas.scale(fitScale, fitScale);

      // If we scaled down, the "effective" size for border drawing should probably reflect that?
      // Or does the border stay large?
      // The prompt says "Auto-Fit (Scale Down) ... to fit the text visually."
      // If we scale the canvas, the text draws smaller.
      // But _cachedSize (used for hit testing and border) is currently the UN-SCALED size.
      // This means the border will appear huge around the tiny text if we don't adjust _cachedSize or the border drawing.

      // However, the prompt says "simulate dragging... assert customWidth updates, but scale remains 1.0".
      // This implies `layer.scale` is 1.0. The "fitScale" is local to painting.

      // If I leave _cachedSize as intrinsic size, the border will be drawn around the large intrinsic text,
      // but the text itself is scaled down.
      // To make it look "fitted", I should update _cachedSize to the Scaled size.
      _cachedSize = _cachedSize * fitScale;
    }

    final paintOffset = Offset(-_cachedSize.width / 2, -_cachedSize.height / 2);

    // 1. Draw Selection Highlights
    if (isEditing) {
      final selectionColor = Colors.blue.withValues(alpha: 0.3);
      final safeSelection = TextSelection(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
      );

      if (!safeSelection.isCollapsed) {
        final boxes = textPainter.getBoxesForSelection(safeSelection);
        for (var box in boxes) {
          // Adjust box for scale if necessary?
          // If we scaled the canvas, the painter coordinates are in the unscaled space.
          // Since we have `canvas.scale(fitScale)`, drawing the unscaled boxes will result in scaled visual boxes.
          // BUT `paintOffset` is calculated from the SCALED size.
          // We need to shift by the UN-SCALED offset if we are inside the scaled canvas context.

          // Wait, if I update `_cachedSize` to be scaled, `paintOffset` is small.
          // The painter thinks it is large.
          // So `box` is large.
          // `box.toRect().shift(...)` -> shifting large box by small offset.
          // Then drawing on scaled canvas -> shrinks everything.

          // Correct approach:
          // Center the painter in the coordinate system.
          // Painter size: W x H (Large)
          // We want to draw it centered.
          // Painter center is (W/2, H/2).
          // We translate by (-W/2, -H/2).

          final intrinsicOffset = Offset(-textPainter.width / 2, -textPainter.height / 2);
          final rect = box.toRect().shift(intrinsicOffset);
          canvas.drawRect(rect, Paint()..color = selectionColor);
        }
      }
    }

    // 2. Draw Text
    // Similarly, paint at intrinsic offset
    final intrinsicOffset = Offset(-textPainter.width / 2, -textPainter.height / 2);
    textPainter.paint(canvas, intrinsicOffset);

    // 3. Draw Cursor
    if (isEditing && showCursor && selection.isCollapsed) {
      final safeOffset = selection.baseOffset.clamp(0, text.length);
      final caretOffset = textPainter.getOffsetForCaret(
        TextPosition(offset: safeOffset),
        Rect.zero,
      );
      final cursorHeight = text.isEmpty
          ? (style.fontSize ?? 30)
          : textPainter.preferredLineHeight;

      final p1 = intrinsicOffset + caretOffset;
      final p2 = p1 + Offset(0, cursorHeight);

      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = Colors.blueAccent
          ..strokeWidth = 2, // This stroke width will also be scaled if we aren't careful.
                             // 2 / fitScale to maintain visual thickness?
                             // For now leaving as is.
      );
    }

    // Restore canvas (remove fitScale) for Border drawing so border isn't scaled weirdly?
    // Actually, if we scaled the text down, the border should also be around the small text.
    // But if we use the `canvas.scale`, the border lines (stroke width) will also scale down.
    // Usually UI handles shouldn't scale with the content "fit".

    canvas.restore();

    // 4. Draw UI Border & Handles (Outside the scale transform)
    if (isSelected) {
      // Now use the `_cachedSize` which we updated to be the visual size (scaled or wrapped).
      final rect = paintOffset & _cachedSize;

      final borderPaint = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;

      _drawDashedRect(canvas, rect, borderPaint);

      final handleFill = Paint()..color = Colors.white;
      final handleStroke = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / scale;
      final radius = handleRadius / scale;

      // Corner Handles
      final corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ];
      for (var point in corners) {
        canvas.drawCircle(point, radius, handleFill);
        canvas.drawCircle(point, radius, handleStroke);
      }

      // SIDE HANDLES (New)
      final sideHandles = [
        rect.centerLeft,
        rect.centerRight,
      ];
      // Only draw side handles if we are in a mode that supports it? Always for Text.
      for (var point in sideHandles) {
        // Maybe use a different visual for side handles? Vertical pill?
        // Prompt just says "Side Handles". Circle is fine.
        canvas.drawCircle(point, radius, handleFill);
        canvas.drawCircle(point, radius, handleStroke);
      }

      final topCenter = rect.topCenter;
      final rotPos = Offset(
        topCenter.dx,
        topCenter.dy - (rotationHandleDistance / scale),
      );
      canvas.drawLine(topCenter, rotPos, borderPaint);
      canvas.drawCircle(rotPos, radius, handleFill);
      canvas.drawCircle(rotPos, radius, handleStroke);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..addRect(rect);
    final dashWidth = 10.0 / scale;
    final dashSpace = 5.0 / scale;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }
}
