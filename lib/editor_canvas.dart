import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'dart:math' as math;
import 'dart:async';
import 'models.dart';

// Constants
const double kTouchTolerance = 40.0;

enum HandleType {
  none,
  body,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  centerLeft,
  centerRight,
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
  double? _initialDistance;

  // Selection Anchoring
  TextSelection? _initialSelection;

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
      // Only sync selection if we are NOT actively dragging (to avoid fighting)
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
                      _initialSelection = null;
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
                maxLines: null, // Pro-Grade Keyboard
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                enableIMEPersonalizedLearning: true,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 1. Math Helpers ---

  Offset _getLocalPoint(BuildContext context, Offset focalPoint) {
    final dx = focalPoint.dx - (widget.composition.dimension.width / 2);
    final dy = focalPoint.dy - (widget.composition.dimension.height / 2);
    return Offset(dx, dy);
  }

  HandleType _getHandleAtPoint(BaseLayer layer, Offset globalTouch) {
    final halfW = layer.size.width / 2;
    final halfH = layer.size.height / 2;
    final matrix = layer.matrix;

    final localMap = {
      HandleType.topLeft: Offset(-halfW, -halfH),
      HandleType.topRight: Offset(halfW, -halfH),
      HandleType.bottomLeft: Offset(-halfW, halfH),
      HandleType.bottomRight: Offset(halfW, halfH),
      HandleType.centerLeft: Offset(-halfW, 0),
      HandleType.centerRight: Offset(halfW, 0),
      HandleType.rotate: Offset(
        0,
        -halfH - (kRotationHandleDistance / layer.scale),
      ),
    };

    for (var entry in localMap.entries) {
      final localPos = entry.value;
      final globalVec = matrix.transform3(Vector3(localPos.dx, localPos.dy, 0));
      final globalPos = Offset(globalVec.x, globalVec.y);

      if ((globalTouch - globalPos).distance <= kTouchTolerance) {
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
    final halfW = layer.size.width / 2;
    final halfH = layer.size.height / 2;
    final rect = Rect.fromLTRB(-halfW, -halfH, halfW, halfH);

    return rect
        .inflate(kTouchTolerance / 2)
        .contains(Offset(point3.x, point3.y));
  }

  // --- 2. Interaction Logic ---

  void _handleTouchStart(Offset localPoint) {
    HandleType foundHandle = HandleType.none;

    if (activeLayer != null) {
      foundHandle = _getHandleAtPoint(activeLayer!, localPoint);
    }

    // Smart Editing Logic (Text Selection vs Drag)
    if (activeLayer is TextLayer && activeLayer!.isEditing) {
      if (foundHandle == HandleType.none || foundHandle == HandleType.body) {
         if (_isPointInsideLayer(activeLayer!, localPoint)) {
            _isTextSelectionDragging = true;
            final index = _getTextIndexFromTouch(activeLayer as TextLayer, localPoint);

            // Anchor Selection
            final newSelection = TextSelection.collapsed(offset: index);
            _textController.selection = newSelection;
            (activeLayer as TextLayer).selection = newSelection;
            _initialSelection = newSelection;

            _currentHandle = HandleType.body;
            return;
         }
      }
    }

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
    }

    setState(() {
      _currentHandle = foundHandle;
      _lastTouchLocalPoint = localPoint;
    });
  }

  void _handleTouchUpdate(Offset localPoint) {
    if (activeLayer == null) return;

    // Text Selection
    if (_isTextSelectionDragging && activeLayer is TextLayer) {
      final index = _getTextIndexFromTouch(activeLayer as TextLayer, localPoint);
      if (_initialSelection != null) {
        // Expand from anchor
        final newSelection = TextSelection(
          baseOffset: _initialSelection!.baseOffset,
          extentOffset: index,
        );
        _textController.selection = newSelection;
        setState(() {
          (activeLayer as TextLayer).selection = newSelection;
        });
      }
      return;
    }

    if (_lastTouchLocalPoint == null) return;

    setState(() {
      switch (_currentHandle) {
        case HandleType.body:
          if (!activeLayer!.isEditing) {
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

        // CORNER HANDLES = UNIFORM SCALE (ZOOM)
        case HandleType.bottomRight:
        case HandleType.topRight:
        case HandleType.bottomLeft:
        case HandleType.topLeft:
          final currentDist = (localPoint - activeLayer!.position).distance;
          if (_initialDistance != null && _initialDistance! > 0) {
            final scaleFactor = currentDist / _initialDistance!;
            activeLayer!.scale = _initialScale! * scaleFactor;
          }
          break;

        // SIDE HANDLES = ANCHORED RESIZING
        case HandleType.centerLeft:
        case HandleType.centerRight:
          if (activeLayer is TextLayer) {
             final layer = activeLayer as TextLayer;

             // 1. Calculate Global Delta
             final globalDelta = localPoint - _lastTouchLocalPoint!;

             // 2. Project onto Layer's Local X-Axis
             final angle = layer.rotation;
             final cos = math.cos(angle);
             final sin = math.sin(angle);

             // Local Delta X (Along the width of the box)
             final localDeltaX = globalDelta.dx * cos + globalDelta.dy * sin;

             // 3. Determine Width Change & Center Shift
             // Right Handle: +Width, +Center (Rightward)
             // Left Handle:  +Width (if moving Left, i.e., neg Delta), +Center (Leftward)

             double widthChange = 0.0;
             double centerShiftLocalX = 0.0;

             if (_currentHandle == HandleType.centerRight) {
               // Dragging Right Handle
               widthChange = localDeltaX;
               // To keep Left edge fixed, center moves by half the growth
               centerShiftLocalX = localDeltaX / 2.0;
             } else {
               // Dragging Left Handle
               // If we move Left (neg delta), width increases.
               widthChange = -localDeltaX;
               // To keep Right edge fixed, center moves Left by half the growth
               // Since localDeltaX is negative when moving left,
               // we want center to move left.
               centerShiftLocalX = localDeltaX / 2.0;
             }

             // 4. Apply Changes
             double currentWidth = layer.customWidth ?? layer.size.width;
             // If transitioning from auto-size to fixed-size, initialize customWidth
             if (layer.customWidth == null) layer.customWidth = currentWidth;

             double newWidth = currentWidth + widthChange;

             if (newWidth >= 20.0) {
               layer.customWidth = newWidth;

               // Rotate center shift back to global
               final shiftDx = centerShiftLocalX * cos;
               final shiftDy = centerShiftLocalX * sin;

               layer.position += Offset(shiftDx, shiftDy);
             }
          }
          _lastTouchLocalPoint = localPoint;
          break;

        default:
          break;
      }
    });
  }

  // --- 3. Helpers ---

  int _getTextIndexFromTouch(TextLayer layer, Offset globalTouch) {
    // We need to map global touch to the text painter's coordinate system.
    // Layer Matrix transforms: Local(0,0)=Center -> Global.
    // Paint Logic transforms: TextPainter(0,0)=TopLeft -> Local(Centered).

    // 1. Global -> Local (Layer Center)
    final matrix = layer.matrix;
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) return 0;

    final point3 = inverse.transform3(
      Vector3(globalTouch.dx, globalTouch.dy, 0),
    );
    final localPoint = Offset(point3.x, point3.y);

    // 2. Local -> Visual Text Coordinates
    // The paint logic in `models.dart` applies "centering" and "fitScale".
    // We need to reverse that.

    final info = layer.computePaintInfo();
    final fitScale = info.fitScale == 0 ? 1.0 : info.fitScale;

    // Calculate visual dimensions
    final visualW = info.painter.width * fitScale;
    final visualH = info.painter.height * fitScale;

    // Calculate Centering Offset (inside Box)
    // Box Size is info.size
    final alignDx = (info.size.width - visualW) / 2;
    final alignDy = (info.size.height - visualH) / 2;

    // Calculate Paint Offset (TopLeft relative to Center)
    final paintOffset = Offset(-info.size.width / 2, -info.size.height / 2);

    // Origin of Text Draw in Local Space
    final textOrigin = paintOffset + Offset(alignDx, alignDy);

    // Point relative to Text Origin
    final pointRelativeText = localPoint - textOrigin;

    // Un-scale
    final pointInPainter = pointRelativeText / fitScale;

    return info.painter
        .getPositionForOffset(pointInPainter)
        .offset
        .clamp(0, layer.text.length);
  }

  TextSelection _getWordSelection(TextLayer layer, int index) {
    final info = layer.computePaintInfo();
    final range = info.painter.getWordBoundary(TextPosition(offset: index));
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
