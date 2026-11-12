import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../domain/insights.dart';

/// "Spent this cycle": the total, the daily average, and a bar for every day.
class SpendingChart extends StatelessWidget {
  const SpendingChart({super.key, required this.insights});

  final CycleInsights insights;

  static const _barAreaHeight = 72.0;

  @override
  Widget build(BuildContext context) {
    final i = insights;
    final tallest = i.biggestDaySen;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Spent this cycle', style: TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 2),
            Text(formatSen(i.totalSpentSen), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              i.totalSpentSen == 0
                  ? 'Nothing spent yet.'
                  : 'About ${formatSen(i.averagePerDaySen)} a day · biggest day ${formatSen(tallest)}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Daily spending this cycle, one bar for each day',
              child: SizedBox(
                height: _barAreaHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var day = 0; day < i.dailySen.length; day++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: _Bar(
                            key: ValueKey('day-$day'),
                            height: tallest == 0 ? 0 : (_barAreaHeight - 4) * i.dailySen[day] / tallest,
                            state: day == i.todayIndex
                                ? _BarState.today
                                : day < i.todayIndex
                                ? _BarState.past
                                : _BarState.future,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Payday', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                Text('Next payday', style: TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _BarState { past, today, future }

class _Bar extends StatelessWidget {
  const _Bar({super.key, required this.height, required this.state});

  final double height;
  final _BarState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _BarState.today => AppColors.brand,
      _BarState.past => const Color(0xFF8CB8AF),
      _BarState.future => AppColors.line,
    };
    // A day with nothing spent still shows a thin baseline, so the row reads as days.
    final h = height < 2 ? 2.0 : height;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: h,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}
