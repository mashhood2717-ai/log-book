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

/// Colours that change between light and dark mode.
/// Use `context.colors.ink` etc. instead of fixed colours in widgets.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color ink; // main text
  final Color muted; // secondary text
  final Color faint; // icons in empty states, hints
  final Color page; // screen background
  final Color card; // cards, sheets, inputs
  final Color border; // hairline borders on cards
  final Color accent; // brand-blue text/icons (lighter in dark mode)
  final Color amberText; // text on the orange "OUT"/"EDITED" chips
  final Color disabled; // inactive vehicle / blocked user tiles

  const AppColors({
    required this.ink,
    required this.muted,
    required this.faint,
    required this.page,
    required this.card,
    required this.border,
    required this.accent,
    required this.amberText,
    required this.disabled,
  });

  static const light = AppColors(
    ink: Brand.ink,
    muted: Color(0x990B1B3F),
    faint: Color(0x4D0B1B3F),
    page: Brand.mist,
    card: Colors.white,
    border: Color(0x120952DF),
    accent: Brand.blue,
    amberText: Color(0xFFB36B00),
    disabled: Color(0xFFE0E0E0),
  );

  static const dark = AppColors(
    ink: Color(0xFFE8EEFF),
    muted: Color(0xA6E8EEFF),
    faint: Color(0x4DE8EEFF),
    page: Color(0xFF0A1020),
    card: Color(0xFF141D33),
    border: Color(0x26397DFF),
    accent: Color(0xFF6E9DFF),
    amberText: Color(0xFFFFC24D),
    disabled: Color(0xFF2A3247),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      page: l(page, other.page),
      card: l(card, other.card),
      border: l(border, other.border),
      accent: l(accent, other.accent),
      amberText: l(amberText, other.amberText),
      disabled: l(disabled, other.disabled),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
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
    final ink = color ?? context.colors.ink;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Weather', style: TextStyle(color: ink)),
            TextSpan(
                text: 'Walay',
                style: TextStyle(color: color ?? context.colors.accent)),
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
                  color: context.colors.muted,
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
