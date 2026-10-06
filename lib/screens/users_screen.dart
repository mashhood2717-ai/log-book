import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../models.dart';
import '../services/db.dart';
import '../widgets/animations.dart';
import '../widgets/brand.dart';
import '../widgets/trip_widgets.dart';

/// Admin: add drivers, reset passwords, block/unblock, make admin.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late Future<List<AppUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = Db.users();
  }

  Future<void> _reload() async {
    final f = Db.users();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {} // shown by the FutureBuilder
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Runs a backend call with a progress dialog; reloads the list on success.
  Future<bool> _run(Future<void> Function() call, String doneMsg) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await call();
      if (mounted) Navigator.pop(context); // progress
      _snack(doneMsg);
      _reload();
      return true;
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack(Db.friendlyError(e));
      return false;
    }
  }

  // ---------------- Add ----------------
  Future<void> _add() async {
    final result = await showDialog<_NewUser>(
        context: context, builder: (_) => const _AddUserDialog());
    if (result == null) return;
    final ok = await _run(
      () => Db.createUser(
        email: result.email,
        password: result.password,
        fullName: result.name,
        role: result.admin ? 'admin' : 'driver',
      ),
      '${result.name} added',
    );
    if (ok) await _showLogin(result.name, result.email, result.password);
  }

  /// After creating a user or resetting a password: show + share the login.
  Future<void> _showLogin(String name, String email, String password) {
    final text = '${AppConfig.appName} login for $name\n'
        'Email: $email\nPassword: $password';
    return showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Login details'),
        content: SelectableText('Email: $email\nPassword: $password\n\n'
            'Send these to $name. They can sign in straight away.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Done')),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Share'),
            onPressed: () => Share.share(text),
          ),
        ],
      ),
    );
  }

  // ---------------- Actions on one user ----------------
  Future<void> _actions(AppUser u) async {
    final self = u.id == Db.uid;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(u.displayName,
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(u.email),
          ),
          const Divider(height: 1),
          _sheetItem(c, 'name', Icons.edit, 'Change name'),
          _sheetItem(c, 'password', Icons.password, 'Reset password'),
          if (!self)
            _sheetItem(
                c,
                'role',
                u.isAdmin ? Icons.person : Icons.admin_panel_settings,
                u.isAdmin ? 'Make driver (remove admin)' : 'Make admin'),
          if (!self)
            _sheetItem(c, 'block', u.banned ? Icons.lock_open : Icons.block,
                u.banned ? 'Unblock – allow sign-in' : 'Block – stop sign-in'),
          if (!self)
            _sheetItem(c, 'delete', Icons.delete_outline, 'Delete',
                color: Theme.of(context).colorScheme.error),
        ]),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'name':
        final name = await _askText('Change name', 'Full name', u.fullName);
        if (name != null && name.isNotEmpty) {
          await _run(() => Db.updateUser(u.id, fullName: name), 'Name updated');
        }
      case 'password':
        final pw = await showDialog<String>(
            context: context,
            builder: (_) => _PasswordDialog(name: u.displayName));
        if (pw != null &&
            await _run(() => Db.updateUser(u.id, password: pw),
                'Password changed')) {
          await _showLogin(u.displayName, u.email, pw);
        }
      case 'role':
        final toAdmin = !u.isAdmin;
        if (await _confirm(
            toAdmin ? 'Make ${u.displayName} an admin?' : 'Remove admin rights?',
            toAdmin
                ? 'Admins can see all trips, manage vehicles and manage users.'
                : '${u.displayName} will only see their own trips.')) {
          await _run(
              () => Db.updateUser(u.id, role: toAdmin ? 'admin' : 'driver'),
              toAdmin ? '${u.displayName} is now an admin' : 'Admin rights removed');
        }
      case 'block':
        final block = !u.banned;
        if (await _confirm(
            block ? 'Block ${u.displayName}?' : 'Unblock ${u.displayName}?',
            block
                ? 'They will not be able to sign in. Their trips stay in the records.\n\n'
                    'If they are signed in right now, it can take up to an hour before they are logged out.'
                : 'They will be able to sign in again.')) {
          await _run(() => Db.updateUser(u.id, banned: block),
              block ? '${u.displayName} blocked' : '${u.displayName} unblocked');
        }
      case 'delete':
        if (await _confirm('Delete ${u.displayName}?',
            'This removes the login permanently. Only possible if they have no trips – otherwise use Block.',
            danger: true)) {
          await _run(() => Db.deleteUser(u.id), '${u.displayName} deleted');
        }
    }
  }

  Widget _sheetItem(BuildContext c, String value, IconData icon, String label,
          {Color? color}) =>
      ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color)),
        onTap: () => Navigator.pop(c, value),
      );

  Future<bool> _confirm(String title, String msg, {bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error)
                  : null,
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> _askText(String title, String label, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
  }

  // ---------------- List ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Drivers & users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add),
        label: const Text('Add driver'),
      ),
      body: FutureBuilder<List<AppUser>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text(Db.friendlyError(snap.error!),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: _reload, child: const Text('Retry')),
                ]),
              ),
            ]);
          }
          if (!snap.hasData) {
            return const Center(child: BrandLoader(label: 'Loading users…'));
          }
          final list = snap.data!;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.only(top: 6, bottom: 90),
              children: [
                for (final (i, u) in list.indexed)
                  FadeSlideIn(index: i, child: _tile(u)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tile(AppUser u) {
    final scheme = Theme.of(context).colorScheme;
    final self = u.id == Db.uid;
    final tags = [
      if (self) 'You',
      if (u.isAdmin) 'Admin',
      if (u.banned) 'Blocked',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              u.banned ? Colors.grey.shade300 : scheme.primaryContainer,
          child: Icon(
            u.banned
                ? Icons.block
                : (u.isAdmin ? Icons.admin_panel_settings : Icons.person),
            color: u.banned ? Colors.grey.shade700 : scheme.primary,
          ),
        ),
        title: Text(
          u.displayName + (tags.isEmpty ? '' : '  · ${tags.join(' · ')}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: u.banned ? Colors.grey.shade600 : null),
        ),
        subtitle: Text(
          '${u.email}\n'
          '${u.lastSignIn == null ? 'Never signed in' : 'Last sign-in ${dateFmt.format(u.lastSignIn!)}'}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.more_vert),
        onTap: () => _actions(u),
      ),
    );
  }
}

// ---------------- Dialogs ----------------

/// Easy-to-type password, e.g. "kite4827".
String _generatePassword() {
  const words = [
    'road', 'kite', 'lion', 'moon', 'rain', 'star', 'wind', 'tree',
    'gold', 'blue', 'fast', 'park', 'hill', 'lake', 'rock', 'bird',
  ];
  final r = Random.secure();
  return '${words[r.nextInt(words.length)]}${1000 + r.nextInt(9000)}';
}

class _NewUser {
  final String name, email, password;
  final bool admin;
  _NewUser(this.name, this.email, this.password, this.admin);
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();

  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController(text: _generatePassword());
  bool _admin = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add driver'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email (used to sign in)',
                  helperText: 'Any address – it does not need an inbox'),
              validator: (v) =>
                  (v == null || !RegExp(r'^\S+@\S+\.\S+$').hasMatch(v.trim()))
                      ? 'Enter a valid email'
                      : null,
            ),
            const SizedBox(height: 12),
            _PasswordField(controller: _password),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _admin,
              onChanged: (v) => setState(() => _admin = v ?? false),
              title: const Text('Admin'),
              subtitle: const Text('Can see all trips and manage users'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
                context,
                _NewUser(_name.text.trim(), _email.text.trim().toLowerCase(),
                    _password.text, _admin));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  final String name;
  const _PasswordDialog({required this.name});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController(text: _generatePassword());

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New password for ${widget.name}'),
      content: Form(key: _form, child: _PasswordField(controller: _password)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, _password.text);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Visible password field with a "new random password" button.
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  const _PasswordField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      decoration: InputDecoration(
        labelText: 'Password',
        helperText: 'At least 6 characters',
        suffixIcon: IconButton(
          tooltip: 'Make a new one',
          icon: const Icon(Icons.casino_outlined),
          onPressed: () => controller.text = _generatePassword(),
        ),
      ),
      validator: (v) =>
          (v == null || v.length < 6) ? 'At least 6 characters' : null,
    );
  }
}
