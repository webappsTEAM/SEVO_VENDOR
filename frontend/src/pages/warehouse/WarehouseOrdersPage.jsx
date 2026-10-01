import React, { useState, useEffect, useMemo } from 'react';
import { useAuth } from '../../context/AuthProvider.jsx';
import { apiWarehouseGetOrders, apiWarehouseGetOrderDetail, apiWarehouseTransitionOrder } from '../../api/workforceService.js';
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
  Check,
  Ban,
  Loader2,
  Package,
  History,
} from 'lucide-react';

export function WarehouseOrdersPage() {
  const { user } = useAuth();

  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('ALL');

  // Action state
  const [actionLoadingId, setActionLoadingId] = useState(null);
  const [cancellationModal, setCancellationModal] = useState({
    isOpen: false,
    orderId: null,
    orderNumber: '',
    reason: '',
  });

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

  const handleTransition = async (orderId, action, notes = '', cancellationReason = '') => {
    if (!orderId) return;
    try {
      setActionLoadingId(orderId);
      const payload = {
        action,
        notes,
        cancellation_reason: cancellationReason,
      };
      const res = await apiWarehouseTransitionOrder(orderId, payload);
      
      // Refresh list
      await fetchOrders();

      // If detail modal is open for this order, update it
      if (selectedOrderId === orderId) {
        if (res?.order) {
          setOrderDetail(res.order);
        } else {
          await handleOpenDetail(orderId);
        }
      }

      if (cancellationModal.isOpen) {
        setCancellationModal({ isOpen: false, orderId: null, orderNumber: '', reason: '' });
      }
    } catch (err) {
      console.error(`Failed to execute ${action} on order ${orderId}:`, err);
      alert(err.message || 'Failed to update order state.');
    } finally {
      setActionLoadingId(null);
    }
  };

  const statusTabs = [
    { key: 'ALL', label: 'All Orders' },
    { key: 'NEW', label: 'New / Action Required' },
    { key: 'IN_PREPARATION', label: 'In Preparation' },
    { key: 'READY_FOR_PICKUP', label: 'Ready for Pickup' },
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
            Orders routed to this hub for warehouse acceptance, picking, packing, verification, and two-wheeler rider handover
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
                orders.map((ord) => {
                  const isActing = actionLoadingId === ord.id;
                  return (
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
                        {ord.delivery_slot && (
                          <div className="text-[10px] text-emerald-700 font-bold bg-emerald-50 border border-emerald-200 px-1.5 py-0.5 rounded w-fit mt-1">
                            Slot: {ord.delivery_slot}
                          </div>
                        )}
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
                          ord.status === 'NEW'
                            ? 'bg-amber-50 text-amber-800 border-amber-300'
                            : ord.status === 'READY_FOR_PICKUP' || ord.status === 'PACKED'
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
                        <div className="flex items-center justify-end gap-1.5 flex-wrap">
                          {/* NEW: Warehouse Accept / Reject Actions */}
                          {ord.status === 'NEW' && (
                            <>
                              <button
                                type="button"
                                onClick={() => handleTransition(ord.id, 'accept')}
                                disabled={isActing}
                                className="px-2.5 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg text-xs font-semibold transition-colors shadow-xs flex items-center gap-1 disabled:opacity-50"
                                title="Accept Order for Warehouse Fulfillment"
                              >
                                {isActing ? (
                                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                                ) : (
                                  <Check className="w-3.5 h-3.5" />
                                )}
                                <span>Accept</span>
                              </button>
                              <button
                                type="button"
                                onClick={() => setCancellationModal({
                                  isOpen: true,
                                  orderId: ord.id,
                                  orderNumber: ord.order_number,
                                  reason: '',
                                })}
                                disabled={isActing}
                                className="px-2 py-1.5 bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 rounded-lg text-xs font-semibold transition-colors flex items-center gap-1 disabled:opacity-50"
                                title="Reject / Cancel Order"
                              >
                                <Ban className="w-3.5 h-3.5" />
                                <span>Reject</span>
                              </button>
                            </>
                          )}

                          {ord.status === 'ACCEPTED' && (
                            <button
                              type="button"
                              onClick={() => handleTransition(ord.id, 'start_picking')}
                              disabled={isActing}
                              className="px-2.5 py-1.5 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-xs font-semibold transition-colors shadow-xs disabled:opacity-50"
                            >
                              {isActing ? 'Processing...' : 'Start Picking'}
                            </button>
                          )}

                          {ord.status === 'PICKING' && (
                            <button
                              type="button"
                              onClick={() => handleTransition(ord.id, 'mark_packed')}
                              disabled={isActing}
                              className="px-2.5 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg text-xs font-semibold transition-colors shadow-xs disabled:opacity-50"
                            >
                              {isActing ? 'Processing...' : 'Mark Packed'}
                            </button>
                          )}

                          {ord.status === 'PACKED' && (
                            <button
                              type="button"
                              onClick={() => handleTransition(ord.id, 'mark_ready')}
                              disabled={isActing}
                              className="px-2.5 py-1.5 bg-purple-600 hover:bg-purple-700 text-white rounded-lg text-xs font-semibold transition-colors shadow-xs flex items-center gap-1 disabled:opacity-50"
                            >
                              <Truck className="w-3.5 h-3.5" />
                              <span>{isActing ? 'Dispatching...' : 'Dispatch Rider'}</span>
                            </button>
                          )}

                          <button
                            type="button"
                            onClick={() => handleOpenDetail(ord.id)}
                            className="p-1.5 text-slate-400 hover:text-indigo-600 hover:bg-slate-100 rounded-lg transition-colors"
                            title="View Order Details"
                          >
                            <Eye className="w-4 h-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* ── MODAL: ORDER DETAILS ── */}
      {selectedOrderId && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white border border-slate-200 rounded-2xl max-w-2xl w-full p-6 shadow-2xl space-y-5 animate-in fade-in zoom-in duration-150 max-h-[90vh] flex flex-col">
            <div className="flex items-center justify-between border-b border-slate-200 pb-3 shrink-0">
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
              <div className="p-12 text-center text-slate-500 my-auto">
                <RefreshCw className="w-6 h-6 animate-spin mx-auto mb-2 text-indigo-600" />
                <span>Loading order details...</span>
              </div>
            ) : orderDetail ? (
              <div className="space-y-4 text-xs overflow-y-auto pr-1">
                {/* Fulfillment Actions Card (Warehouse Operations) */}
                <div className="p-3.5 bg-indigo-50/70 border border-indigo-200 rounded-xl space-y-2.5">
                  <div className="flex items-center justify-between">
                    <span className="text-[10px] font-bold text-indigo-900 uppercase tracking-wider">
                      Warehouse Fulfilment Actions
                    </span>
                    <span className="text-[11px] font-bold text-indigo-700 bg-white px-2 py-0.5 rounded-full border border-indigo-200">
                      Status: {orderDetail.status}
                    </span>
                  </div>

                  <div className="flex flex-wrap items-center gap-2 pt-1">
                    {orderDetail.status === 'NEW' && (
                      <>
                        <button
                          type="button"
                          onClick={() => handleTransition(orderDetail.id, 'accept')}
                          disabled={actionLoadingId === orderDetail.id}
                          className="px-3.5 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg text-xs font-bold transition-colors shadow-xs flex items-center gap-1.5 disabled:opacity-50"
                        >
                          <Check className="w-3.5 h-3.5" />
                          <span>Accept Order</span>
                        </button>
                        <button
                          type="button"
                          onClick={() => setCancellationModal({
                            isOpen: true,
                            orderId: orderDetail.id,
                            orderNumber: orderDetail.order_number,
                            reason: '',
                          })}
                          disabled={actionLoadingId === orderDetail.id}
                          className="px-3 py-1.5 bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 rounded-lg text-xs font-semibold transition-colors flex items-center gap-1.5 disabled:opacity-50"
                        >
                          <Ban className="w-3.5 h-3.5" />
                          <span>Reject / Cancel</span>
                        </button>
                      </>
                    )}

                    {orderDetail.status === 'ACCEPTED' && (
                      <button
                        type="button"
                        onClick={() => handleTransition(orderDetail.id, 'start_picking')}
                        disabled={actionLoadingId === orderDetail.id}
                        className="px-3.5 py-1.5 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-xs font-bold transition-colors shadow-xs disabled:opacity-50"
                      >
                        Start Picking Items
                      </button>
                    )}

                    {orderDetail.status === 'PICKING' && (
                      <button
                        type="button"
                        onClick={() => handleTransition(orderDetail.id, 'mark_packed')}
                        disabled={actionLoadingId === orderDetail.id}
                        className="px-3.5 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg text-xs font-bold transition-colors shadow-xs disabled:opacity-50"
                      >
                        Mark Items Packed
                      </button>
                    )}

                    {orderDetail.status === 'PACKED' && (
                      <button
                        type="button"
                        onClick={() => handleTransition(orderDetail.id, 'mark_ready')}
                        disabled={actionLoadingId === orderDetail.id}
                        className="px-3.5 py-1.5 bg-purple-600 hover:bg-purple-700 text-white rounded-lg text-xs font-bold transition-colors shadow-xs flex items-center gap-1.5 disabled:opacity-50"
                      >
                        <Truck className="w-3.5 h-3.5" />
                        <span>Dispatch 2-Wheeler Rider</span>
                      </button>
                    )}

                    {['ACCEPTED', 'PICKING', 'PACKED'].includes(orderDetail.status) && (
                      <button
                        type="button"
                        onClick={() => setCancellationModal({
                          isOpen: true,
                          orderId: orderDetail.id,
                          orderNumber: orderDetail.order_number,
                          reason: '',
                        })}
                        disabled={actionLoadingId === orderDetail.id}
                        className="px-3 py-1.5 bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 rounded-lg text-xs font-semibold transition-colors disabled:opacity-50"
                      >
                        Cancel Order
                      </button>
                    )}
                  </div>
                </div>

                {/* Status, Delivery Group & Slot */}
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 p-3.5 bg-slate-50 rounded-xl border border-slate-200">
                  <div>
                    <span className="text-[10px] uppercase font-bold text-slate-500">Fulfilment Status</span>
                    <p className="font-bold text-indigo-700 mt-0.5">{orderDetail.status}</p>
                  </div>
                  <div>
                    <span className="text-[10px] uppercase font-bold text-slate-500">Consolidated Batch</span>
                    <p className="font-mono text-slate-700 mt-0.5">{orderDetail.delivery_group_id || 'Single Shipment'}</p>
                  </div>
                  <div>
                    <span className="text-[10px] uppercase font-bold text-slate-500">Delivery Window / Slot</span>
                    <p className="font-bold text-emerald-700 mt-0.5">{orderDetail.delivery_slot || 'Standard / None'}</p>
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
                  {orderDetail.pickup_otp && (
                    <div className="p-2.5 bg-amber-50 border border-amber-200 rounded-lg flex items-center justify-between mt-2">
                      <div className="text-xs text-amber-900">
                        <span className="font-bold">Pickup Verification OTP: </span>
                        <span className="font-mono text-sm font-black text-amber-950 bg-amber-200/80 px-2 py-0.5 rounded ml-1 tracking-widest">
                          {orderDetail.pickup_otp}
                        </span>
                      </div>
                      <span className="text-[10px] text-amber-700 font-medium">Share with Rider at Handover</span>
                    </div>
                  )}
                </div>

                {/* Audit Trail Timeline */}
                {orderDetail.audit_logs?.length > 0 && (
                  <div className="space-y-2">
                    <span className="text-[10px] uppercase font-bold text-slate-500 flex items-center gap-1">
                      <History className="w-3 h-3 text-slate-400" /> Fulfilment Audit Trail
                    </span>
                    <div className="bg-white border border-slate-200 rounded-xl divide-y divide-slate-100 max-h-36 overflow-y-auto">
                      {orderDetail.audit_logs.map((log) => (
                        <div key={log.id} className="p-2.5 text-[11px] flex items-start justify-between gap-2">
                          <div>
                            <span className="font-bold text-slate-800">{log.action}</span>
                            <p className="text-[10px] text-slate-500">
                              Actor: {log.actor_name} | {log.from_status || 'NEW'} → {log.to_status}
                            </p>
                            {log.notes && <p className="text-[10px] text-slate-600 italic mt-0.5">"{log.notes}"</p>}
                          </div>
                          <span className="text-[10px] text-slate-400 shrink-0">
                            {new Date(log.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            ) : null}

            <div className="flex items-center justify-end pt-3 border-t border-slate-200 shrink-0">
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

      {/* ── MODAL: CANCELLATION REASON ── */}
      {cancellationModal.isOpen && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white border border-slate-200 rounded-2xl max-w-md w-full p-6 shadow-2xl space-y-4 animate-in fade-in zoom-in duration-150">
            <div className="flex items-center justify-between border-b border-slate-200 pb-3">
              <div className="flex items-center gap-2">
                <div className="p-2 bg-rose-50 text-rose-600 rounded-xl">
                  <Ban className="w-5 h-5" />
                </div>
                <h3 className="text-sm font-bold text-slate-900">
                  Reject Order {cancellationModal.orderNumber ? `#${cancellationModal.orderNumber}` : ''}
                </h3>
              </div>
              <button
                type="button"
                onClick={() => setCancellationModal({ isOpen: false, orderId: null, orderNumber: '', reason: '' })}
                className="p-1 text-slate-400 hover:text-slate-700 rounded-lg"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <p className="text-xs text-slate-600">
              Please provide a reason for rejecting/cancelling this order. Reserved inventory will be released back to the seller automatically.
            </p>

            <div>
              <label className="block text-[11px] font-bold text-slate-700 mb-1">Cancellation Reason *</label>
              <textarea
                value={cancellationModal.reason}
                onChange={(e) => setCancellationModal({ ...cancellationModal, reason: e.target.value })}
                placeholder="e.g. Stock damaged, item out of stock in warehouse, incorrect packaging..."
                className="w-full text-xs p-3 border border-slate-200 rounded-xl focus:outline-none focus:ring-2 focus:ring-rose-500 min-h-[90px]"
                rows={3}
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2 border-t border-slate-200">
              <button
                type="button"
                onClick={() => setCancellationModal({ isOpen: false, orderId: null, orderNumber: '', reason: '' })}
                className="px-3.5 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={!cancellationModal.reason.trim() || actionLoadingId === cancellationModal.orderId}
                onClick={() => handleTransition(cancellationModal.orderId, 'cancel', '', cancellationModal.reason.trim())}
                className="px-4 py-2 text-xs font-bold text-white bg-rose-600 hover:bg-rose-700 rounded-xl shadow-xs transition-colors disabled:opacity-50 flex items-center gap-1.5"
              >
                {actionLoadingId === cancellationModal.orderId ? (
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                ) : (
                  <Ban className="w-3.5 h-3.5" />
                )}
                <span>Confirm Rejection</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default WarehouseOrdersPage;
