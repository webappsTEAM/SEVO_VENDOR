import React, { useState } from 'react';
import {
  Boxes,
  Users,
  Layers,
  Wrench,
  Truck,
  Building2,
  CheckCircle2,
  XCircle,
  ChevronDown,
  ChevronUp,
  PackageCheck,
  ShieldAlert,
} from 'lucide-react';
import { isPackersMoversJob } from './LogisticsLegController.jsx';

/**
 * PackersMoversManifestCard
 *
 * Dedicated moving manifest and specifications card for Packers & Movers jobs.
 * Surfaces customer moving inventory, helper/crew allocation, floor/lift access,
 * and service add-ons (dismantling, unpacking, packing tier).
 */
export function PackersMoversManifestCard({ job, className = '' }) {
  const [isInventoryExpanded, setIsInventoryExpanded] = useState(true);

  if (!job || !isPackersMoversJob(job)) return null;

  const c0 = Array.isArray(job.cart_data) && job.cart_data.length > 0 ? job.cart_data[0] : (job.cart_data || {});
  const relocation = job.relocation_details || {};

  // Crew Size
  const crewSize = job.crew_size ?? c0.helpers_requested ?? c0.crew_size ?? null;

  // Inventory items
  const rawItems = job.inventory_items || c0.inventory || c0.items || [];
  const inventoryItems = Array.isArray(rawItems)
    ? rawItems.map((it) => ({
        name: it.name || it.item_name || `Item #${it.goods_item_id || ''}`,
        quantity: Number(it.quantity || 1),
        category: it.category || '',
        isFragile: Boolean(it.is_fragile || it.isFragile || it.fragile),
      }))
    : [];

  const totalItemCount = inventoryItems.reduce((acc, curr) => acc + curr.quantity, 0);

  // Access & Floor Specifications
  const pickupFloor = relocation.pickup_floor ?? c0.pickup_floor ?? 0;
  const pickupHasLift = relocation.pickup_has_lift ?? c0.pickup_has_lift ?? true;
  const dropFloor = relocation.drop_floor ?? c0.drop_floor ?? 0;
  const dropHasLift = relocation.drop_has_lift ?? c0.drop_has_lift ?? true;

  // Pricing & Services
  const packingTier = relocation.packing_tier || c0.packing_tier || 'Standard';
  const dismantlingRequired = relocation.dismantling_required ?? c0.dismantling_required ?? false;
  const unpackingRequired = relocation.unpacking_required ?? c0.unpacking_required ?? false;
  const relocationType = relocation.relocation_type || c0.relocation_type || 'Within City';
  const volumeCft = relocation.volume_cft || c0.volume_cft || 0;
  const vehicleName = relocation.vehicle_name || c0.package || '';

  return (
    <div className={`p-4 rounded-xl border border-purple-200 bg-linear-to-b from-purple-50/50 to-white shadow-xs space-y-3.5 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between gap-2 border-b border-purple-100 pb-2.5">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-purple-600 text-white flex items-center justify-center shrink-0 shadow-xs">
            <Boxes className="w-4 h-4" />
          </div>
          <div>
            <div className="flex items-center gap-1.5">
              <h3 className="text-xs font-black text-slate-900 tracking-tight">
                Relocation Manifest & Specifications
              </h3>
              <span className="text-[10px] font-bold text-purple-800 bg-purple-100 px-1.5 py-0.5 rounded">
                Packers & Movers
              </span>
            </div>
            <p className="text-[11px] text-slate-500">
              Moving inventory, crew requirements, and floor access details
            </p>
          </div>
        </div>

        {vehicleName && (
          <span className="text-[10px] font-mono font-bold text-purple-900 bg-purple-50 border border-purple-200 px-2 py-1 rounded-md shrink-0">
            {vehicleName}
          </span>
        )}
      </div>

      {/* Key Move Metrics Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
        <div className="p-2.5 bg-white rounded-lg border border-slate-200 shadow-2xs space-y-0.5">
          <span className="text-[10px] text-slate-400 font-bold uppercase tracking-wider flex items-center gap-1">
            <Users className="w-3 h-3 text-purple-600" />
            <span>Crew Size</span>
          </span>
          <p className="text-xs font-black text-slate-900">
            {crewSize ? `${crewSize} Workers` : 'Standard Crew'}
          </p>
        </div>

        <div className="p-2.5 bg-white rounded-lg border border-slate-200 shadow-2xs space-y-0.5">
          <span className="text-[10px] text-slate-400 font-bold uppercase tracking-wider flex items-center gap-1">
            <Layers className="w-3 h-3 text-purple-600" />
            <span>Packing Tier</span>
          </span>
          <p className="text-xs font-black text-slate-900 capitalize">
            {packingTier}
          </p>
        </div>

        <div className="p-2.5 bg-white rounded-lg border border-slate-200 shadow-2xs space-y-0.5">
          <span className="text-[10px] text-slate-400 font-bold uppercase tracking-wider flex items-center gap-1">
            <Truck className="w-3 h-3 text-purple-600" />
            <span>Move Type</span>
          </span>
          <p className="text-xs font-black text-slate-900 truncate">
            {relocationType}
          </p>
        </div>

        <div className="p-2.5 bg-white rounded-lg border border-slate-200 shadow-2xs space-y-0.5">
          <span className="text-[10px] text-slate-400 font-bold uppercase tracking-wider flex items-center gap-1">
            <PackageCheck className="w-3 h-3 text-purple-600" />
            <span>Volume</span>
          </span>
          <p className="text-xs font-black text-slate-900">
            {volumeCft > 0 ? `${volumeCft} CFT` : 'Standard'}
          </p>
        </div>
      </div>

      {/* Building & Floor Access Specifications */}
      <div className="p-3 bg-white rounded-lg border border-slate-200 shadow-2xs space-y-2">
        <span className="text-[10px] text-slate-500 font-bold uppercase tracking-wider flex items-center gap-1">
          <Building2 className="w-3.5 h-3.5 text-slate-600" />
          <span>Premises & Floor Access</span>
        </span>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs">
          {/* Pickup Location Access */}
          <div className="p-2.5 rounded-lg bg-slate-50 border border-slate-100 flex items-center justify-between">
            <div>
              <span className="text-[10px] font-semibold text-slate-500 block">Pickup Floor</span>
              <span className="font-bold text-slate-800 text-xs">
                {pickupFloor === 0 ? 'Ground Floor (0)' : `Floor ${pickupFloor}`}
              </span>
            </div>
            <span
              className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${
                pickupHasLift
                  ? 'bg-emerald-50 text-emerald-800 border-emerald-200'
                  : 'bg-amber-50 text-amber-800 border-amber-200'
              }`}
            >
              {pickupHasLift ? 'Lift Available' : 'No Lift (Stairs)'}
            </span>
          </div>

          {/* Drop Location Access */}
          <div className="p-2.5 rounded-lg bg-slate-50 border border-slate-100 flex items-center justify-between">
            <div>
              <span className="text-[10px] font-semibold text-slate-500 block">Destination Floor</span>
              <span className="font-bold text-slate-800 text-xs">
                {dropFloor === 0 ? 'Ground Floor (0)' : `Floor ${dropFloor}`}
              </span>
            </div>
            <span
              className={`text-[10px] font-bold px-2 py-0.5 rounded-full border ${
                dropHasLift
                  ? 'bg-emerald-50 text-emerald-800 border-emerald-200'
                  : 'bg-amber-50 text-amber-800 border-amber-200'
              }`}
            >
              {dropHasLift ? 'Lift Available' : 'No Lift (Stairs)'}
            </span>
          </div>
        </div>

        {/* Add-on Services: Dismantling & Unpacking */}
        <div className="grid grid-cols-2 gap-2 pt-1 border-t border-slate-100 text-[11px]">
          <div className="flex items-center gap-1.5">
            <Wrench className="w-3.5 h-3.5 text-slate-500" />
            <span className="text-slate-600">Furniture Dismantling:</span>
            {dismantlingRequired ? (
              <span className="font-bold text-indigo-700 bg-indigo-50 px-1.5 py-0.5 rounded">Required</span>
            ) : (
              <span className="text-slate-400 font-medium">None</span>
            )}
          </div>

          <div className="flex items-center gap-1.5">
            <PackageCheck className="w-3.5 h-3.5 text-slate-500" />
            <span className="text-slate-600">Unpacking at Drop:</span>
            {unpackingRequired ? (
              <span className="font-bold text-sky-700 bg-sky-50 px-1.5 py-0.5 rounded">Required</span>
            ) : (
              <span className="text-slate-400 font-medium">None</span>
            )}
          </div>
        </div>
      </div>

      {/* Itemized Moving Manifest List */}
      <div className="p-3 bg-white rounded-lg border border-slate-200 shadow-2xs space-y-2">
        <button
          type="button"
          onClick={() => setIsInventoryExpanded(!isInventoryExpanded)}
          className="w-full flex items-center justify-between text-left cursor-pointer"
        >
          <div className="flex items-center gap-1.5">
            <Boxes className="w-3.5 h-3.5 text-purple-600" />
            <span className="text-xs font-bold text-slate-900">Moving Item Manifest</span>
            <span className="text-[10px] font-bold text-purple-700 bg-purple-100 px-2 py-0.5 rounded-full">
              {totalItemCount} {totalItemCount === 1 ? 'Item' : 'Items'}
            </span>
          </div>
          {isInventoryExpanded ? (
            <ChevronUp className="w-4 h-4 text-slate-400" />
          ) : (
            <ChevronDown className="w-4 h-4 text-slate-400" />
          )}
        </button>

        {isInventoryExpanded && (
          <div className="pt-1 border-t border-slate-100">
            {inventoryItems.length > 0 ? (
              <div className="max-h-48 overflow-y-auto space-y-1.5 pr-1 divide-y divide-slate-100">
                {inventoryItems.map((item, idx) => (
                  <div key={idx} className="pt-1.5 first:pt-0 flex items-center justify-between text-xs">
                    <div className="flex items-center gap-1.5">
                      <span className="font-medium text-slate-800">{item.name}</span>
                      {item.isFragile && (
                        <span className="text-[9px] font-bold text-rose-600 bg-rose-50 border border-rose-200 px-1.5 py-0.2 rounded">
                          Fragile
                        </span>
                      )}
                    </div>
                    <span className="font-mono font-bold text-slate-900 bg-slate-100 px-2 py-0.5 rounded text-[11px]">
                      x{item.quantity}
                    </span>
                  </div>
                ))}
              </div>
            ) : (
              <div className="py-2 text-center text-slate-500 text-[11px] italic">
                Standard relocation package booked (items surveyed on site).
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

export default PackersMoversManifestCard;
