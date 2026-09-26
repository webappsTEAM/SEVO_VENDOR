import React, { useState } from 'react';
import {
  Grid3X3,
  Layers,
  Boxes,
  Truck,
  Undo2,
  Info,
  X,
  Sparkles,
  MapPin,
  CheckCircle2,
} from 'lucide-react';

export function WarehouseRackViewPage() {
  const [selectedBay, setSelectedBay] = useState(null);

  const aisles = [
    {
      id: 'A',
      name: 'Aisle A – Dry Groceries & Grains',
      color: 'border-amber-200 bg-amber-50 text-amber-800',
      bays: [
        { id: 'A1', name: 'Bay A-01', shelves: ['Shelf 1 (Pallet Base)', 'Shelf 2 (Case Pack)', 'Shelf 3 (Pick Face)', 'Shelf 4 (Overstock)'] },
        { id: 'A2', name: 'Bay A-02', shelves: ['Shelf 1 (Pallet Base)', 'Shelf 2 (Case Pack)', 'Shelf 3 (Pick Face)', 'Shelf 4 (Overstock)'] },
        { id: 'A3', name: 'Bay A-03', shelves: ['Shelf 1 (Pallet Base)', 'Shelf 2 (Case Pack)', 'Shelf 3 (Pick Face)', 'Shelf 4 (Overstock)'] },
        { id: 'A4', name: 'Bay A-04', shelves: ['Shelf 1 (Pallet Base)', 'Shelf 2 (Case Pack)', 'Shelf 3 (Pick Face)', 'Shelf 4 (Overstock)'] },
      ],
    },
    {
      id: 'B',
      name: 'Aisle B – Fresh Fruits & Vegetables',
      color: 'border-emerald-200 bg-emerald-50 text-emerald-800',
      bays: [
        { id: 'B1', name: 'Bay B-01 (Crated)', shelves: ['Crate Bin 1', 'Crate Bin 2', 'Crate Bin 3'] },
        { id: 'B2', name: 'Bay B-02 (Crated)', shelves: ['Crate Bin 1', 'Crate Bin 2', 'Crate Bin 3'] },
        { id: 'B3', name: 'Bay B-03 (Refrigerated)', shelves: ['Cold Tier 1', 'Cold Tier 2', 'Cold Tier 3'] },
        { id: 'B4', name: 'Bay B-04 (Refrigerated)', shelves: ['Cold Tier 1', 'Cold Tier 2', 'Cold Tier 3'] },
      ],
    },
    {
      id: 'C',
      name: 'Aisle C – Dairy, Beverages & Chilled',
      color: 'border-cyan-200 bg-cyan-50 text-cyan-800',
      bays: [
        { id: 'C1', name: 'Bay C-01 (Chiller)', shelves: ['Chiller Level 1', 'Chiller Level 2', 'Chiller Level 3'] },
        { id: 'C2', name: 'Bay C-02 (Chiller)', shelves: ['Chiller Level 1', 'Chiller Level 2', 'Chiller Level 3'] },
        { id: 'C3', name: 'Bay C-03 (Beverage Pallet)', shelves: ['Pallet Base 1', 'Pallet Base 2'] },
        { id: 'C4', name: 'Bay C-04 (Beverage Pallet)', shelves: ['Pallet Base 1', 'Pallet Base 2'] },
      ],
    },
    {
      id: 'D',
      name: 'Aisle D – Fast-Moving & FMCG Packaged',
      color: 'border-indigo-200 bg-indigo-50 text-indigo-800',
      bays: [
        { id: 'D1', name: 'Bay D-01', shelves: ['Tier 1', 'Tier 2', 'Tier 3', 'Tier 4'] },
        { id: 'D2', name: 'Bay D-02', shelves: ['Tier 1', 'Tier 2', 'Tier 3', 'Tier 4'] },
        { id: 'D3', name: 'Bay D-03', shelves: ['Tier 1', 'Tier 2', 'Tier 3', 'Tier 4'] },
        { id: 'D4', name: 'Bay D-04', shelves: ['Tier 1', 'Tier 2', 'Tier 3', 'Tier 4'] },
      ],
    },
  ];

  return (
    <div className="space-y-6 max-w-7xl mx-auto pb-12">
      {/* ── HEADER ── */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-black text-slate-900 flex items-center gap-2.5">
            <Grid3X3 className="w-6 h-6 text-indigo-600" />
            <span>Warehouse Rack & Floorplan Visualization</span>
          </h2>
          <p className="text-xs text-slate-500 mt-1">
            Physical layout mockup of warehouse aisles, storage bays, dispatch staging, and returns dock
          </p>
        </div>

        <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-xl bg-indigo-50 border border-indigo-200 text-indigo-700 text-xs font-bold">
          <Sparkles className="w-4 h-4 text-indigo-600" />
          <span>UI Layout Preview</span>
        </div>
      </div>

      {/* ── STAGING DOCKS STRIP ── */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="p-4 bg-emerald-50/60 border border-emerald-200 rounded-2xl flex items-center gap-3 shadow-xs">
          <div className="p-2.5 bg-emerald-100 text-emerald-700 rounded-xl">
            <Truck className="w-5 h-5" />
          </div>
          <div>
            <h4 className="text-xs font-bold text-slate-900 uppercase tracking-wide">Rider Outbound Staging Dock</h4>
            <p className="text-[11px] text-slate-500">Consolidated order parcels staged for two-wheeler collection</p>
          </div>
        </div>

        <div className="p-4 bg-amber-50/60 border border-amber-200 rounded-2xl flex items-center gap-3 shadow-xs">
          <div className="p-2.5 bg-amber-100 text-amber-700 rounded-xl">
            <Boxes className="w-5 h-5" />
          </div>
          <div>
            <h4 className="text-xs font-bold text-slate-900 uppercase tracking-wide">Merchant Inbound Ingestion Bay</h4>
            <p className="text-[11px] text-slate-500">Vendor bulk vehicle drop-off and intake quality check</p>
          </div>
        </div>

        <div className="p-4 bg-rose-50/60 border border-rose-200 rounded-2xl flex items-center gap-3 shadow-xs">
          <div className="p-2.5 bg-rose-100 text-rose-700 rounded-xl">
            <Undo2 className="w-5 h-5" />
          </div>
          <div>
            <h4 className="text-xs font-bold text-slate-900 uppercase tracking-wide">Reverse Logistics Intake Bay</h4>
            <p className="text-[11px] text-slate-500">Returned customer parcel staging and inspection</p>
          </div>
        </div>
      </div>

      {/* ── AISLES & RACKS GRID ── */}
      <div className="space-y-4">
        {aisles.map((aisle) => (
          <div
            key={aisle.id}
            className="bg-white border border-slate-200 rounded-2xl p-5 space-y-3 shadow-xs"
          >
            <div className="flex items-center justify-between">
              <span className={`px-2.5 py-1 rounded-lg text-xs font-bold border ${aisle.color}`}>
                {aisle.name}
              </span>
              <span className="text-[11px] text-slate-500 font-mono">4 Storage Bays • 16 Shelves</span>
            </div>

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              {aisle.bays.map((bay) => (
                <div
                  key={bay.id}
                  onClick={() => setSelectedBay({ ...bay, aisleName: aisle.name })}
                  className="p-3 bg-slate-50 hover:bg-slate-100 border border-slate-200 hover:border-indigo-400 rounded-xl cursor-pointer transition-all space-y-2 group shadow-xs"
                >
                  <div className="flex items-center justify-between">
                    <span className="font-mono font-bold text-xs text-slate-900 group-hover:text-indigo-600">
                      {bay.name}
                    </span>
                    <span className="w-2 h-2 rounded-full bg-emerald-500" />
                  </div>

                  <div className="space-y-1">
                    {bay.shelves.map((sh, idx) => (
                      <div
                        key={idx}
                        className="p-1 px-2 bg-white border border-slate-200/80 rounded text-[10px] text-slate-600 font-mono flex items-center justify-between"
                      >
                        <span className="truncate">{sh}</span>
                        <span className="text-[9px] text-indigo-600 font-semibold">OK</span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* ── MODAL: BAY DETAILS (MOCKUP) ── */}
      {selectedBay && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white border border-slate-200 rounded-2xl max-w-md w-full p-6 shadow-2xl space-y-4 text-slate-800">
            <div className="flex items-center justify-between border-b border-slate-200 pb-3">
              <div className="flex items-center gap-2">
                <Grid3X3 className="w-5 h-5 text-indigo-600" />
                <h3 className="text-sm font-bold text-slate-900">{selectedBay.name}</h3>
              </div>
              <button
                type="button"
                onClick={() => setSelectedBay(null)}
                className="p-1.5 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="space-y-3 text-xs">
              <p className="text-slate-600 font-semibold">{selectedBay.aisleName}</p>
              <div className="p-3 bg-slate-50 rounded-xl space-y-2 border border-slate-200">
                <span className="text-[10px] uppercase font-bold text-indigo-600">Shelf Storage Tiers</span>
                <div className="space-y-1.5">
                  {selectedBay.shelves.map((sh, idx) => (
                    <div key={idx} className="p-2 bg-white border border-slate-200 rounded-lg flex items-center justify-between font-mono text-[11px]">
                      <span className="text-slate-800">{sh}</span>
                      <span className="text-emerald-700 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded font-bold text-[10px]">Active Storage</span>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            <div className="flex items-center justify-end pt-2 border-t border-slate-200">
              <button
                type="button"
                onClick={() => setSelectedBay(null)}
                className="px-4 py-2 text-xs font-bold text-slate-700 hover:text-slate-900 bg-white border border-slate-200 hover:bg-slate-50 rounded-xl shadow-xs"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default WarehouseRackViewPage;
