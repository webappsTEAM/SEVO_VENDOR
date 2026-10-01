import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/jobs/domain/job.dart';
import 'package:mobile/features/jobs/domain/job_payment.dart';
import 'package:mobile/features/jobs/presentation/widgets/category_helper.dart';

void main() {
  group('Job Domain Model & JSON Parsing', () {
    test('parses full Job JSON with cart items and customer contact', () {
      final json = {
        'id': 2649,
        'request_id': 'EL0827',
        'customer_name': 'Thejjaa',
        'phone': '+919876543210',
        'email': 'customer@example.com',
        'service_category': 'Electrical',
        'service_title': 'Modular Switch Replacement',
        'issue_title': 'Switch sparking',
        'description': 'Main hall light switch needs urgent replacement.',
        'status': 'offered',
        'priority': 'HIGH',
        'address': 'a1, 05, Bagalur Rd, KCC Nagar, Nallur, Tamil Nadu 635109',
        'latitude': 12.7409,
        'longitude': 77.8253,
        'distance_km': 0.12,
        'preferred_date': '2026-08-24',
        'preferred_time': '11:00 AM',
        'total_amount': 999.00,
        'payment_status': 'pending',
        'payment_method': 'CASH_ON_SERVICE',
        'cart_data': [
          {
            'name': 'Modular Switch (16A)',
            'description': 'Anchor Roma 16A modular switch',
            'selectedOption': '1-Way Switch',
            'quantity': 2,
          },
          {
            'name': 'Installation Labor',
            'quantity': 1,
          },
        ],
        'is_offer': true,
        'is_accepted_by_current_employee': false,
        'is_assigned_to_current_employee': false,
        'can_cancel': false,
      };

      final job = Job.fromJson(json);

      expect(job.id, equals(2649));
      expect(job.requestId, equals('EL0827'));
      expect(job.customerName, equals('Thejjaa'));
      expect(job.phone, equals('+919876543210'));
      expect(job.email, equals('customer@example.com'));
      expect(job.displayTitle, equals('Modular Switch Replacement'));
      expect(job.totalAmount, equals(999.00));
      expect(job.cartData.length, equals(2));
      expect(job.cartData[0].name, equals('Modular Switch (16A)'));
      expect(job.cartData[0].selectedOption, equals('1-Way Switch'));
      expect(job.cartData[0].quantity, equals(2));
      expect(job.hasCoordinates, isTrue);
      expect(job.isOffer, isTrue);
    });

    test('falls back correctly when titles are null', () {
      final json = {
        'id': 100,
        'request_id': '#100',
        'service_category': 'Appliance Repair',
        'status': 'assigned',
        'is_offer': false,
        'is_accepted_by_current_employee': false,
        'is_assigned_to_current_employee': false,
        'can_cancel': false,
      };

      final job = Job.fromJson(json);
      expect(job.displayTitle, equals('Appliance Repair'));
    });

    test('parses technician details from flat JSON fields', () {
      final json = {
        'id': 101,
        'request_id': 'REQ-101',
        'status': 'assigned',
        'technician_name': 'Gokul',
        'technician_phone': '9876543210',
        'technician_email': 'gokul.m@caldimengg.in',
        'technician_id': 42,
        'is_offer': false,
        'is_accepted_by_current_employee': false,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final job = Job.fromJson(json);
      expect(job.technicianName, equals('Gokul'));
      expect(job.technicianPhone, equals('9876543210'));
      expect(job.technicianEmail, equals('gokul.m@caldimengg.in'));
      expect(job.technicianId, equals(42));
    });

    test('parses technician details from nested assigned_employee object', () {
      final json = {
        'id': 102,
        'request_id': 'REQ-102',
        'status': 'in_progress',
        'assigned_employee': {
          'id': 55,
          'name': 'Priya Kumar',
          'phone': '9123456780',
          'email': 'priya.k@example.com',
        },
        'is_offer': false,
        'is_accepted_by_current_employee': true,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final job = Job.fromJson(json);
      expect(job.technicianName, equals('Priya Kumar'));
      expect(job.technicianPhone, equals('9123456780'));
      expect(job.technicianEmail, equals('priya.k@example.com'));
      expect(job.technicianId, equals(55));
    });

    test('parses technician details from nested technician object with user profile', () {
      final json = {
        'id': 103,
        'request_id': 'REQ-103',
        'status': 'assigned',
        'technician': {
          'id': 88,
          'user': {
            'first_name': 'Anand',
            'last_name': 'Raj',
            'email': 'anand.r@example.com',
          },
          'phone_number': '9988776655',
        },
        'is_offer': false,
        'is_accepted_by_current_employee': false,
        'is_assigned_to_current_employee': false,
        'can_cancel': true,
      };

      final job = Job.fromJson(json);
      expect(job.technicianName, equals('Anand Raj'));
      expect(job.technicianPhone, equals('9988776655'));
      expect(job.technicianEmail, equals('anand.r@example.com'));
      expect(job.technicianId, equals(88));
    });

    test('parses is_scheduled_future boolean correctly', () {
      final jsonFuture = {
        'id': 104,
        'request_id': 'REQ-104',
        'status': 'assigned',
        'is_scheduled_future': true,
        'is_offer': false,
        'is_accepted_by_current_employee': false,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final jobFuture = Job.fromJson(jsonFuture);
      expect(jobFuture.isScheduledFuture, isTrue);

      final jsonCurrent = {
        'id': 105,
        'request_id': 'REQ-105',
        'status': 'in_progress',
        'is_scheduled_future': false,
        'is_offer': false,
        'is_accepted_by_current_employee': true,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final jobCurrent = Job.fromJson(jsonCurrent);
      expect(jobCurrent.isScheduledFuture, isFalse);
    });

    test('resolves totalAmount from payment.amount_due when total_amount is 0', () {
      final json = {
        'id': 106,
        'request_id': 'REQ-106',
        'status': 'assigned',
        'total_amount': 0.0,
        'payment': {
          'amount_due': '59000.00',
          'amount_paid': '0.00',
          'payment_status': 'PENDING',
          'payment_method': 'CASH_ON_SERVICE',
        },
        'is_offer': false,
        'is_accepted_by_current_employee': true,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final job = Job.fromJson(json);
      expect(job.totalAmount, equals(59000.0));
      expect(job.paymentStatus, equals('PENDING'));
      expect(job.paymentMethod, equals('CASH_ON_SERVICE'));
    });

    test('preserves total_amount when payment object is missing', () {
      final json = {
        'id': 107,
        'request_id': 'REQ-107',
        'status': 'assigned',
        'total_amount': 35400.0,
        'is_offer': false,
        'is_accepted_by_current_employee': true,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final job = Job.fromJson(json);
      expect(job.totalAmount, equals(35400.0));
    });

    test('preserves total_amount when payment.amount_due is 0 or null', () {
      final json = {
        'id': 108,
        'request_id': 'REQ-108',
        'status': 'assigned',
        'total_amount': 35400.0,
        'payment': {
          'amount_due': '0.00',
          'payment_status': 'PENDING',
        },
        'is_offer': false,
        'is_accepted_by_current_employee': true,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final job = Job.fromJson(json);
      expect(job.totalAmount, equals(35400.0));
    });

    test('handles fallback gracefully when both total_amount and payment are null or zero', () {
      final jsonNull = {
        'id': 109,
        'request_id': 'REQ-109',
        'status': 'assigned',
        'is_offer': false,
        'is_accepted_by_current_employee': true,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final jobNull = Job.fromJson(jsonNull);
      expect(jobNull.totalAmount, isNull);

      final jsonZero = {
        'id': 110,
        'request_id': 'REQ-110',
        'status': 'assigned',
        'total_amount': 0.0,
        'payment': {
          'amount_due': '0.00',
        },
        'is_offer': false,
        'is_accepted_by_current_employee': true,
        'is_assigned_to_current_employee': true,
        'can_cancel': false,
      };

      final jobZero = Job.fromJson(jsonZero);
      expect(jobZero.totalAmount, equals(0.0));
    });
  });

  group('CashCollectionResult Domain Model', () {
    test('parses CASH_PENDING collection response correctly', () {
      final json = {
        'message': 'Cash collection recorded. Awaiting customer confirmation OTP.',
        'payment_status': 'CASH_PENDING',
        'amount_due': 500.0,
        'amount_received': 600.0,
        'change_returned': 100.0,
      };

      final result = CashCollectionResult.fromJson(json);
      expect(result.paymentStatus, equals('CASH_PENDING'));
      expect(result.isCashPending, isTrue);
      expect(result.isPaid, isFalse);
      expect(result.amountDue, equals(500.0));
      expect(result.amountReceived, equals(600.0));
      expect(result.changeReturned, equals(100.0));
    });

    test('parses PAID collection response correctly', () {
      final json = {
        'message': 'Cash payment confirmed! Job completed.',
        'payment_status': 'PAID',
        'amount_due': 450.0,
        'amount_received': 450.0,
        'change_returned': 0.0,
      };

      final result = CashCollectionResult.fromJson(json);
      expect(result.paymentStatus, equals('PAID'));
      expect(result.isPaid, isTrue);
      expect(result.isCashPending, isFalse);
    });
  });

  group('Category Presentation & Helper Logic', () {
    test('maps raw "mason" slug to "Masonry & Tile"', () {
      expect(formatCategoryName('mason'), equals('Masonry & Tile'));
      expect(formatCategoryName('masonry'), equals('Masonry & Tile'));
      expect(formatCategoryName('tile_fitting'), equals('Masonry & Tile'));
    });

    test('maps standard service slugs to clean presentation labels', () {
      expect(formatCategoryName('electrical'), equals('Electrical'));
      expect(formatCategoryName('ac_repair'), equals('AC & Appliances'));
      expect(formatCategoryName('plumbing'), equals('Plumbing'));
      expect(formatCategoryName('painting'), equals('Painting'));
      expect(formatCategoryName('locks_carpentry'), equals('Locks & Carpentry'));
      expect(formatCategoryName('cleaning'), equals('Cleaning'));
      expect(formatCategoryName('automotive'), equals('Automotive'));
      expect(formatCategoryName('pest_control'), equals('Pest Control'));
      expect(formatCategoryName('goods_transport_truck'), equals('Mini Truck'));
      expect(formatCategoryName('goods_transport_two_wheeler'), equals('Two-Wheeler'));
      expect(formatCategoryName('packers_movers'), equals('Packers & Movers'));
      expect(formatCategoryName(null), equals('Service Request'));
      expect(formatCategoryName(''), equals('Service Request'));
    });

    test('iconForCategory does not misclassify "replacement" as AC', () {
      // Regression test: "replacement" contains "ac" substring
      final icon = iconForCategory('Complete Bathroom Floor & Wall Tile Replacement');
      expect(icon, equals(Icons.home_repair_service_rounded));
      expect(icon, isNot(equals(Icons.ac_unit_rounded)));
    });

    test('iconForCategory correctly identifies AC and Masonry categories', () {
      expect(iconForCategory('mason'), equals(Icons.home_repair_service_rounded));
      expect(iconForCategory('Masonry & Tile'), equals(Icons.home_repair_service_rounded));
      expect(iconForCategory('AC Repair'), equals(Icons.ac_unit_rounded));
      expect(iconForCategory('Electrical'), equals(Icons.bolt_rounded));
    });
  });
}
