import 'package:flutter/material.dart';

class Handler extends StatefulWidget {
  const Handler({super.key});

  @override
  HandlerState createState() => HandlerState();
}

class HandlerState extends State<Handler> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;

  // 使用 static 变量来跟踪动画是否已经显示过
  static const bool _hasShownAnimation = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _animation = TweenSequence<Offset>([
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(0, 0.8),
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<Offset>(
          begin: const Offset(0, 0.8),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeInQuad)),
        weight: 40,
      ),
    ]).animate(_controller);

    _checkAndPlayAnimation();
  }

  void _checkAndPlayAnimation() {
    if (!_hasShownAnimation) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _playAnimation();
          // _hasShownAnimation = true;
        }
      });
    }
  }

  void _playAnimation() async {
    await _controller.forward();
    await _controller.reverse();
    // await Future.delayed(const Duration(milliseconds: 200));
    // await _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _animation,
      child: Container(
        width: 42,
        height: 6,
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
