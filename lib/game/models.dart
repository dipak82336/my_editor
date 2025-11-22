enum Biome { gramam, nagaram, vanam }

enum ObstacleType { low, high, letter }

class Obstacle {
  final int laneIndex;
  final double distanceFromPlayer;
  final ObstacleType type;
  // Maybe a value for letter?
  final String? letterValue;

  Obstacle({
    required this.laneIndex,
    required this.distanceFromPlayer,
    required this.type,
    this.letterValue,
  });
}

class Player {
  int currentLane;
  bool isJumping;

  Player({
    this.currentLane = 0,
    this.isJumping = false,
  });
}

class GameState {
  final List<String> collectedLetters;
  final int score;

  GameState({
    this.collectedLetters = const [],
    this.score = 0,
  });
}
