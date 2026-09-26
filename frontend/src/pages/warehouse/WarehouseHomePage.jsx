import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '../../context/AuthProvider.jsx';
import { apiWarehouseGetStats, apiWarehouseGetOrders } from '../../api/workforceService.js';
import {
  Warehouse as WarehouseIcon,
  PackageCheck,
  Store,
  Truck,
  CheckCircle2,
  Clock,
  ArrowRight,
  RefreshCw,
  MapPin,
  Grid3X3,
  Building2,
  AlertCircle,
} from 'lucide-react';

export function WarehouseHomePage() {
  const { user } = useAuth();
  const navigate = useNavigate();

  const [stats, setStats] = useState(null);
  const [recentOrders, setRecentOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const fetchData = async () => {
    setLoading(true);
    setError('');
    try {
      const [statsRes, ordersRes] = await Promise.all([
        apiWarehouseGetStats().catch(() => null),
        apiWarehouseGetOrders({ page_size: 5 }).catch(() => ({ results: [] })),
      ]);
      setStats(statsRes);
      setRecentOrders(ordersRes?.results || ordersRes || []);
    } catch (err) {
      console.error('Failed to load warehouse dashboard data:', err);
      setError('Unable to load latest warehouse metrics.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  const warehouseName = stats?.warehouse_name || user?.warehouseName || user?.warehouse?.name || 'Fulfilment Warehouse';
  const warehouseCode = stats?.warehouse_code || user?.warehouseCode || 'WH-MAIN';

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* ── HEADER BANNER ── */}
      <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl bg-indigo-50 border border-indigo-100 flex items-center justify-center text-indigo-600 shadow-xs">
            <WarehouseIcon className="w-7 h-7" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-xl font-black text-slate-900">{warehouseName}</h2>
              <span className="font-mono text-xs px-2 py-0.5 rounded-md bg-indigo-50 text-indigo-700 font-bold border border-indigo-200">
                {warehouseCode}
              </span>
            </div>
            <p className="text-xs text-slate-500 mt-0.5 flex items-center gap-1.5">
              <MapPin className="w-3.5 h-3.5 text-indigo-600" />
              <span>{stats?.city || user?.city || 'Distribution Center'} • Two-Wheeler Delivery Staging Hub</span>
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={fetchData}
            disabled={loading}
            className="inline-flex items-center gap-2 px-3.5 py-2 text-xs font-bold text-slate-700 bg-white hover:bg-slate-50 rounded-xl border border-slate-200 transition-colors shadow-xs"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin text-indigo-600' : ''}`} />
            <span>Refresh</span>
          </button>
          <button
            type="button"
            onClick={() => navigate('/workforce/warehouse/orders')}
            className="inline-flex items-center gap-2 px-4 py-2 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl shadow-xs transition-colors"
          >
            <span>View Orders Queue</span>
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {error && (
        <div className="p-4 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* ── KPI METRIC CARDS ── */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Active Sellers */}
        <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-xs hover:border-slate-300 transition-all">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-500 uppercase tracking-wider">Assigned Merchants</span>
            <div className="p-2 bg-amber-50 text-amber-700 rounded-xl">
              <Store className="w-4 h-4" />
            </div>
          </div>
          <p className="text-2xl font-black text-slate-900 mt-3">
            {stats ? stats.active_sellers_count : (loading ? '—' : 0)}
          </p>
          <p className="text-[11px] text-slate-500 mt-1">Sellers dispatching to this hub</p>
        </div>

        {/* Ready For Pickup */}
        <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-xs hover:border-slate-300 transition-all">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-500 uppercase tracking-wider">Ready For Pickup</span>
            <div className="p-2 bg-indigo-50 text-indigo-600 rounded-xl">
              <PackageCheck className="w-4 h-4" />
            </div>
          </div>
          <p className="text-2xl font-black text-slate-900 mt-3">
            {stats ? stats.ready_for_pickup : (loading ? '—' : 0)}
          </p>
          <p className="text-[11px] text-slate-500 mt-1">Packed & awaiting rider collection</p>
        </div>

        {/* Dispatched Today */}
        <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-xs hover:border-slate-300 transition-all">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-500 uppercase tracking-wider">Dispatched Today</span>
            <div className="p-2 bg-emerald-50 text-emerald-600 rounded-xl">
              <Truck className="w-4 h-4" />
            </div>
          </div>
          <p className="text-2xl font-black text-emerald-700 mt-3">
            {stats ? stats.dispatched_today : (loading ? '—' : 0)}
          </p>
          <p className="text-[11px] text-slate-500 mt-1">Handed over to delivery fleet</p>
        </div>

        {/* Total Orders Routed */}
        <div className="bg-white border border-slate-200 rounded-2xl p-5 shadow-xs hover:border-slate-300 transition-all">
          <div className="flex items-center justify-between">
            <span className="text-xs font-bold text-slate-500 uppercase tracking-wider">Total Orders</span>
            <div className="p-2 bg-purple-50 text-purple-600 rounded-xl">
              <CheckCircle2 className="w-4 h-4" />
            </div>
          </div>
          <p className="text-2xl font-black text-purple-900 mt-3">
            {stats ? stats.total_orders : (loading ? '—' : 0)}
          </p>
          <p className="text-[11px] text-slate-500 mt-1">Lifetime facility order volume</p>
        </div>
      </div>

      {/* ── QUICK ACTION TILES ── */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div
          onClick={() => navigate('/workforce/warehouse/orders')}
          className="p-5 bg-white border border-slate-200 rounded-2xl cursor-pointer hover:border-indigo-300 hover:shadow-xs transition-all group shadow-xs"
        >
          <div className="flex items-center justify-between">
            <div className="p-2.5 bg-indigo-50 text-indigo-600 rounded-xl group-hover:scale-105 transition-transform">
              <PackageCheck className="w-5 h-5" />
            </div>
            <ArrowRight className="w-4 h-4 text-slate-400 group-hover:text-indigo-600 transition-colors" />
          </div>
          <h3 className="text-sm font-bold text-slate-900 mt-4">Orders & Staging Queue</h3>
          <p className="text-xs text-slate-500 mt-1">
            View orders routed to this hub, confirm rider pickup, and manage packing states.
          </p>
        </div>

        <div
          onClick={() => navigate('/workforce/warehouse/rack-view')}
          className="p-5 bg-white border border-slate-200 rounded-2xl cursor-pointer hover:border-violet-300 hover:shadow-xs transition-all group shadow-xs"
        >
          <div className="flex items-center justify-between">
            <div className="p-2.5 bg-violet-50 text-violet-600 rounded-xl group-hover:scale-105 transition-transform">
              <Grid3X3 className="w-5 h-5" />
            </div>
            <ArrowRight className="w-4 h-4 text-slate-400 group-hover:text-violet-600 transition-colors" />
          </div>
          <h3 className="text-sm font-bold text-slate-900 mt-4">Rack & Shelf Layout</h3>
          <p className="text-xs text-slate-500 mt-1">
            Interactive visual layout of warehouse aisles, storage bays, and staging zones.
          </p>
        </div>

        <div
          onClick={() => navigate('/workforce/warehouse/profile')}
          className="p-5 bg-white border border-slate-200 rounded-2xl cursor-pointer hover:border-cyan-300 hover:shadow-xs transition-all group shadow-xs"
        >
          <div className="flex items-center justify-between">
            <div className="p-2.5 bg-cyan-50 text-cyan-600 rounded-xl group-hover:scale-105 transition-transform">
              <Building2 className="w-5 h-5" />
            </div>
            <ArrowRight className="w-4 h-4 text-slate-400 group-hover:text-cyan-600 transition-colors" />
          </div>
          <h3 className="text-sm font-bold text-slate-900 mt-4">Facility Profile & Settings</h3>
          <p className="text-xs text-slate-500 mt-1">
            Review GPS coordinates, operating zone, contact info, and assigned merchant list.
          </p>
        </div>
      </div>

      {/* ── RECENT ORDERS PREVIEW ── */}
      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden shadow-xs">
        <div className="p-5 border-b border-slate-200 flex items-center justify-between bg-slate-50/50">
          <div className="flex items-center gap-2">
            <PackageCheck className="w-4 h-4 text-indigo-600" />
            <h3 className="text-xs font-bold text-slate-900 uppercase tracking-wider">Recent Staged Orders</h3>
          </div>
          <button
            type="button"
            onClick={() => navigate('/workforce/warehouse/orders')}
            className="text-xs font-bold text-indigo-600 hover:text-indigo-800 flex items-center gap-1"
          >
            <span>View All</span>
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs text-slate-700">
            <thead className="bg-slate-50 text-[11px] font-bold text-slate-600 uppercase tracking-wider border-b border-slate-200">
              <tr>
                <th className="p-3.5">Order</th>
                <th className="p-3.5">Merchant</th>
                <th className="p-3.5">Customer</th>
                <th className="p-3.5">Delivery Slot</th>
                <th className="p-3.5 text-center">Status</th>
                <th className="p-3.5 text-right">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {loading ? (
                <tr>
                  <td colSpan={6} className="p-8 text-center text-slate-500">
                    <RefreshCw className="w-5 h-5 animate-spin mx-auto mb-2 text-indigo-600" />
                    <span>Loading recent orders...</span>
                  </td>
                </tr>
              ) : recentOrders.length === 0 ? (
                <tr>
                  <td colSpan={6} className="p-8 text-center text-slate-500">
                    <PackageCheck className="w-6 h-6 mx-auto mb-2 text-slate-400" />
                    <span>No orders currently routed to this warehouse.</span>
                  </td>
                </tr>
              ) : (
                recentOrders.map((ord) => (
                  <tr key={ord.id} className="hover:bg-slate-50/80 transition-colors">
                    <td className="p-3.5">
                      <div className="font-mono font-bold text-slate-900">{ord.order_number}</div>
                      <div className="text-[10px] text-slate-500 font-mono">{ord.source_order_id}</div>
                    </td>
                    <td className="p-3.5 font-medium text-slate-800">{ord.company_name || '—'}</td>
                    <td className="p-3.5 text-slate-800">{ord.customer_name || '—'}</td>
                    <td className="p-3.5 text-slate-500">{ord.delivery_slot || 'Standard Delivery'}</td>
                    <td className="p-3.5 text-center">
                      <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${
                        ord.status === 'READY_FOR_PICKUP' || ord.status === 'PACKED'
                          ? 'bg-amber-50 text-amber-700 border-amber-200'
                          : ord.status === 'HANDED_OVER' || ord.status === 'DELIVERED'
                          ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                          : 'bg-indigo-50 text-indigo-700 border border-indigo-200'
                      }`}>
                        {ord.status}
                      </span>
                    </td>
                    <td className="p-3.5 text-right">
                      <button
                        type="button"
                        onClick={() => navigate('/workforce/warehouse/orders')}
                        className="text-xs font-bold text-indigo-600 hover:text-indigo-800"
                      >
                        Inspect
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

export default WarehouseHomePage;
