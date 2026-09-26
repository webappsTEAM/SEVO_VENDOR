import React, { useState, useEffect, useCallback } from 'react';
import {
  Undo2,
  Package,
  RefreshCw,
  MapPin,
  Clock,
  CheckCircle2,
  AlertTriangle,
  ArrowRight,
  Truck,
  Building2,
} from 'lucide-react';
import { apiWarehouseGetReturns } from '../../api/workforceService';

export function WarehouseReturnsPage() {
  const [returns, setReturns] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState(null);

  const fetchReturns = useCallback(async (isRefresh = false) => {
    if (isRefresh) setRefreshing(true);
    else setLoading(true);
    setError(null);

    try {
      const res = await apiWarehouseGetReturns();
      setReturns(res.returns || res || []);
    } catch (err) {
      console.error('Failed to load warehouse returns:', err);
      setError(err.message || 'Failed to load return records.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    fetchReturns();
  }, [fetchReturns]);

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-12">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-xl font-black text-slate-900 flex items-center gap-2.5">
            <Undo2 className="w-6 h-6 text-indigo-600" />
            <span>Warehouse Returns & Reverse Staging</span>
          </h2>
          <p className="text-xs text-slate-500 mt-1">
            Stage and track rejected inbound batches, damaged parcels, and merchant return shipments
          </p>
        </div>

        <button
          onClick={() => fetchReturns(true)}
          disabled={refreshing || loading}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-slate-50 border border-slate-200 text-xs font-semibold text-slate-700 rounded-lg shadow-xs transition"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${refreshing ? 'animate-spin' : ''}`} />
          <span>Refresh</span>
        </button>
      </div>

      {/* Error Message */}
      {error && (
        <div className="p-4 bg-rose-50 border border-rose-200 rounded-xl text-rose-700 text-xs flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* Content */}
      {loading ? (
        <div className="p-16 text-center bg-white rounded-2xl border border-slate-200 shadow-xs">
          <RefreshCw className="w-6 h-6 animate-spin text-indigo-600 mx-auto mb-2" />
          <p className="text-xs text-slate-500">Loading return staging records...</p>
        </div>
      ) : returns.length === 0 ? (
        <div className="bg-white border border-slate-200 rounded-2xl p-12 text-center space-y-3 shadow-xs">
          <div className="w-12 h-12 rounded-2xl bg-slate-100 border border-slate-200 flex items-center justify-center text-slate-500 mx-auto">
            <Package className="w-6 h-6" />
          </div>
          <h3 className="text-sm font-bold text-slate-900">No Pending Returns in Staging Dock</h3>
          <p className="text-xs text-slate-500 max-w-md mx-auto">
            When a merchant rejects a shortfall delivery batch or returns are initiated, staged return records with merchant pickup addresses will appear here.
          </p>
        </div>
      ) : (
        <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden shadow-xs">
          <div className="p-4 border-b border-slate-200 bg-slate-50/50 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Truck className="w-4 h-4 text-indigo-600" />
              <span className="text-xs font-bold uppercase tracking-wider text-slate-700">
                Staged Return Cases ({returns.length})
              </span>
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-slate-50 text-[11px] uppercase font-bold text-slate-600 border-b border-slate-200">
                <tr>
                  <th className="py-3 px-4">Return Ref / Date</th>
                  <th className="py-3 px-4">Product / Inbound Req</th>
                  <th className="py-3 px-4 text-center">Return Qty</th>
                  <th className="py-3 px-4">Merchant Destination Address</th>
                  <th className="py-3 px-4">Reason & Notes</th>
                  <th className="py-3 px-4 text-right">Staging Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200 text-slate-700 font-medium">
                {returns.map((ret) => (
                  <tr key={ret.id} className="hover:bg-slate-50/80 transition-colors">
                    <td className="py-3.5 px-4 font-mono text-[11px]">
                      <div className="font-bold text-slate-900 text-xs">{ret.return_number}</div>
                      <div className="text-[10px] text-slate-500 mt-0.5">
                        {new Date(ret.created_at).toLocaleDateString()} {new Date(ret.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                      </div>
                    </td>

                    <td className="py-3.5 px-4">
                      <div className="font-bold text-slate-900">{ret.product_title}</div>
                      <div className="text-[10px] font-mono text-slate-500 mt-0.5">
                        SKU: <span className="text-slate-700 font-semibold">{ret.product_sku}</span> • Inbound Req #{ret.inbound_request}
                      </div>
                    </td>

                    <td className="py-3.5 px-4 text-center">
                      <span className="inline-block px-2.5 py-1 rounded-lg bg-rose-50 text-rose-700 border border-rose-200 font-mono font-bold text-xs">
                        {ret.returned_quantity} Units
                      </span>
                    </td>

                    <td className="py-3.5 px-4 max-w-xs">
                      <div className="space-y-1">
                        <div className="flex items-center gap-1.5 font-bold text-slate-900 text-xs">
                          <Building2 className="w-3.5 h-3.5 text-indigo-600 shrink-0" />
                          <span>{ret.company_name}</span>
                        </div>
                        <div className="flex items-start gap-1 text-[11px] text-slate-600 pl-5">
                          <MapPin className="w-3 h-3 text-slate-400 shrink-0 mt-0.5" />
                          <span>{ret.seller_address}</span>
                        </div>
                      </div>
                    </td>

                    <td className="py-3.5 px-4 max-w-xs">
                      <div className="space-y-1">
                        <span className="text-[10px] font-bold text-amber-700 uppercase tracking-wider block">
                          {ret.reason?.replace(/_/g, ' ')}
                        </span>
                        {ret.notes && (
                          <div className="text-[11px] text-slate-700 bg-slate-50 p-2 rounded-lg border border-slate-200">
                            "{ret.notes}"
                          </div>
                        )}
                      </div>
                    </td>

                    <td className="py-3.5 px-4 text-right">
                      <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold bg-amber-50 text-amber-700 border border-amber-200">
                        <Clock className="w-3 h-3" />
                        <span>{ret.status?.replace(/_/g, ' ') || 'Pending Dispatch'}</span>
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}

export default WarehouseReturnsPage;

