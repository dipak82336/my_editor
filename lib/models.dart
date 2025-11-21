import 'package:flutter/material.dart';
import 'dart:math' as math;

// Constants
const double handleRadius = 9.0;
const double rotationHandleDistance = 30.0;
const double kTextSafetyMargin = 8.0; // Safety Margin Requirement

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

  // Matrix logic can be overridden by subclasses if needed
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

  // NEW: Pro-Grade Properties
  double boxWidth; // The constraints width (independent of text)
  double? _computedScale; // The auto-calculated scale for fitting text

  TextSelection selection;
  bool showCursor;

  TextLayer({
    required super.id,
    required this.text,
    super.position,
    super.rotation,
    super.scale, // Global Zoom
    required this.boxWidth, // Must be initialized
    this.style = const TextStyle(fontSize: 30, color: Colors.black),
    this.selection = const TextSelection.collapsed(offset: 0),
    this.showCursor = false,
  });

  @override
  Size get size => _cachedSize;

  // Helper to get the scale actually applied to text (Layout Scale)
  double get effectiveScale => _computedScale ?? 1.0;

  void _computeLayout() {
    // Hybrid Layout System Logic
    // 1. Try to layout text with maxWidth = boxWidth - safetyMargin
    // 2. If it fits, good.
    // 3. If single word is wider than boxWidth, calculate shrink scale.

    final safeWidth = boxWidth - (kTextSafetyMargin * 2);

    // First pass: try wrapping
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout(maxWidth: safeWidth > 0 ? safeWidth : 0);

    // Check if we have a single long word overflow issue
    // Or simply, if the textPainter decided to draw wider than our constraint?
    // TextPainter respects maxWidth, so it will wrap.
    // BUT, if a single word is wider than maxWidth, it might still overflow or clip depending on implementation?
    // In Flutter, TextPainter will report `width` as the widest line.
    // If a single word is wider than maxWidth, `textPainter.width` might exceed maxWidth?
    // Actually, standard TextPainter wraps at characters if softWrap is true (default).
    // Requirement: "Scenario 2 (Single Word): 'SUPERMAN'. If the box narrows below the word's width -> AUTO-SCALE (SHRINK)"
    // "Scenario 1 (Sentence): 'Hello World'. If the box narrows -> WRAP"

    // To detect "Single Word" behavior vs "Sentence" behavior:
    // We can check if there are spaces? Or just generic logic:
    // "Auto-fit text if it exceeds bounds even after wrapping?"

    // Actually, if we enforce `maxWidth` in layout, Flutter wraps.
    // The user wants:
    // - If it CAN wrap (spaces), let it wrap.
    // - If it CANNOT wrap effectively (e.g. single word is wider than box), then Scale Down.

    // Let's detect the "natural" width of the longest word.
    // We can measure the text with infinite width first.

    final unlimitedPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    );
    unlimitedPainter.layout();

    // If the text has no spaces, or we want to be smarter:
    // We can check if `textPainter.width` (the wrapped width) caused any issues?
    // But `textPainter` with `maxWidth` will just force breaks.

    // Let's implement the logic:
    // If text contains spaces, we prefer wrapping.
    // If text does NOT contain spaces (or is a single word), we prefer scaling if it doesn't fit.

    // Simple heuristic:
    bool canWrap = text.trim().contains(' ');

    if (canWrap) {
        // Scenario 1: Sentence. Wrap.
        textPainter.layout(maxWidth: safeWidth > 0 ? safeWidth : 0);
        _computedScale = 1.0;

        // Update cached size based on the wrapped layout
        // Note: The box height will grow.
        _cachedSize = Size(boxWidth, textPainter.height + (kTextSafetyMargin * 2));

        // Wait, if the text is wrapped, the visual width might be less than boxWidth.
        // But the box handle width is `boxWidth`.
        // The "Size" of the layer for hit testing handles is (boxWidth, height).
    } else {
        // Scenario 2: Single Word.
        // Measure natural width
        unlimitedPainter.layout();
        double naturalWidth = unlimitedPainter.width;

        if (naturalWidth > safeWidth && safeWidth > 0) {
            // Scale down
            _computedScale = safeWidth / naturalWidth;
            // Recalculate painter with scaled text size?
            // Or just apply scale transform at paint time?
            // Applying transform is smoother.

            _cachedSize = Size(boxWidth, unlimitedPainter.height * _computedScale! + (kTextSafetyMargin * 2));
        } else {
            _computedScale = 1.0;
            _cachedSize = Size(boxWidth, unlimitedPainter.height + (kTextSafetyMargin * 2));
        }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Recompute layout every paint? Or cache it?
    // Ideally cache, but for now compute to ensure correctness.
    _computeLayout();

    // The `size` parameter passed to paint is often the one from `get size` (cached).
    // We should respect our calculated properties.

    final paintOffset = Offset(-boxWidth / 2, -_cachedSize.height / 2);

    // Visual Polish: Safety Margin
    // We apply the margin by offsetting where we draw the text.

    // 4. Draw UI Border & Handles (Draw first or last? Usually last, but let's follow existing order if we want)
    // Actually, usually handles are on top.

    // Draw Selection Highlights
    if (isEditing) {
       // We need a painter that matches the current layout logic (wrap vs scale)
       // This is getting tricky because we need the exact TextPainter used in _computeLayout
       // to draw selection boxes correctly.

       // Re-instantiate the correct painter
       final safeWidth = boxWidth - (kTextSafetyMargin * 2);
       final textPainter = TextPainter(
         text: TextSpan(text: text, style: style),
         textDirection: TextDirection.ltr,
       );

       bool canWrap = text.trim().contains(' ');

       canvas.save();
       canvas.translate(paintOffset.dx + kTextSafetyMargin, paintOffset.dy + kTextSafetyMargin);

       if (canWrap) {
           textPainter.layout(maxWidth: safeWidth > 0 ? safeWidth : 0);
           // Standard draw
       } else {
           textPainter.layout(); // Natural size
           // Apply scale
           canvas.scale(_computedScale ?? 1.0);
       }

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

      // Draw Text
      textPainter.paint(canvas, Offset.zero);

      // Draw Cursor
      if (showCursor && selection.isCollapsed) {
          final safeOffset = selection.baseOffset.clamp(0, text.length);
          final caretOffset = textPainter.getOffsetForCaret(
            TextPosition(offset: safeOffset),
            Rect.zero,
          );
          // Adjust cursor height for scale if needed?
          // If we scaled the canvas, the cursor draws scaled too, which is good.
           final cursorHeight = text.isEmpty
              ? (style.fontSize ?? 30)
              : textPainter.preferredLineHeight; // This height is unscaled

          final p1 = caretOffset;
          final p2 = p1 + Offset(0, cursorHeight);

          canvas.drawLine(
            p1,
            p2,
            Paint()
              ..color = Colors.blueAccent
              ..strokeWidth = 2 / (_computedScale ?? 1.0), // Keep stroke width constant-ish?
          );
      }

      canvas.restore();

    } else {
        // Not editing, just draw text
       final safeWidth = boxWidth - (kTextSafetyMargin * 2);
       final textPainter = TextPainter(
         text: TextSpan(text: text, style: style),
         textDirection: TextDirection.ltr,
       );

       bool canWrap = text.trim().contains(' ');

       canvas.save();
       canvas.translate(paintOffset.dx + kTextSafetyMargin, paintOffset.dy + kTextSafetyMargin);

       if (canWrap) {
           textPainter.layout(maxWidth: safeWidth > 0 ? safeWidth : 0);
       } else {
           textPainter.layout();
           canvas.scale(_computedScale ?? 1.0);
       }
       textPainter.paint(canvas, Offset.zero);
       canvas.restore();
    }


    // 4. Draw UI Border & Handles
    if (isSelected) {
      final rect = (paintOffset) & Size(boxWidth, _cachedSize.height);

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

      // Draw Side Handles (Middle Left, Middle Right) - Requirement for "Side Handles"
      // The prompt says "Resizing the Right Handle... Side Handles".
      // Standard text boxes usually have corners + side middles.
      // The existing code had corners.
      // "I should be able to drag the Side Handles" implies Middle handles.
      // Let's add Middle Left and Middle Right.

      final corners = [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
        rect.centerLeft, // Side Handle
        rect.centerRight, // Side Handle
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
