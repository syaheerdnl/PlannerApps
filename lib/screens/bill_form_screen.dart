import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/bill_text_parser.dart';
import '../domain/obligation.dart';
import '../domain/recurrence.dart';
import '../providers/bills_controller.dart';
import '../services/bill_scanner.dart';
import '../widgets/stepper_field.dart';
import 'bill_actions.dart';

/// Add a bill, or edit one when [existing] is given.
/// Pops with a short message on success, which the Bills screen shows.
class BillFormScreen extends StatefulWidget {
  const BillFormScreen({super.key, this.existing});

  final Obligation? existing;

  @override
  State<BillFormScreen> createState() => _BillFormScreenState();
}

class _BillFormScreenState extends State<BillFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  late Frequency _frequency;
  late int _interval;
  late DateTime _start;
  DateTime? _end;
  late int _buffer;
  late bool _estimate;

  String? _endError;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final today = context.read<BillsController>().today;

    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(text: e == null ? '' : formatSen(e.amountSen, symbol: false));
    _note = TextEditingController(text: e?.note ?? '');
    _frequency = e?.frequency ?? Frequency.monthly;
    _interval = e?.intervalCount ?? 1;
    _start = e?.startDate ?? today;
    _end = e?.endDate;
    _buffer = e?.payByBufferDays ?? 0;
    _estimate = e?.isEstimate ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repeats = _frequency != Frequency.once;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit bill' : 'New bill')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!_isEdit) ...[
              OutlinedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan a bill'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 16),
                child: Text(
                  'Fills in what it can read. The photo stays on your phone.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ),
            ],
            const _Label('Name'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              decoration: const InputDecoration(hintText: 'e.g. Car loan, Netflix, TNB'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
            ),
            const SizedBox(height: 20),
            const _Label('Amount'),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              // prefixText would stay hidden until the field is focused; a
              // prefixIcon is always visible.
              decoration: const InputDecoration(
                hintText: '0.00',
                prefixIcon: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: EdgeInsets.only(left: 16, right: 10),
                    child: Text(
                      'RM',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.muted),
                    ),
                  ),
                ),
                prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
              ),
              validator: (v) {
                final sen = parseSen(v ?? '');
                if (sen == null) return 'Enter an amount like 68 or 68.50';
                if (sen == 0) return 'The amount must be more than 0';
                return null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('The amount changes each month', style: TextStyle(fontSize: 15)),
              subtitle: const Text(
                'Shown with ~ so you know it is an estimate',
                style: TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              value: _estimate,
              onChanged: (v) => setState(() => _estimate = v),
            ),
            const SizedBox(height: 12),
            const _Label('Repeats'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<Frequency>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: Frequency.once, label: Text('Once')),
                  ButtonSegment(value: Frequency.weekly, label: Text('Weekly')),
                  ButtonSegment(value: Frequency.monthly, label: Text('Monthly')),
                  ButtonSegment(value: Frequency.yearly, label: Text('Yearly')),
                ],
                selected: {_frequency},
                onSelectionChanged: (s) => setState(() {
                  _frequency = s.first;
                  _endError = null;
                }),
              ),
            ),
            if (repeats) ...[
              const SizedBox(height: 12),
              StepperField(
                label: 'Every',
                valueText: '$_interval ${_unit()}',
                onMinus: _interval > 1 ? () => setState(() => _interval--) : null,
                onPlus: _interval < 24 ? () => setState(() => _interval++) : null,
              ),
            ],
            const SizedBox(height: 20),
            _DateField(
              label: _frequency == Frequency.once ? 'Due date' : 'First due date',
              valueText: formatDateWithYear(_start),
              helper: _frequency == Frequency.once
                  ? null
                  : 'The first payment you want to track. Earlier dates are ignored.',
              onTap: _pickStart,
            ),
            if (repeats) ...[
              const SizedBox(height: 16),
              _DateField(
                label: 'Last due date (optional)',
                valueText: _end == null ? 'Never ends' : formatDateWithYear(_end!),
                helper: _endError ?? 'Set this for a loan or plan that finishes.',
                helperIsError: _endError != null,
                onTap: _pickEnd,
                onClear: _end == null
                    ? null
                    : () => setState(() {
                        _end = null;
                        _endError = null;
                      }),
              ),
            ],
            const SizedBox(height: 12),
            _Preview(text: _previewText()),
            const SizedBox(height: 20),
            const _Label('Pay early'),
            StepperField(
              label: 'Days before due',
              valueText: _buffer == 0 ? 'On the day' : '$_buffer ${_buffer == 1 ? 'day' : 'days'}',
              onMinus: _buffer > 0 ? () => setState(() => _buffer--) : null,
              onPlus: _buffer < 14 ? () => setState(() => _buffer++) : null,
              minusLabel: 'Pay one day later',
              plusLabel: 'Pay one day earlier',
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _buffer == 0
                    ? 'You will be reminded on the due date.'
                    : 'Aim to pay by ${formatShortDate(addDays(_start, -_buffer))} for the first one.',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 20),
            const _Label('Note (optional)'),
            TextFormField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [LengthLimitingTextInputFormatter(120)],
              decoration: const InputDecoration(hintText: 'Account number, reminder to scan the bill...'),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: _saving ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete this bill'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.dangerFg,
                  side: const BorderSide(color: AppColors.dangerFg),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            child: Text(_isEdit ? 'Save changes' : 'Add bill'),
          ),
        ),
      ),
    );
  }

  String _unit() {
    final plural = _interval != 1;
    switch (_frequency) {
      case Frequency.weekly:
        return plural ? 'weeks' : 'week';
      case Frequency.monthly:
        return plural ? 'months' : 'month';
      case Frequency.yearly:
        return plural ? 'years' : 'year';
      case Frequency.once:
        return '';
    }
  }

  /// The next three real due dates for what is currently typed in. This calls
  /// the same recurrence engine the Bills screen uses.
  String _previewText() {
    final dates = dueDatesBetween(_draft(), _start, addDays(_start, 3000)).take(3).toList();
    if (dates.isEmpty) return 'No due dates with these settings.';
    return 'Due ${dates.map(formatDateWithYear).join(', ')}${_frequency == Frequency.once ? '' : ' ...'}';
  }

  /// A temporary Obligation built from the form, used only for the preview.
  Obligation _draft() {
    final now = DateTime.now().toUtc();
    return Obligation(
      id: 'preview',
      name: _name.text,
      amountSen: 0,
      frequency: _frequency,
      intervalCount: _interval,
      startDate: _start,
      endDate: _frequency == Frequency.once ? null : _end,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Photo of a bill -> text (on the phone) -> a guess at name, amount and due date.
  /// Only fills what it found, and never saves: the person checks the form first.
  Future<void> _scan() async {
    final source = await showModalBottomSheet<ScanSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ScanSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ScanSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final scanner = context.read<BillScanner>();
    final today = context.read<BillsController>().today;
    final messenger = ScaffoldMessenger.of(context);

    String message;
    try {
      final text = await scanner.readText(source);
      if (!mounted) return;
      if (text == null) return; // backed out of the camera or gallery
      final found = parseBillText(text, today: today);
      if (found.isEmpty) {
        message = 'Could not read a bill from that photo. Try a clearer one, or type it in.';
      } else {
        setState(() {
          if (found.name != null) _name.text = found.name!;
          if (found.amountSen != null) {
            _amount.text = formatSen(found.amountSen!, symbol: false).replaceAll(',', '');
          }
          if (found.dueDate != null) {
            _start = found.dueDate!;
            _endError = null;
          }
        });
        final what = [
          if (found.name != null) 'name',
          if (found.amountSen != null) 'amount',
          if (found.dueDate != null) 'due date',
        ];
        message = 'Filled in the ${what.join(', ')}. Please check before saving.';
      }
    } catch (_) {
      message = 'Could not open the photo. Check that Bayar may use the camera or photos.';
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'First due date',
    );
    if (picked == null) return;
    setState(() {
      _start = dateOnly(picked);
      _endError = null;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end ?? addDays(_start, 365),
      firstDate: _start,
      lastDate: DateTime(2100),
      helpText: 'Last due date',
    );
    if (picked == null) return;
    setState(() {
      _end = dateOnly(picked);
      _endError = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final repeats = _frequency != Frequency.once;
    if (repeats && _end != null && _end!.isBefore(_start)) {
      setState(() => _endError = 'The last due date must not be before the first.');
      return;
    }

    setState(() => _saving = true);
    final controller = context.read<BillsController>();

    final name = _name.text.trim();
    final amountSen = parseSen(_amount.text)!; // validated above
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final interval = repeats ? _interval : 1;
    final end = repeats ? _end : null;

    String? message;
    if (_isEdit) {
      final ok = await controller.updateBill(
        widget.existing!.copyWith(
          name: name,
          amountSen: amountSen,
          isEstimate: _estimate,
          frequency: _frequency,
          intervalCount: interval,
          startDate: _start,
          endDate: end,
          payByBufferDays: _buffer,
          note: note,
        ),
      );
      if (ok) message = '$name updated.';
    } else {
      final created = await controller.createBill(
        name: name,
        amountSen: amountSen,
        isEstimate: _estimate,
        frequency: _frequency,
        intervalCount: interval,
        startDate: _start,
        endDate: end,
        payByBufferDays: _buffer,
        note: note,
      );
      if (created != null) {
        final next = nextDueOnOrAfter(created, controller.today);
        message = next == null ? '$name added.' : '$name added. Next due ${formatShortDate(next)}.';
      }
    }

    if (!mounted) return;
    if (message != null) {
      Navigator.of(context).pop(message);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. Please try again.')));
    }
  }

  Future<void> _confirmDelete() async {
    final name = widget.existing!.name;
    final yes = await confirmDeleteBill(context, name);
    if (!yes || !mounted) return;

    setState(() => _saving = true);
    final ok = await context.read<BillsController>().deleteBill(widget.existing!.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop('$name deleted.');
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete. Please try again.')));
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.muted),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.valueText,
    required this.onTap,
    this.helper,
    this.helperIsError = false,
    this.onClear,
  });

  final String label;
  final String valueText;
  final String? helper;
  final bool helperIsError;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(label),
        Stack(
          alignment: Alignment.centerRight,
          children: [
            Semantics(
              button: true,
              label: '$label, $valueText',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: InputDecorator(
                  decoration: InputDecoration(
                    suffixIcon: onClear == null ? const Icon(Icons.calendar_today_outlined, size: 20) : null,
                  ),
                  child: Text(valueText, style: const TextStyle(fontSize: 16)),
                ),
              ),
            ),
            if (onClear != null)
              IconButton(onPressed: onClear, tooltip: 'Clear $label', icon: const Icon(Icons.close, size: 20)),
          ],
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              helper!,
              style: TextStyle(fontSize: 12, color: helperIsError ? AppColors.dangerFg : AppColors.muted),
            ),
          ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.brandTint, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.event_repeat, size: 18, color: AppColors.brandDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.brandDark)),
          ),
        ],
      ),
    );
  }
}
