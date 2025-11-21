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
                autocorrect: false,
                enableSuggestions: false,
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

  /// **Global Space Hit Testing (The Fix for "Shrinking Hit Box")**
  /// આપણે હેન્ડલ્સને સ્ક્રીન પર ક્યાં છે તે શોધીએ છીએ અને પછી ચેક કરીએ છીએ.
  HandleType _getHandleAtPoint(BaseLayer layer, Offset globalTouch) {
    // લેયરની સાઈઝ
    final halfW = layer.size.width / 2;
    final halfH = layer.size.height / 2;

    // લેયરનું મેટ્રિક્સ
    final matrix = layer.matrix;

    // હેન્ડલ્સના Local Coordinates
    // (rotationHandleDistance અને handleRadius models.dart માંથી આવે છે)
    // આપણે models.dart માં CamelCase કર્યું હતું, તે અહીં વાપરવું.
    final localMap = {
      HandleType.topLeft: Offset(-halfW, -halfH),
      HandleType.topRight: Offset(halfW, -halfH),
      HandleType.bottomLeft: Offset(-halfW, halfH),
      HandleType.bottomRight: Offset(halfW, halfH),
      HandleType.rotate: Offset(
        0,
        -halfH - (rotationHandleDistance / layer.scale),
      ),
    };

    // હેન્ડલ્સ ચેક કરો (Global Space માં)
    for (var entry in localMap.entries) {
      final localPos = entry.value;
      // Local Point ને Global Matrix થી ટ્રાન્સફોર્મ કરો
      final globalVec = matrix.transform3(Vector3(localPos.dx, localPos.dy, 0));
      final globalPos = Offset(globalVec.x, globalVec.y);

      // હવે Distance ચેક કરો. આ TOUCH_TOLERANCE ફિક્સ છે (30px).
      // લેયર નાનું હોય તો પણ આ 30px જ રહેશે.
      if ((globalTouch - globalPos).distance <= TOUCH_TOLERANCE) {
        return entry.key;
      }
    }

    // Body Check (આના માટે Inverse Matrix બરાબર છે)
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
    // Body Hit Test માટે થોડું પેડિંગ આપો જેથી પકડવામાં સરળતા રહે
    // Increased to TOUCH_TOLERANCE for better touch handling
    return rect
        .inflate(TOUCH_TOLERANCE / 2)
        .contains(Offset(point3.x, point3.y));
  }

  // --- 2. Touch Handlers ---

  void _handleTouchStart(Offset localPoint) {
    HandleType foundHandle = HandleType.none;

    // પહેલા Active Layer પર હેન્ડલ્સ ચેક કરો
    if (activeLayer != null) {
      foundHandle = _getHandleAtPoint(activeLayer!, localPoint);
    }

    // SMART EDITING LOGIC
    if (activeLayer is TextLayer && activeLayer!.isEditing) {
      // જો ખૂણો કે રોટેશન પકડ્યું છે -> Allow
      if (foundHandle != HandleType.none && foundHandle != HandleType.body) {
        // Pass through to math init below
      }
      // જો બોડી પકડી છે -> Text Selection Drag (Move નહિ)
      else if (_isPointInsideLayer(activeLayer!, localPoint)) {
        _isTextSelectionDragging = true;
        final index = _getTextIndexFromTouch(
          activeLayer as TextLayer,
          localPoint,
        );
        final newSelection = TextSelection.collapsed(offset: index);
        _textController.selection = newSelection;
        (activeLayer as TextLayer).selection = newSelection;
        _currentHandle = HandleType.body;
        return;
      }
    }

    // Layer Switching / Selection
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

    // --- FIX: Rotation & Scaling Math ---
    if (activeLayer != null) {
      _initialRotationLayer = activeLayer!.rotation;

      // રોટેશન ગણતરી લેયરના સેન્ટર (Position) થી થવી જોઈએ
      _initialRotationTouch = math.atan2(
        localPoint.dy - activeLayer!.position.dy,
        localPoint.dx - activeLayer!.position.dx,
      );

      _initialScale = activeLayer!.scale;

      // સ્કેલિંગ ગણતરી પણ લેયરના સેન્ટરથી થવી જોઈએ (Distance from Object Center)
      // જૂના કોડમાં Screen Center થી થતી હતી જે ભૂલ હતી
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
      final index = _getTextIndexFromTouch(
        activeLayer as TextLayer,
        localPoint,
      );
      final currentBase = _textController.selection.baseOffset;
      final newSelection = TextSelection(
        baseOffset: currentBase,
        extentOffset: index,
      );
      _textController.selection = newSelection;
      setState(() {
        (activeLayer as TextLayer).selection = newSelection;
      });
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
          // Move માટે આપણે last point અપડેટ કરીએ છીએ
          _lastTouchLocalPoint = localPoint;
          break;

        case HandleType.rotate:
          // Rotation relative to Object Center
          final currentTouchAngle = math.atan2(
            localPoint.dy - activeLayer!.position.dy,
            localPoint.dx - activeLayer!.position.dx,
          );
          final angleDelta = currentTouchAngle - _initialRotationTouch!;
          activeLayer!.rotation = _initialRotationLayer! + angleDelta;
          // Rotate/Scale માં last point અપડેટ કરવાની જરૂર નથી હોતી કારણ કે આપણે initial થી ગણીએ છીએ
          break;

        case HandleType.bottomRight:
        case HandleType.topRight:
        case HandleType.bottomLeft:
        case HandleType.topLeft:
          // Scaling relative to Object Center
          final currentDist = (localPoint - activeLayer!.position).distance;
          if (_initialDistance != null && _initialDistance! > 0) {
            final scaleFactor = currentDist / _initialDistance!;
            activeLayer!.scale = _initialScale! * scaleFactor;
          }
          break;
        default:
          break;
      }
    });
  }

  // --- 3. Other Helpers (Tap, Text Index, Find Layer) ---

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
    textPainter.layout();

    final dx = localCenterPoint.dx + (textPainter.width / 2);
    final dy = localCenterPoint.dy + (textPainter.height / 2);
    return textPainter
        .getPositionForOffset(Offset(dx, dy))
        .offset
        .clamp(0, layer.text.length);
  }

  TextSelection _getWordSelection(TextLayer layer, int index) {
    final textPainter = TextPainter(
      text: TextSpan(text: layer.text, style: layer.style),
      textDirection: TextDirection.ltr,
    );
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
