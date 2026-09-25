import React, { useState, useEffect } from 'react';
import {
  X,
  Plus,
  Trash2,
  Camera,
  CheckCircle2,
  AlertTriangle,
  FileText,
  Upload,
  Loader2,
  Wrench,
  Sparkles,
  Layers,
  Activity,
  Gauge,
  Zap,
  Check,
} from 'lucide-react';
import {
  apiSaveInspectionFindings,
  apiUploadInspectionPhoto,
  apiCompleteInspection,
  apiSaveInspectionDetails,
} from '../../api/vendorEstimationService.js';

const DEFECT_TEMPLATES = [
  {
    type: 'Gas Leakage',
    title: 'Refrigerant Gas Leakage at Flare Nut',
    severity: 'HIGH',
    description: 'Oil traces and pressure drop detected at service valve connection.',
    recommended_action: 'Perform nitrogen leak test, braze flare joint, vacuum system, and top up gas.',
    quantity: 1,
    unit: 'refill',
  },
  {
    type: 'Coil Cleaning',
    title: 'Severe Cooling Coil Clogging & Slime',
    severity: 'MEDIUM',
    description: 'Indoor evaporator coil choked with grime, restricting airflow by >50%.',
    recommended_action: 'Deep chemical foam jet wash of indoor and outdoor condenser coil.',
    quantity: 1,
    unit: 'service',
  },
  {
    type: 'Capacitor',
    title: 'Compressor Run Capacitor Weak / Bulged',
    severity: 'HIGH',
    description: 'Dual capacitor measured 18uF against 45uF rated capacity.',
    recommended_action: 'Replace with genuine 45/5 uF heavy-duty capacitor.',
    quantity: 1,
    unit: 'piece',
  },
  {
    type: 'PCB fault',
    title: 'Indoor/Outdoor Inverter PCB Fault',
    severity: 'CRITICAL',
    description: 'Communication error code blinking on display; IPM circuit damaged.',
    recommended_action: 'Bench test and repair motherboard circuit / replace IPM module.',
    quantity: 1,
    unit: 'unit',
  },
  {
    type: 'Fan Motor',
    title: 'Condenser Fan Motor Bearing Jammed',
    severity: 'HIGH',
    description: 'Outdoor unit motor overheating and shutting down within 5 minutes.',
    recommended_action: 'Replace condenser fan motor and inspect blade alignment.',
    quantity: 1,
    unit: 'unit',
  },
  {
    type: 'Drainage',
    title: 'Condensate Drain Tray Overflow & Clog',
    severity: 'LOW',
    description: 'Water dripping from indoor unit front panel onto walls.',
    recommended_action: 'Flush drain pipe, re-pitch slope, and clean drain tray.',
    quantity: 1,
    unit: 'service',
  },
];

const SEVERITY_COLORS = {
  LOW: 'bg-emerald-50 text-emerald-700 border-emerald-200',
  MEDIUM: 'bg-amber-50 text-amber-700 border-amber-200',
  HIGH: 'bg-orange-50 text-orange-700 border-orange-200',
  CRITICAL: 'bg-rose-50 text-rose-700 border-rose-200',
};

export default function TechnicianInspectionSheet({
  estimation,
  isOpen,
  onClose,
  onComplete,
}) {
  const [activeTab, setActiveTab] = useState('specs'); // 'specs' | 'checklist' | 'findings' | 'photos' | 'diagnosis'
  
  // AC Specs State
  const [acBrand, setAcBrand] = useState('');
  const [acType, setAcType] = useState('Split AC');
  const [acCapacity, setAcCapacity] = useState('1.5_TON');
  const [gasType, setGasType] = useState('R32');
  const [unitAge, setUnitAge] = useState('3-5 Years');
  const [modelNo, setModelNo] = useState('');

  // Checklist State
  const [checklist, setChecklist] = useState({
    indoor_filter: 'CHOKED',
    indoor_coil: 'DIRTY',
    blower_fan: 'NORMAL',
    drain_tray: 'CLEAR',
    swing_motor: 'WORKING',
    outdoor_coil: 'DUSTY',
    compressor_status: 'RUNNING_NORMAL',
    condenser_fan: 'NORMAL',
    service_valves: 'NORMAL',
    voltage_reading: '230V Normal',
    capacitor_status: 'NORMAL',
    pcb_status: 'NORMAL',
    earthing_status: 'GOOD',
    standing_pressure: '135 PSI',
    cooling_delta_t: '8°C (Normal is 10-14°C)',
    leakage_detected: 'NO',
  });

  // Findings, Diagnosis, Photos
  const [findings, setFindings] = useState([]);
  const [diagnosis, setDiagnosis] = useState('');
  const [notes, setNotes] = useState('');
  const [photos, setPhotos] = useState([]);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (isOpen) {
      setError(null);
      
      // Pre-fill AC specs
      setAcBrand(estimation?.ac_details?.ac_brand || 'Daikin');
      setAcType(estimation?.ac_details?.ac_type || 'Split AC');
      setAcCapacity(estimation?.ac_details?.ac_capacity || '1.5_TON');
      setModelNo(estimation?.ac_details?.model_number || '');
      setGasType(estimation?.ac_details?.gas_type || 'R32');

      // Populate existing findings if any
      const existingFindings = estimation?.findings || [];
      if (existingFindings.length > 0) {
        setFindings(existingFindings);
      } else {
        setFindings([DEFECT_TEMPLATES[0]]);
      }

      setDiagnosis(
        estimation?.inspection?.diagnosis ||
          `Thorough inspection completed for ${estimation?.ac_details?.ac_brand || 'AC'} ${
            estimation?.ac_details?.ac_type || 'Split'
          }. Root cause identified.`
      );
      setNotes(estimation?.inspection?.notes || '');
      setPhotos(estimation?.photos || []);
    }
  }, [isOpen, estimation]);

  if (!isOpen) return null;

  const handleAddTemplate = (tpl) => {
    if (!findings.some((f) => f.title === tpl.title)) {
      setFindings([...findings, { ...tpl }]);
    }
  };

  const handleRemoveFinding = (index) => {
    setFindings(findings.filter((_, idx) => idx !== index));
  };

  const handleUpdateFinding = (index, field, value) => {
    const updated = [...findings];
    updated[index] = { ...updated[index], [field]: value };
    setFindings(updated);
  };

  const handleChecklistChange = (key, val) => {
    setChecklist((prev) => ({ ...prev, [key]: val }));
  };

  const handlePhotoUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploadingPhoto(true);
    setError(null);
    try {
      const formData = new FormData();
      formData.append('photo', file);
      formData.append('caption', `Defect photo - ${file.name}`);

      const res = await apiUploadInspectionPhoto(estimation.id, formData);
      if (res?.photo) {
        setPhotos((prev) => [...prev, res.photo]);
      }
    } catch (err) {
      setError(err.message || 'Failed to upload photo.');
    } finally {
      setUploadingPhoto(false);
    }
  };

  const handleSubmit = async () => {
    if (findings.length === 0) {
      setError('Please record at least one inspection defect finding.');
      return;
    }

    setSubmitting(true);
    setError(null);
    try {
      // 1. Save complete AC inspection details & specs
      const fullDetails = {
        ac_details: {
          ac_brand: acBrand,
          ac_type: acType,
          ac_capacity: acCapacity,
          gas_type: gasType,
          unit_age: unitAge,
          model_number: modelNo,
          checklist: checklist,
        },
        diagnosis: diagnosis,
        notes: notes,
        findings: findings,
      };

      await apiSaveInspectionDetails(estimation.id, fullDetails);

      // 2. Mark inspection complete with diagnosis summary
      const completeRes = await apiCompleteInspection(estimation.id, {
        diagnosis_summary: diagnosis,
        notes: notes,
      });

      onComplete?.(completeRes?.data || completeRes);
      onClose();
    } catch (err) {
      setError(err.message || 'Failed to complete inspection.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 bg-zinc-950/70 backdrop-blur-xs animate-in fade-in overflow-y-auto">
      <div className="relative w-full max-w-4xl bg-white rounded-2xl shadow-2xl border border-zinc-200 overflow-hidden my-auto max-h-[94vh] flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-zinc-100 bg-zinc-50 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-blue-600 text-white flex items-center justify-center shadow-xs">
              <Wrench className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-sm sm:text-base font-bold text-zinc-900">
                  Technician AC Inspection & Diagnosis Sheet
                </h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-blue-50 text-blue-700 border border-blue-200">
                  On-Site Audit
                </span>
              </div>
              <p className="text-xs text-zinc-500">
                Job #{estimation?.request_id} • Customer: {estimation?.customer_name} • {acBrand} {acType}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-zinc-400 hover:text-zinc-700 hover:bg-zinc-200 transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Navigation Tabs */}
        <div className="flex items-center gap-1 px-6 pt-3 border-b border-zinc-100 bg-white overflow-x-auto shrink-0">
          {[
            { id: 'specs', label: '1. AC Specifications', icon: Layers },
            { id: 'checklist', label: '2. Multi-Point Checklist', icon: Activity },
            { id: 'findings', label: `3. Defect Findings (${findings.length})`, icon: Gauge },
            { id: 'photos', label: `4. Photo Evidence (${photos.length})`, icon: Camera },
            { id: 'diagnosis', label: '5. Diagnosis Summary', icon: Sparkles },
          ].map((tab) => {
            const Icon = tab.icon;
            const isActive = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold border-b-2 transition-all whitespace-nowrap ${
                  isActive
                    ? 'border-blue-600 text-blue-600 bg-blue-50/50'
                    : 'border-transparent text-zinc-600 hover:text-zinc-900 hover:bg-zinc-50'
                }`}
              >
                <Icon className="w-3.5 h-3.5" />
                <span>{tab.label}</span>
              </button>
            );
          })}
        </div>

        {/* Scrollable Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6 text-xs">
          {error && (
            <div className="p-3 bg-red-50 border border-red-200 rounded-xl flex items-center gap-2 text-red-700 font-medium">
              <AlertTriangle className="w-4 h-4 shrink-0 text-red-500" />
              <span>{error}</span>
            </div>
          )}

          {/* TAB 1: AC Specifications */}
          {activeTab === 'specs' && (
            <div className="space-y-4">
              <div className="flex items-center justify-between pb-2 border-b border-zinc-100">
                <h3 className="text-xs font-bold text-zinc-900 uppercase tracking-wider">
                  Air Conditioner Hardware Specifications
                </h3>
                <span className="text-[11px] text-zinc-400">Verify & update on-site specs</span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs font-semibold text-zinc-700 mb-1">Brand Name</label>
                  <input
                    type="text"
                    value={acBrand}
                    onChange={(e) => setAcBrand(e.target.value)}
                    placeholder="e.g. Daikin, Voltas, LG"
                    className="w-full px-3 py-2 bg-white border border-zinc-200 rounded-lg text-xs font-medium"
                  />
                </div>

                <div>
                  <label className="block text-xs font-semibold text-zinc-700 mb-1">AC Type</label>
                  <select
                    value={acType}
                    onChange={(e) => setAcType(e.target.value)}
                    className="w-full px-3 py-2 bg-white border border-zinc-200 rounded-lg text-xs"
                  >
                    <option value="Split AC">Split AC (Inverter)</option>
                    <option value="Non-Inverter Split">Split AC (Non-Inverter)</option>
                    <option value="Window AC">Window AC</option>
                    <option value="Cassette AC">Cassette AC</option>
                    <option value="Tower AC">Tower AC</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-zinc-700 mb-1">Cooling Capacity</label>
                  <select
                    value={acCapacity}
                    onChange={(e) => setAcCapacity(e.target.value)}
                    className="w-full px-3 py-2 bg-white border border-zinc-200 rounded-lg text-xs"
                  >
                    <option value="0.75_TON">0.75 Ton</option>
                    <option value="1.0_TON">1.0 Ton</option>
                    <option value="1.5_TON">1.5 Ton</option>
                    <option value="2.0_TON">2.0 Ton</option>
                    <option value="2.5_TON">2.5+ Ton</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-zinc-700 mb-1">Refrigerant Gas</label>
                  <select
                    value={gasType}
                    onChange={(e) => setGasType(e.target.value)}
                    className="w-full px-3 py-2 bg-white border border-zinc-200 rounded-lg text-xs"
                  >
                    <option value="R32">R32 (Eco Inverter)</option>
                    <option value="R410A">R410A (Inverter Dual)</option>
                    <option value="R22">R22 (Hydrochlorofluorocarbon)</option>
                    <option value="R134A">R134A</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-zinc-700 mb-1">Estimated Unit Age</label>
                  <select
                    value={unitAge}
                    onChange={(e) => setUnitAge(e.target.value)}
                    className="w-full px-3 py-2 bg-white border border-zinc-200 rounded-lg text-xs"
                  >
                    <option value="Under 1 Year">Under 1 Year</option>
                    <option value="1-3 Years">1 - 3 Years</option>
                    <option value="3-5 Years">3 - 5 Years</option>
                    <option value="5-8 Years">5 - 8 Years</option>
                    <option value="8+ Years">8+ Years</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-zinc-700 mb-1">Model / Serial Number</label>
                  <input
                    type="text"
                    value={modelNo}
                    onChange={(e) => setModelNo(e.target.value)}
                    placeholder="e.g. FTKM50TV16U"
                    className="w-full px-3 py-2 bg-white border border-zinc-200 rounded-lg text-xs font-mono"
                  />
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: Multi-Point Checklist */}
          {activeTab === 'checklist' && (
            <div className="space-y-5">
              {/* Indoor Unit Audit */}
              <div className="p-4 bg-zinc-50/70 border border-zinc-200 rounded-xl space-y-3">
                <div className="flex items-center gap-2">
                  <Layers className="w-4 h-4 text-blue-600" />
                  <h4 className="text-xs font-bold text-zinc-900 uppercase">Indoor Unit Audit</h4>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Air Filter</label>
                    <select
                      value={checklist.indoor_filter}
                      onChange={(e) => handleChecklistChange('indoor_filter', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="CLEAN">Clean & Clear</option>
                      <option value="CHOKED">Choked with Dust</option>
                      <option value="TORN">Torn / Damaged</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Evaporator Coil</label>
                    <select
                      value={checklist.indoor_coil}
                      onChange={(e) => handleChecklistChange('indoor_coil', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="CLEAN">Clean Fins</option>
                      <option value="DIRTY">Dust & Slime Accumulation</option>
                      <option value="RUSTED">Rusted / Aluminum Corrosion</option>
                      <option value="ICE_FROST">Ice Formation / Freezing</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Blower Motor & Wheel</label>
                    <select
                      value={checklist.blower_fan}
                      onChange={(e) => handleChecklistChange('blower_fan', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="NORMAL">Normal Air Throw</option>
                      <option value="NOISY">Noisy / Bearing Play</option>
                      <option value="WEAK">Weak Air Throw</option>
                      <option value="JAMMED">Jammed / Not Rotating</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Drain Tray & Pipe</label>
                    <select
                      value={checklist.drain_tray}
                      onChange={(e) => handleChecklistChange('drain_tray', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="CLEAR">Clear Flow</option>
                      <option value="CHOKED">Choked / Algae Buildup</option>
                      <option value="LEAKING">Water Dripping on Wall</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Swing Louver / Motor</label>
                    <select
                      value={checklist.swing_motor}
                      onChange={(e) => handleChecklistChange('swing_motor', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="WORKING">Working Smoothly</option>
                      <option value="STUCK">Stuck / Step Motor Defect</option>
                    </select>
                  </div>
                </div>
              </div>

              {/* Outdoor Unit Audit */}
              <div className="p-4 bg-zinc-50/70 border border-zinc-200 rounded-xl space-y-3">
                <div className="flex items-center gap-2">
                  <Activity className="w-4 h-4 text-purple-600" />
                  <h4 className="text-xs font-bold text-zinc-900 uppercase">Outdoor Unit Audit</h4>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Condenser Coil</label>
                    <select
                      value={checklist.outdoor_coil}
                      onChange={(e) => handleChecklistChange('outdoor_coil', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="CLEAN">Clean & Free Airflow</option>
                      <option value="DUSTY">Choked with Grime/Dirt</option>
                      <option value="FINS_DAMAGED">Fins Bent / Damaged</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Compressor Operation</label>
                    <select
                      value={checklist.compressor_status}
                      onChange={(e) => handleChecklistChange('compressor_status', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="RUNNING_NORMAL">Running Smoothly</option>
                      <option value="OVERHEATING">Overheating & Tripping</option>
                      <option value="NOT_STARTING">Humming / Not Starting</option>
                      <option value="GROUNDED">Shorted / Breaker Trip</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Condenser Fan Motor</label>
                    <select
                      value={checklist.condenser_fan}
                      onChange={(e) => handleChecklistChange('condenser_fan', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="NORMAL">Normal Speed</option>
                      <option value="NOISY">Noisy Vibration</option>
                      <option value="SLOW">Slow / Overheated</option>
                      <option value="JAMMED">Jammed / Burnt</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Service Flare Valves</label>
                    <select
                      value={checklist.service_valves}
                      onChange={(e) => handleChecklistChange('service_valves', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="NORMAL">Dry & Tight</option>
                      <option value="OIL_TRACES">Oil Traces (Leak Indication)</option>
                      <option value="FROST">Ice Frost on Flare Nut</option>
                    </select>
                  </div>
                </div>
              </div>

              {/* Electrical & Gas Measurements */}
              <div className="p-4 bg-zinc-50/70 border border-zinc-200 rounded-xl space-y-3">
                <div className="flex items-center gap-2">
                  <Zap className="w-4 h-4 text-amber-600" />
                  <h4 className="text-xs font-bold text-zinc-900 uppercase">Electrical & Gas Diagnostics</h4>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3">
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Line Voltage</label>
                    <input
                      type="text"
                      value={checklist.voltage_reading}
                      onChange={(e) => handleChecklistChange('voltage_reading', e.target.value)}
                      placeholder="e.g. 230V"
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs font-mono"
                    />
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Run Capacitor (uF)</label>
                    <select
                      value={checklist.capacitor_status}
                      onChange={(e) => handleChecklistChange('capacitor_status', e.target.value)}
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs"
                    >
                      <option value="NORMAL">Within Spec (±5%)</option>
                      <option value="WEAK">Weak / Below Capacity</option>
                      <option value="BULGED">Bulged / Blown</option>
                    </select>
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Gas Standing Pressure</label>
                    <input
                      type="text"
                      value={checklist.standing_pressure}
                      onChange={(e) => handleChecklistChange('standing_pressure', e.target.value)}
                      placeholder="e.g. 135 PSI"
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs font-mono"
                    />
                  </div>
                  <div>
                    <label className="block text-[11px] font-semibold text-zinc-600 mb-1">Cooling Performance (ΔT)</label>
                    <input
                      type="text"
                      value={checklist.cooling_delta_t}
                      onChange={(e) => handleChecklistChange('cooling_delta_t', e.target.value)}
                      placeholder="e.g. 10°C"
                      className="w-full p-1.5 bg-white border border-zinc-200 rounded-md text-xs font-mono"
                    />
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* TAB 3: Defect Findings */}
          {activeTab === 'findings' && (
            <div className="space-y-6">
              {/* Quick-Select Defect Checklist */}
              <div>
                <div className="flex items-center justify-between mb-2">
                  <span className="font-bold text-zinc-900 uppercase tracking-wider text-[11px]">
                    Quick-Select Common Defect Checklist
                  </span>
                  <span className="text-zinc-400 text-[11px]">Click to add to inspection findings</span>
                </div>
                <div className="flex flex-wrap gap-2">
                  {DEFECT_TEMPLATES.map((tpl) => {
                    const isSelected = findings.some((f) => f.title === tpl.title);
                    return (
                      <button
                        key={tpl.type}
                        type="button"
                        onClick={() => handleAddTemplate(tpl)}
                        className={`px-3 py-1.5 rounded-lg border text-xs font-semibold flex items-center gap-1.5 transition-all ${
                          isSelected
                            ? 'bg-blue-50 border-blue-300 text-blue-700 shadow-xs'
                            : 'bg-white border-zinc-200 text-zinc-700 hover:border-zinc-300 hover:bg-zinc-50'
                        }`}
                      >
                        <Plus className="w-3 h-3" />
                        <span>{tpl.type}</span>
                      </button>
                    );
                  })}
                </div>
              </div>

              {/* Active Structured Findings List */}
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <span className="font-bold text-zinc-900 uppercase tracking-wider text-[11px]">
                    Recorded Findings ({findings.length})
                  </span>
                  <button
                    type="button"
                    onClick={() =>
                      setFindings([
                        ...findings,
                        {
                          finding_type: 'Other',
                          title: 'Custom AC Finding',
                          severity: 'MEDIUM',
                          description: '',
                          recommended_action: '',
                          quantity: 1,
                          unit: 'unit',
                        },
                      ])
                    }
                    className="text-blue-600 hover:text-blue-800 font-semibold flex items-center gap-1"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Add Custom Finding</span>
                  </button>
                </div>

                {findings.length === 0 ? (
                  <div className="p-6 text-center border-2 border-dashed border-zinc-200 rounded-xl text-zinc-400">
                    No defects added yet. Click above to add findings.
                  </div>
                ) : (
                  findings.map((finding, idx) => (
                    <div
                      key={idx}
                      className="p-4 border border-zinc-200 rounded-xl bg-zinc-50/50 space-y-3 relative group"
                    >
                      <button
                        type="button"
                        onClick={() => handleRemoveFinding(idx)}
                        className="absolute top-3 right-3 p-1 rounded-md text-zinc-400 hover:text-red-600 hover:bg-red-50 transition-colors"
                        title="Remove finding"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>

                      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 pr-8">
                        <div>
                          <label className="block text-[11px] font-semibold text-zinc-600 mb-1">
                            Defect Type
                          </label>
                          <input
                            type="text"
                            value={finding.finding_type || ''}
                            onChange={(e) => handleUpdateFinding(idx, 'finding_type', e.target.value)}
                            className="w-full px-2.5 py-1.5 bg-white border border-zinc-200 rounded-lg text-xs"
                          />
                        </div>

                        <div>
                          <label className="block text-[11px] font-semibold text-zinc-600 mb-1">
                            Finding Title
                          </label>
                          <input
                            type="text"
                            value={finding.title || ''}
                            onChange={(e) => handleUpdateFinding(idx, 'title', e.target.value)}
                            className="w-full px-2.5 py-1.5 bg-white border border-zinc-200 rounded-lg text-xs font-medium"
                          />
                        </div>

                        <div>
                          <label className="block text-[11px] font-semibold text-zinc-600 mb-1">
                            Severity Level
                          </label>
                          <select
                            value={finding.severity || 'MEDIUM'}
                            onChange={(e) => handleUpdateFinding(idx, 'severity', e.target.value)}
                            className={`w-full px-2.5 py-1.5 border rounded-lg text-xs font-bold ${
                              SEVERITY_COLORS[finding.severity || 'MEDIUM']
                            }`}
                          >
                            <option value="LOW">LOW (Minor cosmetic / routine)</option>
                            <option value="MEDIUM">MEDIUM (Requires attention)</option>
                            <option value="HIGH">HIGH (Affects cooling efficiency)</option>
                            <option value="CRITICAL">CRITICAL (System inoperable / risk)</option>
                          </select>
                        </div>
                      </div>

                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <div>
                          <label className="block text-[11px] font-semibold text-zinc-600 mb-1">
                            Technical Observations / Diagnosis
                          </label>
                          <textarea
                            rows={2}
                            value={finding.description || ''}
                            onChange={(e) => handleUpdateFinding(idx, 'description', e.target.value)}
                            placeholder="Detailed inspection observations..."
                            className="w-full px-2.5 py-1.5 bg-white border border-zinc-200 rounded-lg text-xs"
                          />
                        </div>
                        <div>
                          <label className="block text-[11px] font-semibold text-zinc-600 mb-1">
                            Recommended Remedial Action
                          </label>
                          <textarea
                            rows={2}
                            value={finding.recommended_action || ''}
                            onChange={(e) => handleUpdateFinding(idx, 'recommended_action', e.target.value)}
                            placeholder="Action recommended for quotation builder..."
                            className="w-full px-2.5 py-1.5 bg-white border border-zinc-200 rounded-lg text-xs"
                          />
                        </div>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>
          )}

          {/* TAB 4: Photo Evidence */}
          {activeTab === 'photos' && (
            <div className="space-y-4">
              <span className="font-bold text-zinc-900 uppercase tracking-wider text-[11px]">
                Defect Evidence Photos ({photos.length})
              </span>
              <div className="flex flex-wrap items-center gap-3">
                {photos.map((p, pIdx) => (
                  <div
                    key={pIdx}
                    className="w-28 h-28 rounded-xl border border-zinc-200 overflow-hidden relative group bg-zinc-100 shadow-xs"
                  >
                    <img
                      src={p.photo}
                      alt={p.caption || 'Evidence'}
                      className="w-full h-full object-cover"
                    />
                    <div className="absolute inset-0 bg-zinc-950/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-end p-1">
                      <span className="text-[10px] text-white truncate">{p.caption || 'Photo'}</span>
                    </div>
                  </div>
                ))}

                <label className="w-28 h-28 rounded-xl border-2 border-dashed border-zinc-300 hover:border-blue-500 hover:bg-blue-50/50 flex flex-col items-center justify-center gap-1.5 text-zinc-500 hover:text-blue-600 cursor-pointer transition-colors">
                  <Camera className="w-6 h-6" />
                  <span className="text-[11px] font-bold">
                    {uploadingPhoto ? 'Uploading...' : 'Upload Photo'}
                  </span>
                  <input
                    type="file"
                    accept="image/*"
                    onChange={handlePhotoUpload}
                    disabled={uploadingPhoto}
                    className="hidden"
                  />
                </label>
              </div>
            </div>
          )}

          {/* TAB 5: Diagnosis Summary */}
          {activeTab === 'diagnosis' && (
            <div className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-zinc-900 mb-1">
                  Overall Root Cause Diagnosis Summary
                </label>
                <textarea
                  rows={3}
                  value={diagnosis}
                  onChange={(e) => setDiagnosis(e.target.value)}
                  placeholder="Comprehensive technical diagnosis summary visible to customer & admin..."
                  className="w-full p-3 bg-white border border-zinc-200 rounded-xl focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 text-xs"
                />
              </div>
              <div>
                <label className="block text-xs font-bold text-zinc-900 mb-1">
                  Private Technician Notes (Internal)
                </label>
                <textarea
                  rows={2}
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  placeholder="Private notes for vendor management..."
                  className="w-full p-3 bg-white border border-zinc-200 rounded-xl focus:ring-2 focus:ring-blue-500/20 focus:border-blue-500 text-xs"
                />
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-zinc-100 bg-zinc-50 flex items-center justify-between shrink-0">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-zinc-600 hover:text-zinc-900 hover:bg-zinc-200 rounded-xl transition-colors"
          >
            Cancel
          </button>
          <div className="flex items-center gap-2">
            {activeTab !== 'diagnosis' ? (
              <button
                type="button"
                onClick={() => {
                  if (activeTab === 'specs') setActiveTab('checklist');
                  else if (activeTab === 'checklist') setActiveTab('findings');
                  else if (activeTab === 'findings') setActiveTab('photos');
                  else if (activeTab === 'photos') setActiveTab('diagnosis');
                }}
                className="px-4 py-2 text-xs font-bold text-blue-600 bg-blue-50 hover:bg-blue-100 rounded-xl transition-colors"
              >
                Next Section →
              </button>
            ) : null}
            <button
              type="button"
              disabled={submitting}
              onClick={handleSubmit}
              className="px-5 py-2 text-xs font-bold text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-xl shadow-sm flex items-center gap-2 transition-colors"
            >
              {submitting ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <CheckCircle2 className="w-4 h-4" />
              )}
              <span>Save & Complete Inspection</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
