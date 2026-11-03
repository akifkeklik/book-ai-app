import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/design_system.dart';

/// Animated pulsing micro-dot for SaaS status indicators.
class SaasPulseDot extends StatefulWidget {
  final Color color;
  final double size;

  const SaasPulseDot({
    super.key,
    required this.color,
    this.size = 7.0,
  });

  @override
  State<SaasPulseDot> createState() => _SaasPulseDotState();
}

class _SaasPulseDotState extends State<SaasPulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    final bool isTestMode = Platform.environment.containsKey('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (!isTestMode) {
      _controller.repeat(reverse: true);
    }

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.65),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Reusable SaaS Information / Metric Card for dashboards & analytics.
class SaasMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? footerText;
  final String? contextTag;
  final Color? contextColor;
  final Color? pulseDotColor;
  final Color? accentColor;
  final VoidCallback? onTap;

  const SaasMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.footerText,
    this.contextTag,
    this.contextColor,
    this.pulseDotColor,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryAccent = accentColor ?? DesignSystem.electricBlue;
    final bgColor = isDark ? DesignSystem.saasNavy900 : Colors.white;
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.08);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(DesignSystem.spacing16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: DesignSystem.saasCardShadow(isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Accent Bar (Gradient Hairline)
            Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    primaryAccent,
                    primaryAccent.withOpacity(0.0),
                  ],
                ),
              ),
            ),

            // Header Row: Label & Icon
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryAccent.withOpacity(0.28)),
                  ),
                  child: Icon(icon, size: 16, color: primaryAccent),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Main Metric Value
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : DesignSystem.textLightPrimary,
                  ),
                ),
                if (contextTag != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (contextColor ?? primaryAccent).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      contextTag!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: contextColor ?? primaryAccent,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            if (footerText != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (pulseDotColor != null) ...[
                    SaasPulseDot(color: pulseDotColor!, size: 6.5),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      footerText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Status Badge with Micro-Pulse Dot
class SaasStatusBadge extends StatelessWidget {
  final String status;
  final String label;

  const SaasStatusBadge({
    super.key,
    required this.status,
    required this.label,
  });

  Color _getStatusColor() {
    switch (status.toLowerCase()) {
      case 'reading':
        return const Color(0xFFF59E0B);
      case 'finished':
        return const Color(0xFF10B981);
      case 'want_to_read':
      case 'wanttoread':
        return const Color(0xFF38BDF8);
      case 'favorite':
        return const Color(0xFFF43F5E);
      case 'ai':
      default:
        return const Color(0xFF0EA5E9);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getStatusColor();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SaasPulseDot(color: color, size: 6),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? color : color.withOpacity(0.95),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// 7-Day Reading & Learning Activity Visualizer
class SaasActivityChart extends StatelessWidget {
  final List<double> heights; // 0.0 to 1.0 (7 elements)
  final List<String> labels; // e.g. ['M', 'T', 'W', 'T', 'F', 'S', 'S']
  final int activeDayIndex;

  const SaasActivityChart({
    super.key,
    this.heights = const [0.55, 0.8, 0.4, 0.9, 0.65, 1.0, 0.75],
    this.labels = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
    this.activeDayIndex = 5,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(heights.length, (index) {
          final h = heights[index].clamp(0.1, 1.0);
          final isCurrent = index == activeDayIndex;
          final label = index < labels.length ? labels[index] : '';

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 54,
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: double.infinity,
                      height: 54 * h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: isCurrent
                              ? [
                                  DesignSystem.electricBlue,
                                  const Color(0xFF0284C7),
                                ]
                              : [
                                  DesignSystem.electricBlue.withOpacity(0.7),
                                  DesignSystem.electricBlue.withOpacity(0.25),
                                ],
                        ),
                        boxShadow: isCurrent
                            ? [
                                BoxShadow(
                                  color: DesignSystem.electricBlue.withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: isCurrent
                          ? (isDark ? Colors.white : DesignSystem.textLightPrimary)
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Controlled Glass Card Panel with backdrop blur and hairline border.
class SaasGlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  const SaasGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DesignSystem.spacing16),
    this.borderRadius = 16.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? DesignSystem.saasNavy900.withOpacity(0.85) : Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
        ),
        boxShadow: DesignSystem.saasCardShadow(isDark),
      ),
      child: child,
    );

    if (onTap != null) {
      content = GestureDetector(onTap: onTap, child: content);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: content,
      ),
    );
  }
}

