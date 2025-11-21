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
  double? customWidth; // Added for Smart Fit

  TextSelection selection;
  bool showCursor;

  TextLayer({
    required super.id,
    required this.text,
    super.position,
    super.rotation,
    super.scale,
    this.customWidth,
    this.style = const TextStyle(fontSize: 30, color: Colors.black),
    this.selection = const TextSelection.collapsed(offset: 0),
    this.showCursor = false,
  });

  @override
  Size get size => _cachedSize;

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // --- Smart Fit Logic ---
    final intrinsicWidth = textPainter.width;
    final intrinsicHeight = textPainter.height;
    final boxWidth = customWidth ?? intrinsicWidth;

    // Determine scale factor to fit text inside boxWidth (if text is larger)
    double contentScale = 1.0;
    if (intrinsicWidth > boxWidth) {
      contentScale = boxWidth / intrinsicWidth;
    }

    // Recalculate size based on boxWidth (or intrinsic if larger/null)
    // NOTE: We use boxWidth for the boundary. Height scales with contentScale.
    final scaledHeight = intrinsicHeight * contentScale;
    _cachedSize = Size(boxWidth, scaledHeight);

    // Center the drawing operations
    final paintOffset = Offset(-boxWidth / 2, -scaledHeight / 2);

    // 1. Draw Selection Highlights
    canvas.save();
    // We must apply the contentScale to the TEXT and HIGHLIGHTS, but NOT the UI Handles.
    // However, we usually paint everything relative to center.
    // Let's translate to top-left of the box
    canvas.translate(paintOffset.dx, paintOffset.dy);
    canvas.scale(contentScale, contentScale);

    // Now we are at (0,0) of the scaled text content.

    if (isEditing) {
      final selectionColor = Colors.blue.withValues(alpha: 0.3);
      final safeSelection = TextSelection(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
      );

      if (!safeSelection.isCollapsed) {
        final boxes = textPainter.getBoxesForSelection(safeSelection);
        for (var box in boxes) {
          final rect = box.toRect();
          canvas.drawRect(rect, Paint()..color = selectionColor);
        }
      }
    }

    // 2. Draw Text
    textPainter.paint(canvas, Offset.zero);

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

      final p1 = caretOffset;
      final p2 = p1 + Offset(0, cursorHeight);

      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = Colors.blueAccent
          ..strokeWidth = 2 / contentScale, // Adjust stroke width to be consistent
      );
    }

    canvas.restore(); // Restore scaling

    // 4. Draw UI Border & Handles (No Content Scale)
    if (isSelected) {
      // Use _cachedSize which is already set to (boxWidth, scaledHeight)
      // Centered at (0,0)
      final rect = Rect.fromCenter(
          center: Offset.zero, width: _cachedSize.width, height: _cachedSize.height);

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
