import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'models.dart';

class WorldRenderer extends PositionComponent {
  final Biome currentBiome;

  WorldRenderer({required this.currentBiome});

  @override
  void render(Canvas canvas) {
     Color topColor;
     Color bottomColor;

     switch (currentBiome) {
       case Biome.gramam:
         topColor = Colors.lightBlue.shade300;
         bottomColor = Colors.green.shade800;
         break;
       case Biome.nagaram:
         topColor = Colors.grey.shade400;
         bottomColor = Colors.blueGrey.shade900;
         break;
       case Biome.vanam:
         topColor = Colors.teal.shade200;
         bottomColor = Colors.teal.shade900;
         break;
     }

     final rect = size.toRect();

     // Use ui.Gradient to disambiguate from flutter/painting Gradient
     final paint = Paint()
       ..shader = ui.Gradient.linear(
         Offset(size.x / 2, 0),
         Offset(size.x / 2, size.y),
         [topColor, bottomColor],
       );

     canvas.drawRect(rect, paint);

     // Bloom/Fog simulation
     final fogPaint = Paint()
       ..color = Colors.white.withOpacity(0.1)
       ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

     canvas.drawRect(rect, fogPaint);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }
}
