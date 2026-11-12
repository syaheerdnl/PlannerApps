import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../domain/budget.dart';

/// A small label for how an envelope is doing ("On track", "Spending fast").
class PaceChip extends StatelessWidget {
  const PaceChip(this.pace, {super.key});

  final Pace pace;

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = switch (pace) {
      Pace.none => ('No budget', AppColors.line, AppColors.muted),
      Pace.underPace => ('Well under', AppColors.brandTint, AppColors.brandDark),
      Pace.onTrack => ('On track', AppColors.brandTint, AppColors.brandDark),
      Pace.fast => ('Spending fast', AppColors.warnBg, AppColors.warnFg),
      Pace.over => ('Over budget', AppColors.dangerBg, AppColors.dangerFg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }
}

/// How much of the budget is left, as a bar, with a thin tick where the bar
/// would be if you were spending perfectly evenly through the cycle.
class EnvelopeBar extends StatelessWidget {
  const EnvelopeBar({super.key, required this.fractionLeft, required this.color, this.expectedLeft, this.height = 8});

  /// 0..1, how much of the budget is left.
  final double fractionLeft;

  /// 0..1, where the tick goes. Null hides it.
  final double? expectedLeft;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return SizedBox(
          height: height + 6,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(height / 2)),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                height: height,
                width: width * fractionLeft.clamp(0.0, 1.0),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
              ),
              if (expectedLeft != null)
                Positioned(
                  left: (width * expectedLeft!.clamp(0.0, 1.0)) - 1,
                  child: Container(width: 2, height: height + 6, color: AppColors.ink),
                ),
            ],
          ),
        );
      },
    );
  }
}
