import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Stand-in for tabs that arrive in a later phase.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, required this.phase});

  final String title;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Coming in $phase', style: const TextStyle(color: AppColors.muted, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
