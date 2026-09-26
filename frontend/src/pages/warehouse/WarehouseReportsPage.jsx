import React from 'react';
import { BarChart3, Clock, LineChart, FileText, CheckCircle2, TrendingUp } from 'lucide-react';

export function WarehouseReportsPage() {
  return (
    <div className="space-y-6 max-w-5xl mx-auto">
      <div>
        <h2 className="text-xl font-black text-slate-900 flex items-center gap-2.5">
          <BarChart3 className="w-6 h-6 text-indigo-600" />
          <span>Warehouse Reports & Quality Audits</span>
        </h2>
        <p className="text-xs text-slate-500 mt-1">
          Fulfillment SLA compliance, rider handover turn-around-time, and discrepancy reporting
        </p>
      </div>

      <div className="bg-white border border-slate-200 rounded-2xl p-8 text-center space-y-4 shadow-xs">
        <div className="w-16 h-16 rounded-2xl bg-indigo-50 border border-indigo-100 flex items-center justify-center text-indigo-600 mx-auto">
          <BarChart3 className="w-8 h-8" />
        </div>
        <div className="max-w-md mx-auto space-y-2">
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold bg-amber-50 text-amber-700 border border-amber-200">
            <Clock className="w-3.5 h-3.5" />
            Operations Analytics Module
          </span>
          <h3 className="text-base font-bold text-slate-900">Facility Performance & Quality Audits</h3>
          <p className="text-xs text-slate-500">
            Comprehensive reporting on rider handover times, dispatch SLA breaches, merchant packaging audits, and inventory shrink rates.
          </p>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-6 max-w-2xl mx-auto text-left">
          <div className="p-3.5 bg-slate-50 border border-slate-200 rounded-xl">
            <span className="text-[10px] font-bold uppercase text-indigo-600">Metrics</span>
            <p className="text-xs font-bold text-slate-900 mt-1">Pickup Turnaround Time</p>
            <p className="text-[11px] text-slate-500 mt-0.5">Time between rider arrival at hub and OTP verified departure</p>
          </div>
          <div className="p-3.5 bg-slate-50 border border-slate-200 rounded-xl">
            <span className="text-[10px] font-bold uppercase text-indigo-600">Auditing</span>
            <p className="text-xs font-bold text-slate-900 mt-1">Packaging Quality Check</p>
            <p className="text-[11px] text-slate-500 mt-0.5">Merchant packaging damage & seal verification scorecards</p>
          </div>
          <div className="p-3.5 bg-slate-50 border border-slate-200 rounded-xl">
            <span className="text-[10px] font-bold uppercase text-indigo-600">Export</span>
            <p className="text-xs font-bold text-slate-900 mt-1">Daily Manifest Export</p>
            <p className="text-[11px] text-slate-500 mt-0.5">CSV/PDF export of all outbound consignments for logistics audits</p>
          </div>
        </div>
      </div>
    </div>
  );
}

export default WarehouseReportsPage;
