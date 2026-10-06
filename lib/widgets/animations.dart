import 'package:flutter/material.dart';

/// Fades and slides its child up into place. Give list items increasing
/// [index] values for a staggered "cascade" entrance.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  final double offset;

  const FadeSlideIn(
      {super.key, required this.child, this.index = 0, this.offset = 24});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // Cap the delay so long lists don't keep animating for seconds.
    final delay = Duration(milliseconds: 55 * widget.index.clamp(0, 8));
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
            offset: Offset(0, (1 - _t.value) * widget.offset), child: child),
      ),
    );
  }
}

/// A small dot with an expanding ring – "live / vehicle is out".
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulsingDot({super.key, required this.color, this.size = 10});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(alignment: Alignment.center, children: [
          Container(
            width: s * (1 + _c.value * 1.4),
            height: s * (1 + _c.value * 1.4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: (1 - _c.value) * 0.45),
            ),
          ),
          Container(
            width: s,
            height: s,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: widget.color),
          ),
        ]),
      ),
    );
  }
}

/// Animates a number from its previous value (or 0) to [value].
class CountUp extends StatelessWidget {
  final num value;
  final String Function(num v) format;
  final TextStyle? style;
  final TextAlign? textAlign;

  const CountUp(
      {super.key,
      required this.value,
      required this.format,
      this.style,
      this.textAlign});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(
          format(value is int ? v.round() : v),
          style: style,
          textAlign: textAlign),
    );
  }
}

/// Slowly drifting soft colour blobs – decorative background.
class DriftingBlobs extends StatefulWidget {
  final List<Color> colors;
  const DriftingBlobs({super.key, required this.colors});

  @override
  State<DriftingBlobs> createState() => _DriftingBlobsState();
}

class _DriftingBlobsState extends State<DriftingBlobs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 14))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // (alignment start, alignment end, size factor) per blob
    const paths = [
      (Alignment(-1.2, -1.1), Alignment(-0.4, -0.7), 0.95),
      (Alignment(1.3, -0.5), Alignment(0.7, -0.9), 0.8),
      (Alignment(0.9, 1.2), Alignment(1.3, 0.6), 0.9),
    ];
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final base = box.biggest.shortestSide;
        return AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = Curves.easeInOut.transform(_c.value);
            return Stack(children: [
              for (var i = 0; i < paths.length && i < widget.colors.length; i++)
                Align(
                  alignment: Alignment.lerp(paths[i].$1, paths[i].$2, t)!,
                  child: Container(
                    width: base * paths[i].$3,
                    height: base * paths[i].$3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        widget.colors[i].withValues(alpha: 0.35),
                        widget.colors[i].withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
            ]);
          },
        );
      }),
    );
  }
}
