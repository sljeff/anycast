import 'package:flutter/material.dart';

class Discover extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Discover'),
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
