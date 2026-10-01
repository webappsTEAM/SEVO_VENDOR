import '../../../../shared/widgets/sevo/sevo_module_frame.dart';
import '../../../../shared/widgets/sevo/sevo_module_art.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../locations/presentation/widgets/location_picker_map.dart';
import '../../data/seller_repository.dart';
import '../../domain/seller_models.dart';
import '../seller_providers.dart';

/// Seller Storefront Profile & Operating Controls Screen (Web Parity: AdminStoreProfilePage.jsx).
class SellerStoreProfileScreen extends ConsumerStatefulWidget {
  const SellerStoreProfileScreen({super.key});

  @override
  ConsumerState<SellerStoreProfileScreen> createState() =>
      _SellerStoreProfileScreenState();
}

class _SellerStoreProfileScreenState
    extends ConsumerState<SellerStoreProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _taglineController;
  late TextEditingController _descController;
  late TextEditingController _logoController;
  late TextEditingController _bannerController;
  late TextEditingController _fssaiController;
  late TextEditingController _addressController;
  late TextEditingController _radiusController;
  late TextEditingController _minOrderController;
  late TextEditingController _deliveryMinsController;

  bool _isAcceptingOrders = true;

  /// Store pickup pin (Web: "Store Pickup Pin & Coordinates").
  double? _latitude;
  double? _longitude;
  bool _isInitialized = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _taglineController = TextEditingController();
    _descController = TextEditingController();
    _logoController = TextEditingController();
    _bannerController = TextEditingController();
    _fssaiController = TextEditingController();
    _addressController = TextEditingController();
    _radiusController = TextEditingController();
    _minOrderController = TextEditingController();
    _deliveryMinsController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _taglineController.dispose();
    _descController.dispose();
    _logoController.dispose();
    _bannerController.dispose();
    _fssaiController.dispose();
    _addressController.dispose();
    _radiusController.dispose();
    _minOrderController.dispose();
    _deliveryMinsController.dispose();
    super.dispose();
  }

  void _populateForm(SellerStoreProfile profile) {
    if (_isInitialized) return;
    _nameController.text = profile.storeName;
    _taglineController.text = profile.tagline;
    _descController.text = profile.description;
    _logoController.text = profile.logoUrl;
    _bannerController.text = profile.bannerUrl;
    _fssaiController.text = profile.fssaiLicenseNumber;
    _addressController.text = profile.storeAddress;
    _radiusController.text = profile.deliveryRadiusKm.toString();
    _minOrderController.text = profile.minimumOrderAmount;
    _deliveryMinsController.text = profile.estimatedDeliveryMins.toString();
    _isAcceptingOrders = profile.isAcceptingOrders;
    _latitude = profile.latitude;
    _longitude = profile.longitude;
    _isInitialized = true;
  }

  Future<void> _refresh() async {
    _isInitialized = false;
    ref.invalidate(sellerStoreProfileProvider);
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final payload = {
        'store_name': _nameController.text.trim(),
        'tagline': _taglineController.text.trim(),
        'description': _descController.text.trim(),
        'logo_url': _logoController.text.trim(),
        'banner_url': _bannerController.text.trim(),
        'fssai_license_number': _fssaiController.text.trim(),
        'store_address': _addressController.text.trim(),
        'delivery_radius_km':
            double.tryParse(_radiusController.text.trim()) ?? 5.0,
        'minimum_order_amount': _minOrderController.text.trim().isEmpty
            ? '0.00'
            : _minOrderController.text.trim(),
        'estimated_delivery_mins':
            int.tryParse(_deliveryMinsController.text.trim()) ?? 30,
        'is_accepting_orders': _isAcceptingOrders,
        'latitude': _latitude,
        'longitude': _longitude,
      };

      await ref.read(sellerRepositoryProvider).updateStoreProfile(payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Store profile and operating controls saved successfully!',
            ),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save store profile: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(sellerStoreProfileProvider);

    return SevoModuleFrame(
      module: SevoModule.storeProfile,
      title: 'Seller Store Profile',
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: const Color(0xFF005965),
          child: storeAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFF005965)),
            ),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Failed to load store profile: $err',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF005965),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (profile) {
              _populateForm(profile);

              return Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    // Top Live Status & Action Card
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _isAcceptingOrders
                                      ? const Color(0xFFD1FAE5)
                                      : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.power_settings_new_rounded,
                                  color: _isAcceptingOrders
                                      ? const Color(0xFF059669)
                                      : const Color(0xFFDC2626),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Store Status: ${_isAcceptingOrders ? "OPEN" : "CLOSED"}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _isAcceptingOrders
                                          ? 'Your store is actively accepting customer orders on the CalServices marketplace.'
                                          : 'Store orders are paused. Customers see your shop as closed.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _isAcceptingOrders
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF059669),
                                    side: BorderSide(
                                      color: _isAcceptingOrders
                                          ? const Color(0xFFFCA5A5)
                                          : const Color(0xFF6EE7B7),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(
                                      () => _isAcceptingOrders =
                                          !_isAcceptingOrders,
                                    );
                                  },
                                  child: Text(
                                    _isAcceptingOrders
                                        ? 'Pause Store Orders'
                                        : 'Open Store Now',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF005965),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: _isSaving ? null : _handleSave,
                                  icon: _isSaving
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.save_rounded,
                                          size: 16,
                                        ),
                                  label: Text(
                                    _isSaving ? 'Saving...' : 'Save Settings',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Section 1: Store Identity & Branding
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.storefront_rounded,
                                color: Color(0xFF005965),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Store Identity & Branding',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Store Name *',
                              hintText: 'e.g. GreenFresh Farm Store',
                            ),
                            validator: (val) =>
                                val == null || val.trim().isEmpty
                                ? 'Store name is required'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _taglineController,
                            decoration: const InputDecoration(
                              labelText: 'Store Tagline',
                              hintText:
                                  'e.g. Fresh harvest delivered in 30 mins',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _descController,
                            decoration: const InputDecoration(
                              labelText: 'About Store / Description',
                              hintText: 'Describe produce sourcing, organic certifications, standards...',
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _logoController,
                            decoration: const InputDecoration(
                              labelText: 'Logo Image URL',
                              hintText: 'https://.../logo.png',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _bannerController,
                            decoration: const InputDecoration(
                              labelText: 'Banner Image URL',
                              hintText: 'https://.../banner.jpg',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Section 2: Fulfillment & Delivery Coverage
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.local_shipping_rounded,
                                color: Color(0xFF059669),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Fulfillment & Delivery Zone',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _radiusController,
                                  decoration: const InputDecoration(
                                    labelText: 'Delivery Radius (km)',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _deliveryMinsController,
                                  decoration: const InputDecoration(
                                    labelText: 'Est. Delivery (mins)',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _minOrderController,
                            decoration: const InputDecoration(
                              labelText: 'Minimum Order Amount (₹)',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _addressController,
                            decoration: const InputDecoration(
                              labelText: 'Store & Warehouse Physical Address',
                              hintText:
                                  'Plot number, Street, Area, City, Pincode',
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Store Pickup Pin & Coordinates (Required for Rider Dispatch)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Drop a pin on your exact store/warehouse location. Riders use this exact coordinate '
                            'for pickup matching and navigation.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _latitude != null && _longitude != null
                                ? 'Pin Set (${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)})'
                                : 'Pin not set',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _latitude != null
                                  ? AppColors.emerald
                                  : const Color(0xFFD97706),
                            ),
                          ),
                          const SizedBox(height: 6),
                          LocationPickerMap(
                            latitude: _latitude,
                            longitude: _longitude,
                            height: 220,
                            onPositionChange: (lat, lng) => setState(() {
                              _latitude = lat;
                              _longitude = lng;
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Section 3: Food Safety Compliance & Licensing
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.verified_user_rounded,
                                color: Color(0xFFD97706),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Food Safety Compliance & Licensing',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Government mandated for all fresh grocery & produce suppliers.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const Divider(height: 18),
                          TextFormField(
                            controller: _fssaiController,
                            decoration: const InputDecoration(
                              labelText: 'FSSAI License / Registration Number',
                              hintText: 'e.g. 12422002000123',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF005965),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isSaving ? null : _handleSave,
                      child: Text(
                        _isSaving
                            ? 'Saving Changes...'
                            : 'Save & Publish Storefront',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
