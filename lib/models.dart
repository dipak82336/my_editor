import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;

// Constants
const double kHandleRadius = 9.0;
const double kRotationHandleDistance = 30.0;
const double kTextSafetyMargin = 16.0; // Pro-Grade Safety Margin

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

class TextPaintInfo {
  final Size size;
  final double fitScale;
  final TextPainter painter;

  TextPaintInfo({
    required this.size,
    required this.fitScale,
    required this.painter,
  });
}

class TextLayer extends BaseLayer {
  String text;
  TextStyle style;

  // Logical Constraints
  double? customWidth;
  bool enableAutoFit;

  // State for Selection/Interaction
  TextSelection selection;
  bool showCursor;

  // Caching
  TextPaintInfo? _cachedInfo;

  // Debug
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
  Size get size => _cachedInfo?.size ?? Size.zero;

  // --- PRO-GRADE LOGIC ENGINE ---
  TextPaintInfo computePaintInfo() {
    // 1. Measure Intrinsic Size
    final intrinsicPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    intrinsicPainter.layout();
    final maxIntrinsicWidth = intrinsicPainter.width;

    // 2. Determine Effective & Fit Scale
    double fitScale = 1.0;
    double? layoutMaxWidth;

    if (customWidth != null) {
      // Unbounded Box Logic:
      // If customWidth is LARGER than intrinsic, use customWidth for box, but 1.0 scale.
      // If customWidth is SMALLER, we must adapt.

      final hasSpaces = text.contains(' ');

      if (customWidth! > maxIntrinsicWidth) {
        // Unbounded Mode: Box is wider than text.
        // No wrapping needed, no scaling needed.
        // Text will be drawn centered (or aligned) in the wide box.
        // We set layoutMaxWidth to null (unlimited) or customWidth?
        // If we want alignment, we might want to layout with minWidth=customWidth.
        // But for now, we just want the BOX to report size = customWidth.
      } else {
        // Constrained Mode: Box is narrower than text.
        if (hasSpaces) {
          // Wrap Text
          // Apply Safety Margin for wrapping too, as per spec ("Text must never touch the exact border")
          // Ensure we don't pass negative width to layout
          layoutMaxWidth = math.max(1.0, customWidth! - kTextSafetyMargin);
        } else if (enableAutoFit) {
          // Auto-Fit Single Word
          // Apply Safety Margin
          final effectiveWidth = customWidth! - kTextSafetyMargin;
          final safeWidth = effectiveWidth > 1.0 ? effectiveWidth : 1.0;

          if (safeWidth < maxIntrinsicWidth) {
            fitScale = safeWidth / maxIntrinsicWidth;
          }
        }
      }
    }

    debugFitScale = fitScale;

    // 3. Final Layout
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );

    if (layoutMaxWidth != null) {
      textPainter.layout(maxWidth: layoutMaxWidth);
    } else {
      textPainter.layout();
    }

    // 4. Calculate Visual Box Size
    // If fitScale < 1.0, the "Visual" size is smaller.
    // If Unbounded (customWidth > intrinsic), the "Visual" box is customWidth.

    double boxWidth = textPainter.width * fitScale;
    double boxHeight = textPainter.height * fitScale;

    if (customWidth != null && customWidth! > boxWidth) {
      boxWidth = customWidth!;
    }

    return TextPaintInfo(
      size: Size(boxWidth, boxHeight),
      fitScale: fitScale,
      painter: textPainter,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _cachedInfo = computePaintInfo();
    final info = _cachedInfo!;

    // We draw centered at (0,0) of the layer's coordinate system (which is at position)
    // The layer system has already applied Rotation & Zoom Scale (super.matrix).
    // Now we apply "Fit Scale".

    final paintOffset = Offset(-info.size.width / 2, -info.size.height / 2);

    canvas.save();

    // Check if we need to align text within the Unbounded Box
    // If fitScale == 1.0 and customWidth > textWidth, text is smaller than box.
    // Default alignment: Center.
    // Calculate offset to center the text in the box.

    // Visual Text Size
    final visualTextWidth = info.painter.width * info.fitScale;
    final visualTextHeight = info.painter.height * info.fitScale;

    // Center in Box
    final dx = (info.size.width - visualTextWidth) / 2;
    final dy = (info.size.height - visualTextHeight) / 2;

    // Total translation = Box Origin + Centering Offset
    final textDrawOrigin = paintOffset + Offset(dx, dy);

    // Translate to text origin
    canvas.translate(textDrawOrigin.dx, textDrawOrigin.dy);
    // Apply Fit Scale
    if (info.fitScale != 1.0) {
      canvas.scale(info.fitScale, info.fitScale);
    }

    // Draw Selection Backgrounds (in text local coordinates)
    if (isEditing) {
      final selectionColor = Colors.blue.withValues(alpha: 0.3);
      final safeSelection = TextSelection(
        baseOffset: selection.baseOffset.clamp(0, text.length),
        extentOffset: selection.extentOffset.clamp(0, text.length),
      );

      if (!safeSelection.isCollapsed) {
        final boxes = info.painter.getBoxesForSelection(safeSelection);
        for (var box in boxes) {
          canvas.drawRect(box.toRect(), Paint()..color = selectionColor);
        }
      }
    }

    // Draw Text
    info.painter.paint(canvas, Offset.zero);

    // Draw Cursor
    if (isEditing && showCursor && selection.isCollapsed) {
      final safeOffset = selection.baseOffset.clamp(0, text.length);
      final caretOffset = info.painter.getOffsetForCaret(
        TextPosition(offset: safeOffset),
        Rect.zero,
      );
      final cursorHeight = text.isEmpty
          ? (style.fontSize ?? 30)
          : info.painter.preferredLineHeight;

      canvas.drawLine(
        caretOffset,
        caretOffset + Offset(0, cursorHeight),
        Paint()
          ..color = Colors.blueAccent
          ..strokeWidth = 2 / (info.fitScale == 0 ? 1 : info.fitScale), // Counter-scale stroke?
      );
    }

    canvas.restore();

    // 5. Draw Handles & Border (On the Box Boundary)
    if (isSelected) {
      final rect = paintOffset & info.size;

      final borderPaint = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale; // User zoom scale

      _drawDashedRect(canvas, rect, borderPaint);

      final handleFill = Paint()..color = Colors.white;
      final handleStroke = Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / scale;
      final radius = kHandleRadius / scale;

      // Corners
      for (var point in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
        canvas.drawCircle(point, radius, handleFill);
        canvas.drawCircle(point, radius, handleStroke);
      }

      // Sides
      for (var point in [rect.centerLeft, rect.centerRight]) {
        canvas.drawCircle(point, radius, handleFill);
        canvas.drawCircle(point, radius, handleStroke);
      }

      // Rotation
      final topCenter = rect.topCenter;
      final rotPos = Offset(
        topCenter.dx,
        topCenter.dy - (kRotationHandleDistance / scale),
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
