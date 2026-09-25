import React, { useEffect, useState } from 'react';
import {
  Truck,
  Package,
  CheckCircle2,
  ChevronRight,
  ArrowRight,
  RotateCw,
  AlertCircle,
  Boxes,
  MapPin,
  ShieldCheck,
} from 'lucide-react';
import { apiGetLogisticsLeg, apiSetLogisticsLeg, apiGetLogisticsCheckpoints } from '../../../api/workforceService.js';
import { LogisticsCheckpointGate } from './LogisticsCheckpointGate.jsx';

export const GT_LEG_SEQUENCE = [
  'EN_ROUTE_PICKUP',
  'LOADING',
  'EN_ROUTE_DROP',
  'UNLOADING',
  'DELIVERED',
];

export const PM_LEG_SEQUENCE = [
  'ASSIGNED',
  'TEAM_EN_ROUTE',
  'ARRIVED_PICKUP',
  'PACKING',
  'DISMANTLING',
  'LOADING',
  'IN_TRANSIT',
  'ARRIVED_DROP',
  'UNLOADING',
  'REASSEMBLY',
  'UNPACKING',
  'DELIVERED',
  'COMPLETED',
];

export const LEG_METADATA = {
  // Packers & Movers
  ASSIGNED: {
    label: 'Team Assigned',
    shortLabel: 'Assigned',
    desc: 'Relocation team confirmed and dispatch ready',
    badgeClass: 'bg-slate-100 text-slate-700 border-slate-300',
  },
  TEAM_EN_ROUTE: {
    label: 'Team En Route',
    shortLabel: 'En Route',
    desc: 'Moving crew driving to pickup site',
    badgeClass: 'bg-amber-100 text-amber-900 border-amber-300',
  },
  ARRIVED_PICKUP: {
    label: 'Arrived at Pickup',
    shortLabel: 'Arrived',
    desc: 'Crew reached customer pickup location',
    badgeClass: 'bg-emerald-100 text-emerald-900 border-emerald-300',
  },
  PACKING: {
    label: 'Packing Items',
    shortLabel: 'Packing',
    desc: 'Carton boxing and protective bubble-wrapping',
    badgeClass: 'bg-blue-100 text-blue-900 border-blue-300',
  },
  DISMANTLING: {
    label: 'Dismantling Furniture',
    shortLabel: 'Dismantling',
    desc: 'Disassembling cot frames, wardrobes & appliances',
    badgeClass: 'bg-indigo-100 text-indigo-900 border-indigo-300',
  },
  LOADING: {
    label: 'Loading Vehicle',
    shortLabel: 'Loading',
    desc: 'Safely loading and securing goods onto truck',
    badgeClass: 'bg-purple-100 text-purple-900 border-purple-300',
  },
  IN_TRANSIT: {
    label: 'In Transit to Drop',
    shortLabel: 'In Transit',
    desc: 'Transport vehicle driving to delivery address',
    badgeClass: 'bg-amber-100 text-amber-900 border-amber-300',
  },
  ARRIVED_DROP: {
    label: 'Arrived at Destination',
    shortLabel: 'Arrived Drop',
    desc: 'Vehicle reached destination delivery site',
    badgeClass: 'bg-emerald-100 text-emerald-900 border-emerald-300',
  },
  UNLOADING: {
    label: 'Unloading Vehicle',
    shortLabel: 'Unloading',
    desc: 'Bringing furniture and boxes into premises',
    badgeClass: 'bg-blue-100 text-blue-900 border-blue-300',
  },
  REASSEMBLY: {
    label: 'Reassembling Furniture',
    shortLabel: 'Reassembly',
    desc: 'Rebuilding furniture, cots and appliances',
    badgeClass: 'bg-indigo-100 text-indigo-900 border-indigo-300',
  },
  UNPACKING: {
    label: 'Unpacking Goods',
    shortLabel: 'Unpacking',
    desc: 'Unpacking cartons and arranging items in rooms',
    badgeClass: 'bg-sky-100 text-sky-900 border-sky-300',
  },
  DELIVERED: {
    label: 'Goods Delivered',
    shortLabel: 'Delivered',
    desc: 'All items placed safely at destination',
    badgeClass: 'bg-emerald-100 text-emerald-900 border-emerald-300',
  },
  COMPLETED: {
    label: 'Relocation Completed',
    shortLabel: 'Completed',
    desc: 'Relocation fully finished & customer satisfied',
    badgeClass: 'bg-emerald-600 text-white border-emerald-700',
  },
  // Standard Goods Transport
  EN_ROUTE_PICKUP: {
    label: 'En Route to Pickup',
    shortLabel: 'To Pickup',
    desc: 'Driver navigating to pickup location',
    badgeClass: 'bg-amber-100 text-amber-900 border-amber-300',
  },
  EN_ROUTE_DROP: {
    label: 'En Route to Destination',
    shortLabel: 'To Drop',
    desc: 'Driver navigating to drop destination',
    badgeClass: 'bg-amber-100 text-amber-900 border-amber-300',
  },
};

export function isPackersMoversJob(job) {
  if (!job) return false;
  const cat = (job.service_category || '').trim().toLowerCase();
  const title = (job.service_title || '').trim().toLowerCase();
  if (cat === 'packers_movers' || title.includes('packer') || title.includes('mover')) return true;
  const currentLeg = (job.logistics_leg || '').trim().toUpperCase();
  const pmSpecific = [
    'ASSIGNED',
    'TEAM_EN_ROUTE',
    'ARRIVED_PICKUP',
    'PACKING',
    'DISMANTLING',
    'IN_TRANSIT',
    'ARRIVED_DROP',
    'REASSEMBLY',
    'UNPACKING',
    'COMPLETED',
  ];
  return pmSpecific.includes(currentLeg);
}

export function isLogisticsJob(job) {
  if (!job) return false;
  if (job.is_logistics) return true;
  const cat = (job.service_category || '').trim().toLowerCase();
  const title = (job.service_title || '').trim().toLowerCase();
  return (
    cat.startsWith('goods_transport') ||
    cat === 'packers_movers' ||
    cat === 'goods_transport_truck' ||
    cat === 'goods_transport_two_wheeler' ||
    title.includes('goods') ||
    title.includes('truck') ||
    title.includes('logistics') ||
    title.includes('packer') ||
    isPackersMoversJob(job)
  );
}

export function LogisticsLegController({ job, onLegUpdated, className = '' }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [selectedJumpLeg, setSelectedJumpLeg] = useState('');
  const [waitingCharge, setWaitingCharge] = useState(null);
  // {leg: [missing requirement...]} from the checkpoint endpoint. null =
  // unknown (not loaded / failed): the button is then left enabled and the
  // backend's 400 is the gate.
  const [gates, setGates] = useState(null);
  const [gateTick, setGateTick] = useState(0);

  const jobId = job?.id;
  const legKey = (job?.logistics_leg || '').trim().toUpperCase();
  const isLogistics = !!job && isLogisticsJob(job);
  // Guard: logistics-leg and logistics-checkpoint are gated on assignment.
  // Calling them for offer/unassigned jobs returns 403 from the backend.
  const isAssigned = !!job?.is_assigned_to_current_employee;

  // Read-only waiting/detention info (admin-configured, off by default).
  // Refetched whenever the leg changes. A failed fetch keeps the last known
  // value rather than clearing it, so a transient network error on a flaky
  // mobile connection does not make the panel vanish mid-trip; nothing is
  // shown only if it has never loaded. Informational only -- never blocks
  // leg progression.
  useEffect(() => { setWaitingCharge(null); }, [jobId]);

  useEffect(() => {
    if (!isLogistics || !jobId || !isAssigned) return undefined;
    let cancelled = false;
    apiGetLogisticsLeg(jobId)
      .then((res) => { if (!cancelled) setWaitingCharge(res?.waiting_charge || null); })
      .catch(() => { /* keep last known value */ });
    return () => { cancelled = true; };
  }, [isLogistics, jobId, legKey, isAssigned]);

  useEffect(() => { setGates(null); }, [jobId]);

  useEffect(() => {
    if (!isLogistics || !jobId || !isAssigned) return undefined;
    let cancelled = false;
    apiGetLogisticsCheckpoints(jobId)
      .then((res) => { if (!cancelled) setGates(res?.gates || null); })
      .catch(() => { /* keep last known value; backend still enforces */ });
    return () => { cancelled = true; };
  }, [isLogistics, jobId, legKey, gateTick, isAssigned]);

  if (!isLogistics) return null;

  const isPM = isPackersMoversJob(job);
  const sequence = isPM ? PM_LEG_SEQUENCE : GT_LEG_SEQUENCE;
  const currentLeg = (job.logistics_leg || '').trim().toUpperCase();

  const currentIndex = sequence.indexOf(currentLeg);
  const nextLeg = currentIndex === -1 ? sequence[0] : (currentIndex < sequence.length - 1 ? sequence[currentIndex + 1] : null);
  const isFinalLeg = currentIndex !== -1 && currentIndex === sequence.length - 1;

  // Jump options: all forward legs after the current index
  const jumpLegs = currentIndex === -1
    ? sequence.slice(1)
    : sequence.slice(currentIndex + 1);

  const currentMeta = LEG_METADATA[currentLeg] || {
    label: currentLeg || 'Not Started',
    shortLabel: currentLeg || 'Start',
    desc: 'Logistics trip pending initiation',
    badgeClass: 'bg-slate-100 text-slate-700 border-slate-300',
  };

  const nextMeta = nextLeg ? LEG_METADATA[nextLeg] : null;
  const nextMissing = (nextLeg && gates && gates[nextLeg]) || [];
  const jumpMissing = (selectedJumpLeg && gates && gates[selectedJumpLeg]) || [];

  const handleAdvanceLeg = async (targetLeg) => {
    if (!targetLeg) return;
    setLoading(true);
    setError('');
    try {
      await apiSetLogisticsLeg(job.id, targetLeg);
      setSelectedJumpLeg('');
      if (onLegUpdated) {
        onLegUpdated(targetLeg);
      }
    } catch (err) {
      setError(err?.message || 'Failed to update logistics leg. Please retry.');
      setGateTick((t) => t + 1);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className={`p-4 rounded-xl border border-blue-200 bg-linear-to-b from-blue-50/50 to-white shadow-xs space-y-3.5 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between gap-2 border-b border-blue-100 pb-2.5">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-blue-600 text-white flex items-center justify-center shrink-0 shadow-xs">
            {isPM ? <Boxes className="w-4 h-4" /> : <Truck className="w-4 h-4" />}
          </div>
          <div>
            <div className="flex items-center gap-1.5">
              <h3 className="text-xs font-black text-slate-900 tracking-tight">
                {isPM ? 'Packers & Movers Journey' : 'Goods Transport Journey'}
              </h3>
              <span className="text-[10px] font-bold text-blue-800 bg-blue-100 px-1.5 py-0.5 rounded">
                {isPM ? '13 Stages' : '5 Stages'}
              </span>
            </div>
            <p className="text-[11px] text-slate-500">
              Advance sub-stages to keep customer tracking synchronized in real-time
            </p>
          </div>
        </div>

        {/* Current Leg Badge */}
        <span className={`text-[10px] font-mono font-black uppercase px-2 py-1 rounded-md border tracking-wider shrink-0 ${currentMeta.badgeClass}`}>
          {currentMeta.shortLabel}
        </span>
      </div>

      {/* Error notification */}
      {error && (
        <div role="alert" className="p-2.5 bg-rose-50 border border-rose-200 rounded-lg text-rose-800 text-[11px] font-medium flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0 text-rose-600" />
          <span>{error}</span>
        </div>
      )}

      {/* Current Stage Highlight Box */}
      <div className="p-3 bg-white rounded-lg border border-slate-200 shadow-2xs space-y-1">
        <div className="flex items-center justify-between text-xs">
          <span className="text-slate-500 font-semibold text-[11px]">Current Stage:</span>
          <span className="font-mono text-[11px] font-bold text-slate-700">
            {currentIndex >= 0 ? `Stage ${currentIndex + 1} of ${sequence.length}` : 'Initiation Pending'}
          </span>
        </div>
        <div className="text-sm font-black text-slate-900 flex items-center gap-2">
          <span>{currentMeta.label}</span>
          {isFinalLeg && <CheckCircle2 className="w-4 h-4 text-emerald-600" />}
        </div>
        <p className="text-[11px] text-slate-600 leading-relaxed">
          {currentMeta.desc}
        </p>
      </div>

      {/* Waiting / detention time (only when an admin has enabled it) */}
      {waitingCharge?.enabled && (waitingCharge.loading_minutes > 0 || waitingCharge.unloading_minutes > 0) && (
        <div className="p-2.5 bg-amber-50 border border-amber-200 rounded-lg text-[11px] text-amber-900 space-y-0.5" aria-live="polite">
          <div className="font-bold">Waiting time</div>
          <div>
            Loading: {waitingCharge.loading_minutes} min · Unloading: {waitingCharge.unloading_minutes} min
          </div>
          {waitingCharge.billable_minutes > 0 ? (
            <div>
              Billable beyond free time: {waitingCharge.billable_minutes} min (est. ₹{waitingCharge.amount})
            </div>
          ) : (
            <div>Within free waiting time.</div>
          )}
        </div>
      )}

      {/* Horizontal Mini Stage Track */}
      <div className="overflow-x-auto pb-1 -mx-1 px-1">
        <div className="flex items-center gap-1 min-w-max">
          {sequence.map((legKey, idx) => {
            const isDone = currentIndex > idx;
            const isCurrent = currentIndex === idx;
            const meta = LEG_METADATA[legKey] || { shortLabel: legKey };
            return (
              <React.Fragment key={legKey}>
                <div
                  className={`px-2 py-1 rounded text-[10px] font-bold tracking-tight transition-all flex items-center gap-1 ${
                    isCurrent
                      ? 'bg-blue-600 text-white shadow-xs font-black'
                      : isDone
                      ? 'bg-emerald-100 text-emerald-800 border border-emerald-200'
                      : 'bg-slate-100 text-slate-400 border border-slate-200'
                  }`}
                  title={`${idx + 1}. ${meta.label || legKey}`}
                >
                  {isDone && <CheckCircle2 className="w-3 h-3 text-emerald-600" />}
                  <span>{meta.shortLabel}</span>
                </div>
                {idx < sequence.length - 1 && (
                  <ChevronRight className={`w-3 h-3 shrink-0 ${isDone ? 'text-emerald-500' : 'text-slate-300'}`} />
                )}
              </React.Fragment>
            );
          })}
        </div>
      </div>

      {/* Checkpoint verification required before the next stage */}
      {!isFinalLeg && nextMissing.length > 0 && (
        <LogisticsCheckpointGate
          jobId={job.id}
          targetLabel={nextMeta?.label || nextLeg}
          missing={nextMissing}
          onVerified={() => setGateTick((t) => t + 1)}
        />
      )}

      {/* Action Controls */}
      {!isFinalLeg ? (
        <div className="space-y-2 pt-1 border-t border-slate-100">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {/* Primary: Advance to Immediate Next Leg */}
            {nextLeg && (
              <button
                type="button"
                onClick={() => handleAdvanceLeg(nextLeg)}
                disabled={loading || nextMissing.length > 0}
                title={nextMissing.length > 0 ? `Required first: ${nextMissing.map((m) => m.label).join(', ')}` : undefined}
                className="py-2.5 px-3 bg-blue-600 hover:bg-blue-700 active:bg-blue-800 disabled:opacity-50 text-white font-bold text-xs rounded-lg shadow-xs transition-all flex items-center justify-center gap-1.5 cursor-pointer"
              >
                {loading ? (
                  <RotateCw className="w-3.5 h-3.5 animate-spin" />
                ) : (
                  <ArrowRight className="w-3.5 h-3.5" />
                )}
                <span>Advance: {nextMeta?.shortLabel || nextLeg}</span>
              </button>
            )}

            {/* Secondary: Skip Forward Selector (For stages like Dismantling when not needed) */}
            {jumpLegs.length > 1 && (
              <div className="flex items-center gap-1">
                <select
                  value={selectedJumpLeg}
                  onChange={(e) => setSelectedJumpLeg(e.target.value)}
                  disabled={loading}
                  aria-label="Skip to future stage"
                  className="flex-1 py-2 px-2.5 bg-white border border-slate-300 rounded-lg text-xs font-medium text-slate-800 outline-none focus:border-blue-500 shadow-2xs"
                >
                  <option value="">Skip ahead to stage...</option>
                  {jumpLegs.map((l) => (
                    <option key={l} value={l}>
                      → {LEG_METADATA[l]?.label || l}
                    </option>
                  ))}
                </select>
                <button
                  type="button"
                  onClick={() => handleAdvanceLeg(selectedJumpLeg)}
                  disabled={loading || !selectedJumpLeg || jumpMissing.length > 0}
                  title={jumpMissing.length > 0 ? `Required first: ${jumpMissing.map((m) => m.label).join(', ')}` : undefined}
                  className="py-2 px-3 bg-slate-800 hover:bg-slate-900 disabled:opacity-40 text-white font-bold text-xs rounded-lg transition-all cursor-pointer shrink-0"
                >
                  Jump
                </button>
              </div>
            )}
          </div>
        </div>
      ) : (
        <div className="p-2.5 bg-emerald-50 border border-emerald-200 rounded-lg text-emerald-900 text-xs font-bold flex items-center justify-center gap-1.5">
          <ShieldCheck className="w-4 h-4 text-emerald-600" />
          <span>Trip Completed — All logistics legs finalized</span>
        </div>
      )}
    </div>
  );
}

export default LogisticsLegController;
