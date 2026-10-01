import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Painters for the remaining Platform Governance modules. Each is a single
/// looping `CustomPainter` (t: 0…1) in the same visual language as the Vendor
/// Directory scene: ink-line objects on a ground line, a teal-mint accent,
/// and a pulsing network node.

const _tau = 2 * math.pi;

Color _ink(bool onDark) => onDark ? Colors.white : const Color(0xFF005965);
Color _accent(bool onDark) =>
    onDark ? const Color(0xFF5EEAD4) : const Color(0xFF0D9488);

Paint _fill(bool onDark) =>
    Paint()..color = _ink(onDark).withValues(alpha: onDark ? 0.14 : 0.10);

Paint _line(bool onDark, {double width = 1.5, double alpha = -1}) => Paint()
  ..color = _ink(onDark)
      .withValues(alpha: alpha >= 0 ? alpha : (onDark ? 0.6 : 0.5))
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

void _ground(Canvas canvas, Size s, bool onDark) {
  canvas.drawLine(
    Offset(s.width * 0.05, s.height * 0.9),
    Offset(s.width * 0.95, s.height * 0.9),
    _line(onDark, alpha: 0.35),
  );
}

void _node(Canvas canvas, Offset c, double phase, bool onDark) {
  final pulse = phase % 1.0;
  canvas.drawCircle(
    c,
    5 + 9 * pulse,
    Paint()..color = _accent(onDark).withValues(alpha: (1 - pulse) * 0.35),
  );
  canvas.drawCircle(c, 4.5, Paint()..color = _ink(onDark));
  canvas.drawCircle(c, 2.2, Paint()..color = _accent(onDark));
}

void _tick(
  Canvas canvas,
  Offset c,
  double size,
  Color color, {
  double progress = 1,
}) {
  final p1 = Offset(c.dx - size * 0.45, c.dy + size * 0.02);
  final p2 = Offset(c.dx - size * 0.1, c.dy + size * 0.38);
  final p3 = Offset(c.dx + size * 0.5, c.dy - size * 0.32);
  final path = Path()..moveTo(p1.dx, p1.dy);
  if (progress < 0.4) {
    final f = progress / 0.4;
    path.lineTo(p1.dx + (p2.dx - p1.dx) * f, p1.dy + (p2.dy - p1.dy) * f);
  } else {
    path.lineTo(p2.dx, p2.dy);
    final f = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
    path.lineTo(p2.dx + (p3.dx - p2.dx) * f, p2.dy + (p3.dy - p2.dy) * f);
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, size * 0.16)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}

/// A team of three technicians linked by a pulsing network.
class WorkforcePainter extends CustomPainter {
  WorkforcePainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = _ink(onDark);
    final accent = _accent(onDark);
    final ground = h * 0.9;
    _ground(canvas, size, onDark);

    final people = <({double x, double r, bool lead})>[
      (x: w * 0.24, r: h * 0.068, lead: false),
      (x: w * 0.76, r: h * 0.068, lead: false),
      (x: w * 0.50, r: h * 0.088, lead: true),
    ];
    final heads = <Offset>[];
    for (var i = 0; i < people.length; i++) {
      final p = people[i];
      final bob = math.sin(t * _tau + i * 1.7) * 1.2;
      final hy = (p.lead ? h * 0.44 : h * 0.52) + bob;
      final shoulderTop = hy + p.r + 6;
      final sw = p.r * 3.7;
      final body = RRect.fromRectAndCorners(
        Rect.fromLTWH(p.x - sw / 2, shoulderTop, sw, ground - shoulderTop),
        topLeft: Radius.circular(sw * 0.4),
        topRight: Radius.circular(sw * 0.4),
      );
      canvas.drawRRect(body, _fill(onDark));
      canvas.drawRRect(body, _line(onDark));
      canvas.drawCircle(
        Offset(p.x, hy),
        p.r,
        Paint()..color = ink.withValues(alpha: onDark ? 0.22 : 0.16),
      );
      canvas.drawCircle(Offset(p.x, hy), p.r, _line(onDark));
      // hard hat
      final hatColor = p.lead
          ? accent
          : ink.withValues(alpha: onDark ? 0.55 : 0.45);
      canvas.drawPath(
        Path()
          ..addArc(
            Rect.fromCircle(center: Offset(p.x, hy - 1), radius: p.r + 2.5),
            math.pi,
            math.pi,
          )
          ..close(),
        Paint()..color = hatColor,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(p.x - p.r - 5, hy - 2, (p.r + 5) * 2, 4.5),
          const Radius.circular(2.2),
        ),
        Paint()..color = hatColor,
      );
      if (p.lead) {
        final badge = Offset(p.x + sw * 0.2, shoulderTop + h * 0.10);
        canvas.drawCircle(badge, 5.5, Paint()..color = accent);
        _tick(
          canvas,
          badge,
          8,
          onDark ? const Color(0xFF003B46) : Colors.white,
        );
      }
      heads.add(Offset(p.x, hy - p.r - 5));
    }

    // network arc across the team
    final top = Offset(w * 0.5, h * 0.09);
    final left = Offset(w * 0.24, h * 0.24);
    final right = Offset(w * 0.76, h * 0.24);
    final link = Paint()
      ..color = ink.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.drawLine(left, top, link);
    canvas.drawLine(top, right, link);
    canvas.drawLine(left, heads[0], link..color = ink.withValues(alpha: 0.22));
    canvas.drawLine(right, heads[1], link);
    canvas.drawLine(top, heads[2], link);
    for (var i = 0; i < 2; i++) {
      final f = (t + i * 0.5) % 1.0;
      final a = i == 0 ? left : top;
      final b = i == 0 ? top : right;
      canvas.drawCircle(Offset.lerp(a, b, f)!, 2.6, Paint()..color = accent);
    }
    _node(canvas, left, t, onDark);
    _node(canvas, top, t + 0.33, onDark);
    _node(canvas, right, t + 0.66, onDark);
  }

  @override
  bool shouldRepaint(covariant WorkforcePainter old) =>
      old.t != t || old.onDark != onDark;
}

/// A clipboard whose checklist ticks itself off, with an ID card beside it.
class TechnicianApplicationPainter extends CustomPainter {
  TechnicianApplicationPainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = _ink(onDark);
    final accent = _accent(onDark);
    _ground(canvas, size, onDark);

    // clipboard
    final board = Rect.fromLTWH(w * 0.30, h * 0.16, w * 0.40, h * 0.70);
    final boardR = RRect.fromRectAndRadius(board, const Radius.circular(10));
    canvas.drawRRect(boardR, _fill(onDark));
    canvas.drawRRect(boardR, _line(onDark));
    final clip = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(board.center.dx, board.top),
        width: board.width * 0.36,
        height: h * 0.075,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(clip, Paint()..color = accent);

    // rows tick themselves off in turn, then hold, then reset
    final cycle = (t * 1.25) % 1.0; // 0…1
    for (var i = 0; i < 3; i++) {
      final y = board.top + board.height * (0.24 + i * 0.24);
      final box = Rect.fromLTWH(board.left + board.width * 0.12, y - 6, 12, 12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        _line(onDark, width: 1.3),
      );
      final p = ((cycle - i * 0.2) / 0.2).clamp(0.0, 1.0);
      if (p > 0) _tick(canvas, box.center, 9, accent, progress: p);
      final lx = board.left + board.width * 0.32;
      canvas.drawLine(
        Offset(lx, y - 3),
        Offset(board.right - board.width * 0.12, y - 3),
        _line(onDark, width: 2, alpha: 0.4),
      );
      canvas.drawLine(
        Offset(lx, y + 5),
        Offset(board.right - board.width * 0.30, y + 5),
        _line(onDark, width: 2, alpha: 0.22),
      );
    }

    // ID card (right), gently floating
    final float = math.sin(t * _tau) * 2;
    canvas.save();
    canvas.translate(w * 0.80, h * 0.56 + float);
    canvas.rotate(0.14);
    final card = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w * 0.24, height: h * 0.30),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      card,
      Paint()
        ..color = onDark ? const Color(0xFF0B4F57) : const Color(0xFFE6F4F1),
    );
    canvas.drawRRect(card, _fill(onDark));
    canvas.drawRRect(card, _line(onDark));
    canvas.drawCircle(
      Offset(0, -h * 0.06),
      h * 0.05,
      Paint()..color = ink.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromCenter(
          center: Offset(0, h * 0.045),
          width: h * 0.15,
          height: h * 0.07,
        ),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      ),
      Paint()..color = ink.withValues(alpha: 0.3),
    );
    canvas.drawLine(
      Offset(-w * 0.07, h * 0.11),
      Offset(w * 0.07, h * 0.11),
      _line(onDark, width: 2, alpha: 0.4),
    );
    canvas.restore();

    // approval stamp (left) pulsing
    final s = 1 + 0.06 * math.sin(t * _tau * 2);
    final stamp = Offset(w * 0.15, h * 0.62);
    canvas.drawCircle(
      stamp,
      15 * s,
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    canvas.drawCircle(stamp, 11 * s, Paint()..color = accent);
    _tick(canvas, stamp, 10, onDark ? const Color(0xFF003B46) : Colors.white);
    _node(canvas, Offset(w * 0.85, h * 0.14), t, onDark);
    canvas.drawLine(
      Offset(w * 0.85, h * 0.14),
      Offset(board.right, board.top + 6),
      Paint()
        ..color = ink.withValues(alpha: 0.28)
        ..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(covariant TechnicianApplicationPainter old) =>
      old.t != t || old.onDark != onDark;
}

/// A merchant storefront with an awning, a parcel and a verified badge.
class SellerApplicationPainter extends CustomPainter {
  SellerApplicationPainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = _ink(onDark);
    final accent = _accent(onDark);
    final ground = h * 0.9;
    _ground(canvas, size, onDark);

    // shop body
    final shop = Rect.fromLTWH(w * 0.24, ground - h * 0.46, w * 0.50, h * 0.46);
    final shopR = RRect.fromRectAndRadius(shop, const Radius.circular(6));
    canvas.drawRRect(shopR, _fill(onDark));
    canvas.drawRRect(shopR, _line(onDark));
    // door + window
    final door = Rect.fromLTWH(
      shop.left + shop.width * 0.10,
      ground - h * 0.26,
      shop.width * 0.26,
      h * 0.26,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        door,
        topLeft: const Radius.circular(5),
        topRight: const Radius.circular(5),
      ),
      _line(onDark),
    );
    canvas.drawCircle(
      Offset(door.right - 6, door.center.dy),
      1.6,
      Paint()..color = accent,
    );
    final win = Rect.fromLTWH(
      shop.left + shop.width * 0.48,
      ground - h * 0.30,
      shop.width * 0.40,
      h * 0.18,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(win, const Radius.circular(4)),
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(win, const Radius.circular(4)),
      _line(onDark, width: 1.3),
    );

    // striped scalloped awning with a slow shimmer
    final aTop = shop.top - h * 0.02;
    final aBottom = shop.top + h * 0.09;
    const stripes = 6;
    final sw = (shop.width + 10) / stripes;
    for (var i = 0; i < stripes; i++) {
      final x = shop.left - 5 + sw * i;
      final on = i.isEven;
      final shimmer = 0.06 * math.sin(t * _tau + i);
      final path = Path()
        ..moveTo(x, aTop)
        ..lineTo(x + sw, aTop)
        ..lineTo(x + sw, aBottom - sw * 0.25)
        ..arcToPoint(
          Offset(x, aBottom - sw * 0.25),
          radius: Radius.circular(sw / 2),
          clockwise: true,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = (on ? accent : ink).withValues(
            alpha: (on ? 0.85 : 0.28) + shimmer,
          ),
      );
    }

    // parcel (left), hopping slightly
    final hop = -math.max(0.0, math.sin(t * _tau)) * 4;
    final box = Rect.fromLTWH(
      w * 0.07,
      ground - h * 0.17 + hop,
      w * 0.15,
      h * 0.17,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      _fill(onDark),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      _line(onDark),
    );
    canvas.drawLine(
      Offset(box.center.dx, box.top),
      Offset(box.center.dx, box.bottom),
      _line(onDark, width: 1.2),
    );

    // verified badge (top-right), gently pulsing
    final s = 1 + 0.07 * math.sin(t * _tau * 2);
    final badge = Offset(shop.right + w * 0.08, shop.top - h * 0.08);
    canvas.drawCircle(
      badge,
      17 * s,
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    canvas.drawCircle(badge, 12 * s, Paint()..color = accent);
    _tick(canvas, badge, 11, onDark ? const Color(0xFF003B46) : Colors.white);

    _node(canvas, Offset(w * 0.30, h * 0.10), t, onDark);
    _node(canvas, Offset(w * 0.62, h * 0.06), t + 0.5, onDark);
    canvas.drawLine(
      Offset(w * 0.30, h * 0.10),
      Offset(w * 0.62, h * 0.06),
      Paint()
        ..color = ink.withValues(alpha: 0.32)
        ..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(w * 0.62, h * 0.06),
      badge,
      Paint()
        ..color = ink.withValues(alpha: 0.32)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant SellerApplicationPainter old) =>
      old.t != t || old.onDark != onDark;
}

/// A service van with spinning wheels heading to a location pin.
class ServiceProviderPainter extends CustomPainter {
  ServiceProviderPainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = _ink(onDark);
    final accent = _accent(onDark);
    final ground = h * 0.9;
    _ground(canvas, size, onDark);

    // van (slight suspension bounce)
    final bounce = math.sin(t * _tau * 4) * 0.9;
    final baseY = ground - h * 0.075 + bounce;
    final body = Rect.fromLTWH(w * 0.16, baseY - h * 0.30, w * 0.50, h * 0.30);
    final bodyR = RRect.fromRectAndCorners(
      body,
      topLeft: const Radius.circular(10),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    );
    canvas.drawRRect(bodyR, _fill(onDark));
    canvas.drawRRect(bodyR, _line(onDark));
    final cab = Path()
      ..moveTo(body.right, body.top + h * 0.06)
      ..lineTo(body.right + w * 0.13, body.top + h * 0.13)
      ..lineTo(body.right + w * 0.16, body.bottom)
      ..lineTo(body.right, body.bottom)
      ..close();
    canvas.drawPath(cab, _fill(onDark));
    canvas.drawPath(cab, _line(onDark));
    // window + toolbox emblem on the van side
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.right + w * 0.02,
          body.top + h * 0.10,
          w * 0.09,
          h * 0.08,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = accent.withValues(alpha: 0.28),
    );
    final emblem = Rect.fromCenter(
      center: body.center,
      width: w * 0.16,
      height: h * 0.11,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(emblem, const Radius.circular(3)),
      Paint()..color = accent,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(emblem.center.dx - 6, emblem.top - 5, 12, 5),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // wheels with spinning spokes
    for (final cx in [body.left + w * 0.10, body.right + w * 0.05]) {
      final c = Offset(cx, baseY + 1);
      final r = h * 0.055;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = onDark ? const Color(0xFF0B4F57) : const Color(0xFFE6F4F1),
      );
      canvas.drawCircle(c, r, _line(onDark, width: 1.6));
      final spoke = _line(onDark, width: 1.2);
      for (var k = 0; k < 3; k++) {
        final a = t * _tau * 2 + k * math.pi / 3;
        canvas.drawLine(
          c + Offset(math.cos(a), math.sin(a)) * r * 0.85,
          c - Offset(math.cos(a), math.sin(a)) * r * 0.85,
          spoke,
        );
      }
      canvas.drawCircle(c, 1.8, Paint()..color = accent);
    }

    // speed lines behind the van
    for (var i = 0; i < 3; i++) {
      final f = (t * 1.2 + i / 3) % 1.0;
      final x = body.left - 6 - f * w * 0.12;
      final y = baseY - h * (0.05 + i * 0.07);
      canvas.drawLine(
        Offset(x, y),
        Offset(x - w * 0.05, y),
        Paint()
          ..color = accent.withValues(alpha: (1 - f) * 0.6)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }

    // route to a pulsing location pin
    final pin = Offset(w * 0.80, h * 0.20);
    final route = Path()
      ..moveTo(body.center.dx, body.top - 6)
      ..quadraticBezierTo(w * 0.60, h * 0.12, pin.dx, pin.dy + 14);
    final dash = Paint()
      ..color = ink.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final m in route.computeMetrics()) {
      var d = (t * 12) % 10;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), dash);
        d += 10;
      }
    }
    final pulse = (t * 1.0) % 1.0;
    canvas.drawCircle(
      Offset(pin.dx, pin.dy + 14),
      5 + 10 * pulse,
      Paint()..color = accent.withValues(alpha: (1 - pulse) * 0.35),
    );
    canvas.drawPath(
      Path()
        ..addOval(Rect.fromCircle(center: pin, radius: 10))
        ..moveTo(pin.dx - 7, pin.dy + 7)
        ..lineTo(pin.dx, pin.dy + 17)
        ..lineTo(pin.dx + 7, pin.dy + 7)
        ..close(),
      Paint()..color = accent,
    );
    canvas.drawCircle(
      pin,
      3.6,
      Paint()..color = onDark ? const Color(0xFF003B46) : Colors.white,
    );
    _node(canvas, Offset(w * 0.22, h * 0.14), t + 0.4, onDark);
    canvas.drawLine(
      Offset(w * 0.22, h * 0.14),
      Offset(w * 0.32, body.top - 2),
      Paint()
        ..color = ink.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant ServiceProviderPainter old) =>
      old.t != t || old.onDark != onDark;
}

/// Parcels stacked on a pallet with a delivery tick and motion lines.
class OrdersPainter extends CustomPainter {
  OrdersPainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = _ink(onDark);
    final accent = _accent(onDark);
    final ground = h * 0.9;
    _ground(canvas, size, onDark);

    void box(Rect r, {double lift = 0}) {
      final shifted = r.shift(Offset(0, lift));
      final rr = RRect.fromRectAndRadius(shifted, const Radius.circular(4));
      canvas.drawRRect(rr, _fill(onDark));
      canvas.drawRRect(rr, _line(onDark));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(shifted.center.dx, shifted.center.dy),
          width: shifted.width * 0.16,
          height: shifted.height,
        ),
        Paint()..color = accent.withValues(alpha: 0.5),
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, ground - h * 0.05, w * 0.56, h * 0.05),
        const Radius.circular(2),
      ),
      Paint()..color = ink.withValues(alpha: 0.25),
    );
    box(Rect.fromLTWH(w * 0.16, ground - h * 0.25, w * 0.24, h * 0.20));
    box(Rect.fromLTWH(w * 0.42, ground - h * 0.21, w * 0.26, h * 0.16));
    final hop = -math.max(0.0, math.sin(t * _tau)) * 5;
    box(
      Rect.fromLTWH(w * 0.24, ground - h * 0.44, w * 0.26, h * 0.19),
      lift: hop,
    );

    final s = 1 + 0.07 * math.sin(t * _tau * 2);
    final badge = Offset(w * 0.78, h * 0.34);
    canvas.drawCircle(
      badge,
      22 * s,
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    canvas.drawCircle(badge, 15 * s, Paint()..color = accent);
    _tick(canvas, badge, 13, onDark ? const Color(0xFF003B46) : Colors.white);

    for (var i = 0; i < 3; i++) {
      final f = (t * 1.1 + i / 3) % 1.0;
      final x = w * 0.88 - f * w * 0.10;
      final y = ground - h * (0.06 + i * 0.07);
      canvas.drawLine(
        Offset(x, y),
        Offset(x + w * 0.05, y),
        Paint()
          ..color = accent.withValues(alpha: (1 - f) * 0.6)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
    }
    _node(canvas, Offset(w * 0.30, h * 0.12), t, onDark);
    _node(canvas, Offset(w * 0.62, h * 0.08), t + 0.5, onDark);
    final link = Paint()
      ..color = ink.withValues(alpha: 0.32)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(w * 0.30, h * 0.12),
      Offset(w * 0.62, h * 0.08),
      link,
    );
    canvas.drawLine(
      Offset(w * 0.62, h * 0.08),
      badge - const Offset(0, 22),
      link,
    );
  }

  @override
  bool shouldRepaint(covariant OrdersPainter old) =>
      old.t != t || old.onDark != onDark;
}

/// Warehouse shelving with boxes and a scanning beam.
class InventoryPainter extends CustomPainter {
  InventoryPainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = _ink(onDark);
    final accent = _accent(onDark);
    final ground = h * 0.9;
    _ground(canvas, size, onDark);

    final shelf = Rect.fromLTWH(
      w * 0.12,
      h * 0.16,
      w * 0.76,
      ground - h * 0.16,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(shelf, const Radius.circular(6)),
      _line(onDark),
    );
    const rows = 3;
    for (var r = 1; r < rows; r++) {
      final y = shelf.top + shelf.height * r / rows;
      canvas.drawLine(
        Offset(shelf.left, y),
        Offset(shelf.right, y),
        _line(onDark),
      );
    }
    final cellH = shelf.height / rows;
    const boxes = <List<double>>[
      [0.08, 0.28, 0.6],
      [0.42, 0.22, 0.75],
      [0.7, 0.2, 0.5],
      [0.1, 0.24, 0.8],
      [0.4, 0.3, 0.55],
      [0.76, 0.16, 0.7],
      [0.06, 0.3, 0.5],
      [0.44, 0.2, 0.85],
      [0.68, 0.24, 0.6],
    ];
    for (var i = 0; i < boxes.length; i++) {
      final row = i ~/ 3;
      final b = boxes[i];
      final bw = shelf.width * b[1];
      final bh = cellH * b[2] * 0.85;
      final r = Rect.fromLTWH(
        shelf.left + shelf.width * b[0],
        shelf.top + cellH * (row + 1) - bh - 1.5,
        bw,
        bh,
      );
      final hot = i % 4 == 1;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        Paint()
          ..color = (hot ? accent : ink).withValues(alpha: hot ? 0.55 : 0.16),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        _line(onDark, width: 1.1),
      );
    }

    final y = shelf.top + shelf.height * (0.5 + 0.5 * math.sin(t * _tau));
    canvas.drawRect(
      Rect.fromLTWH(shelf.left - 6, y - 1, shelf.width + 12, 2),
      Paint()..color = accent.withValues(alpha: 0.85),
    );
    canvas.drawRect(
      Rect.fromLTWH(shelf.left - 6, y - 10, shelf.width + 12, 20),
      Paint()..color = accent.withValues(alpha: 0.10),
    );
    _node(canvas, Offset(w * 0.06, h * 0.12), t, onDark);
  }

  @override
  bool shouldRepaint(covariant InventoryPainter old) =>
      old.t != t || old.onDark != onDark;
}

/// A wallet with coins dropping in and a rising trend line.
class FinancePainter extends CustomPainter {
  FinancePainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = _ink(onDark);
    final accent = _accent(onDark);
    final ground = h * 0.9;
    _ground(canvas, size, onDark);

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.14, h * 0.42, w * 0.56, h * 0.44),
      const Radius.circular(12),
    );
    canvas.drawRRect(body, _fill(onDark));
    canvas.drawRRect(body, _line(onDark));
    canvas.drawLine(
      Offset(w * 0.14, h * 0.54),
      Offset(w * 0.70, h * 0.54),
      _line(onDark, alpha: 0.35),
    );
    final clasp = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.56, h * 0.60, w * 0.20, h * 0.14),
      const Radius.circular(8),
    );
    canvas.drawRRect(clasp, Paint()..color = accent.withValues(alpha: 0.28));
    canvas.drawRRect(clasp, _line(onDark));
    canvas.drawCircle(Offset(w * 0.62, h * 0.67), 3, Paint()..color = accent);

    for (var i = 0; i < 3; i++) {
      final f = (t + i / 3) % 1.0;
      final x = w * (0.26 + i * 0.12);
      final y = h * (0.08 + 0.36 * Curves.easeIn.transform(f));
      final a = f < 0.85 ? 1.0 : (1 - (f - 0.85) / 0.15);
      canvas.drawCircle(
        Offset(x, y),
        11,
        Paint()..color = accent.withValues(alpha: 0.85 * a),
      );
      canvas.drawCircle(
        Offset(x, y),
        11,
        Paint()
          ..color = ink.withValues(alpha: 0.5 * a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
      canvas.drawCircle(
        Offset(x, y),
        5,
        Paint()
          ..color = ink.withValues(alpha: 0.35 * a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    final base = Offset(w * 0.78, ground - h * 0.06);
    final pts = [
      base,
      base + Offset(w * 0.06, -h * 0.10),
      base + Offset(w * 0.11, -h * 0.05),
      base + Offset(w * 0.17, -h * 0.26),
    ];
    final trend = Path()..moveTo(pts[0].dx, pts[0].dy);
    final prog = (t * 1.2) % 1.0;
    final total = pts.length - 1;
    for (var i = 1; i < pts.length; i++) {
      final seg = ((prog * total) - (i - 1)).clamp(0.0, 1.0);
      if (seg <= 0) break;
      final p = Offset.lerp(pts[i - 1], pts[i], seg)!;
      trend.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      trend,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    _node(canvas, Offset(w * 0.86, h * 0.14), t + 0.3, onDark);
  }

  @override
  bool shouldRepaint(covariant FinancePainter old) =>
      old.t != t || old.onDark != onDark;
}

/// Bars rising with a trend line and a magnifier on the data.
class AnalyticsPainter extends CustomPainter {
  AnalyticsPainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final ink = _ink(onDark);
    final accent = _accent(onDark);
    final ground = h * 0.9;
    _ground(canvas, size, onDark);

    const heights = [0.30, 0.46, 0.38, 0.62, 0.52];
    final rise = Curves.easeOutCubic.transform(
      (math.sin(t * _tau - math.pi / 2) + 1) / 2,
    );
    final barW = w * 0.09;
    final centers = <Offset>[];
    for (var i = 0; i < heights.length; i++) {
      final bh = h * heights[i] * (0.75 + 0.25 * rise);
      final x = w * (0.16 + i * 0.14);
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, ground - bh, barW, bh),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      final hot = i == 3;
      canvas.drawRRect(
        r,
        Paint()
          ..color = (hot ? accent : ink).withValues(alpha: hot ? 0.7 : 0.18),
      );
      canvas.drawRRect(r, _line(onDark, width: 1.2));
      centers.add(Offset(x + barW / 2, ground - bh - 10));
    }
    final path = Path()..moveTo(centers.first.dx, centers.first.dy);
    for (final c in centers.skip(1)) {
      path.lineTo(c.dx, c.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final c in centers) {
      canvas.drawCircle(c, 3.4, Paint()..color = ink);
      canvas.drawCircle(c, 1.8, Paint()..color = accent);
    }

    final mx = w * (0.62 + 0.10 * math.sin(t * _tau));
    final m = Offset(mx, h * 0.28);
    canvas.drawCircle(m, 17, Paint()..color = accent.withValues(alpha: 0.12));
    canvas.drawCircle(m, 17, _line(onDark, width: 2));
    canvas.drawLine(
      m + const Offset(12, 12),
      m + const Offset(24, 24),
      _line(onDark, width: 3),
    );
    _node(canvas, Offset(w * 0.12, h * 0.12), t, onDark);
  }

  @override
  bool shouldRepaint(covariant AnalyticsPainter old) =>
      old.t != t || old.onDark != onDark;
}

/// Two interlocking gears turning, with a tick badge.
class SettingsPainter extends CustomPainter {
  SettingsPainter({required this.t, required this.onDark});

  final double t;
  final bool onDark;

  void _gear(
    Canvas canvas,
    Offset c,
    double r,
    int teeth,
    double angle,
    Paint fill,
    Paint line,
  ) {
    final path = Path();
    final inner = r * 0.78;
    Offset p(double a, double rad) =>
        c + Offset(math.cos(a), math.sin(a)) * rad;
    for (var i = 0; i < teeth; i++) {
      final a0 = angle + i * _tau / teeth;
      final a1 = a0 + _tau / teeth * 0.22;
      final a2 = a0 + _tau / teeth * 0.5;
      final a3 = a0 + _tau / teeth * 0.72;
      if (i == 0) path.moveTo(p(a0, inner).dx, p(a0, inner).dy);
      path.lineTo(p(a1, r).dx, p(a1, r).dy);
      path.lineTo(p(a2, r).dx, p(a2, r).dy);
      path.lineTo(p(a3, inner).dx, p(a3, inner).dy);
      final next = a0 + _tau / teeth;
      path.lineTo(p(next, inner).dx, p(next, inner).dy);
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, line);
    canvas.drawCircle(c, r * 0.34, line);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final accent = _accent(onDark);
    _ground(canvas, size, onDark);
    final big = Offset(w * 0.40, h * 0.50);
    final small = Offset(w * 0.66, h * 0.66);
    _gear(
      canvas,
      big,
      h * 0.27,
      10,
      t * _tau * 0.25,
      _fill(onDark),
      _line(onDark),
    );
    _gear(
      canvas,
      small,
      h * 0.17,
      7,
      -t * _tau * 0.25 * (10 / 7) + 0.2,
      Paint()..color = accent.withValues(alpha: 0.25),
      _line(onDark),
    );
    final s = 1 + 0.07 * math.sin(t * _tau * 2);
    final badge = Offset(w * 0.78, h * 0.26);
    canvas.drawCircle(
      badge,
      17 * s,
      Paint()..color = accent.withValues(alpha: 0.18),
    );
    canvas.drawCircle(badge, 12 * s, Paint()..color = accent);
    _tick(canvas, badge, 11, onDark ? const Color(0xFF003B46) : Colors.white);
    _node(canvas, Offset(w * 0.16, h * 0.16), t, onDark);
  }

  @override
  bool shouldRepaint(covariant SettingsPainter old) =>
      old.t != t || old.onDark != onDark;
}
