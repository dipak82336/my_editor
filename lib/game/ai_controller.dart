import 'models.dart';

enum GameAction { moveLeft, moveRight, jump, stay }

class AutoPilotSystem {
  GameAction decideMove(Player player, List<Obstacle> obstacles) {
    // 1. Look-Ahead: Filter obstacles < 20 units away
    final relevantObstacles = obstacles.where((o) => o.distanceFromPlayer < 20).toList();

    // Helper to check if a lane is safe (no HIGH/LOW obstacles).
    bool isLaneSafe(int laneIndex) {
      return !relevantObstacles.any((o) =>
        o.laneIndex == laneIndex && (o.type == ObstacleType.high || o.type == ObstacleType.low)
      );
    }

    // Check current lane status
    // We care about the CLOSEST obstacle in the current lane.
    final currentLaneObstacles = relevantObstacles
        .where((o) => o.laneIndex == player.currentLane && (o.type == ObstacleType.high || o.type == ObstacleType.low))
        .toList();

    currentLaneObstacles.sort((a, b) => a.distanceFromPlayer.compareTo(b.distanceFromPlayer));

    final closestThreat = currentLaneObstacles.isNotEmpty ? currentLaneObstacles.first : null;

    bool isCurrentBlocked = closestThreat != null;

    // Check adjacent lanes availability
    bool canMoveLeft = player.currentLane > -1;
    bool canMoveRight = player.currentLane < 1;

    bool leftSafe = canMoveLeft && isLaneSafe(player.currentLane - 1);
    bool rightSafe = canMoveRight && isLaneSafe(player.currentLane + 1);

    // PRIORITY 1: SURVIVAL
    if (isCurrentBlocked) {
      // If we can jump over the immediate threat
      if (closestThreat!.type == ObstacleType.low) {
         // If both sides are blocked, we MUST jump.
         if (!leftSafe && !rightSafe) {
           return GameAction.jump;
         }
         // If one side is safe, we COULD move or jump.
         // Prefer moving to a completely safe lane.
         if (leftSafe) return GameAction.moveLeft;
         if (rightSafe) return GameAction.moveRight;
         return GameAction.jump;
      } else {
        // High obstacle. Must move.
        if (leftSafe) return GameAction.moveLeft;
        if (rightSafe) return GameAction.moveRight;
        // If both blocked and High... dead.
        return GameAction.jump;
      }
    }

    // PRIORITY 2: GREEDY
    // Current lane is safe (no threats). Check for letters in adjacent lanes.
    // We should probably check closest letter? Or any letter?
    // Let's check for any letter in range.

    if (canMoveRight && rightSafe) {
       bool hasLetter = relevantObstacles.any((o) => o.laneIndex == player.currentLane + 1 && o.type == ObstacleType.letter);
       if (hasLetter) return GameAction.moveRight;
    }

    if (canMoveLeft && leftSafe) {
       bool hasLetter = relevantObstacles.any((o) => o.laneIndex == player.currentLane - 1 && o.type == ObstacleType.letter);
       if (hasLetter) return GameAction.moveLeft;
    }

    return GameAction.stay;
  }
}
