import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_notice.dart';
import '../../core/theme.dart';

class PlatformAdminData {
  const PlatformAdminData._();

  static List<PlatformAdminAccount> accountsFromRpc(dynamic response) {
    final rows = response is List
        ? response
        : response is Map && response['accounts'] is List
            ? response['accounts'] as List
            : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => PlatformAdminAccount.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList();
  }

  static List<PlatformAdminAuditEntry> auditFromRpc(dynamic response) {
    final rows = response is List
        ? response
        : response is Map && response['audit'] is List
            ? response['audit'] as List
            : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => PlatformAdminAuditEntry.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList();
  }
}

class PlatformAdminAccount {
  final String ownerEmail;
  final int outletCount;
  final int proOutletCount;
  final int cloudOutletCount;
  final String planCode;
  final DateTime? cloudExpiry;
  final DateTime? lastChangedAt;
  final List<PlatformAdminOutlet> outlets;

  const PlatformAdminAccount({
    required this.ownerEmail,
    required this.outletCount,
    required this.proOutletCount,
    required this.cloudOutletCount,
    required this.planCode,
    required this.cloudExpiry,
    required this.lastChangedAt,
    required this.outlets,
  });

  factory PlatformAdminAccount.fromJson(Map<String, dynamic> json) {
    final rawOutlets = json['outlets'] as List? ?? const [];
    return PlatformAdminAccount(
      ownerEmail: json['owner_email'] as String? ?? 'Email tidak diketahui',
      outletCount: _asInt(json['outlet_count']),
      proOutletCount: _asInt(json['pro_outlet_count']),
      cloudOutletCount: _asInt(json['cloud_outlet_count']),
      planCode: (json['plan_code'] as String? ?? 'FREE').toUpperCase(),
      cloudExpiry: _asDate(json['cloud_expiry']),
      lastChangedAt: _asDate(json['last_changed_at']),
      outlets: rawOutlets
          .whereType<Map>()
          .map((row) => PlatformAdminOutlet.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .toList(),
    );
  }

  String get planLabel => switch (planCode) {
        'CLOUD' => 'Cloud',
        'PRO' => 'Pro',
        'MIXED' => 'Campuran',
        _ => 'Free',
      };
}

class PlatformAdminOutlet {
  final String id;
  final String name;
  final String licenseKey;
  final DateTime? licenseExpiry;
  final DateTime? cloudExpiry;

  const PlatformAdminOutlet({
    required this.id,
    required this.name,
    required this.licenseKey,
    required this.licenseExpiry,
    required this.cloudExpiry,
  });

  factory PlatformAdminOutlet.fromJson(Map<String, dynamic> json) =>
      PlatformAdminOutlet(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Outlet',
        licenseKey: (json['license_key'] as String? ?? 'FREE').toUpperCase(),
        licenseExpiry: _asDate(json['license_expiry']),
        cloudExpiry: _asDate(json['cloud_expiry']),
      );
}

class PlatformAdminAuditEntry {
  final String? actorEmail;
  final String ownerEmail;
  final List<dynamic> previousState;
  final List<dynamic> nextState;
  final String? reason;
  final DateTime? createdAt;

  const PlatformAdminAuditEntry({
    required this.actorEmail,
    required this.ownerEmail,
    required this.previousState,
    required this.nextState,
    required this.reason,
    required this.createdAt,
  });

  factory PlatformAdminAuditEntry.fromJson(Map<String, dynamic> json) =>
      PlatformAdminAuditEntry(
        actorEmail: json['actor_email'] as String?,
        ownerEmail: json['owner_email'] as String? ?? 'Email tidak diketahui',
        previousState: json['previous_state'] as List? ?? const [],
        nextState: json['next_state'] as List? ?? const [],
        reason: json['reason'] as String?,
        createdAt: _asDate(json['created_at']),
      );

  String get nextPlan {
    if (nextState.isEmpty) return 'Tidak diketahui';
    final outlets = nextState.whereType<Map>().toList();
    final pro = outlets.where((outlet) {
      final license = (outlet['license_key']?.toString() ?? '').toUpperCase();
      return license.startsWith('PRO');
    }).length;
    final cloud = outlets.where((outlet) {
      final expiry = _asDate(outlet['cloud_expiry']);
      return expiry != null && expiry.isAfter(DateTime.now());
    }).length;
    if (pro == 0) return 'Free';
    if (pro == outlets.length && cloud == outlets.length) return 'Cloud';
    if (pro == outlets.length) return 'Pro';
    return 'Campuran';
  }
}

class PlatformAdminPage extends StatefulWidget {
  final List<PlatformAdminAccount> accounts;
  final List<PlatformAdminAuditEntry> audit;
  final VoidCallback onRefresh;
  final Future<void> Function({
    required String ownerEmail,
    required String planCode,
    required DateTime? cloudExpiry,
    required String reason,
  }) onSetEntitlement;

  const PlatformAdminPage({
    super.key,
    required this.accounts,
    required this.audit,
    required this.onRefresh,
    required this.onSetEntitlement,
  });

  @override
  State<PlatformAdminPage> createState() => _PlatformAdminPageState();
}

class _PlatformAdminPageState extends State<PlatformAdminPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _busyEmail;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PlatformAdminAccount> get _filteredAccounts {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.accounts;
    return widget.accounts
        .where((account) => account.ownerEmail.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _editAccount(PlatformAdminAccount account) async {
    final change = await showDialog<_EntitlementChange>(
      context: context,
      builder: (_) => _EntitlementDialog(account: account),
    );
    if (change == null || !mounted) return;
    setState(() => _busyEmail = account.ownerEmail);
    try {
      await widget.onSetEntitlement(
        ownerEmail: account.ownerEmail,
        planCode: change.planCode,
        cloudExpiry: change.cloudExpiry,
        reason: change.reason,
      );
      if (!mounted) return;
      AppNotice.show(context,
        SnackBar(content: Text('Paket ${account.ownerEmail} sudah diperbarui.')),
      );
    } catch (_) {
      if (!mounted) return;
      AppNotice.show(context,
        const SnackBar(
          content: Text('Perubahan belum tersimpan. Coba lagi.'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyEmail = null);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        color: AppTheme.surface,
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 40,
        ),
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Akun & paket',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Atur akses Free, Pro, dan Cloud seluruh akun Sajia.',
                              style: TextStyle(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Muat ulang akun',
                        onPressed: widget.onRefresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _AdminInfoCard(onRefresh: widget.onRefresh),
                  const SizedBox(height: 24),
                  _AdminMetrics(accounts: widget.accounts),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      labelText: 'Cari email owner',
                      prefixIcon: Icon(Icons.search_rounded),
                      suffixIcon: Icon(Icons.filter_alt_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_filteredAccounts.isEmpty)
                    const _AdminEmptyState()
                  else
                    for (final account in _filteredAccounts) ...[
                      _AdminAccountCard(
                        account: account,
                        busy: _busyEmail == account.ownerEmail,
                        onEdit: () => _editAccount(account),
                      ),
                      const SizedBox(height: 12),
                    ],
                  if (widget.audit.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Aktivitas entitlement terbaru',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    _AdminAuditCard(entries: widget.audit),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _AdminInfoCard extends StatelessWidget {
  final VoidCallback onRefresh;
  const _AdminInfoCard({required this.onRefresh});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withValues(alpha: .18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.admin_panel_settings_outlined,
                color: AppTheme.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Perubahan hanya bisa dilakukan admin platform dan otomatis masuk audit log. '
                'Cloud akan aktif untuk semua outlet akun sampai tanggal yang dipilih.',
                style: TextStyle(height: 1.45),
              ),
            ),
            TextButton(onPressed: onRefresh, child: const Text('Refresh')),
          ],
        ),
      );
}

class _AdminMetrics extends StatelessWidget {
  final List<PlatformAdminAccount> accounts;
  const _AdminMetrics({required this.accounts});

  @override
  Widget build(BuildContext context) {
    final free = accounts.where((account) => account.planCode == 'FREE').length;
    final pro = accounts.where((account) => account.planCode == 'PRO').length;
    final cloud = accounts.where((account) => account.planCode == 'CLOUD').length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 24) / 4;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AdminMetric(label: 'Akun', value: '${accounts.length}', icon: Icons.people_alt_outlined, width: width),
            _AdminMetric(label: 'Free', value: '$free', icon: Icons.sell_outlined, width: width),
            _AdminMetric(label: 'Pro', value: '$pro', icon: Icons.workspace_premium_outlined, width: width),
            _AdminMetric(label: 'Cloud', value: '$cloud', icon: Icons.cloud_done_outlined, width: width),
          ],
        );
      },
    );
  }
}

class _AdminMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final double width;

  const _AdminMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.width,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width < 170 ? (width * 2) + 8 : width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.primary),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _AdminAccountCard extends StatelessWidget {
  final PlatformAdminAccount account;
  final bool busy;
  final VoidCallback onEdit;

  const _AdminAccountCard({
    required this.account,
    required this.busy,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (account.planCode) {
      'CLOUD' => AppTheme.success,
      'PRO' => AppTheme.primary,
      _ => AppTheme.warning,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.ownerEmail,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  '${account.outletCount} outlet · ${account.proOutletCount} Pro · ${account.cloudOutletCount} Cloud',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                if (account.cloudExpiry != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Cloud s/d ${DateFormat('d MMM y', 'id_ID').format(account.cloudExpiry!)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            );
            final status = Chip(
              label: Text(account.planLabel),
              avatar: Icon(
                account.planCode == 'CLOUD'
                    ? Icons.cloud_done_outlined
                    : account.planCode == 'PRO'
                        ? Icons.workspace_premium_outlined
                        : Icons.sell_outlined,
                size: 16,
                color: color,
              ),
              side: BorderSide(color: color.withValues(alpha: .28)),
              labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
              backgroundColor: color.withValues(alpha: .08),
            );
            final action = FilledButton.tonalIcon(
              onPressed: busy ? null : onEdit,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined, size: 17),
              label: Text(busy ? 'Menyimpan...' : 'Ubah paket'),
            );
            if (constraints.maxWidth < 600) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [Expanded(child: details), status]),
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: details),
                status,
                const SizedBox(width: 14),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminAuditCard extends StatelessWidget {
  final List<PlatformAdminAuditEntry> entries;
  const _AdminAuditCard({required this.entries});

  @override
  Widget build(BuildContext context) => Card(
        child: Column(
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppTheme.primaryLight,
                  child: Icon(Icons.history_rounded, color: AppTheme.primary),
                ),
                title: Text('${entries[index].ownerEmail} → ${entries[index].nextPlan}'),
                subtitle: Text(
                  '${entries[index].actorEmail ?? 'Admin'}${entries[index].reason == null ? '' : ' · ${entries[index].reason}'}\n${_dateTimeLabel(entries[index].createdAt)}',
                ),
                isThreeLine: true,
              ),
              if (index < entries.length - 1)
                const Divider(height: 1, indent: 72),
            ],
          ],
        ),
      );
}

class _AdminEmptyState extends StatelessWidget {
  const _AdminEmptyState();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: Text(
              'Belum ada akun owner yang cocok dengan pencarian.',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ),
      );
}

class _EntitlementChange {
  final String planCode;
  final DateTime? cloudExpiry;
  final String reason;

  const _EntitlementChange({
    required this.planCode,
    required this.cloudExpiry,
    required this.reason,
  });
}

class _EntitlementDialog extends StatefulWidget {
  final PlatformAdminAccount account;
  const _EntitlementDialog({required this.account});

  @override
  State<_EntitlementDialog> createState() => _EntitlementDialogState();
}

class _EntitlementDialogState extends State<_EntitlementDialog> {
  late String _planCode;
  late DateTime? _cloudExpiry;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _planCode = switch (widget.account.planCode) {
      'CLOUD' => 'CLOUD',
      'PRO' => 'PRO',
      _ => 'FREE',
    };
    _cloudExpiry = widget.account.cloudExpiry ??
        DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickCloudExpiry() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _cloudExpiry != null && _cloudExpiry!.isAfter(today)
          ? _cloudExpiry!
          : today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: DateTime(today.year + 10),
      helpText: 'Pilih akhir masa Cloud',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked != null) {
      setState(() => _cloudExpiry = DateTime(
            picked.year,
            picked.month,
            picked.day,
            23,
            59,
            59,
          ));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ubah paket akun'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.account.ownerEmail,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _planCode,
                  decoration: const InputDecoration(labelText: 'Paket'),
                  items: const [
                    DropdownMenuItem(value: 'FREE', child: Text('Free')),
                    DropdownMenuItem(value: 'PRO', child: Text('Pro')),
                    DropdownMenuItem(value: 'CLOUD', child: Text('Cloud')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _planCode = value);
                  },
                ),
                if (_planCode == 'CLOUD') ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _pickCloudExpiry,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_cloudExpiry == null
                        ? 'Pilih tanggal Cloud'
                        : 'Cloud sampai ${DateFormat('d MMM y', 'id_ID').format(_cloudExpiry!)}'),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cloud akan aktif untuk semua outlet akun ini.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _reasonController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Alasan (opsional)',
                    hintText: 'Contoh: aktivasi manual setelah pembayaran transfer',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: _planCode == 'CLOUD' && _cloudExpiry == null
                ? null
                : () => Navigator.of(context).pop(
                      _EntitlementChange(
                        planCode: _planCode,
                        cloudExpiry: _planCode == 'CLOUD' ? _cloudExpiry : null,
                        reason: _reasonController.text,
                      ),
                    ),
            child: const Text('Simpan perubahan'),
          ),
        ],
      );
}

int _asInt(dynamic value) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? 0;

DateTime? _asDate(dynamic value) => DateTime.tryParse(value?.toString() ?? '');

String _dateTimeLabel(DateTime? date) => date == null
    ? 'Waktu tidak diketahui'
    : DateFormat('d MMM y, HH.mm', 'id_ID').format(date.toLocal());
