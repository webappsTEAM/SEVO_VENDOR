import React from 'react';
import { PackageOpen } from 'lucide-react';

/**
 * PTLLoadingNotice
 *
 * Light PTL (Part Truck Load) jobs: the customer loads and unloads the goods.
 * Read-only, from the server-built job.ptl_details (derived from fare_breakdown).
 * Self-gated: renders nothing for non-PTL jobs. Load Assist has no driver-side
 * workflow yet, so it is only mentioned, not actioned.
 */
export function PTLLoadingNotice({ job, className = '' }) {
  const ptl = job?.ptl_details;
  if (!ptl || !ptl.is_ptl) return null;
  const customerLoads = (ptl.loading_responsibility || 'customer') === 'customer';

  return (
    <div
      role="note"
      className={`p-3 rounded-xl border border-amber-200 bg-amber-50 flex items-start gap-2.5 ${className}`}
    >
      <div className="w-8 h-8 rounded-lg bg-amber-500 text-white flex items-center justify-center shrink-0">
        <PackageOpen className="w-4 h-4" />
      </div>
      <div className="text-xs text-slate-800 space-y-0.5">
        <div className="flex items-center gap-1.5 flex-wrap">
          <span className="font-black text-slate-900">Part Truck Load</span>
          {customerLoads && (
            <span className="text-[10px] font-bold text-amber-900 bg-amber-100 px-1.5 py-0.5 rounded">
              Customer handles loading &amp; unloading
            </span>
          )}
        </div>
        {ptl.declared_weight_kg && <p>Declared weight: <strong>{ptl.declared_weight_kg} kg</strong></p>}
        {customerLoads && <p className="text-slate-600">You are not required to load or unload the goods on this trip.</p>}
        {ptl.load_assist && <p className="text-slate-600">Customer requested Load Assist; follow dispatcher instructions.</p>}
      </div>
    </div>
  );
}

export default PTLLoadingNotice;
