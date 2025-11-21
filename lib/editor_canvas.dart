import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'dart:math' as math;
import 'dart:async';
import 'models.dart';

// મોબાઈલ માટે ટચ એરિયા મોટો રાખવો પડે (45px જેવો)
const double TOUCH_TOLERANCE = 40.0;

enum HandleType {
  none,
  body,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  centerLeft, // New
  centerRight, // New
  rotate,
}

class EditorCanvas extends StatefulWidget {
  final EditorComposition composition;

  const EditorCanvas({super.key, required this.composition});

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  BaseLayer? activeLayer;
  HandleType _currentHandle = HandleType.none;

  // Interaction Variables
  Offset? _lastTouchLocalPoint;
  double? _initialRotationLayer;
  double? _initialRotationTouch;
  double? _initialScale;
  double? _initialDistance; // For Scaling

  // Anchored Resizing Variables
  double? _initialBoxWidth;
  Offset? _initialPosition;
  Offset? _initialTouchPoint; // Global-like local point for anchored resize

  SystemMouseCursor _cursor = SystemMouseCursors.basic;

  final FocusNode _textFocusNode = FocusNode();
  final TextEditingController _textController = TextEditingController();
  Timer? _cursorTimer;

  bool _isTextSelectionDragging = false;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_syncControllerToLayer);
  }

  @override
  void dispose() {
    _textController.removeListener(_syncControllerToLayer);
    _textFocusNode.dispose();
    _textController.dispose();
    _cursorTimer?.cancel();
    super.dispose();
  }

  void _syncControllerToLayer() {
    if (activeLayer is TextLayer) {
      final textLayer = activeLayer as TextLayer;
      if (textLayer.text != _textController.text) {
        setState(() {
          textLayer.text = _textController.text;
        });
      }
      if (!_isTextSelectionDragging &&
          textLayer.selection != _textController.selection) {
        setState(() {
          textLayer.selection = _textController.selection;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade900,
      alignment: Alignment.center,
      child: Stack(
        children: [
          FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: widget.composition.dimension.width,
              height: widget.composition.dimension.height,
              child: Container(
                color: widget.composition.backgroundColor,
                child: MouseRegion(
                  cursor: _cursor,
                  onHover: (event) {
                    final localPoint = _getLocalPoint(
                      context,
                      event.localPosition,
                    );
                    _updateCursor(localPoint);
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},

                    onTapDown: (details) {
                      final localPoint = _getLocalPoint(
                        context,
                        details.localPosition,
                      );
                      _handleTap(localPoint);
                    },

                    onDoubleTapDown: (details) {
                      final localPoint = _getLocalPoint(
                        context,
                        details.localPosition,
                      );
                      _handleDoubleTap(localPoint);
                    },

                    onScaleStart: (details) {
                      final localPoint = _getLocalPoint(
                        context,
                        details.localFocalPoint,
                      );
                      _handleTouchStart(localPoint);
                    },

                    onScaleUpdate: (details) {
                      if (activeLayer == null) return;
                      final localPoint = _getLocalPoint(
                        context,
                        details.localFocalPoint,
                      );
                      _handleTouchUpdate(localPoint);
                    },

                    onScaleEnd: (details) {
                      if (_isTextSelectionDragging) {
                        _isTextSelectionDragging = false;
                        _textFocusNode.requestFocus();
                      }
                    },

                    child: CustomPaint(
                      painter: _LayerPainter(widget.composition),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            top: -9999,
            child: SizedBox(
              width: 10,
              height: 10,
              child: TextField(
                focusNode: _textFocusNode,
                controller: _textController,
                maxLines: null,
                keyboardType: TextInputType.multiline, // PRO FIX: Native Input
                autocorrect: false,
                enableSuggestions: false, // PRO FIX: Native Input Experience (Disable secure flags if needed, but enableSuggestions false is usually good)
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 1. New & Improved Math Logic ---

  Offset _getLocalPoint(BuildContext context, Offset focalPoint) {
    final dx = focalPoint.dx - (widget.composition.dimension.width / 2);
    final dy = focalPoint.dy - (widget.composition.dimension.height / 2);
    return Offset(dx, dy);
  }

  HandleType _getHandleAtPoint(BaseLayer layer, Offset globalTouch) {
    // Use "boxWidth" for width if it's a TextLayer, else use size.width
    // Actually size.width in TextLayer (models.dart) returns the cached size which is correct.
    // TextLayer.size is (boxWidth, computedHeight).

    final halfW = (layer is TextLayer) ? (layer.boxWidth / 2) : (layer.size.width / 2);
    final halfH = layer.size.height / 2;

    final matrix = layer.matrix;

    // Handles logic updated for Side Handles
    final localMap = {
      HandleType.topLeft: Offset(-halfW, -halfH),
      HandleType.topRight: Offset(halfW, -halfH),
      HandleType.bottomLeft: Offset(-halfW, halfH),
      HandleType.bottomRight: Offset(halfW, halfH),
      HandleType.centerLeft: Offset(-halfW, 0),
      HandleType.centerRight: Offset(halfW, 0),
      HandleType.rotate: Offset(
        0,
        -halfH - (rotationHandleDistance / layer.scale),
      ),
    };

    for (var entry in localMap.entries) {
      final localPos = entry.value;
      final globalVec = matrix.transform3(Vector3(localPos.dx, localPos.dy, 0));
      final globalPos = Offset(globalVec.x, globalVec.y);

      if ((globalTouch - globalPos).distance <= TOUCH_TOLERANCE) {
        return entry.key;
      }
    }

    if (_isPointInsideLayer(layer, globalTouch)) {
      return HandleType.body;
    }

    return HandleType.none;
  }

  bool _isPointInsideLayer(BaseLayer layer, Offset globalTouch) {
    final matrix = layer.matrix;
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) return false;
    final point3 = inverse.transform3(
      Vector3(globalTouch.dx, globalTouch.dy, 0),
    );

    // Use boxWidth for TextLayer
    final halfW = (layer is TextLayer) ? (layer.boxWidth / 2) : (layer.size.width / 2);
    final halfH = layer.size.height / 2;

    final rect = Rect.fromLTRB(-halfW, -halfH, halfW, halfH);

    return rect
        .inflate(TOUCH_TOLERANCE / 2)
        .contains(Offset(point3.x, point3.y));
  }

  // --- 2. Touch Handlers ---

  void _handleTouchStart(Offset localPoint) {
    HandleType foundHandle = HandleType.none;

    if (activeLayer != null) {
      foundHandle = _getHandleAtPoint(activeLayer!, localPoint);
    }

    // SMART EDITING LOGIC
    if (activeLayer is TextLayer && activeLayer!.isEditing) {
      if (foundHandle != HandleType.none && foundHandle != HandleType.body) {
         // Allow handle interaction
      }
      else if (_isPointInsideLayer(activeLayer!, localPoint)) {
        // Handle Selection Drag Start
        _isTextSelectionDragging = true;
        final index = _getTextIndexFromTouch(
          activeLayer as TextLayer,
          localPoint,
        );

        // Pro Experience: "Dragging a selection handle should extend the selection"
        // But here we are starting a drag.
        // Standard behavior: If tap on cursor, drag extends.
        // But simplify: Just set new cursor/selection on start.
        final newSelection = TextSelection.collapsed(offset: index);
        _textController.selection = newSelection;
        (activeLayer as TextLayer).selection = newSelection;
        _currentHandle = HandleType.body;
        return;
      }
    }

    // Layer Switching
    if (foundHandle == HandleType.none) {
      final clickedLayer = _findLayerAt(localPoint);
      if (clickedLayer != null) {
        setState(() {
          if (clickedLayer != activeLayer) {
            _stopEditing();
            _deselectAll();
            clickedLayer.isSelected = true;
            activeLayer = clickedLayer;
          }
          if (!clickedLayer.isEditing) {
            foundHandle = HandleType.body;
          }
        });
      }
    }

    if (activeLayer != null) {
      _initialRotationLayer = activeLayer!.rotation;
      _initialRotationTouch = math.atan2(
        localPoint.dy - activeLayer!.position.dy,
        localPoint.dx - activeLayer!.position.dx,
      );
      _initialScale = activeLayer!.scale;
      _initialDistance = (localPoint - activeLayer!.position).distance;

      // Anchor Logic Inits
      _initialPosition = activeLayer!.position;
      if (activeLayer is TextLayer) {
        _initialBoxWidth = (activeLayer as TextLayer).boxWidth;
      }
      _initialTouchPoint = localPoint;
    }

    setState(() {
      _currentHandle = foundHandle;
      _lastTouchLocalPoint = localPoint;
    });
  }

  void _handleTouchUpdate(Offset localPoint) {
    if (activeLayer == null) return;

    // Text Selection Dragging
    if (_isTextSelectionDragging && activeLayer is TextLayer) {
      final index = _getTextIndexFromTouch(
        activeLayer as TextLayer,
        localPoint,
      );
      // Update selection extent while keeping the base (anchor) fixed
      final currentBase = (activeLayer as TextLayer).selection.baseOffset;
      final newSelection = TextSelection(
        baseOffset: currentBase,
        extentOffset: index,
      );

      _textController.selection = newSelection;
      setState(() {
        (activeLayer as TextLayer).selection = newSelection;
      });

      // Important: Update lastTouchLocalPoint to keep tracking (though not strictly needed for selection index)
      _lastTouchLocalPoint = localPoint;
      return;
    }

    if (_lastTouchLocalPoint == null) return;

    setState(() {
      switch (_currentHandle) {
        case HandleType.body:
          if (activeLayer is TextLayer && activeLayer!.isEditing && _isTextSelectionDragging) {
            // Do not move layer, selection update is handled at the top of this method
          } else {
            final delta = localPoint - _lastTouchLocalPoint!;
            activeLayer!.position += delta;
          }
          _lastTouchLocalPoint = localPoint;
          break;

        case HandleType.rotate:
          final currentTouchAngle = math.atan2(
            localPoint.dy - activeLayer!.position.dy,
            localPoint.dx - activeLayer!.position.dx,
          );
          final angleDelta = currentTouchAngle - _initialRotationTouch!;
          activeLayer!.rotation = _initialRotationLayer! + angleDelta;
          break;

        case HandleType.bottomRight:
        case HandleType.topRight:
        case HandleType.bottomLeft:
        case HandleType.topLeft:
          // Uniform Scale (Corner Handles) -> Global Zoom
          // "double scale -> Global Zoom (Corner handles)"
          final currentDist = (localPoint - activeLayer!.position).distance;
          if (_initialDistance != null && _initialDistance! > 0) {
            final scaleFactor = currentDist / _initialDistance!;
            activeLayer!.scale = _initialScale! * scaleFactor;
          }
          break;

        case HandleType.centerLeft:
        case HandleType.centerRight:
          // Side Handles -> Anchored Resizing
          // Only applicable for TextLayer (unbounded width logic)
          if (activeLayer is TextLayer) {
             _handleAnchoredResize(localPoint);
          }
          break;

        default:
          break;
      }
    });
  }

  // --- 3. ANCHORED RESIZING MATH ---

  void _handleAnchoredResize(Offset currentTouch) {
     // We need to rotate the touch point into the layer's local space to calculate width changes correctly,
     // OR we can project the drag delta onto the layer's local X axis.

     final layer = activeLayer as TextLayer;

     // 1. Calculate Delta in global space
     final delta = currentTouch - _lastTouchLocalPoint!;

     // 2. Project Delta onto Local X Axis
     // The layer's rotation angle determines the X axis direction.
     final angle = layer.rotation;
     final cosA = math.cos(angle);
     final sinA = math.sin(angle);

     // Local delta X = delta.dx * cos + delta.dy * sin
     // Wait, standard rotation matrix:
     // x' = x cos - y sin
     // y' = x sin + y cos
     // We want to project the GLOBAL movement onto the LOCAL X axis.
     // So we dot product with the X-axis unit vector (cos, sin).

     double deltaLocalX = delta.dx * cosA + delta.dy * sinA;

     // Adjust for Global Scale?
     // Layer properties (width) are in local unscaled units?
     // Wait, `boxWidth` is pre-scale. `scale` applies to everything.
     // So if global scale is 2.0, dragging 100px on screen means 50px increase in boxWidth.

     deltaLocalX /= layer.scale;

     if (_currentHandle == HandleType.centerRight) {
        // Dragging Right Handle
        // Width increases by deltaLocalX
        // Anchor is Left Edge.
        // Requirement: "Right Handle Drag: The LEFT EDGE of the box must act as a concrete ANCHOR."
        // "Logic: delta applied to width + corresponding delta/2 applied to center position"

        double newWidth = layer.boxWidth + deltaLocalX;

        // Constraint: Min Width
        if (newWidth < 50.0) {
           deltaLocalX = 50.0 - layer.boxWidth;
           newWidth = 50.0;
        }

        layer.boxWidth = newWidth;

        // Move Center: The center moves by deltaLocalX / 2 in the direction of the local X axis.
        // We need to convert (deltaLocalX/2, 0) back to global.
        // Global shift = (dx/2 * cos, dx/2 * sin) * scale

        final shiftMagnitude = (deltaLocalX / 2) * layer.scale;
        final shift = Offset(shiftMagnitude * cosA, shiftMagnitude * sinA);

        layer.position += shift;

     } else if (_currentHandle == HandleType.centerLeft) {
        // Dragging Left Handle
        // If dragging LEFTwards (negative delta), width INCREASES.
        // So width change = -deltaLocalX

        double widthChange = -deltaLocalX;
        double newWidth = layer.boxWidth + widthChange;

        if (newWidth < 50.0) {
           widthChange = 50.0 - layer.boxWidth;
           newWidth = 50.0;
        }

        layer.boxWidth = newWidth;

        // Move Center:
        // If left edge moves left (width increases), center moves left.
        // Shift is negative X direction.
        // Shift magnitude = (widthChange / 2) * scale * (-1 direction??)
        // Wait. Center moves by (-widthChange / 2) ?

        // Let's verify:
        // Old Width W. Center C. Left Edge L = C - W/2.
        // New Width W'. Center C'. Left Edge L' = C' - W'/2.
        // We want Right Edge R to be fixed.
        // R = C + W/2.
        // R' = C' + W'/2.
        // R = R' => C + W/2 = C' + W'/2
        // => C' = C + (W - W')/2
        // W' = W + dW.
        // C' = C + (W - (W+dW))/2 = C - dW/2.

        // So center shifts by -dW/2 (in local X).
        // dW is `widthChange`.

        final shiftMagnitude = (-widthChange / 2) * layer.scale;
        final shift = Offset(shiftMagnitude * cosA, shiftMagnitude * sinA);

        layer.position += shift;
     }

     _lastTouchLocalPoint = currentTouch;
  }

  // --- 4. Other Helpers ---

  int _getTextIndexFromTouch(TextLayer layer, Offset globalTouch) {
    final matrix = layer.matrix;
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) return 0;
    final point3 = inverse.transform3(
      Vector3(globalTouch.dx, globalTouch.dy, 0),
    );
    final localCenterPoint = Offset(point3.x, point3.y);

    final textPainter = TextPainter(
      text: TextSpan(text: layer.text, style: layer.style),
      textDirection: TextDirection.ltr,
    );

    // Important: Use the same layout logic as painting to get correct index!
    final safeWidth = layer.boxWidth - (kTextSafetyMargin * 2);
    bool canWrap = layer.text.trim().contains(' ');

    if (canWrap) {
       textPainter.layout(maxWidth: safeWidth > 0 ? safeWidth : 0);
       // Logic for hit testing needs to account for paintOffset (-boxWidth/2, -height/2) + SafetyMargin
       // The localCenterPoint is relative to center (0,0).
       // The painter paints at (-boxWidth/2 + safety, -height/2 + safety).

       final paintOffset = Offset(-layer.boxWidth / 2 + kTextSafetyMargin, -layer.size.height / 2 + kTextSafetyMargin);
       final targetPoint = localCenterPoint - paintOffset;

       return textPainter.getPositionForOffset(targetPoint).offset;

    } else {
       textPainter.layout();
       // Scaled hit testing!
       // The painter was drawn scaled by effectiveScale.
       // So we need to unscale the touch point? Or scale the painter?
       // Easier to unscale touch point.
       final scale = layer.effectiveScale;

       // Paint offset was (-boxWidth/2 + safety, ...)
       // But wait, in scale mode, we did:
       // translate(paintOffset + safety); scale(s); paint(0,0);
       // So coordinate transformation:
       // P_local = (P_touch - (paintOffset + safety)) / scale

       final paintOffset = Offset(-layer.boxWidth / 2 + kTextSafetyMargin, -layer.size.height / 2 + kTextSafetyMargin);
       final targetPoint = (localCenterPoint - paintOffset) / scale;

       return textPainter.getPositionForOffset(targetPoint).offset;
    }
  }

  TextSelection _getWordSelection(TextLayer layer, int index) {
    final textPainter = TextPainter(
      text: TextSpan(text: layer.text, style: layer.style),
      textDirection: TextDirection.ltr,
    );
    // Layout doesn't affect word boundary logic much, but good to be consistent
    textPainter.layout();
    final range = textPainter.getWordBoundary(TextPosition(offset: index));
    return TextSelection(baseOffset: range.start, extentOffset: range.end);
  }

  void _handleTap(Offset localPoint) {
    if (activeLayer != null) {
      final handle = _getHandleAtPoint(activeLayer!, localPoint);
      if (handle != HandleType.none && handle != HandleType.body) return;
    }

    if (activeLayer is TextLayer && activeLayer!.isEditing) {
      final textLayer = activeLayer as TextLayer;
      if (_isPointInsideLayer(textLayer, localPoint)) {
        final index = _getTextIndexFromTouch(textLayer, localPoint);
        final newSelection = TextSelection.collapsed(offset: index);
        _textController.selection = newSelection;
        textLayer.selection = newSelection;
        _textFocusNode.requestFocus();
        _startCursorBlink(textLayer);
        return;
      }
    }

    final clickedLayer = _findLayerAt(localPoint);
    setState(() {
      if (clickedLayer == null) {
        _stopEditing();
        _deselectAll();
        activeLayer = null;
      } else if (clickedLayer != activeLayer) {
        _stopEditing();
        _deselectAll();
        clickedLayer.isSelected = true;
        activeLayer = clickedLayer;
      }
    });
  }

  void _handleDoubleTap(Offset localPoint) {
    if (activeLayer is TextLayer && activeLayer!.isEditing) {
      final textLayer = activeLayer as TextLayer;
      if (_isPointInsideLayer(textLayer, localPoint)) {
        final index = _getTextIndexFromTouch(textLayer, localPoint);
        final wordSelection = _getWordSelection(textLayer, index);
        setState(() {
          _textController.selection = wordSelection;
          textLayer.selection = wordSelection;
        });
        _textFocusNode.requestFocus();
        return;
      }
    }
    final clickedLayer = _findLayerAt(localPoint);
    if (clickedLayer != null && clickedLayer is TextLayer) {
      setState(() {
        _deselectAll();
        clickedLayer.isSelected = true;
        activeLayer = clickedLayer;
        clickedLayer.isEditing = true;
        _textController.text = clickedLayer.text;
        final index = _getTextIndexFromTouch(clickedLayer, localPoint);
        _textController.selection = TextSelection.collapsed(offset: index);
        clickedLayer.selection = _textController.selection;
        _textFocusNode.requestFocus();
        _startCursorBlink(clickedLayer);
      });
    }
  }

  BaseLayer? _findLayerAt(Offset globalTouch) {
    for (var layer in widget.composition.layers.reversed) {
      if (_getHandleAtPoint(layer, globalTouch) != HandleType.none)
        return layer;
    }
    return null;
  }

  void _deselectAll() {
    for (var l in widget.composition.layers) {
      l.isSelected = false;
      if (l is TextLayer) {
        l.isEditing = false;
        l.showCursor = false;
      }
    }
  }

  void _startCursorBlink(TextLayer layer) {
    _cursorTimer?.cancel();
    layer.showCursor = true;
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => layer.showCursor = !layer.showCursor);
    });
  }

  void _stopEditing() {
    _cursorTimer?.cancel();
    if (activeLayer is TextLayer) {
      (activeLayer as TextLayer).isEditing = false;
      (activeLayer as TextLayer).showCursor = false;
      (activeLayer as TextLayer).selection = const TextSelection.collapsed(
        offset: -1,
      );
    }
    _textFocusNode.unfocus();
  }

  void _updateCursor(Offset localPoint) {
    if (activeLayer == null) {
      setState(() => _cursor = SystemMouseCursors.basic);
      return;
    }
    if (activeLayer is TextLayer && activeLayer!.isEditing) {
      if (_isPointInsideLayer(activeLayer!, localPoint)) {
        setState(() => _cursor = SystemMouseCursors.text);
        return;
      }
    }
    final handle = _getHandleAtPoint(activeLayer!, localPoint);
    SystemMouseCursor newCursor = SystemMouseCursors.basic;
    switch (handle) {
      case HandleType.body:
        newCursor = activeLayer!.isEditing
            ? SystemMouseCursors.text
            : SystemMouseCursors.move;
        break;
      case HandleType.topLeft:
      case HandleType.bottomRight:
        newCursor = SystemMouseCursors.resizeUpLeftDownRight;
        break;
      case HandleType.topRight:
      case HandleType.bottomLeft:
        newCursor = SystemMouseCursors.resizeUpRightDownLeft;
        break;
      case HandleType.centerLeft:
      case HandleType.centerRight:
        newCursor = SystemMouseCursors.resizeLeftRight;
        break;
      case HandleType.rotate:
        newCursor = SystemMouseCursors.click;
        break;
      default:
        newCursor = SystemMouseCursors.basic;
    }
    if (_cursor != newCursor) setState(() => _cursor = newCursor);
  }
}

class _LayerPainter extends CustomPainter {
  final EditorComposition composition;
  _LayerPainter(this.composition);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.translate(size.width / 2, size.height / 2);
    for (var layer in composition.layers) {
      canvas.save();
      canvas.transform(layer.matrix.storage);
      layer.paint(canvas, size);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
