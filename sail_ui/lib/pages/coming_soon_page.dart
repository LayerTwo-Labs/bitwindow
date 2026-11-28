import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sail_ui/pages/router.gr.dart';
import 'package:sail_ui/sail_ui.dart';

@RoutePage()
class ComingSoonPage extends StatefulWidget {
  final RootStackRouter router;
  final String message;

  const ComingSoonPage({
    super.key,
    required this.router,
    required this.message,
  });

  @override
  State<ComingSoonPage> createState() => _ComingSoonPageState();
}

class _ComingSoonPageState extends State<ComingSoonPage> with TickerProviderStateMixin {
  late AnimationController _starController;
  late List<_Star> _stars;

  @override
  void initState() {
    super.initState();
    _starController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _stars = List.generate(100, (_) => _Star.random());
  }

  @override
  void dispose() {
    _starController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = SailTheme.of(context);
    return Scaffold(
      backgroundColor: theme.colors.background,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _starController,
            builder: (context, child) {
              return CustomPaint(
                painter: _StarfieldPainter(
                  stars: _stars,
                  animation: _starController.value,
                  color: theme.colors.textSecondary,
                ),
                size: Size.infinite,
              );
            },
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SailStyleValues.padding32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Container(
                  key: const Key('coming-soon-card'),
                  padding: const EdgeInsets.all(SailStyleValues.padding32),
                  decoration: BoxDecoration(
                    color: theme.colors.backgroundSecondary,
                    borderRadius: theme.chrome.radiusLarge,
                    border: Border.all(color: theme.colors.border),
                  ),
                  child: SailColumn(
                    spacing: SailStyleValues.padding12,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SailText.primary22('THIS COULD BE BITCOIN', bold: true),
                      SailText.primary13(widget.message),
                      SailText.secondary13(
                        'Drivechain (BIP-300/301) enables sidechains on Bitcoin. '
                        'This feature requires activation with a soft fork.\n\n'
                        'Until activated, you can continue this demo and take a peak into the future by switching to Signet, where Drivechain is already active.',
                      ),
                      const SizedBox(height: SailStyleValues.padding04),
                      SailButton(
                        label: 'Switch to Signet',
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await widget.router.push(NetworkSwitchRoute());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: SailStyleValues.padding12,
            left: SailStyleValues.padding12,
            child: SailIconBoxButton(
              icon: SailSVGAsset.chevronLeft,
              tooltip: 'Back',
              onPressed: () async => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Star {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double brightness;

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.brightness,
  });

  factory _Star.random() {
    final random = Random();
    return _Star(
      x: random.nextDouble(),
      y: random.nextDouble(),
      size: random.nextDouble() * 2 + 0.5,
      speed: random.nextDouble() * 0.5 + 0.1,
      brightness: random.nextDouble() * 0.5 + 0.5,
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> stars;
  final double animation;
  final Color color;

  _StarfieldPainter({required this.stars, required this.animation, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      final twinkle = (sin((animation + star.speed) * pi * 2) + 1) / 2;
      final alpha = star.brightness * (0.5 + twinkle * 0.5);

      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.size * 0.6,
        Paint()..color = color.withValues(alpha: alpha * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StarfieldPainter oldDelegate) => true;
}
