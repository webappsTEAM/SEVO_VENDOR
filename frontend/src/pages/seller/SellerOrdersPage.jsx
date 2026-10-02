import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { Sidebar } from '../../components/common/Sidebar.jsx';
import { useAuth } from '../../context/AuthProvider.jsx';
import {
  ShoppingBag,
  Clock,
  Package,
  Truck,
  CheckCircle2,
  AlertCircle,
  ArrowRight,
  Info,
  Sparkles,
  Search,
  Filter,
  RefreshCw,
  ChevronRight,
  Eye,
  Printer,
  X,
  FileText,
  User,
  Phone,
  MapPin,
  Calendar,
  CheckSquare,
  Square,
  AlertTriangle,
  ArrowUpRight,
  Check,
  Ban,
  Layers,
  Store,
  Loader2,
  Navigation,
  ShieldAlert,
  Barcode,
} from 'lucide-react';
import { CustomerLiveTrackingModal } from '../../components/common/CustomerLiveTrackingModal.jsx';

export function SellerOrdersPage() {
  const { user, token, isPlatformAdmin } = useAuth();
  const isSuperAdmin = isPlatformAdmin || user?.is_superuser;

  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Filter States
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [fulfillmentFilter, setFulfillmentFilter] = useState('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Pagination & Counts
  const [totalCount, setTotalCount] = useState(0);
  const [page, setPage] = useState(1);
  const [pageSize] = useState(20);

  // Metrics
  const [metrics, setMetrics] = useState({
    today_orders_count: 0,
    pending_orders_count: 0,
    in_prep_orders_count: 0,
    completed_orders_count: 0,
    cancelled_orders_count: 0,
  });

  // Selected Order for Detail Drawer & Packing Slip
  const [selectedOrderId, setSelectedOrderId] = useState(null);
  const [selectedOrderDetail, setSelectedOrderDetail] = useState(null);
  const [drawerLoading, setDrawerLoading] = useState(false);
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);

  // Packing Slip Modal
  const [packingSlipData, setPackingSlipData] = useState(null);
  const [packingSlipOrderId, setPackingSlipOrderId] = useState(null);
  const [isPackingSlipOpen, setIsPackingSlipOpen] = useState(false);

  // Transition & Action State
  const [actionLoading, setActionLoading] = useState(false);
  const [adminOverrideModal, setAdminOverrideModal] = useState({ isOpen: false, orderId: null, action: '', reason: '' });
  const [trackingJobId, setTrackingJobId] = useState(null);

  // Available Riders Diagnostics State (Read-only status for Sellers)
  const [availableRidersModal, setAvailableRidersModal] = useState({
    isOpen: false,
    orderId: null,
    orderNumber: null,
    loading: false,
    data: null,
    error: null,
  });
  const [storeLocationModal, setStoreLocationModal] = useState({
    isOpen: false,
    isWarehouse: false,
    message: '',
  });

  // Debounce search
  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedSearch(searchQuery);
      setPage(1);
    }, 300);
    return () => clearTimeout(handler);
  }, [searchQuery]);

  // Load metrics
  const loadMetrics = useCallback(async () => {
    if (!token) return;
    try {
      const res = await fetch('/api/workforce/seller-hub/metrics/', {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setMetrics({
          today_orders_count: data.today_orders_count || 0,
          pending_orders_count: data.pending_orders_count || 0,
          in_prep_orders_count: data.in_prep_orders_count || 0,
          completed_orders_count: data.completed_orders_count || 0,
          cancelled_orders_count: data.cancelled_orders_count || 0,
        });
      }
    } catch (e) {
      console.error('Failed to load order metrics', e);
    }
  }, [token]);

  // Track newly arrived orders for visual highlight
  const [newOrderIds, setNewOrderIds] = useState(new Set());
  const knownOrderIdsRef = useRef(null);
  const isPollingRef = useRef(false);

  // Load Orders List
  const loadOrders = useCallback(async (isSilent = false) => {
    if (!token) return;
    if (isPollingRef.current && isSilent) return;
    if (!isSilent) {
      setLoading(true);
      setError(null);
    }
    isPollingRef.current = true;
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        page_size: pageSize.toString(),
      });

      if (statusFilter && statusFilter !== 'ALL') {
        params.append('status', statusFilter);
      }
      if (fulfillmentFilter && fulfillmentFilter !== 'ALL') {
        params.append('fulfillment_type', fulfillmentFilter);
      }
      if (debouncedSearch) {
        params.append('search', debouncedSearch);
      }

      const res = await fetch(`/api/workforce/seller-hub/orders/?${params.toString()}`, {
        headers: { Authorization: `Bearer ${token}` },
      });

      if (!res.ok) {
        throw new Error('Failed to fetch orders from server.');
      }

      const data = await res.json();
      const incomingList = data.results || [];

      // Detect brand new incoming orders
      if (knownOrderIdsRef.current !== null) {
        const brandNew = incomingList.filter(o => !knownOrderIdsRef.current.has(o.id)).map(o => o.id);
        if (brandNew.length > 0) {
          setNewOrderIds(prev => new Set([...prev, ...brandNew]));
          setTimeout(() => {
            setNewOrderIds(prev => {
              const next = new Set(prev);
              brandNew.forEach(id => next.delete(id));
              return next;
            });
          }, 8000);
        }
      }
      knownOrderIdsRef.current = new Set(incomingList.map(o => o.id));
      setOrders(incomingList);
      setTotalCount(data.count || 0);
    } catch (err) {
      console.error('Error fetching orders:', err);
      if (!isSilent) {
        setError(err.message || 'Error loading orders.');
      }
    } finally {
      isPollingRef.current = false;
      if (!isSilent) {
        setLoading(false);
      }
    }
  }, [token, page, pageSize, statusFilter, fulfillmentFilter, debouncedSearch]);

  useEffect(() => {
    loadOrders(false);
    loadMetrics();
  }, [loadOrders, loadMetrics]);

  // Background Auto-Refresh Polling (every 10s, pause when tab hidden or modal open)
  useEffect(() => {
    const pollInterval = 10000;
    const intervalId = setInterval(() => {
      if (document.visibilityState === 'visible' && !adminOverrideModal.isOpen && !isDrawerOpen && !isPackingSlipOpen) {
        loadOrders(true);
        loadMetrics();
      }
    }, pollInterval);

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        loadOrders(true);
        loadMetrics();
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      clearInterval(intervalId);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [loadOrders, loadMetrics, adminOverrideModal.isOpen, isDrawerOpen, isPackingSlipOpen]);

  // Available Riders Auto-Refresh when Available Riders modal is open (every 6s)
  useEffect(() => {
    if (!availableRidersModal.isOpen || !availableRidersModal.orderId) return;
    const intervalId = setInterval(async () => {
      if (document.visibilityState !== 'visible') return;
      try {
        const res = await fetch(`/api/workforce/seller-hub/orders/${availableRidersModal.orderId}/available-riders/`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (res.ok) {
          const data = await res.json();
          setAvailableRidersModal(prev => prev.isOpen ? { ...prev, data } : prev);
        }
      } catch (_) {}
    }, 6000);

    return () => clearInterval(intervalId);
  }, [availableRidersModal.isOpen, availableRidersModal.orderId, token]);

  // Open Order Detail Drawer
  const openOrderDetail = async (orderId) => {
    setSelectedOrderId(orderId);
    setIsDrawerOpen(true);
    setDrawerLoading(true);
    try {
      const res = await fetch(`/api/workforce/seller-hub/orders/${orderId}/`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setSelectedOrderDetail(data);
      }
    } catch (err) {
      console.error('Error loading order detail:', err);
    } finally {
      setDrawerLoading(false);
    }
  };

  // Open Packing Slip (quick on-screen preview)
  const openPackingSlip = async (orderId) => {
    try {
      const res = await fetch(`/api/workforce/seller-hub/orders/${orderId}/packing-slip/`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        setPackingSlipData(data);
        setPackingSlipOrderId(orderId);
        setIsPackingSlipOpen(true);
      }
    } catch (err) {
      console.error('Error loading packing slip:', err);
    }
  };

  // Download / open the real shipping-label PDF (4x6, scannable barcode) --
  // this is what actually gets printed and taped to the package. Fetched as a
  // blob (rather than a plain window.open navigation) so the Authorization
  // header reaches the API.
  const [labelDownloadingId, setLabelDownloadingId] = useState(null);
  const downloadPackingSlipPdf = async (orderId) => {
    setLabelDownloadingId(orderId);
    try {
      const res = await fetch(`/api/workforce/seller-hub/orders/${orderId}/packing-slip/pdf/`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const blob = await res.blob();
        const blobUrl = URL.createObjectURL(blob);
        window.open(blobUrl, '_blank');
        // Release the object URL once the new tab has had a chance to load it.
        setTimeout(() => URL.revokeObjectURL(blobUrl), 30000);
      } else {
        console.error('Error generating shipping label PDF:', res.status);
      }
    } catch (err) {
      console.error('Error generating shipping label PDF:', err);
    } finally {
      setLabelDownloadingId(null);
    }
  };

  // Execute Platform Admin Manual Override (Superusers Only)
  const handleAdminOverride = async () => {
    const { orderId, action, reason } = adminOverrideModal;
    if (!orderId || !action) return;
    if (!reason.trim()) {
      alert('A mandatory justification reason is required for platform admin override.');
      return;
    }
    try {
      setActionLoading(true);
      const res = await fetch(`/api/workforce/seller-hub/orders/${orderId}/admin-override/`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          action,
          reason: reason.trim(),
        }),
      });

      const data = await res.json();
      if (!res.ok) {
        alert(data.error || 'Failed to execute admin override.');
        return;
      }

      loadOrders();
      loadMetrics();
      if (selectedOrderId === orderId) {
        setSelectedOrderDetail(data.order);
      }
      setAdminOverrideModal({ isOpen: false, orderId: null, action: '', reason: '' });
    } catch (err) {
      console.error('Error executing admin override:', err);
      alert('Network error executing admin override.');
    } finally {
      setActionLoading(false);
    }
  };

  // Open Available Riders Diagnostics Modal (Read-only for Seller)
  const openAvailableRiders = async (orderId, orderNumber) => {
    setAvailableRidersModal({
      isOpen: true,
      orderId,
      orderNumber,
      loading: true,
      data: null,
      error: null,
    });
    try {
      const res = await fetch(`/api/workforce/seller-hub/orders/${orderId}/available-riders/`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) throw new Error('Failed to load rider availability.');
      const data = await res.json();
      setAvailableRidersModal((prev) => ({ ...prev, loading: false, data }));
    } catch (err) {
      setAvailableRidersModal((prev) => ({ ...prev, loading: false, error: err.message }));
    }
  };

  // Helper: Status Badge Styles
  const renderStatusBadge = (status) => {
    switch (status) {
      case 'NEW':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-amber-50 text-amber-800 border border-amber-300">
            <Clock className="w-3 h-3 text-amber-600" />
            <span>Awaiting Warehouse Review</span>
          </span>
        );
      case 'ACCEPTED':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
            <Check className="w-3 h-3" />
            <span>Accepted</span>
          </span>
        );
      case 'PICKING':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-200">
            <Package className="w-3 h-3" />
            <span>Picking</span>
          </span>
        );
      case 'PACKED':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-purple-50 text-purple-700 border border-purple-200">
            <CheckSquare className="w-3 h-3" />
            <span>Packed</span>
          </span>
        );
      case 'READY_FOR_PICKUP':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-teal-50 text-teal-700 border border-teal-200">
            <Truck className="w-3 h-3" />
            <span>Ready for Pickup</span>
          </span>
        );
      case 'ASSIGNED':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-200">
            <Truck className="w-3 h-3" />
            <span>Rider Assigned</span>
          </span>
        );
      case 'HANDED_OVER':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-purple-50 text-purple-700 border border-purple-200">
            <Truck className="w-3 h-3" />
            <span>Out for Delivery</span>
          </span>
        );
      case 'DELIVERED':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-300">
            <CheckCircle2 className="w-3 h-3" />
            <span>Delivered</span>
          </span>
        );
      case 'CANCELLED':
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-rose-50 text-rose-700 border border-rose-200">
            <Ban className="w-3 h-3" />
            <span>Cancelled</span>
          </span>
        );
      default:
        return (
          <span className="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-slate-100 text-slate-700">
            {status}
          </span>
        );
    }
  };

  return (
    <div className="flex h-screen bg-slate-100 font-sans text-slate-800 overflow-hidden">
      <Sidebar />

      <main className="flex-1 min-w-0 flex flex-col overflow-y-auto">
        {/* Top Header */}
        <header className="bg-white border-b border-slate-200 sticky top-0 z-10 px-8 py-5 flex items-center justify-between shadow-xs">
          <div className="flex items-center gap-3">
            <span className="p-2.5 bg-blue-50 text-blue-600 rounded-xl border border-blue-100">
              <ShoppingBag className="w-5 h-5" />
            </span>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-xl font-bold text-slate-900 tracking-tight">Seller Hub Orders</h1>
                <span className="text-[10px] font-bold uppercase tracking-wider bg-blue-50 text-blue-700 border border-blue-200 px-2 py-0.5 rounded-full">
                  Real Fulfilment Engine
                </span>
              </div>
              <p className="text-xs text-slate-500 mt-0.5">
                Manage incoming orders, item picking, packing, delivery handoffs, and packing slips
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2.5">
            <button
              onClick={() => {
                loadOrders();
                loadMetrics();
              }}
              disabled={loading}
              className="p-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-lg transition-colors"
              title="Refresh Orders"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            </button>
            <Link
              to="/workforce/seller/dashboard"
              className="px-3.5 py-2 text-xs font-semibold text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors"
            >
              Seller Home
            </Link>
            <Link
              to="/workforce/seller-hub/inventory"
              className="px-3.5 py-2 text-xs font-semibold text-white bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors shadow-xs"
            >
              Inventory Balance
            </Link>
          </div>
        </header>

        {/* Content Area */}
        <div className="p-8 w-full space-y-6">
          {/* Top Metrics Cards */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-xs">
              <div className="flex items-center justify-between text-slate-400">
                <span className="text-xs font-medium">Today's Orders</span>
                <Clock className="w-4 h-4 text-blue-500" />
              </div>
              <p className="text-2xl font-extrabold text-slate-900 font-mono mt-2">{metrics.today_orders_count}</p>
              <p className="text-[11px] text-slate-400 mt-0.5">Incoming queue</p>
            </div>

            <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-xs">
              <div className="flex items-center justify-between text-slate-400">
                <span className="text-xs font-medium">New (Warehouse Review)</span>
                <Package className="w-4 h-4 text-amber-500" />
              </div>
              <p className="text-2xl font-extrabold text-amber-600 font-mono mt-2">{metrics.pending_orders_count}</p>
              <p className="text-[11px] text-slate-400 mt-0.5">Awaiting warehouse acceptance</p>
            </div>

            <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-xs">
              <div className="flex items-center justify-between text-slate-400">
                <span className="text-xs font-medium">In Preparation</span>
                <Truck className="w-4 h-4 text-indigo-500" />
              </div>
              <p className="text-2xl font-extrabold text-indigo-600 font-mono mt-2">{metrics.in_prep_orders_count}</p>
              <p className="text-[11px] text-slate-400 mt-0.5">Picking / Packed / Ready</p>
            </div>

            <div className="bg-white p-4 rounded-xl border border-slate-200 shadow-xs">
              <div className="flex items-center justify-between text-slate-400">
                <span className="text-xs font-medium">Fulfilled & Completed</span>
                <CheckCircle2 className="w-4 h-4 text-emerald-500" />
              </div>
              <p className="text-2xl font-extrabold text-emerald-600 font-mono mt-2">{metrics.completed_orders_count}</p>
              <p className="text-[11px] text-slate-400 mt-0.5">Handed over or delivered</p>
            </div>
          </div>

          {/* Filter Tabs and Search Bar */}
          <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-xs space-y-4">
            {/* Status Tabs */}
            <div className="flex flex-wrap items-center gap-1.5 border-b border-slate-100 pb-3">
              {[
                { id: 'ALL', label: 'All Orders' },
                { id: 'NEW', label: 'New (Warehouse Review)' },
                { id: 'IN_PREPARATION', label: 'In Preparation' },
                { id: 'READY_FOR_PICKUP', label: 'Ready for Pickup' },
                { id: 'COMPLETED', label: 'Completed' },
                { id: 'CANCELLED', label: 'Cancelled' },
              ].map((tab) => (
                <button
                  key={tab.id}
                  onClick={() => {
                    setStatusFilter(tab.id);
                    setPage(1);
                  }}
                  className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-all ${
                    statusFilter === tab.id
                      ? 'bg-blue-600 text-white shadow-xs'
                      : 'bg-slate-50 text-slate-600 hover:bg-slate-100'
                  }`}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {/* Secondary Search & Fulfillment Filters */}
            <div className="flex flex-col sm:flex-row items-center justify-between gap-3">
              <div className="relative flex-1 w-full">
                <Search className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2" />
                <input
                  type="text"
                  placeholder="Search by Order #, Customer Name, SKU..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-9 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:border-blue-500 focus:bg-white transition-all"
                />
              </div>

              <div className="flex items-center gap-2 w-full sm:w-auto">
                <select
                  value={fulfillmentFilter}
                  onChange={(e) => {
                    setFulfillmentFilter(e.target.value);
                    setPage(1);
                  }}
                  className="px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-700 focus:outline-none focus:border-blue-500"
                >
                  <option value="ALL">All Fulfilment Types</option>
                  <option value="DELIVERY">Delivery</option>
                  <option value="STORE_PICKUP">Store Pickup</option>
                </select>
              </div>
            </div>
          </div>

          {/* Orders Table Container */}
          <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
            {loading ? (
              <div className="p-16 flex flex-col items-center justify-center text-center">
                <RefreshCw className="w-8 h-8 text-blue-600 animate-spin mb-3" />
                <p className="text-xs font-semibold text-slate-500">Loading orders from database...</p>
              </div>
            ) : error ? (
              <div className="p-12 text-center">
                <AlertCircle className="w-8 h-8 text-rose-500 mx-auto mb-2" />
                <h3 className="text-sm font-bold text-slate-800">Error Loading Orders</h3>
                <p className="text-xs text-slate-500 mt-1">{error}</p>
                <button
                  onClick={loadOrders}
                  className="mt-4 px-4 py-2 bg-blue-600 text-white text-xs font-semibold rounded-lg"
                >
                  Retry
                </button>
              </div>
            ) : orders.length === 0 ? (
              /* Empty State */
              <div className="p-16 flex flex-col items-center justify-center text-center">
                <div className="w-16 h-16 bg-slate-50 border border-slate-200 rounded-2xl flex items-center justify-center text-slate-400 mb-4 shadow-xs">
                  <ShoppingBag className="w-8 h-8 text-slate-400" />
                </div>
                <h3 className="text-base font-bold text-slate-900">No Orders in Queue</h3>
                <p className="text-xs text-slate-500 max-w-md mt-1.5 leading-relaxed">
                  Real marketplace customer bookings will arrive here automatically when customers check out from your approved product catalog.
                </p>

                <div className="mt-6 flex items-center gap-3">
                  <Link
                    to="/workforce/seller-hub/inventory"
                    className="inline-flex items-center gap-1.5 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-xs font-semibold shadow-xs transition-colors"
                  >
                    <Package className="w-4 h-4" />
                    <span>Check Inventory Stock</span>
                  </Link>
                  <Link
                    to="/workforce/seller-hub/products"
                    className="inline-flex items-center gap-1.5 px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-lg text-xs font-semibold transition-colors"
                  >
                    <Layers className="w-4 h-4" />
                    <span>Manage Catalog</span>
                  </Link>
                </div>
              </div>
            ) : (
              /* Orders Table */
              <div className="overflow-x-auto">
                <table className="w-full text-left border-collapse">
                  <thead>
                    <tr className="bg-slate-50/80 border-b border-slate-200 text-[11px] font-bold text-slate-500 uppercase tracking-wider">
                      <th className="py-3.5 px-5">Order Reference</th>
                      <th className="py-3.5 px-4">Customer & Slot</th>
                      <th className="py-3.5 px-4">Items Summary</th>
                      <th className="py-3.5 px-4">Total Amount</th>
                      <th className="py-3.5 px-4">Fulfilment Status</th>
                      <th className="py-3.5 px-5 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 text-xs">
                    {orders.map((ord) => {
                      const isNew = newOrderIds.has(ord.id);
                      return (
                      <tr key={ord.id} className={`transition-all duration-300 ${
                        isNew
                          ? 'bg-emerald-50/80 hover:bg-emerald-100/60 ring-2 ring-emerald-400/40 ring-inset'
                          : 'hover:bg-slate-50/60'
                      }`}>
                        <td className="py-4 px-5 align-top">
                          <div className="flex flex-col">
                            <div className="flex items-center gap-1.5">
                              <span className="font-bold text-slate-900 font-mono text-sm">{ord.order_number}</span>
                              {isNew && (
                                <span className="px-1.5 py-0.2 bg-emerald-600 text-white text-[9px] font-black rounded-full animate-pulse uppercase tracking-wider">
                                  NEW
                                </span>
                              )}
                            </div>
                            <span className="text-[10px] font-mono text-slate-400 mt-0.5">
                              Src: {ord.source_order_id}
                            </span>
                            <span className="text-[10px] text-slate-400 mt-1">
                              {new Date(ord.created_at).toLocaleDateString('en-GB', {
                                day: '2-digit',
                                month: 'short',
                                hour: '2-digit',
                                minute: '2-digit',
                              })}
                            </span>
                          </div>
                        </td>

                        <td className="py-4 px-4 align-top">
                          <div className="flex flex-col max-w-[200px]">
                            <span className="font-semibold text-slate-800">{ord.customer_name}</span>
                            {ord.customer_phone && (
                              <span className="text-[11px] text-slate-500">{ord.customer_phone}</span>
                            )}
                            {ord.delivery_slot && (
                              <span className="text-[10px] bg-slate-100 text-slate-600 px-2 py-0.5 rounded mt-1 inline-block w-fit">
                                Slot: {ord.delivery_slot}
                              </span>
                            )}
                          </div>
                        </td>

                        <td className="py-4 px-4 align-top">
                          <div className="flex flex-col max-w-[260px]">
                            <span className="font-medium text-slate-700">{ord.items_count} item(s)</span>
                            <p className="text-[11px] text-slate-400 line-clamp-2 mt-0.5 leading-relaxed">
                              {ord.items_summary}
                            </p>
                          </div>
                        </td>

                        <td className="py-4 px-4 align-top">
                          <div className="flex flex-col">
                            <span className="font-extrabold text-slate-900 font-mono text-sm">
                              ₹ {parseFloat(ord.total_amount || 0).toFixed(2)}
                            </span>
                            <span className="text-[10px] font-semibold text-emerald-700 bg-emerald-50 px-1.5 py-0.5 rounded border border-emerald-200 w-fit mt-1">
                              {ord.payment_method} ({ord.payment_status})
                            </span>
                          </div>
                        </td>

                        <td className="py-4 px-4 align-top">
                          <div className="flex flex-col gap-1">
                            {renderStatusBadge(ord.status)}
                            <span className="text-[10px] text-slate-400 font-medium">
                              Type: {ord.fulfillment_type === 'STORE_PICKUP' ? 'Store Pickup' : 'Delivery'}
                            </span>
                          </div>
                        </td>

                        <td className="py-4 px-5 align-top text-right">
                          <div className="flex items-center justify-end gap-1.5 flex-wrap">
                            {/* Read-only Fulfillment Status Indicators for Seller Hub */}
                            {ord.status === 'NEW' && (
                              <span
                                className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-1 rounded bg-amber-50 text-amber-800 border border-amber-200"
                                title="Fulfillment warehouse will verify physical stock and accept or dispatch this order"
                              >
                                <Clock className="w-3 h-3 text-amber-600" />
                                <span>In Warehouse Review</span>
                              </span>
                            )}

                            {ord.status === 'ACCEPTED' && (
                              <span
                                className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-1 rounded bg-blue-50 text-blue-700 border border-blue-200"
                                title="Accepted by warehouse — staged for picking"
                              >
                                <Check className="w-3 h-3 text-blue-600" />
                                <span>Accepted</span>
                              </span>
                            )}

                            {ord.status === 'PICKING' && (
                              <span
                                className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-1 rounded bg-indigo-50 text-indigo-700 border border-indigo-200"
                                title="Warehouse staff is picking items"
                              >
                                <Package className="w-3 h-3 text-indigo-600" />
                                <span>Picking</span>
                              </span>
                            )}

                            {ord.status === 'PACKED' && (
                              <span
                                className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-1 rounded bg-purple-50 text-purple-700 border border-purple-200"
                                title="Packed in warehouse — awaiting rider dispatch"
                              >
                                <CheckSquare className="w-3 h-3 text-purple-600" />
                                <span>Packed</span>
                              </span>
                            )}

                            {['READY_FOR_PICKUP', 'ASSIGNED'].includes(ord.status) && (
                              <div className="flex items-center gap-1.5 flex-wrap justify-end">
                                {ord.handling_technician_name ? (
                                  <span className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-1 rounded bg-indigo-50 text-indigo-700 border border-indigo-200">
                                    <Truck className="w-3 h-3" />
                                    <span>{ord.handling_technician_name}</span>
                                  </span>
                                ) : (
                                  <button
                                    type="button"
                                    onClick={() => openAvailableRiders(ord.id, ord.order_number)}
                                    className="inline-flex items-center gap-1 text-[11px] font-semibold px-2 py-1 rounded bg-amber-50 hover:bg-amber-100 text-amber-800 border border-amber-200 transition-colors shadow-2xs"
                                    title="Click to view eligible delivery partners & GPS status"
                                  >
                                    <Loader2 className="w-3 h-3 animate-spin text-amber-600" />
                                    <span>Assigning Delivery Partner...</span>
                                    <Info className="w-3 h-3 ml-0.5 text-amber-600 opacity-80" />
                                  </button>
                                )}
                                {ord.dispatch_job_id && (
                                  <button
                                    onClick={() => setTrackingJobId(ord.dispatch_job_id)}
                                    className="p-1.5 bg-indigo-50 hover:bg-indigo-100 text-indigo-700 rounded-lg transition-colors border border-indigo-200"
                                    title="Live Track Delivery Rider"
                                  >
                                    <Navigation className="w-4 h-4" />
                                  </button>
                                )}
                              </div>
                            )}

                            {ord.status === 'HANDED_OVER' && ord.dispatch_job_id && (
                              <button
                                onClick={() => setTrackingJobId(ord.dispatch_job_id)}
                                className="px-2.5 py-1.5 bg-purple-50 hover:bg-purple-100 text-purple-700 rounded-lg text-xs font-semibold transition-colors border border-purple-200 flex items-center gap-1"
                                title="Live Track Delivery Partner"
                              >
                                <Navigation className="w-3.5 h-3.5" />
                                <span>Track Rider</span>
                              </button>
                            )}

                            {/* View Details Drawer */}
                            <button
                              onClick={() => openOrderDetail(ord.id)}
                              className="p-1.5 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-lg transition-colors"
                              title="Order Details & Picking List"
                            >
                              <Eye className="w-4 h-4" />
                            </button>

                            {/* Packing Slip (quick preview) */}
                            <button
                              onClick={() => openPackingSlip(ord.id)}
                              className="p-1.5 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-lg transition-colors"
                              title="Preview Packing Slip"
                            >
                              <Printer className="w-4 h-4" />
                            </button>

                            {/* Shipping Label PDF (barcode, primary print target) */}
                            <button
                              onClick={() => downloadPackingSlipPdf(ord.id)}
                              disabled={labelDownloadingId === ord.id}
                              className="p-1.5 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-lg transition-colors disabled:opacity-50"
                              title="Download Shipping Label (PDF, scannable barcode)"
                            >
                              {labelDownloadingId === ord.id ? (
                                <Loader2 className="w-4 h-4 animate-spin" />
                              ) : (
                                <Barcode className="w-4 h-4" />
                              )}
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </main>

      {/* ── DRAWER: ORDER DETAIL & FULFILMENT CHECKLIST ── */}
      {isDrawerOpen && (
        <div className="fixed inset-0 z-50 overflow-hidden bg-slate-900/40 backdrop-blur-xs flex justify-end">
          <div className="w-full max-w-2xl bg-white h-full shadow-2xl flex flex-col animate-in slide-in-from-right duration-200">
            {/* Drawer Header */}
            <div className="p-5 border-b border-slate-200 flex items-center justify-between bg-slate-50/50">
              <div className="flex items-center gap-3">
                <span className="p-2 bg-blue-100 text-blue-700 rounded-lg">
                  <ShoppingBag className="w-5 h-5" />
                </span>
                <div>
                  <h2 className="text-base font-bold text-slate-900 font-mono">
                    {selectedOrderDetail?.order_number || 'Loading Order...'}
                  </h2>
                  <p className="text-[11px] text-slate-500">
                    Marketplace Reference: {selectedOrderDetail?.source_order_id}
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-2">
                {selectedOrderDetail && renderStatusBadge(selectedOrderDetail.status)}
                <button
                  onClick={() => setIsDrawerOpen(false)}
                  className="p-1.5 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
            </div>

            {/* Drawer Content */}
            <div className="flex-1 overflow-y-auto p-6 space-y-6">
              {drawerLoading ? (
                <div className="py-20 flex flex-col items-center justify-center text-center">
                  <RefreshCw className="w-8 h-8 text-blue-600 animate-spin mb-3" />
                  <p className="text-xs text-slate-500">Fetching order details & item checklist...</p>
                </div>
              ) : selectedOrderDetail ? (
                <>
                  {/* Customer & Fulfilment Snapshot */}
                  <div className="p-4 bg-slate-50 rounded-xl border border-slate-200 grid grid-cols-2 gap-4 text-xs">
                    <div>
                      <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1">
                        Customer & Delivery
                      </span>
                      <p className="font-bold text-slate-800">{selectedOrderDetail.customer_name}</p>
                      <p className="text-slate-600">{selectedOrderDetail.customer_phone}</p>
                      <p className="text-slate-500 mt-1 line-clamp-2">{selectedOrderDetail.delivery_address}</p>
                    </div>
                    <div>
                      <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1">
                        Fulfilment Info
                      </span>
                      <p className="text-slate-700 font-semibold">
                        Type: {selectedOrderDetail.fulfillment_type === 'STORE_PICKUP' ? 'Store Pickup' : 'Delivery'}
                      </p>
                      {selectedOrderDetail.delivery_slot && (
                        <p className="text-slate-600 mt-0.5">Slot: {selectedOrderDetail.delivery_slot}</p>
                      )}
                      <p className="text-slate-600 mt-0.5 font-mono font-bold">
                        Total: ₹ {parseFloat(selectedOrderDetail.total_amount || 0).toFixed(2)} ({selectedOrderDetail.payment_status})
                      </p>
                    </div>
                  </div>

                    {/* Item Picking & Packing Checklist (Read-Only Status from Warehouse) */}
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      <h3 className="text-xs font-bold text-slate-900 uppercase tracking-wider flex items-center gap-1.5">
                        <CheckSquare className="w-4 h-4 text-blue-600" />
                        <span>Item Picking Checklist ({selectedOrderDetail.items?.length || 0})</span>
                      </h3>
                      <span className="text-[11px] text-slate-400">Managed & verified by Warehouse</span>
                    </div>

                    <div className="divide-y divide-slate-100 border border-slate-200 rounded-xl overflow-hidden">
                      {selectedOrderDetail.items?.map((item) => (
                        <div key={item.id} className="p-3.5 bg-white hover:bg-slate-50/60 transition-colors flex items-center justify-between gap-3">
                          <div className="flex items-center gap-3">
                            <span
                              className={`p-1.5 rounded-lg border ${
                                item.is_picked
                                  ? 'bg-emerald-50 border-emerald-300 text-emerald-600'
                                  : 'bg-slate-50 border-slate-200 text-slate-400'
                              }`}
                              title={item.is_picked ? "Picked in Warehouse" : "Awaiting Picking"}
                            >
                              {item.is_picked ? <CheckSquare className="w-4 h-4" /> : <Square className="w-4 h-4" />}
                            </span>

                            <div>
                              <p className="font-bold text-xs text-slate-800">{item.product_title}</p>
                              <div className="flex items-center gap-2 mt-0.5">
                                <span className="text-[10px] font-mono bg-slate-100 text-slate-600 px-1.5 py-0.5 rounded">
                                  {item.sku}
                                </span>
                                {item.unit && (
                                  <span className="text-[10px] text-slate-400">
                                    {item.pack_size || item.unit}
                                  </span>
                                )}
                                <span className="text-[10px] text-slate-400">
                                  Avail: {item.available_stock} in stock
                                </span>
                              </div>
                            </div>
                          </div>

                          <div className="text-right">
                            <span className="font-extrabold text-sm text-slate-900 font-mono">
                              x {item.ordered_quantity}
                            </span>
                            <p className="text-[10px] text-slate-400 font-mono">
                              ₹ {parseFloat(item.line_total || 0).toFixed(2)}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Rider Assignment & Pickup OTP Banner */}
                  {['READY_FOR_PICKUP', 'ASSIGNED', 'HANDED_OVER'].includes(selectedOrderDetail.status) && (
                    <div className="p-4 bg-slate-50 rounded-xl border border-slate-200 space-y-3">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <div className="p-2 bg-indigo-100 rounded-lg text-indigo-700">
                            <Truck className="w-4 h-4" />
                          </div>
                          <div>
                            <div className="text-xs font-bold text-slate-900">
                              {selectedOrderDetail.handling_technician_name ? `Assigned Partner: ${selectedOrderDetail.handling_technician_name}` : 'Sevo Delivery Partner Dispatch'}
                            </div>
                            <div className="text-[11px] text-slate-500">
                              {selectedOrderDetail.handling_technician_phone ? `Contact: ${selectedOrderDetail.handling_technician_phone}` : 'Dispatching to nearest available Sevo Delivery Partner'}
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-1.5">
                          {!selectedOrderDetail.handling_technician_name && (
                            <button
                              type="button"
                              onClick={() => openAvailableRiders(selectedOrderDetail.id, selectedOrderDetail.order_number)}
                              className="px-2.5 py-1 bg-white hover:bg-slate-100 text-slate-700 border border-slate-300 rounded-lg text-xs font-semibold flex items-center gap-1 shadow-2xs"
                            >
                              <Info className="w-3 h-3 text-blue-600" />
                              <span>Riders Status</span>
                            </button>
                          )}
                          {selectedOrderDetail.dispatch_job_id && (
                            <button
                              onClick={() => setTrackingJobId(selectedOrderDetail.dispatch_job_id)}
                              className="px-2.5 py-1 bg-white hover:bg-slate-100 text-indigo-700 border border-indigo-200 rounded-lg text-xs font-semibold flex items-center gap-1 shadow-2xs"
                            >
                              <Navigation className="w-3 h-3" />
                              <span>Track</span>
                            </button>
                          )}
                        </div>
                      </div>
                      {selectedOrderDetail.pickup_otp && (
                        <div className="p-2.5 bg-amber-50 border border-amber-200 rounded-lg flex items-center justify-between">
                          <div className="text-xs text-amber-900">
                            <span className="font-bold">Pickup Verification OTP: </span>
                            <span className="font-mono text-sm font-black text-amber-950 bg-amber-200/80 px-2 py-0.5 rounded ml-1 tracking-widest">{selectedOrderDetail.pickup_otp}</span>
                          </div>
                          <span className="text-[10px] text-amber-700 font-medium">Share with Rider at Handover</span>
                        </div>
                      )}
                    </div>
                  )}

                  {/* Warehouse Fulfilment Status (Read-Only) */}
                  <div className="p-4 bg-slate-50 border border-slate-200 rounded-xl space-y-2.5">
                    <div className="flex items-center justify-between">
                      <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wider block">
                        Fulfilment Operations
                      </span>
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
                        Warehouse Fulfilled (FBS)
                      </span>
                    </div>

                    <div className="p-3 bg-white border border-slate-200 rounded-lg flex items-start gap-2.5 text-xs text-slate-700">
                      <Store className="w-4 h-4 text-blue-600 shrink-0 mt-0.5" />
                      <div className="space-y-1">
                        <span className="font-bold text-slate-900 block">
                          {selectedOrderDetail.status === 'NEW' && 'Order Awaiting Warehouse Acceptance'}
                          {selectedOrderDetail.status === 'ACCEPTED' && 'Order Accepted — Staged for Warehouse Picking'}
                          {selectedOrderDetail.status === 'PICKING' && 'Warehouse Staff is Picking Items'}
                          {selectedOrderDetail.status === 'PACKED' && 'Order Packed — Awaiting Rider Dispatch'}
                          {selectedOrderDetail.status === 'READY_FOR_PICKUP' && 'Order Ready — Dispatching Nearest Sevo Delivery Partner'}
                          {selectedOrderDetail.status === 'ASSIGNED' && 'Delivery Partner Assigned — En Route to Warehouse'}
                          {selectedOrderDetail.status === 'HANDED_OVER' && 'Handed Over to Delivery Partner — Out for Delivery'}
                          {selectedOrderDetail.status === 'DELIVERED' && 'Order Successfully Delivered to Customer'}
                          {selectedOrderDetail.status === 'CANCELLED' && 'Order Cancelled'}
                        </span>
                        <p className="text-[11px] text-slate-500 leading-relaxed">
                          Fulfillment lifecycle transitions (acceptance, picking, packing, QC and handover) are executed exclusively by warehouse operations to guarantee single-source physical stock integrity.
                        </p>
                      </div>
                    </div>

                    {['READY_FOR_PICKUP', 'ASSIGNED', 'HANDED_OVER'].includes(selectedOrderDetail.status) && selectedOrderDetail.dispatch_job_id && (
                      <div className="pt-1">
                        <button
                          onClick={() => setTrackingJobId(selectedOrderDetail.dispatch_job_id)}
                          className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg text-xs font-bold shadow-xs transition-colors flex items-center gap-1.5"
                        >
                          <Navigation className="w-3.5 h-3.5" />
                          <span>Live Track Rider</span>
                        </button>
                      </div>
                    )}
                  </div>

                  {/* Platform Admin Manual Override Controls (Superusers / Platform Admins Only) */}
                  {isSuperAdmin && !['DELIVERED', 'CANCELLED'].includes(selectedOrderDetail.status) && (
                    <div className="p-4 bg-amber-50/70 border border-amber-300 rounded-xl space-y-2.5">
                      <div className="flex items-center gap-2 text-amber-900">
                        <ShieldAlert className="w-4 h-4 text-amber-700" />
                        <span className="text-xs font-bold uppercase tracking-wider">
                          Platform Admin Manual Override
                        </span>
                      </div>
                      <p className="text-[11px] text-amber-800">
                        Emergency bypass for stuck orders (rider device died, OTP delivery failure, unreachable customer). Reason is required and logged in immutable audit history.
                      </p>
                      <div className="flex flex-wrap items-center gap-2 pt-1">
                        {['READY_FOR_PICKUP', 'ASSIGNED'].includes(selectedOrderDetail.status) && (
                          <button
                            onClick={() => setAdminOverrideModal({
                              isOpen: true,
                              orderId: selectedOrderDetail.id,
                              action: 'admin_override_handover',
                              reason: '',
                            })}
                            disabled={actionLoading}
                            className="px-3.5 py-1.5 bg-amber-700 hover:bg-amber-800 text-white rounded-lg text-xs font-bold shadow-xs transition-colors"
                          >
                            Override: Force Handover
                          </button>
                        )}
                        {['READY_FOR_PICKUP', 'ASSIGNED', 'HANDED_OVER'].includes(selectedOrderDetail.status) && (
                          <button
                            onClick={() => setAdminOverrideModal({
                              isOpen: true,
                              orderId: selectedOrderDetail.id,
                              action: 'admin_override_deliver',
                              reason: '',
                            })}
                            disabled={actionLoading}
                            className="px-3.5 py-1.5 bg-emerald-700 hover:bg-emerald-800 text-white rounded-lg text-xs font-bold shadow-xs transition-colors"
                          >
                            Override: Force Deliver
                          </button>
                        )}
                      </div>
                    </div>
                  )}

                  {/* Immutable Audit Trail Timeline */}
                  <div className="space-y-3">
                    <h3 className="text-xs font-bold text-slate-900 uppercase tracking-wider">
                      Fulfilment Audit History
                    </h3>

                    <div className="divide-y divide-slate-100 border border-slate-200 rounded-xl overflow-hidden bg-white">
                      {selectedOrderDetail.audit_logs?.length === 0 ? (
                        <p className="p-4 text-xs text-slate-400 text-center">No history logs recorded yet.</p>
                      ) : (
                        selectedOrderDetail.audit_logs?.map((log) => (
                          <div key={log.id} className="p-3 text-xs flex items-start justify-between gap-3">
                            <div>
                              <span className="font-bold text-slate-800">{log.action}</span>
                              <p className="text-[11px] text-slate-500 mt-0.5">
                                Actor: {log.actor_name} | From: {log.from_status || 'NEW'} → To: {log.to_status}
                              </p>
                              {log.notes && (
                                <p className="text-[11px] text-slate-600 mt-1 italic">Note: "{log.notes}"</p>
                              )}
                            </div>
                            <span className="text-[10px] text-slate-400 shrink-0">
                              {new Date(log.created_at).toLocaleString('en-GB')}
                            </span>
                          </div>
                        ))
                      )}
                    </div>
                  </div>
                </>
              ) : null}
            </div>

            {/* Drawer Footer */}
            <div className="p-4 border-t border-slate-200 bg-slate-50 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <button
                  onClick={() => selectedOrderDetail && downloadPackingSlipPdf(selectedOrderDetail.id)}
                  disabled={labelDownloadingId === selectedOrderDetail?.id}
                  className="inline-flex items-center gap-1.5 px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white text-xs font-semibold rounded-lg transition-colors shadow-xs disabled:opacity-50"
                >
                  {labelDownloadingId === selectedOrderDetail?.id ? (
                    <Loader2 className="w-4 h-4 animate-spin" />
                  ) : (
                    <Barcode className="w-4 h-4" />
                  )}
                  <span>Shipping Label (PDF)</span>
                </button>
                <button
                  onClick={() => selectedOrderDetail && openPackingSlip(selectedOrderDetail.id)}
                  className="inline-flex items-center gap-1.5 px-3 py-2 bg-slate-200 hover:bg-slate-300 text-slate-700 text-xs font-semibold rounded-lg transition-colors"
                  title="Quick on-screen preview"
                >
                  <Printer className="w-4 h-4" />
                  <span>Preview</span>
                </button>
              </div>
              <button
                onClick={() => setIsDrawerOpen(false)}
                className="px-4 py-2 bg-slate-800 hover:bg-slate-900 text-white text-xs font-semibold rounded-lg transition-colors"
              >
                Close Drawer
              </button>
            </div>
          </div>
        </div>
      )}



      {/* ── MODAL: PRINTABLE PACKING SLIP ── */}
      {isPackingSlipOpen && packingSlipData && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-2xl w-full p-8 shadow-2xl space-y-6">
            <div className="flex items-center justify-between border-b border-slate-200 pb-4">
              <div>
                <h2 className="text-lg font-black text-slate-900 tracking-tight">PACKING SLIP</h2>
                <p className="text-xs font-mono text-slate-500 font-bold">Order #{packingSlipData.order_number}</p>
                <p className="text-[10px] text-slate-400 mt-0.5">On-screen preview &mdash; use "Shipping Label (PDF)" to print the actual barcode label</p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => packingSlipOrderId && downloadPackingSlipPdf(packingSlipOrderId)}
                  disabled={labelDownloadingId === packingSlipOrderId}
                  className="px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white text-xs font-bold rounded-lg flex items-center gap-1.5 shadow-xs disabled:opacity-50"
                >
                  {labelDownloadingId === packingSlipOrderId ? (
                    <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  ) : (
                    <Barcode className="w-3.5 h-3.5" />
                  )}
                  <span>Shipping Label (PDF)</span>
                </button>
                <button
                  onClick={() => window.print()}
                  className="px-3 py-1.5 bg-slate-200 hover:bg-slate-300 text-slate-700 text-xs font-bold rounded-lg flex items-center gap-1.5"
                  title="Print this on-screen preview"
                >
                  <Printer className="w-3.5 h-3.5" />
                </button>
                <button
                  onClick={() => setIsPackingSlipOpen(false)}
                  className="p-1.5 text-slate-400 hover:text-slate-600 hover:bg-slate-100 rounded-lg"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>
            </div>

            {/* Merchant & Customer Header */}
            <div className="grid grid-cols-2 gap-6 text-xs">
              <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200">
                <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1">
                  Merchant / Store
                </span>
                <p className="font-bold text-slate-900">{packingSlipData.seller?.name}</p>
                <p className="text-slate-600">{packingSlipData.seller?.address || 'Verified Merchant Store'}</p>
                {packingSlipData.seller?.phone && <p className="text-slate-600">Tel: {packingSlipData.seller?.phone}</p>}
              </div>

              <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200">
                <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block mb-1">
                  Ship / Handover To
                </span>
                <p className="font-bold text-slate-900">{packingSlipData.customer?.name}</p>
                <p className="text-slate-600">{packingSlipData.customer?.delivery_address}</p>
                {packingSlipData.customer?.phone && <p className="text-slate-600">Tel: {packingSlipData.customer?.phone}</p>}
              </div>
            </div>

            {/* Item Table */}
            <table className="w-full text-left border-collapse text-xs">
              <thead>
                <tr className="bg-slate-100 border-b border-slate-200 text-[10px] font-bold text-slate-600 uppercase">
                  <th className="py-2 px-3">Check</th>
                  <th className="py-2 px-3">Product / SKU</th>
                  <th className="py-2 px-3 text-center">Unit / Pack</th>
                  <th className="py-2 px-3 text-right">Quantity</th>
                  <th className="py-2 px-3 text-right">Total Price</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {packingSlipData.items?.map((item, idx) => (
                  <tr key={idx} className="hover:bg-slate-50/50">
                    <td className="py-2.5 px-3">
                      <div className="w-4 h-4 border border-slate-400 rounded-sm"></div>
                    </td>
                    <td className="py-2.5 px-3">
                      <p className="font-bold text-slate-900">{item.title}</p>
                      <span className="text-[10px] font-mono text-slate-400">SKU: {item.sku}</span>
                    </td>
                    <td className="py-2.5 px-3 text-center text-slate-600">
                      {item.pack_size || item.unit || '–'}
                    </td>
                    <td className="py-2.5 px-3 text-right font-mono font-bold text-slate-900">
                      {item.ordered_qty}
                    </td>
                    <td className="py-2.5 px-3 text-right font-mono text-slate-700">
                      ₹ {parseFloat(item.line_total || 0).toFixed(2)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            {/* Total Footer */}
            <div className="border-t border-slate-200 pt-3 flex items-center justify-between text-xs">
              <span className="text-slate-500">
                Payment: {packingSlipData.payment_method} ({packingSlipData.payment_status})
              </span>
              <div className="text-right">
                <span className="text-slate-400 text-[10px] uppercase font-bold block">Grand Total</span>
                <span className="text-base font-black text-slate-900 font-mono">
                  ₹ {parseFloat(packingSlipData.total_amount || 0).toFixed(2)}
                </span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Platform Admin Override Modal */}
      {adminOverrideModal.isOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl border border-amber-200 space-y-4 animate-in fade-in zoom-in-95 duration-150">
            <div className="flex items-center gap-2.5 text-amber-900 border-b border-amber-100 pb-3">
              <span className="p-2 bg-amber-100 text-amber-800 rounded-xl">
                <ShieldAlert className="w-5 h-5" />
              </span>
              <div>
                <h3 className="text-sm font-bold text-slate-900">
                  {adminOverrideModal.action === 'admin_override_handover' ? 'Admin Override Handover' : 'Admin Override Delivery'}
                </h3>
                <p className="text-[11px] text-slate-500">Bypass OTP verification for order #{selectedOrderDetail?.order_number}</p>
              </div>
            </div>

            <div className="p-3 bg-amber-50 border border-amber-200 rounded-xl text-xs text-amber-900 space-y-1">
              <p className="font-semibold">Important Notice:</p>
              <p className="text-[11px] text-amber-800">
                This action forcefully advances the order status without requiring rider OTP entry. Your username, timestamp, and mandatory justification reason will be recorded in the immutable audit trail.
              </p>
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1.5">
                Justification Reason <span className="text-rose-500">*</span>
              </label>
              <textarea
                value={adminOverrideModal.reason}
                onChange={(e) => setAdminOverrideModal(prev => ({ ...prev, reason: e.target.value }))}
                placeholder="e.g. Rider device battery failed at store; physical package handover confirmed by store manager via phone."
                rows={3}
                className="w-full text-xs p-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-amber-500 focus:outline-hidden"
              />
            </div>

            <div className="flex items-center justify-end gap-2 pt-2 border-t border-slate-100">
              <button
                type="button"
                onClick={() => setAdminOverrideModal({ isOpen: false, orderId: null, action: '', reason: '' })}
                disabled={actionLoading}
                className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleAdminOverride}
                disabled={actionLoading || !adminOverrideModal.reason.trim()}
                className="px-4 py-2 text-xs font-bold text-white bg-amber-600 hover:bg-amber-700 disabled:opacity-50 rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
              >
                {actionLoading && <Loader2 className="w-3.5 h-3.5 animate-spin" />}
                <span>Confirm Override</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── MODAL: 2-WHEELER RIDER AVAILABILITY & ELIGIBILITY DIAGNOSTICS ── */}
      {availableRidersModal.isOpen && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-lg w-full p-6 shadow-2xl space-y-4 animate-in fade-in zoom-in duration-150 border border-slate-200">
            <div className="flex items-center justify-between border-b border-slate-100 pb-3">
              <div className="flex items-center gap-2.5">
                <div className="p-2 bg-indigo-100 text-indigo-700 rounded-xl">
                  <Truck className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-sm font-bold text-slate-900">
                    Sevo Delivery Partner Availability
                  </h3>
                  <p className="text-[11px] text-slate-500 font-mono">
                    Order #{availableRidersModal.orderNumber}
                  </p>
                </div>
              </div>
              <button
                onClick={() => setAvailableRidersModal(prev => ({ ...prev, isOpen: false }))}
                className="p-1 text-slate-400 hover:text-slate-600 rounded-lg hover:bg-slate-100 transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {availableRidersModal.loading ? (
              <div className="p-8 flex flex-col items-center justify-center text-center">
                <Loader2 className="w-6 h-6 text-blue-600 animate-spin mb-2" />
                <p className="text-xs font-semibold text-slate-600">Evaluating 10-gate dispatch criteria & live GPS...</p>
              </div>
            ) : availableRidersModal.error ? (
              <div className="p-4 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700 flex items-start gap-2">
                <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />
                <span>{availableRidersModal.error}</span>
              </div>
            ) : (
              <div className="space-y-3.5">
                {/* Status Summary Banner */}
                <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200 space-y-1">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-slate-800">Dispatch Evaluation Status</span>
                    <span className={`text-[11px] font-bold px-2 py-0.5 rounded-full ${
                      availableRidersModal.data?.store_location_missing
                        ? 'bg-amber-100 text-amber-800'
                        : availableRidersModal.data?.eligible_count > 0
                        ? 'bg-emerald-100 text-emerald-800'
                        : 'bg-amber-100 text-amber-800'
                    }`}>
                      {availableRidersModal.data?.store_location_missing
                        ? 'Location Not Set'
                        : `${availableRidersModal.data?.eligible_count || 0} Eligible Rider(s)`}
                    </span>
                  </div>
                  <p className="text-xs text-slate-600 font-medium">
                    {availableRidersModal.data?.diagnostic_summary}
                  </p>
                </div>

                {/* Store Location Missing Warning Banner */}
                {availableRidersModal.data?.store_location_missing && (
                  <div className="p-3.5 bg-amber-50 border border-amber-300 rounded-xl space-y-2.5">
                    <div className="flex items-start gap-2.5">
                      <MapPin className="w-5 h-5 text-amber-600 shrink-0 mt-0.5" />
                      <div>
                        <h4 className="text-xs font-bold text-amber-900">
                          Store Location Pin Missing
                        </h4>
                        <p className="text-[11px] text-amber-800 mt-0.5 leading-relaxed">
                          Your store or warehouse GPS coordinates have not been configured. Rider matching and dispatch require exact store coordinates to calculate distances and route nearby riders.
                        </p>
                      </div>
                    </div>
                    <div className="pt-1">
                      <Link
                        to="/workforce/seller-hub/store-profile"
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-amber-600 hover:bg-amber-700 text-white rounded-lg text-xs font-bold transition-colors shadow-xs"
                      >
                        <MapPin className="w-3.5 h-3.5" />
                        <span>Configure Store Location</span>
                      </Link>
                    </div>
                  </div>
                )}

                {/* Active Offer Status */}
                {availableRidersModal.data?.active_offer && (
                  <div className="p-3 bg-indigo-50 border border-indigo-200 rounded-xl text-xs text-indigo-900 space-y-1">
                    <div className="flex items-center justify-between">
                      <span className="font-bold flex items-center gap-1">
                        <Clock className="w-3.5 h-3.5 text-indigo-600" />
                        <span>Live Exclusive Offer Active</span>
                      </span>
                      <span className="text-[10px] font-mono bg-indigo-200/70 text-indigo-900 px-1.5 py-0.5 rounded font-bold">
                        Pending Accept
                      </span>
                    </div>
                    <p className="text-[11px] text-indigo-700">
                      Offered to <span className="font-bold">{availableRidersModal.data.active_offer.employee_name}</span>. Auto-expires if not accepted within the dispatch window.
                    </p>
                  </div>
                )}

                {/* Eligible Riders List */}
                {availableRidersModal.data?.eligible_riders?.length > 0 && (
                  <div className="space-y-2">
                    <span className="text-[11px] font-bold text-slate-700 uppercase tracking-wider block">
                      Eligible Technicians Ready For Offer
                    </span>
                    <div className="space-y-1.5 max-h-36 overflow-y-auto">
                      {availableRidersModal.data.eligible_riders.map((r) => (
                        <div key={r.employee_id} className="p-2.5 bg-emerald-50/60 border border-emerald-200 rounded-xl flex items-center justify-between text-xs">
                          <div>
                            <span className="font-bold text-slate-900">{r.name}</span>
                            <div className="text-[10px] text-slate-500">
                              {r.distance_km} km away • Proximity score: {r.score} • GPS ping {Math.round(r.gps_age_seconds)}s ago
                            </div>
                          </div>
                          <span className="text-[10px] font-bold px-2 py-0.5 bg-emerald-100 text-emerald-800 rounded">
                            Ready
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Ineligible Riders Diagnostic Breakdown */}
                {availableRidersModal.data?.ineligible_riders?.length > 0 && (
                  <div className="space-y-2">
                    <span className="text-[11px] font-bold text-slate-500 uppercase tracking-wider block">
                      Other Registered Technicians (Rejection Reason)
                    </span>
                    <div className="space-y-1.5 max-h-40 overflow-y-auto">
                      {availableRidersModal.data.ineligible_riders.map((r) => (
                        <div key={r.employee_id} className="p-2.5 bg-slate-50 border border-slate-200 rounded-xl flex items-start justify-between text-xs gap-2">
                          <div>
                            <span className="font-semibold text-slate-800">{r.name}</span>
                            <p className="text-[11px] text-slate-500 mt-0.5 leading-snug">
                              {r.reason}
                            </p>
                          </div>
                          <span className="text-[9px] font-mono px-1.5 py-0.5 bg-slate-200 text-slate-700 rounded shrink-0">
                            {r.gate}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Action Footer */}
                <div className="pt-3 border-t border-slate-100 flex items-center justify-between">
                  <span className="text-[10px] text-slate-400">
                    Warehouse automated dispatcher sweeps continuously
                  </span>
                  <button
                    type="button"
                    onClick={() => openAvailableRiders(availableRidersModal.orderId, availableRidersModal.orderNumber)}
                    disabled={availableRidersModal.loading}
                    className="px-3.5 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-xl text-xs font-bold transition-colors shadow-xs flex items-center gap-1.5 disabled:opacity-50"
                  >
                    <RefreshCw className={`w-3.5 h-3.5 ${availableRidersModal.loading ? 'animate-spin' : ''}`} />
                    <span>Refresh Rider Status</span>
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ── MODAL: WAREHOUSE / STORE LOCATION REQUIRED ALERT ── */}
      {storeLocationModal.isOpen && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 shadow-2xl space-y-4 animate-in fade-in zoom-in duration-150 border border-amber-200">
            <div className="flex items-start gap-3">
              <div className="p-2.5 bg-amber-100 text-amber-700 rounded-xl shrink-0">
                <MapPin className="w-6 h-6" />
              </div>
              <div className="space-y-1">
                <h3 className="text-sm font-bold text-slate-900">
                  {storeLocationModal.isWarehouse
                    ? 'Warehouse Assignment Required'
                    : 'Store Location Required for Dispatch'}
                </h3>
                <p className="text-xs text-slate-600 leading-relaxed">
                  {storeLocationModal.message}
                </p>
              </div>
            </div>

            <div className="p-3 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-500 space-y-1">
              <p className="font-semibold text-slate-700">Why is this required?</p>
              <p className="text-[11px]">
                {storeLocationModal.isWarehouse
                  ? 'In SEVO logistics, rider pickups originate from designated regional warehouses where stock is consolidated. Only platform administrators can assign or update your fulfillment warehouse.'
                  : 'To assign delivery riders automatically, SEVO calculates real driving distances from your store pin to the customer address.'}
              </p>
            </div>

            <div className="flex items-center justify-end gap-2 pt-2 border-t border-slate-100">
              <button
                type="button"
                onClick={() => setStoreLocationModal({ isOpen: false, message: '' })}
                className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
              >
                Close
              </button>
              {!storeLocationModal.isWarehouse && (
                <Link
                  to="/workforce/seller-hub/store-profile"
                  className="inline-flex items-center gap-1.5 px-4 py-2 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl shadow-xs transition-colors"
                >
                  <MapPin className="w-3.5 h-3.5" />
                  <span>Set Store Location</span>
                </Link>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Customer / Rider Live Tracking Modal */}
      {trackingJobId && (
        <CustomerLiveTrackingModal
          jobId={trackingJobId}
          isOpen={Boolean(trackingJobId)}
          onClose={() => setTrackingJobId(null)}
          viewRole="admin"
        />
      )}
    </div>
  );
}

export default SellerOrdersPage;
