import 'package:test/test.dart';
import 'package:my_editor/game/models.dart';
import 'package:my_editor/game/ai_controller.dart';

void main() {
  group('AutoPilotSystem Tests', () {
    late AutoPilotSystem ai;

    setUp(() {
      ai = AutoPilotSystem();
    });

    test('Scenario A: Avoid obstacle in Lane 0', () {
      final player = Player(currentLane: 0);
      final obstacles = [
        Obstacle(laneIndex: 0, distanceFromPlayer: 10, type: ObstacleType.high)
      ];

      final action = ai.decideMove(player, obstacles);
      expect(action, anyOf(GameAction.moveLeft, GameAction.moveRight));
    });

    test('Scenario B: Jump over low obstacle when blocked', () {
      final player = Player(currentLane: 0);
      final obstacles = [
        Obstacle(laneIndex: 0, distanceFromPlayer: 10, type: ObstacleType.low),
        Obstacle(laneIndex: -1, distanceFromPlayer: 10, type: ObstacleType.high),
        Obstacle(laneIndex: 1, distanceFromPlayer: 10, type: ObstacleType.high),
      ];

      final action = ai.decideMove(player, obstacles);
      expect(action, GameAction.jump);
    });

    test('Scenario C: Greedy move to collectible', () {
      final player = Player(currentLane: 0);
      final obstacles = [
        Obstacle(laneIndex: 1, distanceFromPlayer: 15, type: ObstacleType.letter)
      ];

      final action = ai.decideMove(player, obstacles);
      expect(action, GameAction.moveRight); // Assuming lane 1 is right of 0
    });
  });
}
