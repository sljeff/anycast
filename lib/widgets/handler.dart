import 'package:flutter/material.dart';

class Handler extends StatelessWidget {
  const Handler({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 6,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: Colors.white.withOpacity(0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
