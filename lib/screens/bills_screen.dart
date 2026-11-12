import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../providers/bills_controller.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/bill_row.dart';
import 'bill_actions.dart';

class BillsScreen extends StatelessWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // watch = rebuild this screen whenever the controller calls notifyListeners().
    final c = context.watch<BillsController>();
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, bottomInset + 24),
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  // Debug builds only: long-press the title to fire a test notification.
                  onLongPress: kDebugMode ? () => context.read<ReminderCoordinator>().sendTest() : null,
                  child: Text(
                    'Bills',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => openBillForm(context),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add bill'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  shape: const StadiumBorder(),
                  backgroundColor: AppColors.brandTint,
                  foregroundColor: AppColors.brandDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryCard(controller: c),
          const SizedBox(height: 16),
          const _RemindersCard(),
          _FilterSwitch(current: c.filter, onChanged: c.setFilter),
          const SizedBox(height: 16),
          if (c.errorMessage != null) _Notice(c.errorMessage!),
          if (c.isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _BillList(controller: c),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.controller});

  final BillsController controller;

  @override
  Widget build(BuildContext context) {
    final overdue = controller.overdueCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Due in the next month', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            const SizedBox(height: 4),
            Text(formatSen(controller.toPaySen), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              overdue > 0
                  ? '$overdue overdue. Pay ${overdue == 1 ? 'it' : 'those'} first.'
                  : 'Nothing overdue. ${formatSen(controller.paidSen)} paid recently.',
              style: TextStyle(fontSize: 13, height: 1.35, color: overdue > 0 ? AppColors.dangerFg : AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for notification permission, in context, instead of at launch.
/// Disappears once reminders are on.
class _RemindersCard extends StatelessWidget {
  const _RemindersCard();

  @override
  Widget build(BuildContext context) {
    final reminders = context.watch<ReminderCoordinator>();
    if (reminders.isOn) return const SizedBox.shrink();

    final denied = reminders.permission == ReminderPermission.denied;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: denied ? AppColors.warnBg : AppColors.brandTint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              denied ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
              color: denied ? AppColors.warnFg : AppColors.brandDark,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    denied ? 'Reminders are off' : 'Get reminders',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: denied ? AppColors.warnFg : AppColors.brandDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    denied
                        ? 'Turn on notifications for Bayar in your phone Settings to get reminders.'
                        : 'Allow notifications so Bayar can remind you before each bill is due.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: denied ? AppColors.warnFg : AppColors.brandDark,
                    ),
                  ),
                  if (!denied) ...[
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: reminders.requestPermission,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        shape: const StadiumBorder(),
                        backgroundColor: AppColors.brand,
                      ),
                      child: const Text('Allow notifications'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSwitch extends StatelessWidget {
  const _FilterSwitch({required this.current, required this.onChanged});

  final BillFilter current;
  final ValueChanged<BillFilter> onChanged;

  static const _labels = {BillFilter.upcoming: 'Upcoming', BillFilter.paid: 'Paid', BillFilter.all: 'All'};

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          for (final entry in _labels.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == current,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(entry.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.key == current ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: entry.key == current
                          ? const [BoxShadow(color: Color(0x26101828), blurRadius: 2, offset: Offset(0, 1))]
                          : null,
                    ),
                    child: Text(entry.value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BillList extends StatelessWidget {
  const _BillList({required this.controller});

  final BillsController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.visible;

    if (items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _emptyText(controller),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(),
            BillRow(
              // Keyed by occurrence so Flutter keeps each row's identity when
              // the list reorders after a payment.
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

  String _emptyText(BillsController c) {
    if (!c.hasBills) return 'No bills yet. Tap "Add bill" to enter your first one.';
    switch (c.filter) {
      case BillFilter.upcoming:
        return 'Nothing left to pay in the next month.';
      case BillFilter.paid:
        return 'No payments recorded in the last ${BillsController.lookBackDays} days.';
      case BillFilter.all:
        return 'Nothing to show.';
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(12)),
        child: Text(message, style: const TextStyle(fontSize: 13, color: AppColors.dangerFg)),
      ),
    );
  }
}
