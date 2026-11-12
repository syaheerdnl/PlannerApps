import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/budget.dart';
import '../domain/insights.dart';
import '../providers/budget_controller.dart';
import '../widgets/envelope_widgets.dart';
import '../widgets/spending_chart.dart';
import '../widgets/spending_sheet.dart';
import 'bill_actions.dart';

/// How much is left in each envelope, and where it went.
class EnvelopesScreen extends StatelessWidget {
  const EnvelopesScreen({super.key, required this.selectedTab});

  /// Used to jump to the Plan tab.
  final ValueNotifier<int> selectedTab;

  static const planTab = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BudgetController>();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final views = c.envelopeViews;
    final noBudgets = c.isSetUp && views.isNotEmpty && views.every((v) => v.budgetSen == 0);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, bottomInset + 96),
        children: [
          Text('Envelopes', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            c.isSetUp
                ? '${formatSen(c.leftToSpendSen)} left · ${c.daysLeft} ${c.daysLeft == 1 ? 'day' : 'days'} to payday'
                : 'Split your salary into pots, then watch them drain.',
            style: const TextStyle(fontSize: 13, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          if (!c.isSetUp)
            _Prompt(
              title: 'Set up your salary first',
              body: 'Tell Bayar your payday and salary, then give each envelope an amount.',
              button: 'Set up salary',
              onPressed: () => selectedTab.value = planTab,
            )
          else ...[
            if (noBudgets)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _Prompt(
                  title: 'No budgets yet',
                  body: 'Choose how much each envelope gets this cycle.',
                  button: 'Plan budgets',
                  onPressed: () => selectedTab.value = planTab,
                ),
              ),
            if (views.isNotEmpty) ...[
              SpendingChart(
                insights: buildInsights(views: views, cycle: c.cycle!, today: c.today),
              ),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < views.length; i++) ...[
              _EnvelopeCard(key: ValueKey(views[i].envelope.id), view: views[i], color: AppColors.envelope(i)),
              const SizedBox(height: 12),
            ],
            if (views.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'You have no envelopes. Add one on the Plan tab.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.title, required this.body, required this.button, required this.onPressed});

  final String title;
  final String body;
  final String button;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44), shape: const StadiumBorder()),
              child: Text(button),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnvelopeCard extends StatefulWidget {
  const _EnvelopeCard({super.key, required this.view, required this.color});

  final EnvelopeView view;
  final Color color;

  @override
  State<_EnvelopeCard> createState() => _EnvelopeCardState();
}

class _EnvelopeCardState extends State<_EnvelopeCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    final c = context.read<BudgetController>();
    final over = v.leftSen < 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(v.envelope.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                PaceChip(v.pace),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              formatSen(v.leftSen),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: over ? AppColors.dangerFg : AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            EnvelopeBar(
              fractionLeft: v.leftFraction,
              color: over ? AppColors.dangerFg : widget.color,
              expectedLeft: v.budgetSen > 0 ? v.expectedLeftFraction : null,
            ),
            const SizedBox(height: 8),
            Text(
              v.budgetSen == 0
                  ? 'No budget set for this cycle'
                  : over
                  ? 'Over by ${formatSen(-v.leftSen)} · budget ${formatSen(v.budgetSen)}'
                  : 'of ${formatSen(v.budgetSen)} · ${formatSen(v.dailySafeSen)} a day for ${c.daysLeft} ${c.daysLeft == 1 ? 'day' : 'days'}',
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _open = !_open),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: const StadiumBorder(),
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: Color(0xFFC9D0D8)),
                    ),
                    child: Text(_open ? 'Hide history' : 'History (${v.spendings.length})'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => showSpendingSheet(context, envelopeId: v.envelope.id),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44), shape: const StadiumBorder()),
                    child: const Text('Add spending'),
                  ),
                ),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 8),
              if (v.spendings.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Nothing spent yet this cycle.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
              for (final s in v.spendings) _SpendingRow(spending: s),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpendingRow extends StatelessWidget {
  const _SpendingRow({required this.spending});

  final Spending spending;

  @override
  Widget build(BuildContext context) {
    final c = context.read<BudgetController>();
    final label = spending.note ?? 'Spending';

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(formatShortDate(spending.spentOn), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          Text('-${formatSen(spending.amountSen)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          IconButton(
            tooltip: 'Delete $label, ${formatSen(spending.amountSen)}',
            icon: const Icon(Icons.delete_outline, size: 20),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete this spending?'),
                  content: Text('$label, ${formatSen(spending.amountSen)}. The money goes back into the envelope.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(foregroundColor: AppColors.dangerFg),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (yes != true) return;
              await c.deleteSpending(spending.id);
              if (context.mounted) showBillMessage(context, 'Deleted. ${formatSen(spending.amountSen)} is back.');
            },
          ),
        ],
      ),
    );
  }
}
