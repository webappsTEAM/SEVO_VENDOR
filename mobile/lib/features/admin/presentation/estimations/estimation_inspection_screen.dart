import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/photo_source_sheet.dart';
import '../../../seller/presentation/widgets/seller_hub_widgets.dart';
import '../../data/vendor_estimation_repository.dart';
import '../../domain/vendor_estimation.dart';
import 'admin_estimation_detail_screen.dart' show severityColor;

typedef _Opts = List<(String, String)>;

const _acTypes = <(String, String)>[
  ('Split AC', 'Split AC (Inverter)'),
  ('Non-Inverter Split', 'Split AC (Non-Inverter)'),
  ('Window AC', 'Window AC'),
  ('Cassette AC', 'Cassette AC'),
  ('Tower AC', 'Tower AC'),
];
const _capacities = <(String, String)>[
  ('0.75_TON', '0.75 Ton'),
  ('1.0_TON', '1.0 Ton'),
  ('1.5_TON', '1.5 Ton'),
  ('2.0_TON', '2.0 Ton'),
  ('2.5_TON', '2.5+ Ton'),
];
const _gases = <(String, String)>[
  ('R32', 'R32 (Eco Inverter)'),
  ('R410A', 'R410A (Inverter Dual)'),
  ('R22', 'R22 (Hydrochlorofluorocarbon)'),
  ('R134A', 'R134A'),
];
const _ages = <(String, String)>[
  ('Under 1 Year', 'Under 1 Year'),
  ('1-3 Years', '1 - 3 Years'),
  ('3-5 Years', '3 - 5 Years'),
  ('5-8 Years', '5 - 8 Years'),
  ('8+ Years', '8+ Years'),
];
const _severities = <(String, String)>[
  ('LOW', 'LOW (Minor cosmetic / routine)'),
  ('MEDIUM', 'MEDIUM (Requires attention)'),
  ('HIGH', 'HIGH (Affects cooling efficiency)'),
  ('CRITICAL', 'CRITICAL (System inoperable / risk)'),
];

/// (key, label, options) — Web "Multi-Point Checklist", indoor then outdoor.
const _indoor = <(String, String, _Opts)>[
  (
    'indoor_filter',
    'Air Filter',
    [
      ('CLEAN', 'Clean & Clear'),
      ('CHOKED', 'Choked with Dust'),
      ('TORN', 'Torn / Damaged'),
    ],
  ),
  (
    'indoor_coil',
    'Evaporator Coil',
    [
      ('CLEAN', 'Clean Fins'),
      ('DIRTY', 'Dust & Slime Accumulation'),
      ('RUSTED', 'Rusted / Aluminum Corrosion'),
      ('ICE_FROST', 'Ice Formation / Freezing'),
    ],
  ),
  (
    'blower_fan',
    'Blower Motor & Wheel',
    [
      ('NORMAL', 'Normal Air Throw'),
      ('NOISY', 'Noisy / Bearing Play'),
      ('WEAK', 'Weak Air Throw'),
      ('JAMMED', 'Jammed / Not Rotating'),
    ],
  ),
  (
    'drain_tray',
    'Drain Tray & Pipe',
    [
      ('CLEAR', 'Clear Flow'),
      ('CHOKED', 'Choked / Algae Buildup'),
      ('LEAKING', 'Water Dripping on Wall'),
    ],
  ),
  (
    'swing_motor',
    'Swing Louver / Motor',
    [('WORKING', 'Working Smoothly'), ('STUCK', 'Stuck / Step Motor Defect')],
  ),
];
const _outdoor = <(String, String, _Opts)>[
  (
    'outdoor_coil',
    'Condenser Coil',
    [
      ('CLEAN', 'Clean & Free Airflow'),
      ('DUSTY', 'Choked with Grime/Dirt'),
      ('FINS_DAMAGED', 'Fins Bent / Damaged'),
    ],
  ),
  (
    'compressor_status',
    'Compressor Operation',
    [
      ('RUNNING_NORMAL', 'Running Smoothly'),
      ('OVERHEATING', 'Overheating & Tripping'),
      ('NOT_STARTING', 'Humming / Not Starting'),
      ('GROUNDED', 'Shorted / Breaker Trip'),
    ],
  ),
  (
    'condenser_fan',
    'Condenser Fan Motor',
    [
      ('NORMAL', 'Normal Speed'),
      ('NOISY', 'Noisy Vibration'),
      ('SLOW', 'Slow / Overheated'),
      ('JAMMED', 'Jammed / Burnt'),
    ],
  ),
  (
    'service_valves',
    'Service Flare Valves',
    [
      ('NORMAL', 'Dry & Tight'),
      ('OIL_TRACES', 'Oil Traces (Leak Indication)'),
      ('FROST', 'Ice Frost on Flare Nut'),
    ],
  ),
  (
    'capacitor_status',
    'Run Capacitor (uF)',
    [
      ('NORMAL', 'Within Spec (±5%)'),
      ('WEAK', 'Weak / Below Capacity'),
      ('BULGED', 'Bulged / Blown'),
    ],
  ),
];
const _readings = <(String, String, String)>[
  ('voltage_reading', 'Line Voltage', 'e.g. 230V'),
  ('standing_pressure', 'Gas Standing Pressure', 'e.g. 135 PSI'),
  ('cooling_delta_t', 'Cooling Performance (ΔT)', 'e.g. 10°C'),
];

/// Quick-add defect templates of the Web inspection sheet (suggested wording
/// the technician edits; none is recorded until it is added).
const _templates = <Map<String, dynamic>>[
  {
    'finding_type': 'Gas Leakage',
    'title': 'Refrigerant Gas Leakage at Flare Nut',
    'severity': 'HIGH',
    'description':
        'Oil traces and pressure drop detected at service valve connection.',
    'recommended_action': 'Perform nitrogen leak test, braze flare joint, vacuum system, and top up gas.',
    'quantity': 1,
    'unit': 'refill',
  },
  {
    'finding_type': 'Coil Cleaning',
    'title': 'Severe Cooling Coil Clogging & Slime',
    'severity': 'MEDIUM',
    'description': 'Indoor evaporator coil choked with grime, restricting airflow by >50%.',
    'recommended_action':
        'Deep chemical foam jet wash of indoor and outdoor condenser coil.',
    'quantity': 1,
    'unit': 'service',
  },
  {
    'finding_type': 'Capacitor',
    'title': 'Compressor Run Capacitor Weak / Bulged',
    'severity': 'HIGH',
    'description': 'Dual capacitor measured below rated capacity.',
    'recommended_action': 'Replace with genuine heavy-duty capacitor.',
    'quantity': 1,
    'unit': 'piece',
  },
  {
    'finding_type': 'PCB fault',
    'title': 'Indoor/Outdoor Inverter PCB Fault',
    'severity': 'CRITICAL',
    'description':
        'Communication error code blinking on display; IPM circuit damaged.',
    'recommended_action':
        'Bench test and repair motherboard circuit / replace IPM module.',
    'quantity': 1,
    'unit': 'unit',
  },
  {
    'finding_type': 'Fan Motor',
    'title': 'Condenser Fan Motor Bearing Jammed',
    'severity': 'HIGH',
    'description':
        'Outdoor unit motor overheating and shutting down within 5 minutes.',
    'recommended_action':
        'Replace condenser fan motor and inspect blade alignment.',
    'quantity': 1,
    'unit': 'unit',
  },
  {
    'finding_type': 'Drainage',
    'title': 'Condensate Drain Tray Overflow & Clog',
    'severity': 'LOW',
    'description': 'Water dripping from indoor unit front panel onto walls.',
    'recommended_action':
        'Flush drain pipe, re-pitch slope, and clean drain tray.',
    'quantity': 1,
    'unit': 'service',
  },
];

/// Web `TechnicianInspectionSheet` — on-site AC audit: specs, checklist,
/// defect findings, photo evidence and diagnosis. Pops `true` when completed.
class EstimationInspectionScreen extends ConsumerStatefulWidget {
  const EstimationInspectionScreen({super.key, required this.lead});

  final VendorEstimation lead;

  @override
  ConsumerState<EstimationInspectionScreen> createState() =>
      _EstimationInspectionScreenState();
}

class _EstimationInspectionScreenState
    extends ConsumerState<EstimationInspectionScreen> {
  late final _brand = TextEditingController(text: widget.lead.acBrand ?? '');
  late final _model = TextEditingController(
    text:
        '${widget.lead.raw['ac_details'] is Map ? (widget.lead.raw['ac_details'] as Map)['model_number'] ?? '' : ''}',
  );
  late String _type = _acTypes.any((t) => t.$1 == widget.lead.acType)
      ? widget.lead.acType!
      : 'Split AC';
  late String _capacity = _capacities.any((t) => t.$1 == widget.lead.acCapacity)
      ? widget.lead.acCapacity!
      : '1.5_TON';
  String _gas = 'R32';
  String _age = '3-5 Years';

  // Web defaults for the checklist form.
  final Map<String, String> _checklist = {
    'indoor_filter': 'CHOKED',
    'indoor_coil': 'DIRTY',
    'blower_fan': 'NORMAL',
    'drain_tray': 'CLEAR',
    'swing_motor': 'WORKING',
    'outdoor_coil': 'DUSTY',
    'compressor_status': 'RUNNING_NORMAL',
    'condenser_fan': 'NORMAL',
    'service_valves': 'NORMAL',
    'capacitor_status': 'NORMAL',
    'voltage_reading': '230V Normal',
    'standing_pressure': '135 PSI',
    'cooling_delta_t': '8°C (Normal is 10-14°C)',
    'pcb_status': 'NORMAL',
    'earthing_status': 'GOOD',
    'leakage_detected': 'NO',
  };
  final Map<String, TextEditingController> _readingCtl = {};

  late final List<Map<String, dynamic>> _findings = [
    for (final f
        in (widget.lead.raw['findings'] is List
            ? widget.lead.raw['findings'] as List
            : const []))
      if (f is Map) Map<String, dynamic>.from(f),
  ];
  late final List<Map<String, dynamic>> _photos = [
    for (final p
        in (widget.lead.raw['photos'] is List
            ? widget.lead.raw['photos'] as List
            : const []))
      if (p is Map) Map<String, dynamic>.from(p),
  ];
  late final _diagnosis = TextEditingController(
    text:
        _inspectionText('diagnosis') ??
        'Thorough inspection completed for ${widget.lead.acBrand ?? 'AC'} ${widget.lead.acType ?? 'Split'}. Root cause identified.',
  );
  late final _notes = TextEditingController(
    text: _inspectionText('notes') ?? '',
  );
  bool _uploading = false;
  bool _submitting = false;
  String? _error;

  String? _inspectionText(String key) {
    final i = widget.lead.raw['inspection'];
    return i is Map && i[key] != null && '${i[key]}'.isNotEmpty
        ? '${i[key]}'
        : null;
  }

  @override
  void initState() {
    super.initState();
    for (final r in _readings) {
      _readingCtl[r.$1] = TextEditingController(text: _checklist[r.$1]);
    }
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _diagnosis.dispose();
    _notes.dispose();
    for (final c in _readingCtl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final path = await pickJobPhoto(context);
    if (path == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final name = path.split(RegExp(r'[\\/]')).last;
      final photo = await ref
          .read(vendorEstimationRepositoryProvider)
          .uploadInspectionPhoto(
            widget.lead.id,
            path,
            caption: 'Defect photo - $name',
          );
      if (photo != null && mounted) setState(() => _photos.add(photo));
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is VendorEstimationException
              ? e.message
              : 'Failed to upload photo.',
        );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    if (_findings.isEmpty) {
      setState(
        () => _error = 'Please record at least one inspection defect finding.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = ref.read(vendorEstimationRepositoryProvider);
    try {
      for (final r in _readings) {
        _checklist[r.$1] = _readingCtl[r.$1]!.text;
      }
      await repo.saveInspectionDetails(widget.lead.id, {
        'ac_details': {
          'ac_brand': _brand.text.trim(),
          'ac_type': _type,
          'ac_capacity': _capacity,
          'gas_type': _gas,
          'unit_age': _age,
          'model_number': _model.text.trim(),
          'checklist': _checklist,
        },
        'diagnosis': _diagnosis.text,
        'notes': _notes.text,
        'findings': _findings,
      });
      await repo.completeInspection(
        widget.lead.id,
        diagnosis: _diagnosis.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e is VendorEstimationException
              ? e.message
              : 'Failed to complete inspection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('AC Inspection & Diagnosis Sheet'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: '1. AC Specs'),
              const Tab(text: '2. Checklist'),
              Tab(text: '3. Findings (${_findings.length})'),
              Tab(text: '4. Photos (${_photos.length})'),
              const Tab(text: '5. Diagnosis'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                padding: const EdgeInsets.all(10),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12.5,
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _specs(),
                  _checklistTab(),
                  _findingsTab(),
                  _photosTab(),
                  _diagnosisTab(),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          _submitting ? 'Submitting...' : 'Complete Inspection',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<(String, String)> options,
    ValueChanged<String> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DropdownButtonFormField<String>(
      initialValue: options.any((o) => o.$1 == value)
          ? value
          : options.first.$1,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o.$1,
            child: Text(o.$2, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v != null) setState(() => onChanged(v));
      },
    ),
  );

  Widget _specs() => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      Text(
        'Air Conditioner Hardware Specifications',
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      Text(
        'Verify & update on-site specs',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _brand,
        decoration: const InputDecoration(
          labelText: 'Brand Name',
          hintText: 'e.g. Daikin, Voltas, LG',
        ),
      ),
      const SizedBox(height: 10),
      _dropdown('AC Type', _type, _acTypes, (v) => _type = v),
      _dropdown(
        'Cooling Capacity',
        _capacity,
        _capacities,
        (v) => _capacity = v,
      ),
      _dropdown('Refrigerant Gas', _gas, _gases, (v) => _gas = v),
      _dropdown('Estimated Unit Age', _age, _ages, (v) => _age = v),
      TextField(
        controller: _model,
        decoration: const InputDecoration(
          labelText: 'Model / Serial Number',
          hintText: 'e.g. FTKM50TV16U',
        ),
      ),
    ],
  );

  Widget _checklistTab() => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      SellerSectionLabel('Indoor Unit'),
      const SizedBox(height: 8),
      for (final c in _indoor)
        _dropdown(c.$2, _checklist[c.$1]!, c.$3, (v) => _checklist[c.$1] = v),
      SellerSectionLabel('Outdoor Unit & Electrical'),
      const SizedBox(height: 8),
      for (final c in _outdoor)
        _dropdown(c.$2, _checklist[c.$1]!, c.$3, (v) => _checklist[c.$1] = v),
      for (final r in _readings)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _readingCtl[r.$1],
            decoration: InputDecoration(labelText: r.$2, hintText: r.$3),
          ),
        ),
    ],
  );

  Widget _findingsTab() => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      Text(
        'Quick-add common defects',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in _templates)
            FilterChip(
              label: Text('${t['finding_type']}'),
              selected: _findings.any((f) => f['title'] == t['title']),
              onSelected: (_) {
                if (!_findings.any((f) => f['title'] == t['title']))
                  setState(() => _findings.add(Map<String, dynamic>.from(t)));
              },
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Custom Finding'),
            onPressed: () => setState(
              () => _findings.add({
                'finding_type': 'Custom',
                'title': 'Custom AC Finding',
                'severity': 'MEDIUM',
                'description': '',
                'recommended_action': '',
                'quantity': 1,
                'unit': 'unit',
              }),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (_findings.isEmpty)
        const SellerStateMessage(
          icon: Icons.fact_check_outlined,
          title: 'No findings yet',
          message:
              'Add at least one defect finding to complete the inspection.',
        )
      else
        for (var i = 0; i < _findings.length; i++)
          _FindingEditor(
            key: ObjectKey(_findings[i]),
            finding: _findings[i],
            onChanged: () => setState(() {}),
            onRemove: () => setState(() => _findings.removeAt(i)),
          ),
    ],
  );

  Widget _photosTab() => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      FilledButton.icon(
        onPressed: _uploading ? null : _addPhoto,
        icon: const Icon(Icons.photo_camera_rounded, size: 18),
        label: Text(_uploading ? 'Uploading...' : 'Add Defect Photo'),
      ),
      const SizedBox(height: 12),
      if (_photos.isEmpty)
        const SellerStateMessage(
          icon: Icons.photo_outlined,
          title: 'No photos',
          message: 'Photo evidence is optional but recommended.',
        )
      else
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final p in _photos)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  '${p['url'] ?? p['photo'] ?? p['image'] ?? ''}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.surfaceMuted,
                    child: Icon(
                      Icons.image_outlined,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
    ],
  );

  Widget _diagnosisTab() => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      TextField(
        controller: _diagnosis,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Diagnosis Summary',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _notes,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Internal Notes',
          alignLabelWithHint: true,
        ),
      ),
    ],
  );
}

class _FindingEditor extends StatefulWidget {
  const _FindingEditor({
    super.key,
    required this.finding,
    required this.onChanged,
    required this.onRemove,
  });

  final Map<String, dynamic> finding;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_FindingEditor> createState() => _FindingEditorState();
}

class _FindingEditorState extends State<_FindingEditor> {
  late final _title = TextEditingController(
    text: '${widget.finding['title'] ?? ''}',
  );
  late final _desc = TextEditingController(
    text: '${widget.finding['description'] ?? ''}',
  );
  late final _fix = TextEditingController(
    text: '${widget.finding['recommended_action'] ?? ''}',
  );
  late final _qty = TextEditingController(
    text: '${widget.finding['quantity'] ?? 1}',
  );

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _fix.dispose();
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.finding;
    final severity = '${f['severity'] ?? 'MEDIUM'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: severityColor(severity).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${f['finding_type'] ?? 'Finding'}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onRemove,
                tooltip: 'Remove finding',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          TextField(
            controller: _title,
            onChanged: (v) => f['title'] = v,
            decoration: const InputDecoration(labelText: 'Finding title'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _severities.any((s) => s.$1 == severity)
                ? severity
                : 'MEDIUM',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Severity'),
            items: [
              for (final s in _severities)
                DropdownMenuItem(
                  value: s.$1,
                  child: Text(s.$2, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              f['severity'] = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            onChanged: (v) => f['description'] = v,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observation',
              hintText: 'Detailed inspection observations...',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _fix,
            onChanged: (v) => f['recommended_action'] = v,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Recommended action',
              hintText: 'Action recommended for quotation builder...',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) => f['quantity'] = double.tryParse(v) ?? 1,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: '${f['unit'] ?? 'unit'}',
                  onChanged: (v) => f['unit'] = v,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
