import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Sidebar } from '../../components/common/Sidebar.jsx';
import { useAuth } from '../../context/AuthProvider.jsx';
import {
  apiAdminGetWarehouses,
  apiAdminGetDeliverySlots,
  apiAdminCreateDeliverySlot,
  apiAdminUpdateDeliverySlot,
  apiAdminDeleteDeliverySlot,
} from '../../api/workforceService.js';
import {
  Clock,
  Warehouse as WarehouseIcon,
  Search,
  Plus,
  Edit2,
  Trash2,
  CheckCircle2,
  XCircle,
  AlertCircle,
  RefreshCw,
  X,
  Zap,
  Calendar,
  Layers,
  ChevronDown,
} from 'lucide-react';

const DAYS_OF_WEEK = [
  { id: 0, label: 'Mon', full: 'Monday' },
  { id: 1, label: 'Tue', full: 'Tuesday' },
  { id: 2, label: 'Wed', full: 'Wednesday' },
  { id: 3, label: 'Thu', full: 'Thursday' },
  { id: 4, label: 'Fri', full: 'Friday' },
  { id: 5, label: 'Sat', full: 'Saturday' },
  { id: 6, label: 'Sun', full: 'Sunday' },
];

export function AdminDeliverySlotsPage() {
  const { user, isPlatformAdmin } = useAuth();
  const isSuperAdmin = isPlatformAdmin || user?.is_superuser;

  const [warehouses, setWarehouses] = useState([]);
  const [selectedWarehouseId, setSelectedWarehouseId] = useState('all');
  const [slots, setSlots] = useState([]);
  const [loading, setLoading] = useState(true);
  const [warehousesLoading, setWarehousesLoading] = useState(true);
  const [error, setError] = useState(null);

  // Filters
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all'); // 'all', 'active', 'inactive'
  const [typeFilter, setTypeFilter] = useState('all'); // 'all', 'STANDARD', 'EXPRESS'

  // Create / Edit Modal State
  const [modalOpen, setModalOpen] = useState(false);
  const [editingSlot, setEditingSlot] = useState(null);
  const [formData, setFormData] = useState({
    warehouse_id: '',
    label: '',
    start_time: '09:00',
    end_time: '11:00',
    slot_type: 'STANDARD',
    max_orders_per_slot: '',
    applicable_days: [0, 1, 2, 3, 4, 5, 6],
    is_active: true,
  });
  const [formErrors, setFormErrors] = useState({});
  const [saving, setSaving] = useState(false);
  const [deleteModalSlot, setDeleteModalSlot] = useState(null);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState(null);

  // ── Fetch Warehouses ────────────────────────────────────────────────────────
  const fetchWarehouses = useCallback(async () => {
    setWarehousesLoading(true);
    try {
      const data = await apiAdminGetWarehouses({ is_active: true });
      const whList = Array.isArray(data) ? data : (data?.results || []);
      setWarehouses(whList);
      if (whList.length > 0 && selectedWarehouseId === 'all') {
        // keep 'all' or default
      }
    } catch (err) {
      console.error('Error fetching warehouses:', err);
    } finally {
      setWarehousesLoading(false);
    }
  }, [selectedWarehouseId]);

  // ── Fetch Delivery Slots ────────────────────────────────────────────────────
  const fetchSlots = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const params = {};
      if (selectedWarehouseId && selectedWarehouseId !== 'all') {
        params.warehouse_id = selectedWarehouseId;
      }
      if (statusFilter === 'active') params.is_active = true;
      if (statusFilter === 'inactive') params.is_active = false;
      if (typeFilter !== 'all') params.slot_type = typeFilter;
      if (search.trim()) params.search = search.trim();

      const data = await apiAdminGetDeliverySlots(params);
      setSlots(Array.isArray(data) ? data : (data?.results || []));
    } catch (err) {
      console.error('Error loading delivery slots:', err);
      setError(err.message || 'Failed to fetch delivery slots.');
    } finally {
      setLoading(false);
    }
  }, [selectedWarehouseId, statusFilter, typeFilter, search]);

  useEffect(() => {
    fetchWarehouses();
  }, [fetchWarehouses]);

  useEffect(() => {
    fetchSlots();
  }, [fetchSlots]);

  // ── Modal Handlers ──────────────────────────────────────────────────────────
  const openCreateModal = () => {
    setEditingSlot(null);
    const defaultWhId = (selectedWarehouseId !== 'all' && selectedWarehouseId)
      ? selectedWarehouseId
      : (warehouses[0]?.id || '');
    setFormData({
      warehouse_id: defaultWhId,
      label: '09:00 AM - 11:00 AM',
      start_time: '09:00',
      end_time: '11:00',
      slot_type: 'STANDARD',
      max_orders_per_slot: '',
      applicable_days: [0, 1, 2, 3, 4, 5, 6],
      is_active: true,
    });
    setFormErrors({});
    setModalOpen(true);
  };

  const openEditModal = (slot) => {
    setEditingSlot(slot);
    let dayIndices = [0, 1, 2, 3, 4, 5, 6];
    if (slot.applicable_days && slot.applicable_days.trim()) {
      dayIndices = slot.applicable_days.split(',').map(d => parseInt(d.trim(), 10)).filter(d => !isNaN(d));
    }

    setFormData({
      warehouse_id: slot.warehouse || slot.warehouse_id || '',
      label: slot.label || '',
      start_time: slot.start_time ? slot.start_time.substring(0, 5) : '09:00',
      end_time: slot.end_time ? slot.end_time.substring(0, 5) : '11:00',
      slot_type: slot.slot_type || 'STANDARD',
      max_orders_per_slot: slot.max_orders_per_slot != null ? String(slot.max_orders_per_slot) : '',
      applicable_days: dayIndices,
      is_active: slot.is_active ?? true,
    });
    setFormErrors({});
    setModalOpen(true);
  };

  const toggleDaySelection = (dayId) => {
    setFormData((prev) => {
      const current = prev.applicable_days;
      if (current.includes(dayId)) {
        return { ...prev, applicable_days: current.filter(d => d !== dayId) };
      } else {
        return { ...prev, applicable_days: [...current, dayId].sort((a, b) => a - b) };
      }
    });
  };

  const toggleAllDays = () => {
    setFormData((prev) => {
      if (prev.applicable_days.length === 7) {
        return { ...prev, applicable_days: [] };
      } else {
        return { ...prev, applicable_days: [0, 1, 2, 3, 4, 5, 6] };
      }
    });
  };

  const validateForm = () => {
    const errors = {};
    if (!formData.warehouse_id) {
      errors.warehouse_id = 'Please select a warehouse facility.';
    }
    if (!formData.label.trim()) {
      errors.label = 'Slot label is required (e.g. 09:00 AM - 11:00 AM).';
    }
    if (!formData.start_time) {
      errors.start_time = 'Start time is required.';
    }
    if (!formData.end_time) {
      errors.end_time = 'End time is required.';
    }
    if (formData.start_time && formData.end_time && formData.start_time >= formData.end_time) {
      errors.end_time = 'End time must be strictly after start time.';
    }
    if (formData.max_orders_per_slot && (isNaN(Number(formData.max_orders_per_slot)) || Number(formData.max_orders_per_slot) < 1)) {
      errors.max_orders_per_slot = 'Capacity cap must be a positive integer or left blank.';
    }
    setFormErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleSaveSlot = async (e) => {
    e.preventDefault();
    if (!validateForm()) return;

    setSaving(true);
    setFormErrors({});
    try {
      const daysStr = formData.applicable_days.length === 7
        ? ''
        : formData.applicable_days.join(',');

      const payload = {
        warehouse_id: parseInt(formData.warehouse_id, 10),
        label: formData.label.trim(),
        start_time: formData.start_time,
        end_time: formData.end_time,
        slot_type: formData.slot_type,
        max_orders_per_slot: formData.max_orders_per_slot ? parseInt(formData.max_orders_per_slot, 10) : null,
        applicable_days: daysStr,
        is_active: formData.is_active,
      };

      if (editingSlot) {
        await apiAdminUpdateDeliverySlot(editingSlot.id, payload);
      } else {
        await apiAdminCreateDeliverySlot(payload);
      }

      setModalOpen(false);
      fetchSlots();
    } catch (err) {
      console.error('Failed to save delivery slot:', err);
      const serverErr = err.response?.data || err.data || {};
      if (serverErr.error) {
        setFormErrors({ general: serverErr.error });
      } else if (typeof serverErr === 'object') {
        setFormErrors(serverErr);
      } else {
        setFormErrors({ general: err.message || 'Failed to save delivery slot.' });
      }
    } finally {
      setSaving(false);
    }
  };

  const handleToggleActive = async (slot) => {
    try {
      await apiAdminUpdateDeliverySlot(slot.id, { is_active: !slot.is_active });
      fetchSlots();
    } catch (err) {
      console.error('Failed to toggle slot active state:', err);
      alert(err.message || 'Failed to update slot status.');
    }
  };

  const handleDeleteSlot = async () => {
    if (!deleteModalSlot) return;
    setDeleting(true);
    setDeleteError(null);
    try {
      await apiAdminDeleteDeliverySlot(deleteModalSlot.id);
      setDeleteModalSlot(null);
      fetchSlots();
    } catch (err) {
      console.error('Failed to delete delivery slot:', err);
      setDeleteError(err.message || 'Failed to delete slot. It may have existing orders.');
    } finally {
      setDeleting(false);
    }
  };

  const formatDaysDisplay = (daysStr) => {
    if (!daysStr || !daysStr.trim()) return 'Every Day (Mon - Sun)';
    const dayNums = daysStr.split(',').map(d => parseInt(d.trim(), 10)).filter(d => !isNaN(d));
    if (dayNums.length === 7) return 'Every Day (Mon - Sun)';
    if (dayNums.length === 0) return 'None';
    return dayNums.map(n => DAYS_OF_WEEK.find(d => d.id === n)?.label || n).join(', ');
  };

  return (
    <div className="flex h-screen bg-slate-50 text-slate-900 overflow-hidden">
      <Sidebar />

      <main className="flex-1 min-w-0 flex flex-col pt-16 lg:pt-0 overflow-y-auto">
        <div className="p-6 md:p-8 w-full space-y-6">

          {/* Header Banner */}
          <div className="bg-white rounded-2xl p-6 border border-slate-200 shadow-sm flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div>
              <div className="flex items-center gap-2.5">
                <div className="w-10 h-10 rounded-xl bg-emerald-50 border border-emerald-200 flex items-center justify-center text-emerald-600">
                  <Clock className="w-5 h-5" />
                </div>
                <div>
                  <h1 className="text-xl font-bold text-slate-900 tracking-tight">Delivery Slots & Capacity</h1>
                  <p className="text-xs text-slate-500 font-medium">Configure fulfillment delivery windows, fast dispatch slots, and capacity caps per warehouse</p>
                </div>
              </div>
            </div>

            <div className="flex items-center gap-3">
              <button
                onClick={fetchSlots}
                disabled={loading}
                className="p-2.5 bg-white border border-slate-200 rounded-xl hover:bg-slate-50 text-slate-600 transition-colors shadow-sm disabled:opacity-50"
                title="Refresh Slots"
              >
                <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-emerald-600' : ''}`} />
              </button>

              <button
                onClick={openCreateModal}
                className="flex items-center gap-2 px-4 py-2.5 bg-emerald-600 hover:bg-emerald-700 text-white text-sm font-semibold rounded-xl shadow-sm shadow-emerald-600/20 transition-all hover:shadow-md"
              >
                <Plus className="w-4 h-4" />
                <span>Add Delivery Slot</span>
              </button>
            </div>
          </div>

          {/* Filters & Warehouse Selector Bar */}
          <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-sm space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">

              {/* Warehouse Selector */}
              <div>
                <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wider mb-1.5 flex items-center gap-1.5">
                  <WarehouseIcon className="w-3.5 h-3.5 text-slate-400" />
                  Warehouse Facility
                </label>
                <select
                  value={selectedWarehouseId}
                  onChange={(e) => setSelectedWarehouseId(e.target.value)}
                  className="w-full text-xs font-semibold bg-slate-50 border border-slate-200 rounded-xl px-3 py-2.5 text-slate-800 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500"
                >
                  <option value="all">All Warehouses ({warehouses.length})</option>
                  {warehouses.map((wh) => (
                    <option key={wh.id} value={wh.id}>
                      {wh.name} ({wh.city || 'General'})
                    </option>
                  ))}
                </select>
              </div>

              {/* Search */}
              <div>
                <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wider mb-1.5">Search Slots</label>
                <div className="relative">
                  <Search className="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                  <input
                    type="text"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    placeholder="Search by label or name..."
                    className="w-full text-xs bg-slate-50 border border-slate-200 rounded-xl pl-9 pr-3 py-2.5 text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500"
                  />
                </div>
              </div>

              {/* Slot Type Filter */}
              <div>
                <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wider mb-1.5">Slot Type</label>
                <select
                  value={typeFilter}
                  onChange={(e) => setTypeFilter(e.target.value)}
                  className="w-full text-xs font-semibold bg-slate-50 border border-slate-200 rounded-xl px-3 py-2.5 text-slate-800 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500"
                >
                  <option value="all">All Types</option>
                  <option value="STANDARD">Standard Delivery</option>
                  <option value="EXPRESS">Fast / Express Delivery</option>
                </select>
              </div>

              {/* Status Filter */}
              <div>
                <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wider mb-1.5">Status</label>
                <select
                  value={statusFilter}
                  onChange={(e) => setStatusFilter(e.target.value)}
                  className="w-full text-xs font-semibold bg-slate-50 border border-slate-200 rounded-xl px-3 py-2.5 text-slate-800 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500"
                >
                  <option value="all">All Statuses</option>
                  <option value="active">Active Only</option>
                  <option value="inactive">Inactive Only</option>
                </select>
              </div>

            </div>
          </div>

          {/* Error Banner */}
          {error && (
            <div className="bg-rose-50 border border-rose-200 rounded-xl p-4 flex items-center gap-3 text-rose-700 text-sm">
              <AlertCircle className="w-5 h-5 flex-shrink-0" />
              <p className="font-medium">{error}</p>
            </div>
          )}

          {/* Slots Table */}
          <div className="bg-white rounded-2xl border border-slate-200 shadow-sm overflow-hidden">
            <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h2 className="text-sm font-bold text-slate-800">Configured Delivery Windows</h2>
                <span className="px-2 py-0.5 rounded-full text-[11px] font-bold bg-slate-100 text-slate-600">
                  {slots.length}
                </span>
              </div>
            </div>

            {loading ? (
              <div className="p-12 text-center text-slate-400">
                <RefreshCw className="w-8 h-8 animate-spin mx-auto mb-3 text-emerald-600" />
                <p className="text-xs font-medium">Loading delivery slots...</p>
              </div>
            ) : slots.length === 0 ? (
              <div className="p-12 text-center text-slate-400">
                <Clock className="w-12 h-12 mx-auto mb-3 text-slate-300 stroke-[1.5]" />
                <p className="font-bold text-slate-700 text-sm">No Delivery Slots Found</p>
                <p className="text-xs text-slate-500 mt-1 max-w-sm mx-auto">
                  {selectedWarehouseId !== 'all'
                    ? 'No delivery slots configured for this warehouse yet. Click "Add Delivery Slot" above.'
                    : 'Get started by creating your first delivery window.'}
                </p>
                <button
                  onClick={openCreateModal}
                  className="mt-4 inline-flex items-center gap-2 px-4 py-2 bg-emerald-50 text-emerald-700 hover:bg-emerald-100 text-xs font-bold rounded-xl transition-colors border border-emerald-200"
                >
                  <Plus className="w-4 h-4" />
                  <span>Create Delivery Slot</span>
                </button>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs border-collapse">
                  <thead>
                    <tr className="bg-slate-50/80 border-b border-slate-100 text-[11px] font-bold text-slate-500 uppercase tracking-wider">
                      <th className="py-3.5 px-6">Slot Window & Label</th>
                      <th className="py-3.5 px-6">Warehouse Facility</th>
                      <th className="py-3.5 px-6">Delivery Type</th>
                      <th className="py-3.5 px-6">Capacity Cap</th>
                      <th className="py-3.5 px-6">Applicable Days</th>
                      <th className="py-3.5 px-6">Status</th>
                      <th className="py-3.5 px-6 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {slots.map((slot) => {
                      const isExpress = slot.slot_type === 'EXPRESS';
                      return (
                        <tr key={slot.id} className="hover:bg-slate-50/60 transition-colors">
                          {/* Slot Window & Label */}
                          <td className="py-4 px-6">
                            <div className="flex items-center gap-3">
                              <div className={`w-8 h-8 rounded-lg flex items-center justify-center font-bold text-xs ${
                                isExpress
                                  ? 'bg-amber-50 text-amber-600 border border-amber-200'
                                  : 'bg-blue-50 text-blue-600 border border-blue-200'
                              }`}>
                                {isExpress ? <Zap className="w-4 h-4" /> : <Clock className="w-4 h-4" />}
                              </div>
                              <div>
                                <div className="font-bold text-slate-900 text-xs">{slot.label}</div>
                                <div className="text-[11px] text-slate-500 font-mono">
                                  {slot.start_time?.substring(0, 5)} - {slot.end_time?.substring(0, 5)}
                                </div>
                              </div>
                            </div>
                          </td>

                          {/* Warehouse */}
                          <td className="py-4 px-6">
                            <div className="flex items-center gap-2">
                              <WarehouseIcon className="w-3.5 h-3.5 text-slate-400" />
                              <span className="font-semibold text-slate-800">{slot.warehouse_name || `Warehouse #${slot.warehouse || slot.warehouse_id}`}</span>
                            </div>
                          </td>

                          {/* Type */}
                          <td className="py-4 px-6">
                            {isExpress ? (
                              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold bg-amber-50 text-amber-700 border border-amber-200">
                                <Zap className="w-3 h-3 text-amber-500" />
                                Fast Delivery
                              </span>
                            ) : (
                              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold bg-blue-50 text-blue-700 border border-blue-200">
                                <Clock className="w-3 h-3 text-blue-500" />
                                Standard Delivery
                              </span>
                            )}
                          </td>

                          {/* Capacity */}
                          <td className="py-4 px-6 font-medium text-slate-700">
                            {slot.max_orders_per_slot != null ? (
                              <span className="inline-flex items-center gap-1 font-semibold text-slate-900">
                                <span className="text-emerald-700 font-bold">{slot.max_orders_per_slot}</span>
                                <span className="text-slate-500 text-[11px]">orders / day</span>
                              </span>
                            ) : (
                              <span className="text-slate-400 text-[11px] italic">Unlimited Capacity</span>
                            )}
                          </td>

                          {/* Applicable Days */}
                          <td className="py-4 px-6 text-[11px] text-slate-600 font-medium">
                            <div className="flex items-center gap-1.5">
                              <Calendar className="w-3.5 h-3.5 text-slate-400 flex-shrink-0" />
                              <span>{formatDaysDisplay(slot.applicable_days)}</span>
                            </div>
                          </td>

                          {/* Status */}
                          <td className="py-4 px-6">
                            <button
                              onClick={() => handleToggleActive(slot)}
                              className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold transition-all ${
                                slot.is_active
                                  ? 'bg-emerald-50 text-emerald-700 border border-emerald-200 hover:bg-emerald-100'
                                  : 'bg-slate-100 text-slate-600 border border-slate-200 hover:bg-slate-200'
                              }`}
                              title="Click to toggle active status"
                            >
                              {slot.is_active ? (
                                <>
                                  <CheckCircle2 className="w-3 h-3 text-emerald-600" />
                                  <span>Active</span>
                                </>
                              ) : (
                                <>
                                  <XCircle className="w-3 h-3 text-slate-400" />
                                  <span>Inactive</span>
                                </>
                              )}
                            </button>
                          </td>

                          {/* Actions */}
                          <td className="py-4 px-6 text-right">
                            <div className="flex items-center justify-end gap-1.5">
                              <button
                                onClick={() => openEditModal(slot)}
                                className="p-2 hover:bg-slate-100 rounded-lg text-slate-600 transition-colors"
                                title="Edit Slot"
                              >
                                <Edit2 className="w-3.5 h-3.5" />
                              </button>
                              <button
                                onClick={() => {
                                  setDeleteModalSlot(slot);
                                  setDeleteError(null);
                                }}
                                className="p-2 hover:bg-rose-50 rounded-lg text-rose-600 transition-colors"
                                title="Delete Slot"
                              >
                                <Trash2 className="w-3.5 h-3.5" />
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

      {/* ── Create / Edit Delivery Slot Modal ───────────────────────────────── */}
      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl max-w-xl w-full max-h-[90vh] flex flex-col border border-slate-200 shadow-2xl overflow-hidden">
            {/* Modal Header */}
            <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50/50">
              <div className="flex items-center gap-2.5">
                <div className="w-9 h-9 rounded-xl bg-emerald-50 border border-emerald-200 flex items-center justify-center text-emerald-600">
                  <Clock className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="font-bold text-slate-900 text-sm">
                    {editingSlot ? 'Edit Delivery Slot' : 'Create Delivery Slot'}
                  </h3>
                  <p className="text-[11px] text-slate-500 font-medium">Define delivery timing and capacity restrictions</p>
                </div>
              </div>
              <button
                onClick={() => setModalOpen(false)}
                className="p-1.5 text-slate-400 hover:text-slate-600 rounded-lg hover:bg-slate-100 transition-colors"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            {/* Modal Form */}
            <form onSubmit={handleSaveSlot} className="flex-1 overflow-y-auto p-6 space-y-4">
              {formErrors.general && (
                <div className="p-3.5 bg-rose-50 border border-rose-200 rounded-xl text-rose-700 text-xs font-semibold flex items-center gap-2">
                  <AlertCircle className="w-4 h-4 flex-shrink-0" />
                  <span>{formErrors.general}</span>
                </div>
              )}

              {/* Warehouse Selection */}
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Warehouse Facility <span className="text-rose-500">*</span>
                </label>
                <select
                  value={formData.warehouse_id}
                  onChange={(e) => setFormData({ ...formData, warehouse_id: e.target.value })}
                  className={`w-full text-xs font-semibold bg-slate-50 border rounded-xl px-3.5 py-2.5 text-slate-900 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 ${
                    formErrors.warehouse_id ? 'border-rose-400 bg-rose-50/20' : 'border-slate-200 focus:border-emerald-500'
                  }`}
                >
                  <option value="">Select a warehouse facility...</option>
                  {warehouses.map((wh) => (
                    <option key={wh.id} value={wh.id}>
                      {wh.name} ({wh.city || 'General'})
                    </option>
                  ))}
                </select>
                {formErrors.warehouse_id && (
                  <p className="text-[11px] text-rose-500 font-semibold mt-1">{formErrors.warehouse_id}</p>
                )}
              </div>

              {/* Slot Label */}
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Slot Display Label <span className="text-rose-500">*</span>
                </label>
                <input
                  type="text"
                  value={formData.label}
                  onChange={(e) => setFormData({ ...formData, label: e.target.value })}
                  placeholder="e.g. 09:00 AM - 11:00 AM"
                  className={`w-full text-xs bg-slate-50 border rounded-xl px-3.5 py-2.5 text-slate-900 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 ${
                    formErrors.label ? 'border-rose-400 bg-rose-50/20' : 'border-slate-200 focus:border-emerald-500'
                  }`}
                />
                {formErrors.label && (
                  <p className="text-[11px] text-rose-500 font-semibold mt-1">{formErrors.label}</p>
                )}
              </div>

              {/* Timing Grid: Start & End Time */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">
                    Start Time <span className="text-rose-500">*</span>
                  </label>
                  <input
                    type="time"
                    value={formData.start_time}
                    onChange={(e) => setFormData({ ...formData, start_time: e.target.value })}
                    className={`w-full text-xs font-mono bg-slate-50 border rounded-xl px-3.5 py-2.5 text-slate-900 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 ${
                      formErrors.start_time ? 'border-rose-400 bg-rose-50/20' : 'border-slate-200 focus:border-emerald-500'
                    }`}
                  />
                  {formErrors.start_time && (
                    <p className="text-[11px] text-rose-500 font-semibold mt-1">{formErrors.start_time}</p>
                  )}
                </div>

                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">
                    End Time <span className="text-rose-500">*</span>
                  </label>
                  <input
                    type="time"
                    value={formData.end_time}
                    onChange={(e) => setFormData({ ...formData, end_time: e.target.value })}
                    className={`w-full text-xs font-mono bg-slate-50 border rounded-xl px-3.5 py-2.5 text-slate-900 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 ${
                      formErrors.end_time ? 'border-rose-400 bg-rose-50/20' : 'border-slate-200 focus:border-emerald-500'
                    }`}
                  />
                  {formErrors.end_time && (
                    <p className="text-[11px] text-rose-500 font-semibold mt-1">{formErrors.end_time}</p>
                  )}
                </div>
              </div>

              {/* Slot Type & Capacity Grid */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">Delivery Slot Type</label>
                  <select
                    value={formData.slot_type}
                    onChange={(e) => setFormData({ ...formData, slot_type: e.target.value })}
                    className="w-full text-xs font-semibold bg-slate-50 border border-slate-200 rounded-xl px-3.5 py-2.5 text-slate-900 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500"
                  >
                    <option value="STANDARD">Standard Delivery</option>
                    <option value="EXPRESS">Fast / Express Delivery</option>
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">
                    Max Capacity <span className="text-slate-400 font-normal">(Optional)</span>
                  </label>
                  <input
                    type="number"
                    min="1"
                    value={formData.max_orders_per_slot}
                    onChange={(e) => setFormData({ ...formData, max_orders_per_slot: e.target.value })}
                    placeholder="Leave empty for unlimited"
                    className={`w-full text-xs bg-slate-50 border rounded-xl px-3.5 py-2.5 text-slate-900 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 ${
                      formErrors.max_orders_per_slot ? 'border-rose-400 bg-rose-50/20' : 'border-slate-200 focus:border-emerald-500'
                    }`}
                  />
                  {formErrors.max_orders_per_slot && (
                    <p className="text-[11px] text-rose-500 font-semibold mt-1">{formErrors.max_orders_per_slot}</p>
                  )}
                </div>
              </div>

              {/* Applicable Days Selector */}
              <div>
                <div className="flex items-center justify-between mb-2">
                  <label className="text-xs font-bold text-slate-700">Applicable Days</label>
                  <button
                    type="button"
                    onClick={toggleAllDays}
                    className="text-[11px] font-bold text-emerald-600 hover:text-emerald-700 transition-colors"
                  >
                    {formData.applicable_days.length === 7 ? 'Deselect All' : 'Select All (Every Day)'}
                  </button>
                </div>

                <div className="grid grid-cols-7 gap-1.5">
                  {DAYS_OF_WEEK.map((day) => {
                    const isSelected = formData.applicable_days.includes(day.id);
                    return (
                      <button
                        key={day.id}
                        type="button"
                        onClick={() => toggleDaySelection(day.id)}
                        className={`py-2 px-1 text-center rounded-xl text-xs font-bold transition-all border ${
                          isSelected
                            ? 'bg-emerald-600 text-white border-emerald-600 shadow-sm'
                            : 'bg-slate-50 text-slate-600 border-slate-200 hover:bg-slate-100'
                        }`}
                      >
                        {day.label}
                      </button>
                    );
                  })}
                </div>
                <p className="text-[11px] text-slate-400 mt-1.5">
                  {formData.applicable_days.length === 7
                    ? 'Slot applies to all 7 days of the week.'
                    : formData.applicable_days.length === 0
                    ? 'Warning: No days selected. Slot will not appear on checkout.'
                    : `Active on ${formData.applicable_days.length} selected day(s).`}
                </p>
              </div>

              {/* Active Toggle */}
              <div className="pt-2">
                <label className="flex items-center gap-2.5 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={formData.is_active}
                    onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                    className="w-4 h-4 rounded text-emerald-600 focus:ring-emerald-500 border-slate-300"
                  />
                  <span className="text-xs font-bold text-slate-800">Active (Visible for Customer Checkout)</span>
                </label>
              </div>

              {/* Modal Footer */}
              <div className="pt-4 border-t border-slate-100 flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setModalOpen(false)}
                  className="px-4 py-2 text-xs font-semibold text-slate-600 hover:text-slate-800 hover:bg-slate-100 rounded-xl transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={saving}
                  className="flex items-center gap-2 px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold rounded-xl shadow-sm shadow-emerald-600/20 disabled:opacity-50 transition-all"
                >
                  {saving && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                  <span>{editingSlot ? 'Save Changes' : 'Create Slot'}</span>
                </button>
              </div>

            </form>
          </div>
        </div>
      )}

      {/* ── Delete Confirmation Modal ───────────────────────────────────────── */}
      {deleteModalSlot && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-in fade-in duration-150">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 border border-slate-200 shadow-2xl space-y-4">
            <div className="flex items-center gap-3 text-rose-600">
              <div className="w-10 h-10 rounded-xl bg-rose-50 border border-rose-200 flex items-center justify-center">
                <Trash2 className="w-5 h-5" />
              </div>
              <div>
                <h3 className="font-bold text-slate-900 text-sm">Delete Delivery Slot</h3>
                <p className="text-xs text-slate-500 font-medium">Permanently remove slot window</p>
              </div>
            </div>

            <p className="text-xs text-slate-600">
              Are you sure you want to delete delivery slot <strong className="text-slate-900">{deleteModalSlot.label}</strong> for warehouse <strong className="text-slate-900">{deleteModalSlot.warehouse_name}</strong>?
            </p>

            {deleteError && (
              <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-700 text-xs font-semibold flex items-center gap-2">
                <AlertCircle className="w-4 h-4 flex-shrink-0" />
                <span>{deleteError}</span>
              </div>
            )}

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                onClick={() => setDeleteModalSlot(null)}
                className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleDeleteSlot}
                disabled={deleting}
                className="flex items-center gap-1.5 px-4 py-2 bg-rose-600 hover:bg-rose-700 text-white text-xs font-bold rounded-xl shadow-sm disabled:opacity-50 transition-all"
              >
                {deleting && <RefreshCw className="w-3.5 h-3.5 animate-spin" />}
                <span>Delete Slot</span>
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );
}

export default AdminDeliverySlotsPage;
