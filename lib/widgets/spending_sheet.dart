import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/amount_input.dart';
import '../core/dates.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/budget.dart';
import '../providers/budget_controller.dart';
import '../screens/bill_actions.dart';

/// The quick "I just spent money" sheet: type an amount, pick an envelope, save.
///
/// [envelopeId] preselects an envelope (from that envelope's own button).
Future<void> showSpendingSheet(BuildContext context, {String? envelopeId}) async {
  final message = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _SpendingSheet(initialEnvelopeId: envelopeId),
  );
  if (message != null && context.mounted) showBillMessage(context, message);
}

class _SpendingSheet extends StatefulWidget {
  const _SpendingSheet({this.initialEnvelopeId});

  final String? initialEnvelopeId;

  @override
  State<_SpendingSheet> createState() => _SpendingSheetState();
}

class _SpendingSheetState extends State<_SpendingSheet> {
  final _note = TextEditingController();
  String _keys = '';
  String? _envelopeId;
  bool _yesterday = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<BudgetController>();
    _envelopeId = c.envelopes.any((e) => e.id == widget.initialEnvelopeId)
        ? widget.initialEnvelopeId
        : (c.envelopes.isEmpty ? null : c.envelopes.first.id);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BudgetController>();
    final views = c.envelopeViews;
    final amount = AmountKeys.amountSenFromKeys(_keys);
    final selected = views.where((v) => v.envelope.id == _envelopeId).firstOrNull;
    final left = selected?.leftSen ?? 0;
    final over = selected != null && amount > 0 && amount > left;
    final recent = _envelopeId == null ? const <String>[] : c.recentNotes(_envelopeId!);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Add spending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('RM', style: TextStyle(fontSize: 20, color: AppColors.muted)),
                const SizedBox(width: 8),
                Text(
                  AmountKeys.display(_keys),
                  key: const ValueKey('amount'),
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w500, height: 1.1),
                ),
              ],
            ),
            SizedBox(
              height: 22,
              child: Text(
                selected == null || amount == 0
                    ? ''
                    : over
                    ? 'This is ${formatSen(amount - (left < 0 ? 0 : left))} over your ${selected.envelope.name} envelope.'
                    : '${selected.envelope.name} will have ${formatSen(left - amount)} left.',
                style: TextStyle(fontSize: 13, color: over ? AppColors.dangerFg : AppColors.muted),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < views.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _EnvelopeChoice(
                      view: views[i],
                      color: AppColors.envelope(i),
                      selected: views[i].envelope.id == _envelopeId,
                      onTap: () => setState(() => _envelopeId = views[i].envelope.id),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: !_yesterday,
                  onSelected: (_) => setState(() => _yesterday = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Yesterday'),
                  selected: _yesterday,
                  onSelected: (_) => setState(() => _yesterday = true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 40,
              decoration: const InputDecoration(hintText: 'Note (optional)', counterText: ''),
            ),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final note in recent)
                    ActionChip(label: Text(note), onPressed: () => setState(() => _note.text = note)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _Keypad(onKey: (key) => setState(() => _keys = AmountKeys.press(_keys, key))),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (amount > 0 && selected != null && !_saving) ? _save : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                backgroundColor: over ? AppColors.dangerFg : AppColors.brand,
              ),
              child: Text(
                amount == 0
                    ? 'Enter an amount'
                    : over
                    ? 'Save anyway'
                    : 'Save to ${selected?.envelope.name ?? 'envelope'}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final c = context.read<BudgetController>();
    final id = _envelopeId!;
    final today = c.today;
    final ok = await c.addSpending(
      envelopeId: id,
      amountSen: AmountKeys.amountSenFromKeys(_keys),
      spentOn: _yesterday ? addDays(today, -1) : today,
      note: _note.text,
    );
    if (!mounted) return;

    if (!ok) {
      setState(() => _saving = false);
      showBillMessage(context, 'Could not save. Please try again.');
      return;
    }
    final view = c.envelopeViews.firstWhere((v) => v.envelope.id == id);
    Navigator.pop(
      context,
      view.leftSen < 0
          ? '${view.envelope.name} is over budget by ${formatSen(-view.leftSen)}.'
          : '${view.envelope.name}: ${formatSen(view.leftSen)} left.',
    );
  }
}

class _EnvelopeChoice extends StatelessWidget {
  const _EnvelopeChoice({required this.view, required this.color, required this.selected, required this.onTap});

  final EnvelopeView view;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${view.envelope.name}, ${formatSen(view.leftSen)} left',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 96, minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.12) : Colors.white,
              border: Border.all(color: selected ? color : const Color(0xFFC9D0D8), width: selected ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(view.envelope.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(
                  '${formatSen(view.leftSen, symbol: false, decimals: false)} left',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});

  final ValueChanged<String> onKey;

  static const _keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', 'del'];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childAspectRatio: 2.6,
      children: [
        for (final key in _keys)
          Material(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => onKey(key),
              borderRadius: BorderRadius.circular(12),
              child: Semantics(
                button: true,
                label: key == 'del' ? 'Delete last digit' : (key == '.' ? 'Decimal point' : key),
                child: ExcludeSemantics(
                  child: Center(
                    child: key == 'del'
                        ? const Icon(Icons.backspace_outlined, size: 22)
                        : Text(key, style: const TextStyle(fontSize: 22)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
