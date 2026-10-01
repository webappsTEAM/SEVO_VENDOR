import 'package:flutter/material.dart';

class CategoryInfo {
  const CategoryInfo({required this.name, required this.icon});

  final String name;
  final IconData icon;
}

/// Standard categories mapped to clean Material icons matching Web.
const List<CategoryInfo> kStandardServiceCategories = [
  CategoryInfo(name: 'Mini Truck', icon: Icons.local_shipping_rounded),
  CategoryInfo(name: 'Two-Wheeler', icon: Icons.two_wheeler_rounded),
  CategoryInfo(name: 'Packers & Movers', icon: Icons.inventory_2_rounded),
  CategoryInfo(name: 'Electrical', icon: Icons.bolt_rounded),
  CategoryInfo(name: 'AC & Appliances', icon: Icons.ac_unit_rounded),
  CategoryInfo(name: 'Plumbing', icon: Icons.water_drop_rounded),
  CategoryInfo(name: 'Locks & Carpentry', icon: Icons.handyman_rounded),
  CategoryInfo(name: 'Masonry & Tile', icon: Icons.home_repair_service_rounded),
  CategoryInfo(name: 'Cleaning', icon: Icons.cleaning_services_rounded),
  CategoryInfo(name: 'Painting', icon: Icons.format_paint_rounded),
  CategoryInfo(name: 'Automotive', icon: Icons.directions_car_rounded),
  CategoryInfo(name: 'Pest Control', icon: Icons.pest_control_rounded),
];

/// Formats raw category slugs / strings into clean, user-facing labels.
/// For example: 'mason' -> 'Masonry & Tile', 'goods_transport_truck' -> 'Mini Truck'.
String formatCategoryName(String? category) {
  if (category == null || category.trim().isEmpty) {
    return 'Service Request';
  }
  final trimmed = category.trim();
  final lower = trimmed.toLowerCase();

  // 1. Mini Truck / Heavy Goods Transport
  if (lower == 'mini truck' ||
      lower == 'goods_transport_truck' ||
      lower.contains('mini truck') ||
      lower.contains('three wheeler') ||
      lower.contains('3 wheeler') ||
      lower.contains('pickup') ||
      lower.contains('tata ace') ||
      lower.contains('bolero') ||
      lower.contains('truck')) {
    return 'Mini Truck';
  }

  // 2. Two-Wheeler / Bike Courier
  if (lower == 'two-wheeler' ||
      lower == 'two_wheeler' ||
      lower == 'goods_transport_two_wheeler' ||
      lower.contains('two_wheeler') ||
      lower.contains('two wheeler') ||
      lower.contains('bike') ||
      lower.contains('scooter') ||
      lower.contains('motorcycle') ||
      lower.contains('parcel') ||
      lower.contains('courier')) {
    return 'Two-Wheeler';
  }

  // 3. Packers & Movers
  if (lower == 'packers & movers' ||
      lower == 'packers_movers' ||
      lower.contains('packer') ||
      lower.contains('mover') ||
      lower.contains('relocation') ||
      lower.contains('shifting')) {
    return 'Packers & Movers';
  }

  // 4. Masonry & Tile
  if (lower == 'mason' ||
      lower == 'masonry' ||
      lower.contains('mason') ||
      lower.contains('tile') ||
      lower.contains('civil')) {
    return 'Masonry & Tile';
  }

  // 5. Electrical
  if (lower == 'electrical' ||
      lower.contains('electr') ||
      lower.contains('wiring') ||
      lower.contains('circuit') ||
      lower.contains('switch') ||
      lower.contains('socket') ||
      lower.contains('inverter') ||
      lower.contains('mcb') ||
      lower.contains('fuse')) {
    return 'Electrical';
  }

  // 6. AC & Appliances
  if (lower == 'ac' ||
      lower == 'ac_repair' ||
      lower == 'air_conditioning' ||
      lower == 'appliances' ||
      lower == 'appliance_repair' ||
      lower.contains('appliance') ||
      lower.contains('hvac') ||
      lower.contains('refrigerat') ||
      lower.contains('air condition') ||
      RegExp(r'\bac\b').hasMatch(lower)) {
    return 'AC & Appliances';
  }

  // 7. Plumbing
  if (lower == 'plumbing' ||
      lower.contains('plumb') ||
      lower.contains('pipe') ||
      lower.contains('faucet') ||
      lower.contains('drain') ||
      lower.contains('geyser') ||
      lower.contains('leak')) {
    return 'Plumbing';
  }

  // 8. Locks & Carpentry
  if (lower == 'locks_carpentry' ||
      lower == 'carpentry' ||
      lower.contains('carpent') ||
      lower.contains('lock') ||
      lower.contains('furniture') ||
      lower.contains('door') ||
      lower.contains('wood') ||
      lower.contains('hinge')) {
    return 'Locks & Carpentry';
  }

  // 9. Cleaning
  if (lower == 'cleaning' ||
      lower.contains('clean') ||
      lower.contains('sanit') ||
      lower.contains('housekeep') ||
      lower.contains('deep clean') ||
      lower.contains('disinfect') ||
      lower.contains('maid')) {
    return 'Cleaning';
  }

  // 10. Painting
  if (lower == 'painting' || lower.contains('paint')) {
    return 'Painting';
  }

  // 11. Automotive
  if (lower == 'automotive' ||
      lower.contains('auto') ||
      lower.contains('mechanic') ||
      lower.contains('vehicle') ||
      lower.contains('car')) {
    return 'Automotive';
  }

  // 12. Pest Control
  if (lower == 'pest_control' ||
      lower.contains('pest') ||
      lower.contains('termite') ||
      lower.contains('insect')) {
    return 'Pest Control';
  }

  // 13. General Goods & Transport fallback
  if (lower.startsWith('goods_transport') ||
      lower.contains('logistic') ||
      lower.contains('transport')) {
    return 'Mini Truck';
  }

  // Fallback: title case snake_case or words
  return trimmed
      .split(RegExp(r'[_-\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Resolves a clean Material icon based on category or service name string.
IconData iconForCategory(String? category) {
  if (category == null || category.trim().isEmpty) {
    return Icons.handyman_rounded;
  }
  final lower = category.toLowerCase();
  if (lower.contains('two_wheeler') ||
      lower.contains('two wheeler') ||
      lower.contains('two-wheeler') ||
      lower.contains('bike') ||
      lower.contains('scooter') ||
      lower.contains('motorcycle')) {
    return Icons.two_wheeler_rounded;
  }
  if (lower.contains('packer') ||
      lower.contains('mover') ||
      lower.contains('relocation') ||
      lower.contains('shifting')) {
    return Icons.inventory_2_rounded;
  }
  if (lower.contains('truck') ||
      lower.contains('mini truck') ||
      lower.contains('mini_truck') ||
      lower.contains('pickup') ||
      lower.contains('logistic') ||
      lower.contains('deliver') ||
      lower.contains('transport')) {
    return Icons.local_shipping_rounded;
  }
  if (lower.contains('electr') ||
      lower.contains('wiring') ||
      lower.contains('circuit')) {
    return Icons.bolt_rounded;
  }
  if (lower.contains('air condition') ||
      lower.contains('appliance') ||
      lower.contains('hvac') ||
      lower.contains('refrigerat') ||
      lower.contains('cooling') ||
      RegExp(r'\bac\b').hasMatch(lower)) {
    return Icons.ac_unit_rounded;
  }
  if (lower.contains('plumb') ||
      lower.contains('pipe') ||
      lower.contains('drain') ||
      lower.contains('water') ||
      lower.contains('leak') ||
      lower.contains('faucet')) {
    return Icons.water_drop_rounded;
  }
  if (lower.contains('lock') ||
      lower.contains('carpent') ||
      lower.contains('door') ||
      lower.contains('wood') ||
      lower.contains('furniture') ||
      lower.contains('handyman')) {
    return Icons.handyman_rounded;
  }
  if (lower.contains('clean') ||
      lower.contains('wash') ||
      lower.contains('sanit') ||
      lower.contains('maid') ||
      lower.contains('housekeep')) {
    return Icons.cleaning_services_rounded;
  }
  if (lower.contains('roof') ||
      lower.contains('construct') ||
      lower.contains('mason') ||
      lower.contains('tile') ||
      lower.contains('civil') ||
      lower.contains('renovat')) {
    return Icons.home_repair_service_rounded;
  }
  if (lower.contains('paint') ||
      lower.contains('whitewash') ||
      lower.contains('primer') ||
      lower.contains('distemper') ||
      lower.contains('polish')) {
    return Icons.format_paint_rounded;
  }
  if (lower.contains('auto') ||
      lower.contains('car') ||
      lower.contains('vehicle') ||
      lower.contains('mechanic')) {
    return Icons.directions_car_rounded;
  }
  if (lower.contains('pest') ||
      lower.contains('termite') ||
      lower.contains('insect')) {
    return Icons.pest_control_rounded;
  }
  return Icons.handyman_rounded;
}
