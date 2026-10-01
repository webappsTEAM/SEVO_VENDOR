import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_motion.dart';
import 'sevo_module_art_more.dart';

/// The illustration families available to modules.
enum SevoArt {
  vendor,
  workforce,
  applications,
  storefront,
  van,
  orders,
  inventory,
  finance,
  analytics,
  settings,
}

/// Every module that has a branded transition + artwork. Several modules share
/// one illustration family (see [art]).
enum SevoModule {
  // Platform Governance
  vendorDirectory('Vendor Directory', Icons.storefront_rounded, SevoArt.vendor),
  workforceRoster('Workforce Roster', Icons.groups_rounded, SevoArt.workforce),
  technicianApplications(
    'Technician Applications',
    Icons.assignment_ind_rounded,
    SevoArt.applications,
  ),
  sellerApplications(
    'Seller Applications',
    Icons.store_mall_directory_rounded,
    SevoArt.storefront,
  ),
  serviceProviders(
    'Service Providers',
    Icons.home_repair_service_rounded,
    SevoArt.van,
  ),
  // Seller Hub
  sellerHome('Seller Hub', Icons.storefront_rounded, SevoArt.storefront),
  sellerOrders('Orders', Icons.shopping_bag_rounded, SevoArt.orders),
  sellerReturns('Returns', Icons.assignment_return_rounded, SevoArt.orders),
  sellerClaims('Claims', Icons.gavel_rounded, SevoArt.applications),
  sellerInventory('Inventory', Icons.inventory_2_rounded, SevoArt.inventory),
  catalogUploads(
    'Catalog Uploads',
    Icons.cloud_upload_rounded,
    SevoArt.inventory,
  ),
  categories('Categories', Icons.category_rounded, SevoArt.inventory),
  categoriesApproval(
    'Categories Approval',
    Icons.fact_check_rounded,
    SevoArt.applications,
  ),
  warehouses('Warehouses', Icons.warehouse_rounded, SevoArt.inventory),
  coupons('Coupons', Icons.local_offer_rounded, SevoArt.storefront),
  reportsQuality(
    'Reports & Quality',
    Icons.bar_chart_rounded,
    SevoArt.analytics,
  ),
  storeProfile('Store Profile', Icons.store_rounded, SevoArt.storefront),
  // Operations
  estimations('AC Estimations', Icons.air_rounded, SevoArt.vendor),
  quotations(
    'Quotation Approvals',
    Icons.request_quote_rounded,
    SevoArt.applications,
  ),
  invoices('Invoices', Icons.receipt_long_rounded, SevoArt.finance),
  fieldJobs('Field Jobs', Icons.work_rounded, SevoArt.van),
  dispatchRadar('Dispatch Radar', Icons.radar_rounded, SevoArt.van),
  skills('Skills Master', Icons.workspace_premium_rounded, SevoArt.workforce),
  pricing('Pricing & Approvals', Icons.calculate_rounded, SevoArt.finance),
  stock('Stock Management', Icons.eco_rounded, SevoArt.inventory),
  scorecards('Scorecards', Icons.emoji_events_rounded, SevoArt.analytics),
  socialSecurity(
    'Social Security',
    Icons.health_and_safety_rounded,
    SevoArt.workforce,
  ),
  // Finance
  treasury('Treasury', Icons.account_balance_wallet_rounded, SevoArt.finance),
  transactions('Transactions', Icons.swap_horiz_rounded, SevoArt.finance),
  withdrawals('Withdrawals', Icons.arrow_circle_down_rounded, SevoArt.finance),
  payoutAccounts(
    'Payout Accounts',
    Icons.account_balance_rounded,
    SevoArt.finance,
  ),
  // Telemetry & settings
  databaseEgress('Database & Egress', Icons.storage_rounded, SevoArt.analytics),
  reportsAudits('Reports & Audits', Icons.insights_rounded, SevoArt.analytics),
  systemSettings('System Settings', Icons.settings_rounded, SevoArt.settings),
  // Vendor-admin workforce
  employees('Employee Roster', Icons.how_to_reg_rounded, SevoArt.workforce),
  invitations('Send Invitations', Icons.mail_rounded, SevoArt.applications),
  tiedTechnicians('Tied Technicians', Icons.link_rounded, SevoArt.workforce),
  companyProfile('Company Profile', Icons.business_rounded, SevoArt.storefront),
  vendorApplications(
    'Applications',
    Icons.assignment_rounded,
    SevoArt.applications,
  );

  const SevoModule(this.label, this.icon, this.art);

  final String label;
  final IconData icon;
  final SevoArt art;
}

/// Lightweight, dependency-free animated artwork for a [SevoModule]. It is a
/// single `CustomPainter` driven by one looping controller; under reduced
/// motion it renders one still frame. The artwork is presentation only.
class SevoModuleArt extends StatefulWidget {
  const SevoModuleArt({
    super.key,
    required this.module,
    this.size = 200,
    this.onDark = true,
  });

  final SevoModule module;

  /// Width of the art; height follows a 4:3 ratio.
  final double size;

  /// True on the teal transition backdrop (light strokes); false on a card
  /// surface (teal strokes).
  final bool onDark;

  @override
  State<SevoModuleArt> createState() => _SevoModuleArtState();
}

class _SevoModuleArtState extends State<SevoModuleArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void initState() {
    super.initState();
    if (!AppMotion.isReduced) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.size,
          height: widget.size * 0.75,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _painterFor(widget.module, _c.value, widget.onDark),
            ),
          ),
        ),
      ),
    );
  }
}

CustomPainter _painterFor(SevoModule m, double t, bool onDark) =>
    switch (m.art) {
      SevoArt.vendor => _VendorNetworkPainter(t: t, onDark: onDark),
      SevoArt.workforce => WorkforcePainter(t: t, onDark: onDark),
      SevoArt.applications => TechnicianApplicationPainter(
        t: t,
        onDark: onDark,
      ),
      SevoArt.storefront => SellerApplicationPainter(t: t, onDark: onDark),
      SevoArt.van => ServiceProviderPainter(t: t, onDark: onDark),
      SevoArt.orders => OrdersPainter(t: t, onDark: onDark),
      SevoArt.inventory => InventoryPainter(t: t, onDark: onDark),
      SevoArt.finance => FinancePainter(t: t, onDark: onDark),
      SevoArt.analytics => AnalyticsPainter(t: t, onDark: onDark),
      SevoArt.settings => SettingsPainter(t: t, onDark: onDark),
    };

/// Service-vendor scene: a wall AC unit blowing air, a technician in a hard
/// hat, and a toolbox with a swinging wrench, linked by a pulsing network.
class _VendorNetworkPainter extends CustomPainter {
  _VendorNetworkPainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = onDark ? Colors.white : const Color(0xFF005965);
    final accent = onDark ? const Color(0xFF5EEAD4) : const Color(0xFF0D9488);
    final tau = 2 * math.pi;

    final fill = Paint()..color = ink.withValues(alpha: onDark ? 0.14 : 0.10);
    final line = Paint()
      ..color = ink.withValues(alpha: onDark ? 0.6 : 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final ground = h * 0.9;
    canvas.drawLine(
      Offset(w * 0.05, ground),
      Offset(w * 0.95, ground),
      line..color = ink.withValues(alpha: 0.35),
    );
    line.color = ink.withValues(alpha: onDark ? 0.6 : 0.5);

    // ── Wall AC unit (left) with airflow ────────────────────────────────
    final ac = Rect.fromLTWH(w * 0.04, h * 0.36, w * 0.30, h * 0.16);
    final acR = RRect.fromRectAndRadius(ac, const Radius.circular(9));
    canvas.drawRRect(acR, fill);
    canvas.drawRRect(acR, line);
    for (var i = 0; i < 2; i++) {
      final y = ac.top + ac.height * (0.52 + i * 0.2);
      canvas.drawLine(
        Offset(ac.left + ac.width * 0.14, y),
        Offset(ac.right - ac.width * 0.14, y),
        line..strokeWidth = 1.1,
      );
    }
    line.strokeWidth = 1.5;
    final led = 0.45 + 0.55 * ((math.sin(t * tau * 2) + 1) / 2);
    canvas.drawCircle(
      Offset(ac.right - ac.width * 0.14, ac.top + ac.height * 0.24),
      2.4,
      Paint()..color = accent.withValues(alpha: led),
    );
    for (var i = 0; i < 3; i++) {
      final x0 = ac.left + ac.width * (0.22 + i * 0.28);
      final path = Path()..moveTo(x0, ac.bottom + 4);
      const steps = 16;
      final len = h * 0.26;
      for (var k = 1; k <= steps; k++) {
        final f = k / steps;
        final y = ac.bottom + 4 + len * f;
        path.lineTo(x0 + math.sin(f * 7 - t * tau * 2 + i) * 3.2 * f, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── Technician (centre) ─────────────────────────────────────────────
    final cx = w * 0.5;
    final bob = math.sin(t * tau) * 1.2;
    final headR = h * 0.085;
    final hy = h * 0.42 + bob;
    final shoulders = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        cx - h * 0.17,
        hy + headR + 7,
        h * 0.34,
        ground - (hy + headR + 7),
      ),
      topLeft: Radius.circular(h * 0.13),
      topRight: Radius.circular(h * 0.13),
    );
    canvas.drawRRect(shoulders, fill);
    canvas.drawRRect(shoulders, line);
    canvas.drawCircle(
      Offset(cx, hy),
      headR,
      Paint()..color = ink.withValues(alpha: onDark ? 0.22 : 0.16),
    );
    canvas.drawCircle(Offset(cx, hy), headR, line);
    // hard hat
    final hat = Path()
      ..addArc(
        Rect.fromCircle(center: Offset(cx, hy - 1), radius: headR + 3),
        math.pi,
        math.pi,
      );
    canvas.drawPath(hat..close(), Paint()..color = accent);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - headR - 7, hy - 2.5, (headR + 7) * 2, 5),
        const Radius.circular(2.5),
      ),
      Paint()..color = accent,
    );
    canvas.drawLine(
      Offset(cx, hy - headR - 3),
      Offset(cx, hy - 3),
      Paint()
        ..color = onDark ? const Color(0x33000000) : const Color(0x33FFFFFF)
        ..strokeWidth = 1.4,
    );
    // chest badge with a tick
    final badge = Offset(cx + h * 0.075, hy + headR + h * 0.11);
    canvas.drawCircle(badge, 5.5, Paint()..color = accent);
    canvas.drawPath(
      Path()
        ..moveTo(badge.dx - 2.4, badge.dy)
        ..lineTo(badge.dx - 0.6, badge.dy + 2)
        ..lineTo(badge.dx + 2.6, badge.dy - 1.8),
      Paint()
        ..color = onDark ? const Color(0xFF003B46) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    // ── Toolbox + swinging wrench (right) ───────────────────────────────
    final box = Rect.fromLTWH(w * 0.66, ground - h * 0.20, w * 0.28, h * 0.20);
    // wrench, behind the box
    canvas.save();
    canvas.translate(box.left + box.width * 0.72, box.top);
    canvas.rotate(-0.38 + math.sin(t * tau) * 0.09);
    final wrenchLen = h * 0.30;
    // handle
    canvas.drawLine(Offset.zero, Offset(0, -wrenchLen), line..strokeWidth = 4);
    // open-end jaw: a "C" with a clear gap facing up
    canvas.drawArc(
      Rect.fromCircle(center: Offset(0, -wrenchLen - 4), radius: 8.5),
      -math.pi / 2 + 0.62,
      tau - 1.24,
      false,
      line..strokeWidth = 3.2,
    );
    line.strokeWidth = 1.5;
    canvas.restore();

    final boxR = RRect.fromRectAndRadius(box, const Radius.circular(5));
    canvas.drawRRect(
      boxR,
      Paint()
        ..color = onDark ? const Color(0xFF0B4F57) : const Color(0xFFE6F4F1),
    );
    canvas.drawRRect(boxR, fill);
    canvas.drawRRect(boxR, line);
    canvas.drawLine(
      Offset(box.left, box.top + box.height * 0.42),
      Offset(box.right, box.top + box.height * 0.42),
      line..strokeWidth = 1.1,
    );
    line.strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(box.center.dx, box.top + box.height * 0.42),
          width: 10,
          height: 8,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = accent,
    );
    final handle = Rect.fromLTWH(
      box.left + box.width * 0.30,
      box.top - h * 0.07,
      box.width * 0.40,
      h * 0.07,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        handle,
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
      ),
      line,
    );

    // ── Network above: nodes over each element, with travelling pulses ──
    final nodes = <Offset>[
      Offset(ac.center.dx, h * 0.15),
      Offset(cx, h * 0.07),
      Offset(box.center.dx, h * 0.15),
    ];
    final link = Paint()
      ..color = ink.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(nodes[0], nodes[1], link);
    canvas.drawLine(nodes[1], nodes[2], link);
    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      canvas.drawCircle(
        Offset.lerp(nodes[i], nodes[i + 1], p)!,
        2.6,
        Paint()..color = accent,
      );
    }
    for (var i = 0; i < nodes.length; i++) {
      final pulse = (t + i / 3) % 1.0;
      canvas.drawCircle(
        nodes[i],
        5 + 9 * pulse,
        Paint()..color = accent.withValues(alpha: (1 - pulse) * 0.35),
      );
      canvas.drawCircle(nodes[i], 4.5, Paint()..color = ink);
      canvas.drawCircle(nodes[i], 2.2, Paint()..color = accent);
    }
    final drop = Paint()
      ..color = ink.withValues(alpha: 0.22)
      ..strokeWidth = 1;
    canvas.drawLine(nodes[0], Offset(ac.center.dx, ac.top), drop);
    canvas.drawLine(nodes[1], Offset(cx, hy - headR - 4), drop);
    canvas.drawLine(nodes[2], Offset(box.center.dx, handle.top), drop);
  }

  @override
  bool shouldRepaint(covariant _VendorNetworkPainter old) =>
      old.t != t || old.onDark != onDark;
}
