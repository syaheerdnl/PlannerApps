import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/budget.dart';
import '../domain/pay_cycle.dart';
import '../providers/budget_controller.dart';
import '../widgets/stepper_field.dart';
import 'bill_actions.dart';
import 'sync_screen.dart';

/// Where you tell Bayar your payday and salary, and split the salary into envelopes.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  bool _editing = false;

  /// How much each +/- tap moves a budget: RM 50.
  static const _step = 5000;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BudgetController>();
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 20, 16, bottomInset + 24),
        children: [
          Text('Plan salary', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          if (!c.isSetUp || _editing)
            _SetupForm(
              initial: c.plan,
              onCancel: c.isSetUp ? () => setState(() => _editing = false) : null,
              onSaved: () => setState(() => _editing = false),
            )
          else
            ..._planBody(context, c),
          const SizedBox(height: 16),
          const SyncTile(),
        ],
      ),
    );
  }

  List<Widget> _planBody(BuildContext context, BudgetController c) {
    final cycle = c.planCycle!;
    final unassigned = c.unassignedSen;
    final rows = c.planRows;
    final arrives = cycle.start.isAfter(c.today);

    return [
      Text(
        'Pay cycle ${_short(cycle.start)} to ${_short(cycle.end)} · ${cycle.lengthDays} days',
        style: const TextStyle(fontSize: 13, color: AppColors.muted),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('This cycle')),
            ButtonSegment(value: true, label: Text('Next cycle')),
          ],
          selected: {c.planningNext},
          onSelectionChanged: (s) => c.setPlanningNext(s.first),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Salary ${arrives ? 'arrives' : 'arrived'} ${formatShortDate(cycle.start)}',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const SizedBox(height: 2),
              Text(formatSen(c.salarySen), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _AllocationBar(controller: c),
              const SizedBox(height: 12),
              _StatusPill(unassignedSen: unassigned),
              if (unassigned > 0 && rows.isNotEmpty) ...[
                const SizedBox(height: 10),
                PopupMenuButton<String>(
                  tooltip: 'Give the rest to an envelope',
                  onSelected: (id) {
                    c.adjustBudget(id, unassigned);
                  },
                  itemBuilder: (context) => [
                    for (final r in rows) PopupMenuItem(value: r.envelope.id, child: Text(r.envelope.name)),
                  ],
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.brand),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Give ${formatSen(unassigned)} to...',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: AppColors.brand),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => setState(() => _editing = true),
                child: const Text('Change salary or payday'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _BillsRow(amountSen: c.billsReservedSen),
            for (var i = 0; i < rows.length; i++) ...[
              const Divider(),
              _EnvelopeRow(
                key: ValueKey(rows[i].envelope.id),
                row: rows[i],
                color: AppColors.envelope(i),
                cycle: cycle,
                step: _step,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () async {
          final name = await _askText(context, title: 'New envelope', hint: 'e.g. Savings, Kids, Gym');
          if (name == null || !context.mounted) return;
          final ok = await c.addEnvelope(name);
          if (!context.mounted) return;
          showBillMessage(
            context,
            ok ? '$name added. Give it a budget above.' : 'Could not add "$name". Is the name already used?',
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add envelope'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
          foregroundColor: AppColors.brand,
          side: const BorderSide(color: AppColors.brand),
        ),
      ),
    ];
  }

  static String _short(DateTime d) => '${d.day} ${monthAbbr(d)}';
}

/// Payday and salary. Used the first time, and again from "Change salary or payday".
class _SetupForm extends StatefulWidget {
  const _SetupForm({required this.initial, required this.onSaved, this.onCancel});

  final PlanSettings? initial;
  final VoidCallback onSaved;
  final VoidCallback? onCancel;

  @override
  State<_SetupForm> createState() => _SetupFormState();
}

class _SetupFormState extends State<_SetupForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _salary;
  late int _payday;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final plan = widget.initial;
    _payday = plan?.paydayDay ?? 25;
    _salary = TextEditingController(text: plan == null ? '' : formatSen(plan.salarySen, symbol: false));
  }

  @override
  void dispose() {
    _salary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null ? 'Set up your salary' : 'Salary and payday',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Bayar splits your money into pay cycles, from one payday to the next.',
                style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text('Monthly take-home salary', style: TextStyle(fontSize: 13, color: AppColors.muted)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _salary,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixIcon: Center(
                    widthFactor: 1,
                    child: Padding(
                      padding: EdgeInsets.only(left: 16, right: 10),
                      child: Text(
                        'RM',
                        style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.muted),
                      ),
                    ),
                  ),
                  prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                ),
                validator: (v) {
                  final sen = parseSen(v ?? '');
                  if (sen == null) return 'Enter an amount like 3800 or 3800.50';
                  if (sen == 0) return 'The salary must be more than 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              StepperField(
                label: 'Payday is on day',
                valueText: '$_payday',
                onMinus: _payday > 1 ? () => setState(() => _payday--) : null,
                onPlus: _payday < 31 ? () => setState(() => _payday++) : null,
                minusLabel: 'Earlier payday',
                plusLabel: 'Later payday',
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _payday > 28
                      ? 'In shorter months it falls on the last day of the month.'
                      : 'Every month, on the $_payday${_suffix(_payday)}.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.onCancel != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : widget.onCancel,
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder()),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder()),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await context.read<BudgetController>().savePlan(paydayDay: _payday, salarySen: parseSen(_salary.text)!);
    if (!mounted) return;
    if (ok) {
      widget.onSaved();
    } else {
      setState(() => _saving = false);
      showBillMessage(context, 'Could not save. Please try again.');
    }
  }

  static String _suffix(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return 'th';
    return switch (n % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }
}

/// Salary split into bills, each envelope, and what is still unassigned.
class _AllocationBar extends StatelessWidget {
  const _AllocationBar({required this.controller});

  final BudgetController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final parts = <(int, Color)>[
      (c.billsReservedSen, const Color(0xFF3B4540)),
      for (var i = 0; i < c.planRows.length; i++) (c.planRows[i].budgetSen, AppColors.envelope(i)),
      if (c.unassignedSen > 0) (c.unassignedSen, AppColors.line),
    ].where((p) => p.$1 > 0).toList();

    return Semantics(
      label: 'How the salary is split between bills and envelopes',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          height: 10,
          child: parts.isEmpty
              ? const ColoredBox(color: AppColors.line)
              : Row(
                  children: [
                    for (final p in parts)
                      Expanded(
                        // Flex wants whole numbers: use sen, which already are.
                        flex: p.$1,
                        child: Container(color: p.$2, margin: const EdgeInsets.only(right: 1)),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.unassignedSen});

  final int unassignedSen;

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = unassignedSen == 0
        ? ('Every ringgit has a job.', AppColors.brandTint, AppColors.brandDark)
        : unassignedSen > 0
        ? ('${formatSen(unassignedSen)} is not assigned yet.', AppColors.warnBg, AppColors.warnFg)
        : (
            'You have given out ${formatSen(-unassignedSen)} more than your salary.',
            AppColors.dangerBg,
            AppColors.dangerFg,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg, height: 1.3),
      ),
    );
  }
}

class _BillsRow extends StatelessWidget {
  const _BillsRow({required this.amountSen});

  final int amountSen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: const Color(0xFF3B4540), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bills and subscriptions', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                Text('Set aside first, from your Bills tab', style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          Text(formatSen(amountSen), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _EnvelopeRow extends StatelessWidget {
  const _EnvelopeRow({super.key, required this.row, required this.color, required this.cycle, required this.step});

  final PlanRow row;
  final Color color;
  final PayCycle cycle;
  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.read<BudgetController>();
    final name = row.envelope.name;
    final perDay = (row.budgetSen / cycle.lengthDays).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: 'Options for $name',
              onSelected: (choice) => choice == 'rename' ? _rename(context, c) : _delete(context, c),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 20, color: AppColors.muted),
                      ],
                    ),
                    Text(
                      'about ${formatSen(perDay)} a day',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: row.budgetSen > 0 ? () => c.adjustBudget(row.envelope.id, -step) : null,
            tooltip: 'Decrease $name by RM 50',
            icon: const Icon(Icons.remove, size: 20),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            style: IconButton.styleFrom(side: const BorderSide(color: Color(0xFFC9D0D8))),
          ),
          InkWell(
            onTap: () => _enterAmount(context, c),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 76,
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              child: Text(
                formatSen(row.budgetSen, symbol: false, decimals: false),
                key: ValueKey('budget-$name'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          IconButton(
            onPressed: () => c.adjustBudget(row.envelope.id, step),
            tooltip: 'Increase $name by RM 50',
            icon: const Icon(Icons.add, size: 20),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            style: IconButton.styleFrom(side: const BorderSide(color: Color(0xFFC9D0D8))),
          ),
        ],
      ),
    );
  }

  Future<void> _enterAmount(BuildContext context, BudgetController c) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _InputDialog(
        title: '${row.envelope.name} budget',
        initial: row.budgetSen == 0 ? '' : formatSen(row.budgetSen, symbol: false),
        money: true,
      ),
    );
    if (text != null) await c.setBudget(row.envelope.id, parseSen(text) ?? 0);
  }

  Future<void> _rename(BuildContext context, BudgetController c) async {
    final name = await _askText(context, title: 'Rename envelope', initial: row.envelope.name);
    if (name == null || !context.mounted) return;
    final ok = await c.renameEnvelope(row.envelope.id, name);
    if (!context.mounted) return;
    showBillMessage(context, ok ? 'Renamed to $name.' : 'Could not rename. Is "$name" already used?');
  }

  Future<void> _delete(BuildContext context, BudgetController c) async {
    final name = row.envelope.name;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text('Its budget and spending history will be hidden too.'),
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
    await c.deleteEnvelope(row.envelope.id);
    if (context.mounted) showBillMessage(context, '$name deleted.');
  }
}

/// A small dialog with one text field. Returns the trimmed text, or null if cancelled or empty.
Future<String?> _askText(BuildContext context, {required String title, String? initial, String? hint}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _InputDialog(title: title, initial: initial, hint: hint),
  );
  final clean = result?.trim();
  return (clean == null || clean.isEmpty) ? null : clean;
}

/// A dialog with one text field that OWNS its controller.
///
/// The controller must live as long as the dialog is on screen, including while
/// it fades out. Disposing it right after showDialog() returns (as an earlier
/// version did) throws "used after being disposed" during that animation.
class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.title, this.initial, this.hint, this.money = false});

  final String title;
  final String? initial;
  final String? hint;

  /// A money field: digits and a decimal point only, with an "RM" prefix.
  final bool money;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: widget.money ? TextCapitalization.none : TextCapitalization.words,
        keyboardType: widget.money ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        inputFormatters: widget.money
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
            : [LengthLimitingTextInputFormatter(24)],
        decoration: InputDecoration(
          hintText: widget.hint ?? (widget.money ? '0' : null),
          prefixText: widget.money ? 'RM ' : null,
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Save')),
      ],
    );
  }
}
