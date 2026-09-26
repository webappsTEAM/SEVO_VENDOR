import React, { useState, useEffect, useMemo } from 'react';
import { useAuth } from '../../context/AuthProvider.jsx';
import { apiWarehouseGetOrders, apiWarehouseGetOrderDetail } from '../../api/workforceService.js';
import {
  PackageCheck,
  Search,
  RefreshCw,
  Filter,
  Eye,
  X,
  Store,
  User,
  Phone,
  MapPin,
  Calendar,
  Layers,
  Truck,
  CheckCircle2,
  Clock,
  AlertCircle,
  Hash,
} from 'lucide-react';

export function WarehouseOrdersPage() {
  const { user } = useAuth();

  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');

  // Selected Order for Detail Modal
  const [selectedOrderId, setSelectedOrderId] = useState(null);
  const [orderDetail, setOrderDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const fetchOrders = async () => {
    setLoading(true);
    setError('');
    try {
      const params = {};
      if (statusFilter !== 'ALL') params.status = statusFilter;
      if (searchTerm.trim()) params.search = searchTerm.trim();

      const res = await apiWarehouseGetOrders(params);
      setOrders(res?.results || res || []);
    } catch (err) {
      console.error('Failed to load warehouse orders:', err);
      setError('Unable to load orders for this warehouse facility.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchOrders();
  }, [statusFilter]);

  const handleSearchSubmit = (e) => {
    e.preventDefault();
    fetchOrders();
  };

  const handleOpenDetail = async (orderId) => {
    setSelectedOrderId(orderId);
    setDetailLoading(true);
    try {
      const data = await apiWarehouseGetOrderDetail(orderId);
      setOrderDetail(data);
    } catch (err) {
      console.error('Failed to load order details:', err);
    } finally {
      setDetailLoading(false);
    }
  };

  const statusTabs = [
    { key: 'ALL', label: 'All Orders' },
    { key: 'READY_FOR_PICKUP', label: 'Ready for Pickup' },
    { key: 'IN_PREPARATION', label: 'In Preparation' },
    { key: 'COMPLETED', label: 'Completed / Handed Over' },
    { key: 'CANCELLED', label: 'Cancelled' },
  ];

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* ── TOP HEADER ── */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-black text-slate-900 flex items-center gap-2.5">
            <PackageCheck className="w-6 h-6 text-indigo-600" />
            <span>Warehouse Staging Orders</span>
          </h2>
          <p className="text-xs text-slate-500 mt-1">
            Orders routed to this hub for consolidation, verification, and two-wheeler rider handover
          </p>
        </div>

        <button
          type="button"
          onClick={fetchOrders}
          disabled={loading}
          className="inline-flex items-center gap-2 px-3.5 py-2 text-xs font-bold text-slate-700 bg-white hover:bg-slate-50 rounded-xl border border-slate-200 transition-colors shadow-xs w-fit"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin text-indigo-600' : ''}`} />
          <span>Refresh Orders</span>
        </button>
      </div>

      {error && (
        <div className="p-4 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {/* ── FILTER & SEARCH TOOLBAR ── */}
      <div className="bg-white border border-slate-200 p-4 rounded-2xl space-y-4 shadow-xs">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-3">
          {/* Status Tabs */}
          <div className="flex items-center gap-1 overflow-x-auto pb-1 md:pb-0">
            {statusTabs.map((tab) => (
              <button
                key={tab.key}
                type="button"
                onClick={() => setStatusFilter(tab.key)}
                className={`px-3 py-1.5 rounded-xl text-xs font-bold whitespace-nowrap transition-colors ${
                  statusFilter === tab.key
                    ? 'bg-indigo-600 text-white shadow-xs'
                    : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {/* Search Bar */}
          <form onSubmit={handleSearchSubmit} className="flex items-center gap-2">
            <div className="relative">
              <Search className="w-3.5 h-3.5 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
              <input
                type="text"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="Search Order #, Customer, Merchant..."
                className="pl-8 pr-3 py-1.5 text-xs bg-white border border-slate-200 rounded-xl text-slate-900 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 w-64 shadow-xs"
              />
            </div>
            <button
              type="submit"
              className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold transition-colors shadow-xs"
            >
              Filter
            </button>
          </form>
        </div>
      </div>

      {/* ── ORDERS TABLE ── */}
      <div className="bg-white border border-slate-200 rounded-2xl overflow-hidden shadow-xs">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs text-slate-700">
            <thead className="bg-slate-50 text-[11px] font-bold text-slate-600 uppercase tracking-wider border-b border-slate-200">
              <tr>
                <th className="p-3.5">Order ID</th>
                <th className="p-3.5">Merchant Seller</th>
                <th className="p-3.5">Customer</th>
                <th className="p-3.5">Consolidated Batch</th>
                <th className="p-3.5">Items Summary</th>
                <th className="p-3.5 text-center">Status</th>
                <th className="p-3.5 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {loading ? (
                <tr>
                  <td colSpan={7} className="p-12 text-center text-slate-500">
                    <RefreshCw className="w-6 h-6 animate-spin mx-auto mb-2 text-indigo-600" />
                    <span>Loading warehouse orders...</span>
                  </td>
                </tr>
              ) : orders.length === 0 ? (
                <tr>
                  <td colSpan={7} className="p-12 text-center text-slate-400">
                    <PackageCheck className="w-8 h-8 mx-auto mb-2 text-slate-400" />
                    <p className="font-bold text-slate-800">No matching orders found</p>
                    <p className="text-[11px] text-slate-500 mt-1">
                      No merchant orders matching "{statusFilter}" are currently routed to this warehouse.
                    </p>
                  </td>
                </tr>
              ) : (
                orders.map((ord) => (
                  <tr
                    key={ord.id}
                    onClick={() => handleOpenDetail(ord.id)}
                    className="hover:bg-slate-50/80 cursor-pointer transition-colors"
                  >
                    <td className="p-3.5">
                      <div className="font-mono font-bold text-slate-900 flex items-center gap-1.5">
                        <Hash className="w-3 h-3 text-indigo-600" />
                        <span>{ord.order_number}</span>
                      </div>
                      <div className="text-[10px] text-slate-500 font-mono mt-0.5">{ord.source_order_id}</div>
                    </td>

                    <td className="p-3.5">
                      <div className="font-bold text-slate-800 flex items-center gap-1">
                        <Store className="w-3 h-3 text-amber-500 shrink-0" />
                        <span>{ord.company_name || `Company #${ord.company}`}</span>
                      </div>
                    </td>

                    <td className="p-3.5">
                      <div className="font-medium text-slate-800">{ord.customer_name || 'Customer'}</div>
                      <div className="text-[10px] text-slate-500 font-mono">{ord.customer_phone || ''}</div>
                    </td>

                    <td className="p-3.5 font-mono text-[11px]">
                      {ord.delivery_group_id ? (
                        <span className="bg-indigo-50 text-indigo-700 px-2 py-0.5 rounded border border-indigo-200">
                          {ord.delivery_group_id.slice(0, 16)}
                        </span>
                      ) : (
                        <span className="text-slate-400">Single</span>
                      )}
                    </td>

                    <td className="p-3.5">
                      <div className="text-slate-800 truncate max-w-xs">{ord.items_summary || `${ord.items_count || 1} items`}</div>
                      <div className="text-[10px] text-slate-500 font-semibold">₹{Number(ord.total_amount || 0).toFixed(2)}</div>
                    </td>

                    <td className="p-3.5 text-center">
                      <span className={`px-2.5 py-1 rounded-full text-[10px] font-bold border ${
                        ord.status === 'READY_FOR_PICKUP' || ord.status === 'PACKED'
                          ? 'bg-amber-50 text-amber-700 border-amber-200'
                          : ord.status === 'HANDED_OVER' || ord.status === 'DELIVERED'
                          ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                          : ord.status === 'CANCELLED'
                          ? 'bg-rose-50 text-rose-700 border-rose-200'
                          : 'bg-indigo-50 text-indigo-700 border border-indigo-200'
                      }`}>
                        {ord.status}
                      </span>
                    </td>

                    <td className="p-3.5 text-right" onClick={(e) => e.stopPropagation()}>
                      <button
                        type="button"
                        onClick={() => handleOpenDetail(ord.id)}
                        className="p-1.5 text-slate-400 hover:text-indigo-600 hover:bg-slate-100 rounded-lg transition-colors"
                        title="View Order Details"
                      >
                        <Eye className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── MODAL: ORDER DETAILS ── */}
      {selectedOrderId && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white border border-slate-200 rounded-2xl max-w-2xl w-full p-6 shadow-2xl space-y-5 animate-in fade-in zoom-in duration-150">
            <div className="flex items-center justify-between border-b border-slate-200 pb-3">
              <div className="flex items-center gap-2.5">
                <div className="p-2 bg-indigo-50 text-indigo-600 rounded-xl border border-indigo-100">
                  <PackageCheck className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-sm font-bold text-slate-900">
                    Order {orderDetail?.order_number || `#${selectedOrderId}`}
                  </h3>
                  <p className="text-xs text-slate-500 font-mono">
                    Source: {orderDetail?.source_order_id || 'Marketplace Order'}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => {
                  setSelectedOrderId(null);
                  setOrderDetail(null);
                }}
                className="p-1.5 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded-lg transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {detailLoading ? (
              <div className="p-12 text-center text-slate-500">
                <RefreshCw className="w-6 h-6 animate-spin mx-auto mb-2 text-indigo-600" />
                <span>Loading order details...</span>
              </div>
            ) : orderDetail ? (
              <div className="space-y-4 text-xs">
                {/* Status & Delivery Group */}
                <div className="grid grid-cols-2 gap-3 p-3.5 bg-slate-50 rounded-xl border border-slate-200">
                  <div>
                    <span className="text-[10px] uppercase font-bold text-slate-500">Fulfilment Status</span>
                    <p className="font-bold text-indigo-700 mt-0.5">{orderDetail.status}</p>
                  </div>
                  <div>
                    <span className="text-[10px] uppercase font-bold text-slate-500">Consolidated Batch</span>
                    <p className="font-mono text-slate-700 mt-0.5">{orderDetail.delivery_group_id || 'Single Shipment'}</p>
                  </div>
                </div>

                {/* Merchant & Customer Info */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200 space-y-1">
                    <span className="text-[10px] uppercase font-bold text-amber-700 flex items-center gap-1">
                      <Store className="w-3 h-3" /> Merchant Seller
                    </span>
                    <p className="font-bold text-slate-900">{orderDetail.company_name}</p>
                    <p className="text-[11px] text-slate-500 font-mono">Seller ID #{orderDetail.company}</p>
                  </div>

                  <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200 space-y-1">
                    <span className="text-[10px] uppercase font-bold text-indigo-700 flex items-center gap-1">
                      <User className="w-3 h-3" /> Customer Details
                    </span>
                    <p className="font-bold text-slate-900">{orderDetail.customer_name}</p>
                    <p className="text-[11px] text-slate-500 font-mono">{orderDetail.customer_phone}</p>
                  </div>
                </div>

                {/* Items List */}
                <div className="space-y-2">
                  <span className="text-[10px] uppercase font-bold text-slate-500">Order Items ({orderDetail.items?.length || 0})</span>
                  <div className="bg-slate-50 border border-slate-200 rounded-xl divide-y divide-slate-200 max-h-48 overflow-y-auto">
                    {orderDetail.items?.map((item) => (
                      <div key={item.id} className="p-3 flex items-center justify-between">
                        <div>
                          <p className="font-bold text-slate-900">{item.product_title || item.product_name || `Item #${item.id}`}</p>
                          <p className="text-[10px] text-slate-500 font-mono">SKU: {item.sku || '—'}</p>
                        </div>
                        <div className="text-right">
                          <span className="font-bold text-slate-900">x{item.quantity}</span>
                          <span className="text-[11px] text-slate-500 block font-mono">₹{Number(item.total_price || 0).toFixed(2)}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Rider & Delivery Info */}
                <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200 space-y-2">
                  <span className="text-[10px] uppercase font-bold text-slate-500 flex items-center gap-1">
                    <Truck className="w-3 h-3 text-indigo-600" /> Dispatch Delivery Info
                  </span>
                  <div className="grid grid-cols-2 gap-2 text-[11px]">
                    <div>
                      <span className="text-slate-500 block">Assigned Rider</span>
                      <span className="font-bold text-slate-900">
                        {orderDetail.handling_technician_name || 'Awaiting Rider Assignment'}
                      </span>
                    </div>
                    <div>
                      <span className="text-slate-500 block">Delivery Address</span>
                      <span className="text-slate-700 truncate block">{orderDetail.delivery_address || '—'}</span>
                    </div>
                  </div>
                </div>
              </div>
            ) : null}

            <div className="flex items-center justify-end pt-3 border-t border-slate-200">
              <button
                type="button"
                onClick={() => {
                  setSelectedOrderId(null);
                  setOrderDetail(null);
                }}
                className="px-4 py-2 text-xs font-bold text-slate-700 hover:text-slate-900 bg-white hover:bg-slate-50 border border-slate-200 rounded-xl transition-colors shadow-xs"
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

export default WarehouseOrdersPage;
