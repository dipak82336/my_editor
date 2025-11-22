import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'game/drishya_game.dart';

void main() {
  runApp(const ProviderScope(child: DrishyaApp()));
}

class DrishyaApp extends StatefulWidget {
  const DrishyaApp({super.key});
  @override
  State<DrishyaApp> createState() => _DrishyaAppState();
}

class _DrishyaAppState extends State<DrishyaApp> {
  final DrishyaGame game = DrishyaGame();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          children: [
            GameWidget(game: game),
            Positioned(
              bottom: 50,
              right: 20,
              child: FloatingActionButton.extended(
                onPressed: () {
                  game.toggleAI();
                  setState(() {}); // To update UI text
                },
                backgroundColor: game.isAIActive ? Colors.green : Colors.red,
                icon: Icon(game.isAIActive ? Icons.smart_toy : Icons.person),
                label: Text(game.isAIActive ? "AUTO-PILOT ON" : "ENABLE AUTO-PILOT"),
              ),
            ),
            const Positioned(
              top: 40,
              left: 20,
              child: Text(
                "DRISHYA: THE ETERNAL PATH",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(blurRadius: 10, color: Colors.black)]
                ),
              )
            )
          ],
        ),
      ),
    );
  }
}
