import 'package:anycast/widgets/player.dart';
import 'package:flutter/material.dart';

class Channel extends StatelessWidget {
  const Channel({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: PlayerWidget(),
      appBar: AppBar(
        title: Text('Channel'),
      ),
      body: Center(
        child: Text(
          'Hello, world!',
          style: TextStyle(fontSize: 24),
        ),
      ),
    );
  }
}
