import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/widgets/sevo/sevo_animated_card.dart';
import '../../../../shared/widgets/sevo/sevo_controls.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';
import '../../../../shared/widgets/sevo/sevo_module_scaffold.dart';
import '../../../../shared/widgets/sevo/sevo_search_field.dart';
import '../../../../shared/widgets/sevo/sevo_skeleton.dart';
import '../../../../shared/widgets/sevo/sevo_state_views.dart';
import '../../../../shared/widgets/sevo/sevo_typography.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../data/service_providers_repository.dart';
import '../domain/service_provider.dart';

/// Platform Governance › Service Providers (Web `AdminServiceProvidersPage`):
/// search + status filter, provider cards, an Inspect dossier and Create.
class ServiceProvidersScreen extends ConsumerStatefulWidget {
  const ServiceProvidersScreen({super.key});

  @override
  ConsumerState<ServiceProvidersScreen> createState() =>
      _ServiceProvidersScreenState();
}

class _ServiceProvidersScreenState
    extends ConsumerState<ServiceProvidersScreen> {
  final _search = TextEditingController();
  String _status = 'all'; // all | active | inactive
  List<ServiceProvider> _providers = const [];
  bool _loading = true;
  String? _error;
  bool _unavailable = false;
  String? _flash;
  int _seq = 0;

  bool get _isSuperAdmin =>
      ref.read(authControllerProvider).user?.isSuperAdmin == true;

  @override
  void initState() {
    super.initState();
    if (_isSuperAdmin) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      _unavailable = false;
    });
    try {
      final rows = await ref
          .read(serviceProvidersRepositoryProvider)
          .list(
            q: _search.text,
            isActive: _status == 'all' ? null : _status == 'active',
          );
      if (mounted && seq == _seq) {
        setState(() {
          _providers = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _loading = false;
          _error = e is ServiceProvidersException
              ? e.message
              : 'Failed to load service providers.';
          _unavailable = e is ServiceProvidersException && e.unavailable;
        });
      }
    }
  }

  void _setStatus(String v) {
    if (v == _status) return;
    setState(() => _status = v);
    _load();
  }

  Future<void> _create() async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (_) => const _CreateProviderSheet(),
    );
    if (message != null && mounted) {
      setState(
        () => _flash = message.isEmpty
            ? 'Service Provider and Primary Admin created successfully.'
            : message,
      );
      await _load();
    }
  }

  void _inspect(ServiceProvider p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) => _ProviderDossier(
        provider: p,
        onViewTechnicians: () {
          Navigator.of(ctx).pop();
          context.go('${AppRoutes.superAdminWorkforce}?vendor_id=${p.id}');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _isSuperAdmin;
    return SevoModuleScaffold(
      module: SevoModule.serviceProviders,
      title: 'Service Providers',
      subtitle: 'Govern partner organizations',
      ready: !_loading,
      onRefresh: allowed ? _load : null,
      heroTrailing: allowed
          ? IconButton.filled(
              icon: const Icon(Icons.add_rounded, size: 22),
              color: Colors.white,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.16),
              ),
              tooltip: 'Create Service Provider',
              onPressed: _create,
            )
          : null,
      heroBottom: allowed
          ? SevoSearchField(
              controller: _search,
              hint: 'Search providers or display ID...',
              onChanged: (_) => _load(),
            )
          : null,
      children: allowed ? _body() : const [_AccessRequired()],
    );
  }

  List<Widget> _body() {
    return [
      if (_flash != null) ...[
        _FlashBanner(
          message: _flash!,
          onClose: () => setState(() => _flash = null),
        ),
        const SizedBox(height: 12),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SevoFilterChip(
            label: 'All Statuses',
            selected: _status == 'all',
            onTap: () => _setStatus('all'),
          ),
          SevoFilterChip(
            label: 'Active Only',
            selected: _status == 'active',
            onTap: () => _setStatus('active'),
          ),
          SevoFilterChip(
            label: 'Inactive Only',
            selected: _status == 'inactive',
            onTap: () => _setStatus('inactive'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      if (_loading)
        const SevoListSkeleton(count: 3)
      else if (_error != null)
        SevoErrorState(message: _error!, onRetry: _load, offline: !_unavailable)
      else if (_providers.isEmpty)
        SevoEmptyState(
          module: SevoModule.serviceProviders,
          title: 'No Service Providers Found',
          message: _search.text.isNotEmpty
              ? 'No providers match your search query. Try clearing filters.'
              : 'Tap + above to add the first service provider and primary admin.',
          actionLabel: _search.text.isEmpty ? 'Create Service Provider' : null,
          onAction: _search.text.isEmpty ? _create : null,
        )
      else
        for (var i = 0; i < _providers.length; i++)
          _ProviderCard(
            index: i,
            provider: _providers[i],
            onInspect: () => _inspect(_providers[i]),
          ),
    ];
  }
}

class _AccessRequired extends StatelessWidget {
  const _AccessRequired();

  @override
  Widget build(BuildContext context) {
    return const SevoEmptyState(
      module: SevoModule.serviceProviders,
      title: 'Superadmin Access Required',
      message: 'Only platform Superadministrators have authority to manage and create Service Providers.',
    );
  }
}

class _FlashBanner extends StatelessWidget {
  const _FlashBanner({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.successBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: AppColors.successText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: SevoText.caption.copyWith(color: AppColors.successText),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.successText,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.index,
    required this.provider,
    required this.onInspect,
  });

  final int index;
  final ServiceProvider provider;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final admin = p.primaryAdmin;
    return SevoAnimatedCard(
      index: index,
      margin: const EdgeInsets.only(bottom: 14),
      onTap: onInspect,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.home_repair_service_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.companyName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.cardTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        p.identifier,
                        if ((p.industry ?? '').isNotEmpty) p.industry!,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SevoText.meta,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SevoBadge(
                label: p.isActive ? 'Active' : 'Inactive',
                tone: p.isActive ? SevoTone.success : SevoTone.neutral,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (admin != null) ...[
            _line(
              Icons.person_outline_rounded,
              admin.displayName,
              strong: true,
            ),
            _line(
              Icons.mail_outline_rounded,
              (admin.email ?? '').isEmpty ? 'No email' : admin.email!,
            ),
          ] else
            _line(Icons.person_off_outlined, 'No admin assigned'),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              SevoBadge(
                label: '${p.employeeCount} Technicians',
                tone: SevoTone.info,
                icon: Icons.groups_rounded,
              ),
              if (p.createdAt != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${p.createdAt!.day.toString().padLeft(2, '0')}/${p.createdAt!.month.toString().padLeft(2, '0')}/${p.createdAt!.year}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: SevoText.meta,
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: onInspect,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.selectedOnTint,
                  backgroundColor: AppColors.selectedTint,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text('Inspect', style: SevoText.button),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text, {bool strong = false}) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: strong
                ? SevoText.bodyStrong
                : SevoText.caption.copyWith(color: AppColors.bodyText),
          ),
        ),
      ],
    ),
  );
}

/// The Inspect dossier (Web `Drawer`).
class _ProviderDossier extends StatelessWidget {
  const _ProviderDossier({
    required this.provider,
    required this.onViewTechnicians,
  });

  final ServiceProvider provider;
  final VoidCallback onViewTechnicians;

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final admin = p.primaryAdmin;
    Widget kv(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: SevoText.caption)),
          Expanded(child: Text(value, style: SevoText.bodyStrong)),
        ],
      ),
    );
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: SevoText.family),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.companyName, style: SevoText.pageTitle),
              const SizedBox(height: 2),
              Text('Identifier: ${p.identifier}', style: SevoText.pageSubtitle),
              const SizedBox(height: 16),
              kv('Status:', p.isActive ? 'Active' : 'Inactive'),
              kv('Technician Roster:', '${p.employeeCount} Technicians'),
              kv(
                'Created:',
                p.createdAt == null
                    ? '—'
                    : '${p.createdAt!.day.toString().padLeft(2, '0')}/${p.createdAt!.month.toString().padLeft(2, '0')}/${p.createdAt!.year}',
              ),
              const SizedBox(height: 12),
              Text('Primary Administrator', style: SevoText.section),
              const SizedBox(height: 6),
              if (admin != null) ...[
                kv('Name:', admin.displayName),
                kv('Email:', (admin.email ?? '').isEmpty ? '—' : admin.email!),
                if ((admin.phone ?? '').isNotEmpty) kv('Phone:', admin.phone!),
              ] else
                Text(
                  'No primary administrator configured.',
                  style: SevoText.caption,
                ),
              const SizedBox(height: 12),
              Text('Organization Information', style: SevoText.section),
              const SizedBox(height: 6),
              kv(
                'Address:',
                (p.address ?? '').isEmpty
                    ? 'Address not registered'
                    : p.address!,
              ),
              if ((p.website ?? '').isNotEmpty) kv('Website:', p.website!),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onViewTechnicians,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text('View Technicians (${p.employeeCount})'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.actionColor,
                    minimumSize: const Size(0, 46),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Create Service Provider form. Pops with the server message ('' if none).
class _CreateProviderSheet extends ConsumerStatefulWidget {
  const _CreateProviderSheet();

  @override
  ConsumerState<_CreateProviderSheet> createState() =>
      _CreateProviderSheetState();
}

class _CreateProviderSheetState extends ConsumerState<_CreateProviderSheet> {
  final _c = <String, TextEditingController>{
    for (final k in [
      'company_name',
      'display_id',
      'industry',
      'address',
      'website',
      'admin_username',
      'admin_email',
      'admin_password',
      'admin_phone',
      'admin_first_name',
      'admin_last_name',
    ])
      k: TextEditingController(),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String k) => _c[k]!.text.trim();

  Future<void> _submit() async {
    // Same validation order and messages as the Web.
    if (_t('company_name').isEmpty)
      return setState(() => _error = 'Company Name is required.');
    if (_t('admin_username').isEmpty)
      return setState(() => _error = 'Admin Username is required.');
    if (_t('admin_email').isEmpty)
      return setState(() => _error = 'Admin Email is required.');
    if (_c['admin_password']!.text.length < 6)
      return setState(
        () => _error = 'Admin Password must be at least 6 characters.',
      );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final message = await ref
          .read(serviceProvidersRepositoryProvider)
          .create(
            NewServiceProvider(
              companyName: _t('company_name'),
              displayId: _t('display_id'),
              address: _t('address'),
              industry: _t('industry'),
              website: _t('website'),
              adminUsername: _t('admin_username'),
              adminEmail: _t('admin_email'),
              adminPassword: _c['admin_password']!.text,
              adminFirstName: _t('admin_first_name'),
              adminLastName: _t('admin_last_name'),
              adminPhone: _t('admin_phone'),
            ),
          );
      if (mounted) Navigator.of(context).pop(message ?? '');
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is ServiceProvidersException
              ? e.message
              : 'Failed to create Service Provider.';
        });
      }
    }
  }

  Widget _field(
    String key,
    String label, {
    String? hint,
    bool obscure = false,
    TextInputType? type,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: _c[key],
      obscureText: obscure,
      keyboardType: type,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: SevoText.family),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create Service Provider', style: SevoText.pageTitle),
                const SizedBox(height: 2),
                Text(
                  'Establishes a new provider organization and provisions its primary Service Provider Admin.',
                  style: SevoText.pageSubtitle,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.errorBorder),
                    ),
                    child: Text(
                      _error!,
                      style: SevoText.caption.copyWith(
                        color: AppColors.errorText,
                      ),
                    ),
                  ),
                Text('Organization Information', style: SevoText.section),
                const SizedBox(height: 8),
                _field(
                  'company_name',
                  'Company Name *',
                  hint: 'e.g. Apex Electrical Solutions',
                ),
                _field(
                  'display_id',
                  'Display Identifier / Code',
                  hint: 'e.g. APEX',
                ),
                _field(
                  'industry',
                  'Industry / Specialization',
                  hint: 'e.g. HVAC, Electrical',
                ),
                _field(
                  'address',
                  'Registered Business Address',
                  hint: 'e.g. 100 Main Street, Suite 400',
                ),
                _field(
                  'website',
                  'Official Website',
                  hint: 'https://example.com',
                  type: TextInputType.url,
                ),
                const SizedBox(height: 6),
                Text(
                  'Primary Service Provider Admin Account',
                  style: SevoText.section,
                ),
                const SizedBox(height: 2),
                Text(
                  'This user will receive Service Provider Admin privileges to manage technicians under this organization.',
                  style: SevoText.caption,
                ),
                const SizedBox(height: 8),
                _field(
                  'admin_username',
                  'Admin Username *',
                  hint: 'e.g. apex_admin',
                ),
                _field(
                  'admin_email',
                  'Admin Email *',
                  hint: 'admin@apex.com',
                  type: TextInputType.emailAddress,
                ),
                _field(
                  'admin_password',
                  'Initial Password *',
                  hint: 'Minimum 6 characters',
                  obscure: true,
                ),
                _field(
                  'admin_phone',
                  'Contact Phone',
                  hint: '+1 555-0199',
                  type: TextInputType.phone,
                ),
                _field('admin_first_name', 'First Name', hint: 'John'),
                _field('admin_last_name', 'Last Name', hint: 'Doe'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(
                          _saving ? 'Creating Provider...' : 'Create Provider',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.actionColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
