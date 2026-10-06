import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WeatherWalay brand colours (sampled from the official mark).
class Brand {
  static const orange = Color(0xFFFFB000); // sun
  static const blue = Color(0xFF0952DF); // front drop
  static const sky = Color(0xFF397DFF); // back drop
  static const ink = Color(0xFF0B1B3F); // text on light backgrounds
  static const mist = Color(0xFFF3F7FF); // page background

  static const blueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, sky],
  );
  static const sunGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFC233), Color(0xFFFF9500)],
  );
}

/// Draws the WeatherWalay mark: two drops and a sun.
///
/// Geometry is traced from the 512×512 logo; the mark's own box is 400×244.
/// [entrance] runs 0→1 once (drops fall in, sun pops up);
/// [idle] loops 0→1 for the loading animation (gentle bobbing).
class _MarkPainter extends CustomPainter {
  final double entrance;
  final double idle;
  final bool loading;

  _MarkPainter({required this.entrance, this.idle = 0, this.loading = false});

  static const _w = 400.0, _h = 244.0;
  static const _ox = 56.0, _oy = 134.0; // top-left of the mark in the 512 logo

  static double _interval(double t, double a, double b, Curve c) =>
      c.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  Path _drop(double left) {
    const top = 136.0, r = 158.0;
    return Path()
      ..moveTo(left, top)
      ..arcTo(Rect.fromCircle(center: Offset(left, top + r), radius: r),
          -math.pi / 2, math.pi / 2, false)
      ..arcTo(
          Rect.fromCircle(
              center: Offset(left + r / 2, top + r), radius: r / 2),
          0,
          math.pi,
          false)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / _w, size.height / _h);
    canvas.translate(
        (size.width - _w * s) / 2 - _ox * s, (size.height - _h * s) / 2 - _oy * s);
    canvas.scale(s);

    final wave = idle * 2 * math.pi;

    void drawDrop(double left, Color color, double t, double phase) {
      if (t <= 0) return;
      final bob = loading ? math.sin(wave + phase) * 10 : 0.0;
      canvas.save();
      canvas.translate(0, (1 - t) * -90 + bob);
      canvas.drawPath(
          _drop(left),
          Paint()
            ..color = color.withValues(alpha: t.clamp(0.0, 1.0)));
      canvas.restore();
    }

    // Back drop, front drop, then the sun on top – same order as the logo.
    drawDrop(296, Brand.sky,
        _interval(entrance, 0.0, 0.55, Curves.easeOutBack), 0);
    drawDrop(177, Brand.blue,
        _interval(entrance, 0.15, 0.7, Curves.easeOutBack), math.pi / 2);

    final sunT = _interval(entrance, 0.45, 1.0, Curves.elasticOut);
    if (sunT > 0) {
      final pulse = loading ? 1 + math.sin(wave + math.pi) * 0.06 : 1.0;
      canvas.drawCircle(const Offset(137, 296.5), 78.5 * sunT * pulse,
          Paint()..color = Brand.orange);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.entrance != entrance || old.idle != idle || old.loading != loading;
}

/// The WeatherWalay mark. Plays its entrance animation once when shown;
/// with [loading] it keeps bobbing (used as the app's loading indicator).
class BrandMark extends StatefulWidget {
  final double width;
  final bool animate;
  final bool loading;

  const BrandMark(
      {super.key, this.width = 120, this.animate = true, this.loading = false});

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
    value: widget.animate ? 0 : 1,
  );
  late final AnimationController _idle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _entrance.forward();
    if (widget.loading) _idle.repeat();
  }

  @override
  void didUpdateWidget(BrandMark old) {
    super.didUpdateWidget(old);
    if (widget.loading && !_idle.isAnimating) _idle.repeat();
    if (!widget.loading) _idle.stop();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_entrance, _idle]),
        builder: (_, __) => CustomPaint(
          size: Size(widget.width, widget.width * 244 / 400),
          painter: _MarkPainter(
              entrance: _entrance.value,
              idle: _idle.value,
              loading: widget.loading),
        ),
      ),
    );
  }
}

/// "WeatherWalay / DEPLOYMENT" wordmark.
class BrandWordmark extends StatelessWidget {
  final double size;
  final Color? color;
  final CrossAxisAlignment align;

  const BrandWordmark(
      {super.key,
      this.size = 26,
      this.color,
      this.align = CrossAxisAlignment.center});

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Brand.ink;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Weather', style: TextStyle(color: ink)),
            TextSpan(
                text: 'Walay',
                style: TextStyle(color: color ?? Brand.blue)),
          ]),
          style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.05),
        ),
        Text(
          'DEPLOYMENT',
          style: TextStyle(
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            letterSpacing: size * 0.22,
            color: color ?? Brand.orange,
          ),
        ),
      ],
    );
  }
}

/// Full-screen / section loading state: the bobbing mark plus a label.
class BrandLoader extends StatelessWidget {
  final String? label;
  const BrandLoader({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(width: 72, animate: false, loading: true),
        if (label != null) ...[
          const SizedBox(height: 14),
          Text(label!,
              style: TextStyle(
                  color: Brand.ink.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500)),
        ],
      ],
    );
  }
}

/// [BrandLoader] centred in a scrollable, so pull-to-refresh keeps working.
class BrandLoaderList extends StatelessWidget {
  final String? label;
  const BrandLoaderList({super.key, this.label});

  @override
  Widget build(BuildContext context) => ListView(children: [
        const SizedBox(height: 140),
        Center(child: BrandLoader(label: label)),
      ]);
}
