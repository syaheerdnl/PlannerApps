import 'package:flutter/material.dart';

import '../core/money.dart';
import '../domain/obligation.dart';
import '../providers/bills_controller.dart';
import 'bill_form_screen.dart';

/// Things you can do to a bill from any screen. They live here, not inside one
/// screen, so Home and Bills behave exactly the same way.

/// A floating message that sits above the glass tab bar.
void showBillMessage(BuildContext context, String message, {SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      content: Text(message),
      action: action,
    ),
  );
}

/// Opens the add / edit form. When it closes with a message ("Car loan added.
/// Next due Tue 17 Nov."), shows that message here.
Future<void> openBillForm(BuildContext context, {Obligation? existing}) async {
  final message = await Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => BillFormScreen(existing: existing)));
  if (message == null || !context.mounted) return;
  showBillMessage(context, message);
}

/// Marks a bill paid (or undoes it) and says what happened, with an Undo.
Future<void> toggleBillPaid(BuildContext context, BillsController controller, BillItem item) async {
  final name = item.occurrence.obligation.name;
  final wasPaid = item.isPaid;

  if (wasPaid) {
    await controller.undoPaid(item);
  } else {
    await controller.markPaid(item);
  }

  // The widget may have left the screen while we waited for the database.
  if (!context.mounted) return;

  if (wasPaid) {
    showBillMessage(context, '$name is unpaid again.');
  } else {
    showBillMessage(
      context,
      '$name marked paid. ${formatSen(controller.toPaySen)} still to pay.',
      action: SnackBarAction(label: 'Undo', onPressed: () => controller.undoPaid(item)),
    );
  }
}
