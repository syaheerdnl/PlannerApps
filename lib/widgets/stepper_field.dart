import 'package:flutter/material.dart';

import '../core/theme.dart';

/// "Label     [-]  3 days  [+]". Passing null for [onMinus] or [onPlus] greys
/// that button out, so the caller decides the limits.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onMinus,
    required this.onPlus,
    this.minusLabel,
    this.plusLabel,
  });

  final String label;
  final String valueText;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final String? minusLabel;
  final String? plusLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
        _RoundButton(icon: Icons.remove, onPressed: onMinus, tooltip: minusLabel ?? 'Decrease $label'),
        SizedBox(
          width: 84,
          child: Text(
            valueText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
        _RoundButton(icon: Icons.add, onPressed: onPlus, tooltip: plusLabel ?? 'Increase $label'),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onPressed, required this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      // 44 x 44 is the minimum comfortable touch target.
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        side: BorderSide(color: onPressed == null ? AppColors.line : const Color(0xFFC9D0D8)),
        foregroundColor: AppColors.ink,
        backgroundColor: Colors.white,
      ),
    );
  }
}
