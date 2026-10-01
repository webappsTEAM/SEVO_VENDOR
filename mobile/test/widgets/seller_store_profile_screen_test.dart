import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/features/seller/domain/seller_models.dart';
import 'package:mobile/features/seller/presentation/seller_providers.dart';
import 'package:mobile/features/seller/presentation/store_profile/seller_store_profile_screen.dart';

void main() {
  testWidgets('Food Safety section sits below the pickup map with the FSSAI field and publish button', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sellerStoreProfileProvider.overrideWith(
            (ref) async => SellerStoreProfile.fromJson({
              'id': 1,
              'store_name': 'Hosur Fresh Mart',
              'store_address': 'Shop 1, MG Road, Hosur, Tamil Nadu',
              'delivery_radius_km': '10.00',
              'fssai_license_number': '12422002000123',
              'latitude': '12.7409',
              'longitude': '77.8253',
            }),
          ),
        ],
        child: const MaterialApp(home: SellerStoreProfileScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Food Safety Compliance & Licensing'), findsOneWidget);
    expect(find.text('Government mandated for all fresh grocery & produce suppliers.'), findsOneWidget);
    expect(find.text('FSSAI License / Registration Number'), findsOneWidget);
    expect(find.text('12422002000123'), findsOneWidget);
    expect(find.text('Save & Publish Storefront'), findsOneWidget);

    final pinY = tester.getTopLeft(find.text('Store Pickup Pin & Coordinates (Required for Rider Dispatch)')).dy;
    final fssaiY = tester.getTopLeft(find.text('Food Safety Compliance & Licensing')).dy;
    expect(fssaiY, greaterThan(pinY));
  });
}
