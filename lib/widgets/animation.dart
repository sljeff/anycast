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
                  color: Colors.black.withValues(alpha: _backOpacityAnimation.value),
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

class PlayPauseAnimation extends StatefulWidget {
  final bool isPlaying;

  const PlayPauseAnimation({super.key, required this.isPlaying});

  @override
  State<PlayPauseAnimation> createState() => _PlayPauseAnimationState();
}

class _PlayPauseAnimationState extends State<PlayPauseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(80, 80),
          painter: PlayPausePainter(
            progress: _animation.value,
            isPlaying: widget.isPlaying,
          ),
        );
      },
    );
  }
}

class PlayPausePainter extends CustomPainter {
  final double progress;
  final bool isPlaying;

  PlayPausePainter({required this.progress, required this.isPlaying});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.fill;

    if (isPlaying) {
      // 绘制暂停图标
      final left = size.width * (0.3 + 0.1 * progress);
      final right = size.width * (0.7 - 0.1 * progress);
      canvas.drawRect(
          Rect.fromLTRB(left, size.height * 0.2, left + size.width * 0.1,
              size.height * 0.8),
          paint);
      canvas.drawRect(
          Rect.fromLTRB(right, size.height * 0.2, right + size.width * 0.1,
              size.height * 0.8),
          paint);
    } else {
      // 绘制播放图标
      final path = Path();
      path.moveTo(size.width * 0.3, size.height * 0.2);
      path.lineTo(size.width * (0.3 + 0.5 * progress), size.height * 0.5);
      path.lineTo(size.width * 0.3, size.height * 0.8);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CenterPlayArrow extends StatelessWidget {
  const CenterPlayArrow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.play_arrow, color: Colors.white),
    );
  }
}
