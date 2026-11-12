import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/dates.dart';
import '../core/theme.dart';
import '../providers/sync_controller.dart';

/// Sign in to keep your data the same on every phone.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Sync across devices')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          switch (sync.state) {
            SyncState.notConfigured => const _NotConfigured(),
            SyncState.signedOut => _signedOut(sync),
            _ => _signedIn(sync),
          },
        ],
      ),
    );
  }

  Widget _signedOut(SyncController sync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sign in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Use the same account on every phone to keep your bills, budget and spending the same everywhere. Bayar still works without a connection.',
              style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (sync.message != null) ...[
              const SizedBox(height: 12),
              Text(sync.message!, style: const TextStyle(fontSize: 13, color: AppColors.dangerFg)),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _run(() => sync.signUp(_email.text, _password.text)),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder()),
                    child: const Text('Create account'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _run(() => sync.signIn(_email.text, _password.text)),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: const StadiumBorder()),
                    child: const Text('Sign in'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(Future<bool> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  Widget _signedIn(SyncController sync) {
    final syncing = sync.state == SyncState.syncing;
    final last = sync.lastSynced;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Signed in as ${sync.email}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              syncing
                  ? 'Syncing...'
                  : last == null
                  ? 'Not synced yet.'
                  : 'Last synced ${formatShortDate(last)}, ${_clock(last)}.',
              style: const TextStyle(fontSize: 14, color: AppColors.muted),
            ),
            if (sync.state == SyncState.error && sync.message != null) ...[
              const SizedBox(height: 8),
              Text(sync.message!, style: const TextStyle(fontSize: 13, color: AppColors.dangerFg)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: syncing ? null : sync.syncNow,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              child: const Text('Sync now'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text(
                      'Your data stays on this phone. It just stops syncing until you sign in again.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sign out')),
                    ],
                  ),
                );
                if (yes == true) await sync.signOut();
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(DateTime t) {
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sync is not set up in this build', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text(
              'Bayar works fully on this phone without it. To keep several phones in step, build the app with your own Supabase project. The steps are in supabase/README.md.',
              style: TextStyle(fontSize: 14, color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row on the Plan tab that opens [SyncScreen] and shows its state.
class SyncTile extends StatelessWidget {
  const SyncTile({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncController>();
    final (icon, subtitle) = switch (sync.state) {
      SyncState.notConfigured => (Icons.cloud_off_outlined, 'Not set up in this build'),
      SyncState.signedOut => (Icons.cloud_outlined, 'Sign in to share data between phones'),
      SyncState.syncing => (Icons.cloud_sync_outlined, 'Syncing...'),
      SyncState.error => (Icons.cloud_off_outlined, 'Could not sync. Will retry.'),
      SyncState.idle => (Icons.cloud_done_outlined, 'Signed in as ${sync.email}'),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: AppColors.brand),
        title: const Text('Sync across devices', style: TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
      ),
    );
  }
}
