import 'package:flutter/material.dart';
import 'models.dart';
import 'editor_canvas.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Pro Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const EditorPage(),
    );
  }
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => EditorPageState();
}

@visibleForTesting
class EditorPageState extends State<EditorPage> {
  late EditorComposition composition;

  @override
  void initState() {
    super.initState();
    composition = EditorComposition(
      dimension: const Size(1080, 1080),
      backgroundColor: Colors.white,
      layers: [
        TextLayer(
          id: '1',
          text: 'Smart Text Editor',
          position: Offset.zero,
          style: const TextStyle(
            fontSize: 50,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        TextLayer(
          id: '2',
          text: 'Double Tap Me!',
          position: const Offset(0, 200),
          rotation: -0.1,
          style: const TextStyle(fontSize: 40, color: Colors.purple),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Advanced Editor Engine"),
        backgroundColor: Colors.black,
      ),
      body: EditorCanvas(composition: composition),
    );
  }
}