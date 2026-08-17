import 'dart:ui';

import 'package:budget_ai/src/banking/bank_connection_service.dart';
import 'package:budget_ai/src/banking/bank_models.dart';
import 'package:budget_ai/src/finances/finances_screen.dart';
import 'package:budget_ai/src/helpers/app_theme.dart';
import 'package:budget_ai/src/helpers/responsive_info_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ConnectedBanksScreen extends StatefulWidget {
  const ConnectedBanksScreen({super.key});

  @override
  State<ConnectedBanksScreen> createState() => _ConnectedBanksScreenState();
}

class _ConnectedBanksScreenState extends State<ConnectedBanksScreen> {
  late Future<BankDashboardData> _dashboard;
  String? _busyConnection;
  bool _isLaunchingPlaid = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _dashboard = BankConnectionService.instance.dashboard();

  Future<void> _connect() async {
    final theme = Theme.of(context);
    final country = await ResponsiveInfoSheet.show<String>(
      context,
      title: 'Where is your bank?',
      headerIcon: Icon(
        CupertinoIcons.building_2_fill,
        color: AppTheme.readableOn(theme.colorScheme.primary),
        size: 28,
      ),
      gradientColors: [
        theme.colorScheme.primary,
        theme.colorScheme.primary.withValues(alpha: 0.78),
      ],
      contentWidgets: [
        Text(
          'Availability depends on Plaid product access.',
          style: AppTheme.bodySmall.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        for (final option in const {
          'GB': 'United Kingdom',
          'CA': 'Canada',
          'US': 'United States',
          'IE': 'Ireland',
          'FR': 'France',
          'DE': 'Germany',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pop(context, option.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.value,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      option.key,
                      style: AppTheme.bodySmall.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    if (country == null) return;
    if (!mounted) return;
    final now = DateTime.now();
    final importRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2, now.month, now.day),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month - 3, now.day),
        end: now,
      ),
      helpText: 'Choose history to import',
      saveText: 'Continue',
    );
    if (importRange == null) return;
    setState(() {
      _busyConnection = 'new';
      _isLaunchingPlaid = true;
    });
    try {
      await BankConnectionService.instance.connect(
        countryCode: country,
        importStart: importRange.start,
        importEnd: importRange.end,
        onLinkOpened: () {
          if (mounted) setState(() => _isLaunchingPlaid = false);
        },
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _busyConnection = null;
          _isLaunchingPlaid = false;
        });
      }
    }
  }

  Future<void> _sync(BankConnection connection) async {
    setState(() => _busyConnection = connection.id);
    try {
      final changes = await BankConnectionService.instance.sync(connection.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$changes bank changes synchronized.')),
      );
      setState(_reload);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyConnection = null);
    }
  }

  Future<void> _disconnect(BankConnection connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disconnect ${connection.institutionName}?'),
        content: const Text(
          'Previously imported entries stay in Budget AI. New bank updates will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyConnection = connection.id);
    try {
      await BankConnectionService.instance.disconnect(connection.id);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyConnection = null);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_isLaunchingPlaid,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('Connected Banks'),
              actions: [
                IconButton(
                  tooltip: 'Connect another bank',
                  onPressed: _busyConnection == null ? _connect : null,
                  icon: const Icon(CupertinoIcons.plus),
                ),
              ],
            ),
            body: FutureBuilder<BankDashboardData>(
              future: _dashboard,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                    error: snapshot.error,
                    onRetry: () => setState(_reload),
                  );
                }
                final data = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: () async => setState(_reload),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                    children: [
                      Text(
                        'YOUR BANKS',
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (data.connections.isEmpty)
                        _EmptyBanks(onConnect: _connect)
                      else ...[
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FinancesScreen(
                                title: 'All Bank Activity',
                                bankOnly: true,
                              ),
                            ),
                          ),
                          icon: const Icon(CupertinoIcons.rectangle_3_offgrid),
                          label: const Text('View combined finances'),
                        ),
                        const SizedBox(height: 10),
                        for (final connection in data.connections)
                          _ConnectionCard(
                            connection: connection,
                            busy: _busyConnection == connection.id,
                            onSync: () => _sync(connection),
                            onDisconnect: () => _disconnect(connection),
                            onOpenAccount: (account) => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FinancesScreen(
                                  connectionId: connection.id,
                                  accountId: account.id,
                                  title: account.name,
                                ),
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'SYNC HISTORY',
                        style: AppTheme.bodySmall.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (data.history.isEmpty)
                        const Text(
                          'No bank transactions have been synchronized yet.',
                        )
                      else
                        for (final record in data.history.take(30))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              child: Icon(CupertinoIcons.arrow_2_circlepath),
                            ),
                            title: Text(record.institutionName),
                            subtitle: Text(
                              '${record.added} added • ${record.modified} updated • ${record.removed} removed',
                            ),
                            trailing: Text(_shortDate(record.startedAt)),
                          ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_isLaunchingPlaid) const BankLaunchOverlay(),
        ],
      ),
    );
  }

  static String _shortDate(DateTime value) =>
      '${value.day}/${value.month}/${value.year}';
}

class BankLaunchOverlay extends StatelessWidget {
  const BankLaunchOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      key: const ValueKey('bank-connect-loading-overlay'),
      child: Material(
        color: Colors.transparent,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: ColoredBox(
              color: theme.colorScheme.scrim.withValues(alpha: 0.28),
              child: Center(
                child: Semantics(
                  label: 'Opening secure bank connection',
                  liveRegion: true,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: .25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .16),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                          strokeWidth: 2,
                          strokeCap: StrokeCap.round,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Opening Plaid',
                          style: AppTheme.headingSmall.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

BoxDecoration _bankCardDecoration(ThemeData theme) {
  return BoxDecoration(
    color: theme.colorScheme.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.18)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.16 : 0.05,
        ),
        blurRadius: 14,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.busy,
    required this.onSync,
    required this.onOpenAccount,
    required this.onDisconnect,
  });
  final BankConnection connection;
  final bool busy;
  final VoidCallback onSync;
  final ValueChanged<BankAccountSummary> onOpenAccount;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _bankCardDecoration(theme),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    connection.institutionName.substring(0, 1).toUpperCase(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connection.institutionName,
                        style: AppTheme.headingSmall,
                      ),
                      Text(
                        '${connection.accounts.length} account${connection.accounts.length == 1 ? '' : 's'} • ${connection.countryCode}',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sync now',
                  onPressed: busy ? null : onSync,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.arrow_2_circlepath),
                ),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'Bank actions',
              enabled: !busy,
              onSelected: (value) {
                if (value == 'disconnect') onDisconnect();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'disconnect',
                  child: Text('Disconnect bank'),
                ),
              ],
            ),
            if (connection.accounts.isNotEmpty) ...[
              const Divider(height: 24),
              for (final account in connection.accounts)
                InkWell(
                  onTap: () => onOpenAccount(account),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(CupertinoIcons.creditcard, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(account.name)),
                        Text(
                          [
                            if (account.currencyCode != null)
                              account.currencyCode!,
                            if (account.mask != null) '••${account.mask}',
                          ].join('  '),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyBanks extends StatelessWidget {
  const _EmptyBanks({required this.onConnect});
  final VoidCallback onConnect;
  @override
  Widget build(BuildContext context) => Container(
    decoration: _bankCardDecoration(Theme.of(context)),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(CupertinoIcons.building_2_fill, size: 38),
          const SizedBox(height: 12),
          const Text(
            'Bring your accounts together',
            style: AppTheme.headingSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Connect Revolut or another supported institution. Amounts and dates stay read-only; your notes and categories remain yours.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onConnect,
            icon: const Icon(CupertinoIcons.link),
            label: const Text('Connect a bank'),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle, size: 36),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    ),
  );
}
