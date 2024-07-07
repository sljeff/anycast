import 'package:flutter/material.dart';

class AnimatedPlaylistIndicator extends StatefulWidget {
  final Offset startPosition;
  final Offset endPosition;
  final VoidCallback onAnimationComplete;

  const AnimatedPlaylistIndicator(
      {super.key,
      required this.startPosition,
      required this.endPosition,
      required this.onAnimationComplete});

  @override
  AnimatedPlaylistIndicatorState createState() =>
      AnimatedPlaylistIndicatorState();
}

class AnimatedPlaylistIndicatorState extends State<AnimatedPlaylistIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _positionAnimation;
  late Animation<double> _heightAnimation;
  late Animation<double> _widthAnimation;
  late Animation<double> _backOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _positionAnimation = Tween<Offset>(
      begin: widget.startPosition,
      end: widget.endPosition,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _heightAnimation = Tween<double>(begin: 48, end: 24).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _widthAnimation = Tween<double>(begin: 200, end: 24).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _backOpacityAnimation = Tween<double>(begin: 0.8, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward().then((_) {
      widget.onAnimationComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Positioned(
              left: _positionAnimation.value.dx - _widthAnimation.value / 2,
              top: _positionAnimation.value.dy - _heightAnimation.value / 2,
              child: Container(
                width: _widthAnimation.value,
                height: _heightAnimation.value,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(_backOpacityAnimation.value),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
