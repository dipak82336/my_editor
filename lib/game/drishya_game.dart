import 'dart:async';
import 'dart:math';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'ai_controller.dart';
import 'world_renderer.dart';

class DrishyaGame extends FlameGame with TapCallbacks {
  final AutoPilotSystem _aiController = AutoPilotSystem();

  // State
  Player playerModel = Player();
  List<Obstacle> obstacles = [];
  Biome currentBiome = Biome.gramam;
  bool isAIActive = false;

  late WorldRenderer _worldRenderer;
  late PlayerComponent _playerComponent;

  // Spawning logic
  double _spawnTimer = 0;
  final Random _rng = Random();

  // Game speed
  double gameSpeed = 10.0;

  @override
  Future<void> onLoad() async {
    _worldRenderer = WorldRenderer(currentBiome: currentBiome);
    add(_worldRenderer);

    _playerComponent = PlayerComponent(playerModel);
    add(_playerComponent);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // 1. Move obstacles
    double moveAmount = gameSpeed * dt;

    obstacles = obstacles.map((o) {
       return Obstacle(
         laneIndex: o.laneIndex,
         distanceFromPlayer: o.distanceFromPlayer - moveAmount,
         type: o.type,
         letterValue: o.letterValue
       );
    }).where((o) => o.distanceFromPlayer > -5).toList(); // Remove passed obstacles

    // 2. Spawn new obstacles
    _spawnTimer -= dt;
    if (_spawnTimer <= 0) {
       _spawnObstacle();
       _spawnTimer = 1.5 + _rng.nextDouble(); // Spawn every 1.5-2.5 seconds
    }

    // 3. AI Logic
    if (isAIActive) {
      final action = _aiController.decideMove(playerModel, obstacles);
      _applyAction(action);
    }

    // 4. Update Visuals
    _playerComponent.lane = playerModel.currentLane;
    _playerComponent.isJumping = playerModel.isJumping;

    // Sync Obstacle Components
    // For simplicity, we'll remove all obstacle components and re-add them,
    // or better: Update existing ones?
    // Since we recreate the list, matching is hard.
    // Let's just clear and redraw for this prototype or use a Manager.
    // For performance, this is bad, but for prototype it works.
    children.whereType<ObstacleComponent>().forEach((c) => c.removeFromParent());
    for (var o in obstacles) {
      add(ObstacleComponent(o));
    }
  }

  void _spawnObstacle() {
    // Random lane
    int lane = _rng.nextInt(3) - 1; // -1, 0, 1

    // Random type
    ObstacleType type;
    double r = _rng.nextDouble();
    if (r < 0.2) type = ObstacleType.letter;
    else if (r < 0.6) type = ObstacleType.low;
    else type = ObstacleType.high;

    obstacles.add(Obstacle(
      laneIndex: lane,
      distanceFromPlayer: 25, // Start further out
      type: type
    ));
  }

  void _applyAction(GameAction action) {
    switch (action) {
      case GameAction.moveLeft:
        if (playerModel.currentLane > -1) playerModel.currentLane--;
        break;
      case GameAction.moveRight:
        if (playerModel.currentLane < 1) playerModel.currentLane++;
        break;
      case GameAction.jump:
        if (!playerModel.isJumping) {
          playerModel.isJumping = true;
          Future.delayed(const Duration(milliseconds: 600), () {
             playerModel.isJumping = false;
          });
        }
        break;
      case GameAction.stay:
        break;
    }
  }

  void toggleAI() {
    isAIActive = !isAIActive;
  }

  @override
  void onTapDown(TapDownEvent event) {
    // Manual control?
    if (!isAIActive) {
      if (event.localPosition.x < size.x / 2) {
        _applyAction(GameAction.moveLeft);
      } else {
        _applyAction(GameAction.moveRight);
      }
    }
  }
}

class PlayerComponent extends PositionComponent {
  Player player;
  int lane = 0;
  bool isJumping = false;

  PlayerComponent(this.player);

  @override
  void render(Canvas canvas) {
    Paint paint = Paint()..color = isJumping ? Colors.orange : Colors.yellow;
    canvas.drawCircle(Offset.zero, 15, paint);

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 20), width: 15, height: 5),
      Paint()..color = Colors.black.withOpacity(0.3)
    );
  }

  @override
  void update(double dt) {
     // Position on screen
     // Center X, Y based on lane
     // Lanes: -1 (Top), 0 (Center), 1 (Bottom)
     double centerX = 100;
     double centerY = 300 + lane * 60.0;

     if (isJumping) {
       centerY -= 30; // Visual jump
     }

     x = centerX;
     y = centerY;
  }
}

class ObstacleComponent extends PositionComponent {
  final Obstacle obstacle;

  ObstacleComponent(this.obstacle);

  @override
  void render(Canvas canvas) {
    Paint paint = Paint();
    switch (obstacle.type) {
      case ObstacleType.high: paint.color = Colors.red; break;
      case ObstacleType.low: paint.color = Colors.amber; break;
      case ObstacleType.letter: paint.color = Colors.purpleAccent; break;
    }

    // Draw Box or Shape
    if (obstacle.type == ObstacleType.letter) {
       canvas.drawCircle(Offset.zero, 10, paint);
    } else {
       canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 20, height: 20), paint);
    }
  }

  @override
  void update(double dt) {
     // Convert distance to Screen X
     // Player is at X=100. Obstacle at 100 + distance * scale
     double scale = 20.0; // Pixels per unit
     x = 100 + obstacle.distanceFromPlayer * scale;
     y = 300 + obstacle.laneIndex * 60.0;
  }
}
