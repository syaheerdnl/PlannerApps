import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/budget.dart';
import '../providers/bills_controller.dart';
import '../providers/budget_controller.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/bill_row.dart';
import '../widgets/envelope_widgets.dart';
import 'bill_actions.dart';

/// The first thing you see: what is left to pay, what is next, and quick actions.
/// It reads the same [BillsController] as the Bills tab, so the two always agree.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.selectedTab});

  /// Used to jump to the Bills tab.
  final ValueNotifier<int> selectedTab;

  static const billsTab = 1;
  static const envelopesTab = 2;
  static const planTab = 3;

  /// How many unpaid bills "Pay next" shows before pointing you to the full list.
  static const payNextCount = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BillsController>();
    final budget = context.watch<BudgetController>();
    final insets = MediaQuery.paddingOf(context);

    final unpaid = c.all.where((i) => !i.isPaid).toList();
    // c.all is oldest first, so reversing puts the latest payments on top.
    final recentlyPaid = c.all.where((i) => i.isPaid).toList().reversed.take(3).toList();

    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.only(bottom: insets.bottom + 24),
          children: [
            // A Stack only passes taps to children INSIDE its own bounds. So the
            // Stack is made 40 px taller than the header, and the quick-actions
            // card sits at its bottom edge: it overlaps the teal header by its
            // own height minus 40, and every part of it stays tappable.
            Stack(
              children: [
                Column(
                  children: [
                    _Header(
                      controller: c,
                      budget: budget,
                      unpaid: unpaid,
                      topInset: insets.top,
                      onOpenBills: () {
                        c.setFilter(BillFilter.upcoming);
                        selectedTab.value = billsTab;
                      },
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  child: _QuickActions(
                    onAdd: () => openBillForm(context),
                    onPay: () {
                      c.setFilter(BillFilter.upcoming);
                      selectedTab.value = billsTab;
                    },
                    onPaid: () {
                      c.setFilter(BillFilter.paid);
                      selectedTab.value = billsTab;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (budget.isSetUp) ...[
                    _SectionTitle(
                      'Envelopes',
                      trailing: TextButton(
                        onPressed: () => selectedTab.value = envelopesTab,
                        child: const Text('See all'),
                      ),
                    ),
                    _EnvelopeSummary(views: budget.envelopeViews.take(3).toList()),
                    const SizedBox(height: 24),
                  ] else ...[
                    _SetupCard(onSetUp: () => selectedTab.value = planTab),
                    const SizedBox(height: 24),
                  ],
                  _SectionTitle(
                    'Pay next',
                    trailing: unpaid.length > payNextCount
                        ? TextButton(
                            onPressed: () {
                              c.setFilter(BillFilter.upcoming);
                              selectedTab.value = billsTab;
                            },
                            child: Text('See all ${unpaid.length}'),
                          )
                        : null,
                  ),
                  _PayNext(controller: c, unpaid: unpaid),
                  if (recentlyPaid.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const _SectionTitle('Recently paid'),
                    _BillCard(controller: c, items: recentlyPaid),
                  ],
                ],
              ),
            ),
          ],
        ),
        // Keeps the strip behind the status bar teal while the list scrolls, so
        // the light status-bar icons always sit on a dark background.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: insets.top,
          child: const ColoredBox(color: AppColors.brand),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.budget,
    required this.unpaid,
    required this.topInset,
    required this.onOpenBills,
  });

  final BillsController controller;
  final BudgetController budget;
  final List<BillItem> unpaid;
  final double topInset;
  final VoidCallback onOpenBills;

  static const _soft = Color(0xE6FFFFFF);

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final overdue = c.overdueCount;
    final budgeted = budget.isSetUp;

    final String label;
    final String amount;
    final String sub;
    if (budgeted) {
      final days = budget.daysLeft;
      label = 'Left to spend';
      amount = formatSen(budget.leftToSpendSen);
      sub =
          '${formatSen(budget.dailySafeSen)} a day for $days ${days == 1 ? 'day' : 'days'} · payday ${formatShortDate(budget.nextPayday!)}';
    } else if (!c.hasBills) {
      label = 'Welcome to Bayar';
      amount = 'No bills yet';
      sub = 'Add your bills and subscriptions, and Bayar will tell you what to pay and when.';
    } else {
      label = 'Still to pay (next month)';
      amount = formatSen(c.toPaySen);
      sub = unpaid.isEmpty ? 'Everything is paid. Nice.' : _nextLine(unpaid.first, c.today);
    }

    return Container(
      width: double.infinity,
      color: AppColors.brand,
      // 80 = the card's overlap into the header (about 48) plus a 32 px gap.
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 20, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(formatShortDate(c.today), style: const TextStyle(fontSize: 14, color: _soft)),
              ),
              const _ReminderChip(),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 14, color: _soft)),
          const SizedBox(height: 2),
          Text(
            amount,
            style: TextStyle(
              fontSize: (budgeted || c.hasBills) ? 38 : 30,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (budgeted) ...[
            Text(sub, style: const TextStyle(fontSize: 13, height: 1.35, color: _soft)),
            const SizedBox(height: 12),
            _BillsPill(
              text: !c.hasBills
                  ? 'No bills yet'
                  : overdue > 0
                  ? '$overdue overdue. Pay ${overdue == 1 ? 'it' : 'those'} first.'
                  : unpaid.isEmpty
                  ? 'All bills paid'
                  : '${formatSen(c.toPaySen)} in bills still to pay',
              warn: overdue > 0,
              onTap: onOpenBills,
            ),
          ] else if (overdue > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$overdue overdue. Pay ${overdue == 1 ? 'it' : 'those'} first.',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.warnFg),
              ),
            )
          else
            Text(sub, style: const TextStyle(fontSize: 13, height: 1.35, color: _soft)),
        ],
      ),
    );
  }

  /// "Water is due today" / "Car loan is due tomorrow" / "Next: Car loan, Tue 17 Nov".
  static String _nextLine(BillItem next, DateTime today) {
    final name = next.occurrence.obligation.name;
    final days = next.occurrence.daysUntilDue(today);
    if (days == 0) return '$name is due today';
    if (days == 1) return '$name is due tomorrow';
    return 'Next: $name, ${formatShortDate(next.occurrence.dueDate)}';
  }
}

/// A tappable line in the header about bills, so money to spend and money owed sit side by side.
class _BillsPill extends StatelessWidget {
  const _BillsPill({required this.text, required this.warn, required this.onTap});

  final String text;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: warn ? AppColors.warnBg : const Color(0x29FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 16, color: warn ? AppColors.warnFg : Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: warn ? AppColors.warnFg : Colors.white,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: warn ? AppColors.warnFg : Colors.white),
          ],
        ),
      ),
    );
  }
}

/// Shows whether reminders are on, and lets you turn them on if you have not been asked yet.
class _ReminderChip extends StatelessWidget {
  const _ReminderChip();

  @override
  Widget build(BuildContext context) {
    final reminders = context.watch<ReminderCoordinator>();

    final IconData icon;
    final String text;
    VoidCallback? onTap;
    switch (reminders.permission) {
      case ReminderPermission.granted:
        icon = Icons.notifications_active_outlined;
        text = 'Reminders on';
      case ReminderPermission.needsAsk:
        icon = Icons.notifications_none;
        text = 'Turn on reminders';
        onTap = reminders.requestPermission;
      case ReminderPermission.denied:
        icon = Icons.notifications_off_outlined;
        text = 'Reminders off';
    }

    return Semantics(
      button: onTap != null,
      label: text,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: ConstrainedBox(
            // A 44 px tall touch target around a 32 px pill.
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              widthFactor: 1,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0x29FFFFFF), borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(text, style: const TextStyle(fontSize: 12, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onAdd, required this.onPay, required this.onPaid});

  final VoidCallback onAdd;
  final VoidCallback onPay;
  final VoidCallback onPaid;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shadowColor: const Color(0x33101828),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            Expanded(
              child: _Action(icon: Icons.add, label: 'Add bill', onTap: onAdd),
            ),
            Expanded(
              child: _Action(icon: Icons.receipt_long_outlined, label: 'Pay bills', onTap: onPay),
            ),
            Expanded(
              child: _Action(icon: Icons.check_circle_outline, label: 'Paid', onTap: onPaid),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.brandTint, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.brand, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _PayNext extends StatelessWidget {
  const _PayNext({required this.controller, required this.unpaid});

  final BillsController controller;
  final List<BillItem> unpaid;

  @override
  Widget build(BuildContext context) {
    if (!controller.hasBills) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Start with the bills you pay every month, like rent, phone or electricity.',
                style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => openBillForm(context),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44), shape: const StadiumBorder()),
                child: const Text('Add your first bill'),
              ),
            ],
          ),
        ),
      );
    }

    if (unpaid.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Nothing left to pay in the next month.',
            style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
          ),
        ),
      );
    }

    return _BillCard(controller: controller, items: unpaid.take(HomeScreen.payNextCount).toList());
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.controller, required this.items});

  final BillsController controller;
  final List<BillItem> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(),
            BillRow(
              key: ValueKey(items[i].occurrence.key),
              item: items[i],
              today: controller.today,
              onToggle: () => toggleBillPaid(context, controller, items[i]),
              onTap: () => openBillForm(context, existing: items[i].occurrence.obligation),
            ),
          ],
        ],
      ),
    );
  }
}

/// The first few envelopes, each with how much is left.
class _EnvelopeSummary extends StatelessWidget {
  const _EnvelopeSummary({required this.views});

  final List<EnvelopeView> views;

  @override
  Widget build(BuildContext context) {
    if (views.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('You have no envelopes yet. Add one on the Plan tab.', style: TextStyle(color: AppColors.muted)),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < views.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          views[i].envelope.name,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        formatSen(views[i].leftSen),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: views[i].leftSen < 0 ? AppColors.dangerFg : AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  EnvelopeBar(
                    fractionLeft: views[i].leftFraction,
                    color: views[i].leftSen < 0 ? AppColors.dangerFg : AppColors.envelope(i),
                    expectedLeft: views[i].budgetSen > 0 ? views[i].expectedLeftFraction : null,
                    height: 6,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    views[i].budgetSen == 0
                        ? 'No budget set'
                        : views[i].leftSen < 0
                        ? 'Over budget'
                        : '${formatSen(views[i].dailySafeSen)} a day · of ${formatSen(views[i].budgetSen, decimals: false)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown until payday and salary are entered.
class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.onSetUp});

  final VoidCallback onSetUp;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Set up your salary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Add your payday and salary to see how much you can spend each day, and split it into envelopes.',
              style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onSetUp,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44), shape: const StadiumBorder()),
              child: const Text('Set up salary'),
            ),
          ],
        ),
      ),
    );
  }
}
