import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/recurrence.dart';
import '../providers/bills_controller.dart';

/// One bill occurrence: date, name, status line, amount and a Mark paid / Undo button.
class BillRow extends StatelessWidget {
  const BillRow({
    super.key,
    required this.item,
    required this.today,
    required this.onToggle,
    required this.onTap,
    this.onDelete,
  });

  final BillItem item;
  final DateTime today;

  /// Mark paid / Undo.
  final VoidCallback onToggle;

  /// Tapping anywhere else on the row opens the bill for editing.
  final VoidCallback onTap;

  /// Swiping the row to the right shows a Delete panel; letting go past the threshold calls this.
  /// It asks the person to confirm and returns true if the bill was deleted. Null = no swipe.
  final Future<bool> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final occ = item.occurrence;
    final bill = occ.obligation;
    final tag = _tagFor(occ, paid: item.isPaid, today: today);
    final shownAmount = item.isPaid ? item.payment!.amountSen : bill.amountSen;
    final estimatePrefix = bill.isEstimate && !item.isPaid ? '~' : '';

    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  Text(
                    '${occ.dueDate.day}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.1),
                  ),
                  Text(monthAbbr(occ.dueDate), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle(occ, paid: item.isPaid, today: today),
                    style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.3),
                  ),
                  if (tag != null) ...[const SizedBox(height: 5), _Tag(tag)],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$estimatePrefix${formatSen(shownAmount)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Semantics(
                  button: true,
                  label: item.isPaid ? 'Undo payment for ${bill.name}' : 'Mark ${bill.name} as paid',
                  child: ExcludeSemantics(
                    child: _ToggleButton(paid: item.isPaid, onPressed: onToggle),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final delete = onDelete;
    if (delete == null) return row;

    // Swipe right (start to end) to reveal Delete. We answer "false" to confirmDismiss on purpose:
    // the row is not removed by the swipe itself, it disappears when the list reloads after a real
    // delete. Cancel therefore just springs the row back.
    return Dismissible(
      key: ValueKey('swipe-${occ.key}'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.35},
      confirmDismiss: (_) async {
        await delete();
        return false;
      },
      background: Container(
        color: AppColors.dangerFg,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Delete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      child: row,
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({required this.paid, required this.onPressed});

  final bool paid;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const shape = StadiumBorder();
    const padding = EdgeInsets.symmetric(horizontal: 14);
    const textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w500);
    const size = Size(0, 40);

    if (paid) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: size,
          padding: padding,
          shape: shape,
          textStyle: textStyle,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: Color(0xFFC9D0D8)),
        ),
        child: const Text('Undo'),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: size,
        padding: padding,
        shape: shape,
        textStyle: textStyle,
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
      child: const Text('Mark paid'),
    );
  }
}

class _TagStyle {
  const _TagStyle(this.text, this.bg, this.fg);
  final String text;
  final Color bg;
  final Color fg;
}

class _Tag extends StatelessWidget {
  const _Tag(this.style);

  final _TagStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        style.text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: style.fg),
      ),
    );
  }
}

/// "Due Thu 12 Nov, pay by today" / "Due 8 Nov, paid".
String _subtitle(Occurrence occ, {required bool paid, required DateTime today}) {
  final due = 'Due ${formatShortDate(occ.dueDate)}';
  if (paid) return '$due, paid';

  final parts = <String>[due];
  // Once the pay-by date has passed there is nothing left to tell you: the
  // tag ("Due today", "Overdue by 2 days") already says what matters.
  final daysToPayBy = daysBetween(today, occ.payBy);
  if (occ.obligation.payByBufferDays > 0 && daysToPayBy >= 0) {
    final when = switch (daysToPayBy) {
      0 => 'today',
      1 => 'tomorrow',
      _ => formatShortDate(occ.payBy),
    };
    parts.add('pay by $when');
  }
  if (occ.obligation.isEstimate) parts.add('estimate');
  return parts.join(', ');
}

_TagStyle? _tagFor(Occurrence occ, {required bool paid, required DateTime today}) {
  switch (occ.statusOn(today, paid: paid)) {
    case DueStatus.paid:
      return null;
    case DueStatus.overdue:
      final days = -occ.daysUntilDue(today);
      return _TagStyle(
        days == 1 ? 'Overdue by 1 day' : 'Overdue by $days days',
        AppColors.dangerBg,
        AppColors.dangerFg,
      );
    case DueStatus.payNow:
      final days = occ.daysUntilDue(today);
      if (days == 0) return const _TagStyle('Due today', AppColors.warnBg, AppColors.warnFg);
      if (days == 1) return const _TagStyle('Due tomorrow', AppColors.warnBg, AppColors.warnFg);
      return const _TagStyle('Time to pay', AppColors.brandTint, AppColors.brandDark);
    case DueStatus.upcoming:
      return null;
  }
}
