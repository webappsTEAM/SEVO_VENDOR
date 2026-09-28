import React, { useState, useEffect, useMemo, useCallback } from 'react';
import { Sidebar } from '../../components/common/Sidebar.jsx';
import { useAuth } from '../../context/AuthProvider.jsx';
import { LocationPickerMap } from '../../components/common/LocationPickerMap.jsx';
import {
  apiAdminGetWarehouses,
  apiAdminGetWarehouseDetail,
  apiAdminCreateWarehouse,
  apiAdminUpdateWarehouse,
  apiAdminDeleteWarehouse,
  apiAdminAssignMerchantToWarehouse,
  apiAdminUnassignMerchantFromWarehouse,
  apiAdminGetCompanies,
} from '../../api/workforceService.js';
import {
  Building2,
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
  MapPin,
  Phone,
  Store,
  Layers,
  Globe,
  Navigation,
  Check,
  ChevronRight,
  ShieldCheck,
  Users,
  Key,
} from 'lucide-react';

export function AdminWarehousesPage() {
  const { user, isPlatformAdmin } = useAuth();
  const isSuperAdmin = isPlatformAdmin || user?.is_superuser;

  const [warehouses, setWarehouses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('all'); // 'all', 'active', 'inactive'
  const [cityFilter, setCityFilter] = useState('all');

  // Create / Edit Modal State
  const [modalOpen, setModalOpen] = useState(false);
  const [editingWarehouse, setEditingWarehouse] = useState(null);
  const [formData, setFormData] = useState({
    name: '',
    code: '',
    address: '',
    city: '',
    region: '',
    contact_phone: '',
    latitude: 12.9716,
    longitude: 77.5946,
    is_active: true,
  });
  const [formErrors, setFormErrors] = useState({});
  const [saving, setSaving] = useState(false);

  // Detail / Assigned Sellers Drawer State
  const [selectedWarehouseId, setSelectedWarehouseId] = useState(null);
  const [warehouseDetail, setWarehouseDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);

  // Assign Merchant to Warehouse State
  const [isAssigningMerchant, setIsAssigningMerchant] = useState(false);
  const [companySearch, setCompanySearch] = useState('');
  const [companyResults, setCompanyResults] = useState([]);
  const [companiesLoading, setCompaniesLoading] = useState(false);
  const [selectedCompany, setSelectedCompany] = useState(null);
  const [assignmentNotes, setAssignmentNotes] = useState('');
  const [assigningLoading, setAssigningLoading] = useState(false);
  const [assignError, setAssignError] = useState(null);
  const [unassigningId, setUnassigningId] = useState(null);

  // ── Fetch Warehouses ────────────────────────────────────────────────────────
  const fetchWarehouses = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const params = {};
      if (search.trim()) params.search = search.trim();
      if (cityFilter !== 'all') params.city = cityFilter;
      if (statusFilter === 'active') params.is_active = true;
      if (statusFilter === 'inactive') params.is_active = false;

      const data = await apiAdminGetWarehouses(params);
      setWarehouses(data || []);
    } catch (err) {
      console.error('Error loading warehouses:', err);
      setError(err.message || 'Failed to fetch warehouse facilities.');
    } finally {
      setLoading(false);
    }
  }, [search, cityFilter, statusFilter]);

  useEffect(() => {
    fetchWarehouses();
  }, [fetchWarehouses]);

  // Distinct cities for filter dropdown
  const cities = useMemo(() => {
    const set = new Set();
    warehouses.forEach((w) => {
      if (w.city) set.add(w.city);
    });
    return Array.from(set).sort();
  }, [warehouses]);

  // Aggregate Metrics
  const metrics = useMemo(() => {
    const total = warehouses.length;
    const active = warehouses.filter((w) => w.is_active).length;
    const assignedSellers = warehouses.reduce(
      (acc, w) => acc + (w.assigned_sellers_count || 0),
      0
    );
    return { total, active, assignedSellers };
  }, [warehouses]);

  // ── Open Create Modal ───────────────────────────────────────────────────────
  const handleOpenCreate = () => {
    setEditingWarehouse(null);
    setFormData({
      name: '',
      code: '',
      address: '',
      city: 'Bangalore',
      region: 'Karnataka',
      contact_phone: '',
      latitude: 12.9716,
      longitude: 77.5946,
      is_active: true,
      username: '',
      password: '',
      email: '',
    });
    setFormErrors({});
    setModalOpen(true);
  };

  // ── Open Edit Modal ─────────────────────────────────────────────────────────
  const handleOpenEdit = (wh) => {
    setEditingWarehouse(wh);
    setFormData({
      name: wh.name || '',
      code: wh.code || '',
      address: wh.address || '',
      city: wh.city || '',
      region: wh.region || '',
      contact_phone: wh.contact_phone || '',
      latitude: wh.latitude != null ? parseFloat(wh.latitude) : 12.9716,
      longitude: wh.longitude != null ? parseFloat(wh.longitude) : 77.5946,
      is_active: wh.is_active ?? true,
      username: wh.staff_login?.username || '',
      password: '',
      email: wh.staff_login?.email || '',
    });
    setFormErrors({});
    setModalOpen(true);
  };

  // ── Open Warehouse Detail ───────────────────────────────────────────────────
  const handleOpenDetail = async (id) => {
    setSelectedWarehouseId(id);
    setIsAssigningMerchant(false);
    setSelectedCompany(null);
    setAssignError(null);
    setDetailLoading(true);
    try {
      const data = await apiAdminGetWarehouseDetail(id);
      setWarehouseDetail(data);
    } catch (err) {
      console.error('Failed to load warehouse detail:', err);
    } finally {
      setDetailLoading(false);
    }
  };

  // ── Assign Merchant Handlers ────────────────────────────────────────────────
  const handleOpenAssignMerchant = async () => {
    setIsAssigningMerchant(true);
    setCompanySearch('');
    setSelectedCompany(null);
    setAssignmentNotes('');
    setAssignError(null);
    setCompaniesLoading(true);
    try {
      const data = await apiAdminGetCompanies();
      setCompanyResults(data || []);
    } catch (err) {
      console.error('Failed to load companies:', err);
      setAssignError('Failed to load merchant companies.');
    } finally {
      setCompaniesLoading(false);
    }
  };

  const handleSearchCompanies = async (query) => {
    setCompanySearch(query);
    setCompaniesLoading(true);
    setAssignError(null);
    try {
      const data = await apiAdminGetCompanies({ search: query });
      setCompanyResults(data || []);
    } catch (err) {
      console.error('Failed to search companies:', err);
    } finally {
      setCompaniesLoading(false);
    }
  };

  const handleConfirmAssignMerchant = async (e) => {
    if (e && e.preventDefault) e.preventDefault();
    if (!selectedCompany || !warehouseDetail) return;
    setAssigningLoading(true);
    setAssignError(null);
    try {
      await apiAdminAssignMerchantToWarehouse(warehouseDetail.id, selectedCompany.id, assignmentNotes);
      setIsAssigningMerchant(false);
      setSelectedCompany(null);
      setAssignmentNotes('');
      // Refresh detail and warehouse list
      const updated = await apiAdminGetWarehouseDetail(warehouseDetail.id);
      setWarehouseDetail(updated);
      fetchWarehouses();
    } catch (err) {
      console.error('Failed to assign merchant:', err);
      let errorMsg = err.message || 'Failed to assign merchant to warehouse.';
      try {
        const parsed = JSON.parse(err.message);
        if (typeof parsed === 'object') {
          errorMsg = parsed.error || parsed.detail || JSON.stringify(parsed);
        }
      } catch {
        // Keep string
      }
      setAssignError(errorMsg);
    } finally {
      setAssigningLoading(false);
    }
  };

  const handleUnassignMerchant = async (companyId, companyName) => {
    if (!warehouseDetail) return;
    const confirmed = window.confirm(`Are you sure you want to remove merchant "${companyName}" from this warehouse?`);
    if (!confirmed) return;
    setUnassigningId(companyId);
    try {
      await apiAdminUnassignMerchantFromWarehouse(warehouseDetail.id, companyId);
      const updated = await apiAdminGetWarehouseDetail(warehouseDetail.id);
      setWarehouseDetail(updated);
      fetchWarehouses();
    } catch (err) {
      console.error('Failed to unassign merchant:', err);
      alert(err.message || 'Failed to unassign merchant.');
    } finally {
      setUnassigningId(null);
    }
  };

  // ── Save Warehouse (Create / Edit) ──────────────────────────────────────────
  const handleSaveWarehouse = async (e) => {
    e.preventDefault();
    const errors = {};
    if (!formData.name.trim()) errors.name = 'Warehouse facility name is required.';
    if (!formData.address.trim()) errors.address = 'Street address is required.';
    if (formData.latitude == null || formData.longitude == null) {
      errors.coordinates = 'GPS coordinates are required. Pin your warehouse location on the map.';
    }

    if (!editingWarehouse) {
      if (!formData.username.trim()) {
        errors.username = 'Warehouse operator login username is required.';
      }
      if (!formData.password) {
        errors.password = 'Initial password is required for warehouse portal login.';
      } else if (formData.password.length < 6) {
        errors.password = 'Password must be at least 6 characters.';
      }
    } else {
      if (formData.password && formData.password.length < 6) {
        errors.password = 'Password must be at least 6 characters.';
      }
    }

    if (Object.keys(errors).length > 0) {
      setFormErrors(errors);
      return;
    }

    setSaving(true);
    setFormErrors({});
    try {
      const payload = {
        name: formData.name.trim(),
        code: formData.code.trim() || null,
        address: formData.address.trim(),
        city: formData.city.trim(),
        region: formData.region.trim(),
        contact_phone: formData.contact_phone.trim(),
        latitude: parseFloat(Number(formData.latitude).toFixed(7)),
        longitude: parseFloat(Number(formData.longitude).toFixed(7)),
        is_active: formData.is_active,
        username: formData.username.trim() || undefined,
        password: formData.password || undefined,
        email: formData.email.trim() || undefined,
      };

      if (editingWarehouse) {
        await apiAdminUpdateWarehouse(editingWarehouse.id, payload);
      } else {
        await apiAdminCreateWarehouse(payload);
      }

      setModalOpen(false);
      fetchWarehouses();
      if (selectedWarehouseId && editingWarehouse?.id === selectedWarehouseId) {
        handleOpenDetail(selectedWarehouseId);
      }
    } catch (err) {
      console.error('Failed to save warehouse:', err);
      let errorMsg = err.message || 'Failed to save warehouse facility.';
      try {
        const parsed = JSON.parse(err.message);
        if (typeof parsed === 'object') {
          const firstKey = Object.keys(parsed)[0];
          const val = parsed[firstKey];
          errorMsg = Array.isArray(val) ? `${firstKey}: ${val.join(', ')}` : String(val);
        }
      } catch {
        // Keep standard message
      }
      setFormErrors({ general: errorMsg });
    } finally {
      setSaving(false);
    }
  };

  // ── Toggle Active State ─────────────────────────────────────────────────────
  const handleToggleActive = async (wh) => {
    try {
      if (wh.is_active) {
        if (
          !window.confirm(
            `Are you sure you want to deactivate "${wh.name}"? Merchants assigned to this facility won't be able to dispatch orders until reassigned.`
          )
        ) {
          return;
        }
        await apiAdminDeleteWarehouse(wh.id);
      } else {
        await apiAdminUpdateWarehouse(wh.id, { is_active: true });
      }
      fetchWarehouses();
      if (selectedWarehouseId === wh.id) {
        handleOpenDetail(wh.id);
      }
    } catch (err) {
      alert(err.message || 'Failed to toggle warehouse active state.');
    }
  };

  return (
    <div className="flex h-screen bg-slate-50 font-sans antialiased text-slate-800">
      <Sidebar />

      <main className="flex-1 flex flex-col min-w-0 overflow-y-auto">
        {/* Header Bar */}
        <header className="bg-white border-b border-slate-200 px-6 py-4 sticky top-0 z-20 shadow-xs">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div>
              <div className="flex items-center gap-2">
                <span className="p-2 bg-indigo-50 text-indigo-600 rounded-xl border border-indigo-100">
                  <WarehouseIcon className="w-5 h-5" />
                </span>
                <div>
                  <h1 className="text-lg font-bold text-slate-900 tracking-tight">
                    Fulfillment Warehouses
                  </h1>
                  <p className="text-xs text-slate-500">
                    Platform Regional Hubs & Dispatch Pickup Coordinates Master
                  </p>
                </div>
              </div>
            </div>

            <div className="flex items-center gap-3">
              <button
                type="button"
                onClick={fetchWarehouses}
                className="p-2 text-slate-600 hover:text-slate-900 bg-white hover:bg-slate-100 border border-slate-200 rounded-xl transition-colors shadow-xs"
                title="Refresh Warehouses"
              >
                <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-indigo-600' : ''}`} />
              </button>

              <button
                type="button"
                onClick={handleOpenCreate}
                className="inline-flex items-center gap-2 px-4 py-2 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl shadow-xs transition-colors"
              >
                <Plus className="w-4 h-4" />
                <span>Add Warehouse</span>
              </button>
            </div>
          </div>
        </header>

        {/* Content Body */}
        <div className="p-6 space-y-6 max-w-7xl w-full mx-auto">
          {/* Metrics Header */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-xs flex items-center gap-4">
              <div className="p-3 bg-indigo-50 text-indigo-600 rounded-xl">
                <Building2 className="w-6 h-6" />
              </div>
              <div>
                <p className="text-xs font-medium text-slate-500">Total Facilities</p>
                <p className="text-xl font-bold text-slate-900">{metrics.total}</p>
              </div>
            </div>

            <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-xs flex items-center gap-4">
              <div className="p-3 bg-emerald-50 text-emerald-600 rounded-xl">
                <CheckCircle2 className="w-6 h-6" />
              </div>
              <div>
                <p className="text-xs font-medium text-slate-500">Active Facilities</p>
                <p className="text-xl font-bold text-emerald-700">{metrics.active}</p>
              </div>
            </div>

            <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-xs flex items-center gap-4">
              <div className="p-3 bg-amber-50 text-amber-700 rounded-xl">
                <Store className="w-6 h-6" />
              </div>
              <div>
                <p className="text-xs font-medium text-slate-500">Assigned Merchants</p>
                <p className="text-xl font-bold text-amber-900">{metrics.assignedSellers}</p>
              </div>
            </div>
          </div>

          {/* Search & Filters */}
          <div className="bg-white p-4 rounded-2xl border border-slate-200 shadow-xs flex items-center justify-between gap-4 flex-wrap">
            <div className="flex items-center gap-3 flex-1 min-w-[240px]">
              <div className="relative flex-1 max-w-md">
                <Search className="w-4 h-4 text-slate-400 absolute left-3 top-2.5" />
                <input
                  type="text"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  placeholder="Search warehouse by name, code, address, city..."
                  className="w-full pl-9 pr-3 py-2 text-xs rounded-xl border border-slate-300 bg-white placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                />
              </div>

              {cities.length > 0 && (
                <select
                  value={cityFilter}
                  onChange={(e) => setCityFilter(e.target.value)}
                  className="px-3 py-2 text-xs rounded-xl border border-slate-300 bg-white font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                >
                  <option value="all">All Cities</option>
                  {cities.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </select>
              )}

              <select
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
                className="px-3 py-2 text-xs rounded-xl border border-slate-300 bg-white font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500"
              >
                <option value="all">All Statuses</option>
                <option value="active">Active Only</option>
                <option value="inactive">Inactive Only</option>
              </select>
            </div>
          </div>

          {/* Warehouses Table / List */}
          <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse text-xs">
                <thead>
                  <tr className="bg-slate-50/80 border-b border-slate-200 text-[11px] font-bold text-slate-600 uppercase tracking-wider">
                    <th className="p-3.5 min-w-[220px]">Warehouse Facility</th>
                    <th className="p-3.5 min-w-[140px]">City / Region</th>
                    <th className="p-3.5 min-w-[220px]">Physical Street Address</th>
                    <th className="p-3.5 min-w-[160px]">GPS Coordinates</th>
                    <th className="p-3.5 text-center min-w-[110px]">Merchants</th>
                    <th className="p-3.5 text-center min-w-[100px]">Status</th>
                    <th className="p-3.5 text-right min-w-[140px]">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {loading ? (
                    <tr>
                      <td colSpan={7} className="p-12 text-center text-slate-500">
                        <RefreshCw className="w-6 h-6 animate-spin mx-auto mb-2 text-indigo-600" />
                        <span>Loading warehouse facilities...</span>
                      </td>
                    </tr>
                  ) : error ? (
                    <tr>
                      <td colSpan={7} className="p-8 text-center text-rose-600">
                        <AlertCircle className="w-6 h-6 mx-auto mb-2" />
                        <span>{error}</span>
                      </td>
                    </tr>
                  ) : warehouses.length === 0 ? (
                    <tr>
                      <td colSpan={7} className="p-12 text-center text-slate-500">
                        <WarehouseIcon className="w-10 h-10 mx-auto mb-2 text-slate-300" />
                        <p className="font-semibold text-slate-700">No Warehouses Found</p>
                        <p className="text-xs text-slate-400 mt-1">
                          No fulfillment facilities match the current filters. Click "Add Warehouse" to create one.
                        </p>
                      </td>
                    </tr>
                  ) : (
                    warehouses.map((wh) => (
                      <tr
                        key={wh.id}
                        className="hover:bg-slate-50/80 transition-colors cursor-pointer"
                        onClick={() => handleOpenDetail(wh.id)}
                      >
                        <td className="p-3.5">
                          <div className="flex items-center gap-3">
                            <div
                              className={`w-9 h-9 rounded-xl flex items-center justify-center font-bold text-sm shrink-0 border ${
                                wh.is_active
                                  ? 'bg-indigo-50 text-indigo-700 border-indigo-200'
                                  : 'bg-slate-100 text-slate-400 border-slate-200'
                              }`}
                            >
                              <WarehouseIcon className="w-4 h-4" />
                            </div>
                            <div className="min-w-0">
                              <div className="flex items-center gap-1.5 flex-wrap">
                                <span className="font-bold text-slate-900 truncate hover:text-indigo-600">
                                  {wh.name}
                                </span>
                                {wh.staff_login?.has_login && (
                                  <span className="inline-flex items-center gap-1 px-1.5 py-0.2 rounded text-[10px] font-mono font-bold bg-indigo-50 text-indigo-700 border border-indigo-100" title={`Operator Login: ${wh.staff_login.username}`}>
                                    <Key className="w-2.5 h-2.5 text-indigo-500" />
                                    {wh.staff_login.username}
                                  </span>
                                )}
                              </div>
                              <div className="flex items-center gap-2 text-[11px] text-slate-400 mt-0.5">
                                {wh.code && (
                                  <span className="font-mono bg-slate-100 text-slate-600 px-1.5 py-0.5 rounded text-[10px]">
                                    {wh.code}
                                  </span>
                                )}
                                {wh.contact_phone && (
                                  <span className="flex items-center gap-1">
                                    <Phone className="w-3 h-3" />
                                    {wh.contact_phone}
                                  </span>
                                )}
                              </div>
                            </div>
                          </div>
                        </td>

                        <td className="p-3.5">
                          <div className="font-semibold text-slate-700">{wh.city || '—'}</div>
                          <div className="text-[11px] text-slate-400">{wh.region || '—'}</div>
                        </td>

                        <td className="p-3.5">
                          <div className="text-slate-600 text-xs max-w-xs line-clamp-2" title={wh.address}>
                            {wh.address || '—'}
                          </div>
                        </td>

                        <td className="p-3.5">
                          {wh.latitude != null && wh.longitude != null ? (
                            <div className="flex items-center gap-1.5 font-mono text-[11px] text-slate-700 bg-slate-50 px-2 py-1 rounded-lg border border-slate-200 w-fit">
                              <MapPin className="w-3 h-3 text-indigo-600 shrink-0" />
                              <span>
                                {Number(wh.latitude).toFixed(4)}, {Number(wh.longitude).toFixed(4)}
                              </span>
                            </div>
                          ) : (
                            <span className="text-rose-500 font-semibold text-[11px]">Missing GPS Pin</span>
                          )}
                        </td>

                        <td className="p-3.5 text-center">
                          <span
                            className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-bold border ${
                              (wh.assigned_sellers_count || 0) > 0
                                ? 'bg-amber-50 text-amber-800 border-amber-200'
                                : 'bg-slate-50 text-slate-500 border-slate-200'
                            }`}
                          >
                            <Store className="w-3 h-3" />
                            <span>{wh.assigned_sellers_count || 0}</span>
                          </span>
                        </td>

                        <td className="p-3.5 text-center">
                          {wh.is_active ? (
                            <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                              <Check className="w-3 h-3" /> Active
                            </span>
                          ) : (
                            <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold bg-slate-100 text-slate-500 border border-slate-200">
                              <X className="w-3 h-3" /> Inactive
                            </span>
                          )}
                        </td>

                        <td className="p-3.5 text-right" onClick={(e) => e.stopPropagation()}>
                          <div className="flex items-center justify-end gap-1">
                            <button
                              type="button"
                              onClick={() => handleOpenEdit(wh)}
                              className="p-1.5 text-slate-500 hover:text-indigo-600 hover:bg-indigo-50 rounded-lg transition-colors"
                              title="Edit Warehouse"
                            >
                              <Edit2 className="w-3.5 h-3.5" />
                            </button>
                            <button
                              type="button"
                              onClick={() => handleToggleActive(wh)}
                              className={`p-1.5 rounded-lg transition-colors ${
                                wh.is_active
                                  ? 'text-slate-500 hover:text-rose-600 hover:bg-rose-50'
                                  : 'text-slate-500 hover:text-emerald-600 hover:bg-emerald-50'
                              }`}
                              title={wh.is_active ? 'Deactivate Warehouse' : 'Activate Warehouse'}
                            >
                              {wh.is_active ? (
                                <Trash2 className="w-3.5 h-3.5" />
                              ) : (
                                <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
                              )}
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {/* ── MODAL: CREATE / EDIT WAREHOUSE ── */}
        {modalOpen && (
          <div className="fixed inset-0 z-50 overflow-y-auto bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
            <div className="bg-white rounded-2xl max-w-2xl w-full p-6 shadow-2xl space-y-5 animate-in fade-in zoom-in duration-150 border border-slate-200">
              <div className="flex items-center justify-between border-b border-slate-100 pb-3">
                <div className="flex items-center gap-2.5">
                  <div className="p-2 bg-indigo-50 text-indigo-600 rounded-xl">
                    <WarehouseIcon className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm font-bold text-slate-900">
                      {editingWarehouse ? 'Edit Warehouse Facility' : 'Create New Warehouse'}
                    </h3>
                    <p className="text-xs text-slate-500">
                      Set facility information and precise GPS coordinates for rider pickup routing
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setModalOpen(false)}
                  className="p-1.5 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded-lg transition-colors"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              {formErrors.general && (
                <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700 flex items-center gap-2">
                  <AlertCircle className="w-4 h-4 shrink-0" />
                  <span>{formErrors.general}</span>
                </div>
              )}

              <form onSubmit={handleSaveWarehouse} className="space-y-4">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">
                      Facility Name <span className="text-rose-500">*</span>
                    </label>
                    <input
                      type="text"
                      value={formData.name}
                      onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                      placeholder="e.g. Central Bangalore Hub"
                      className="w-full px-3 py-2 text-xs rounded-xl border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                    {formErrors.name && (
                      <p className="text-[11px] text-rose-600 mt-1">{formErrors.name}</p>
                    )}
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">
                      Facility Code (Optional)
                    </label>
                    <input
                      type="text"
                      value={formData.code}
                      onChange={(e) => setFormData({ ...formData, code: e.target.value.toUpperCase() })}
                      placeholder="e.g. WH-BLR-01"
                      className="w-full px-3 py-2 text-xs font-mono rounded-xl border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500 uppercase"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">City</label>
                    <input
                      type="text"
                      value={formData.city}
                      onChange={(e) => setFormData({ ...formData, city: e.target.value })}
                      placeholder="e.g. Bangalore"
                      className="w-full px-3 py-2 text-xs rounded-xl border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">Region / State</label>
                    <input
                      type="text"
                      value={formData.region}
                      onChange={(e) => setFormData({ ...formData, region: e.target.value })}
                      placeholder="e.g. Karnataka"
                      className="w-full px-3 py-2 text-xs rounded-xl border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">Contact Phone</label>
                    <input
                      type="text"
                      value={formData.contact_phone}
                      onChange={(e) => setFormData({ ...formData, contact_phone: e.target.value })}
                      placeholder="e.g. +91 98765 43210"
                      className="w-full px-3 py-2 text-xs rounded-xl border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-slate-700 mb-1">
                    Street Address <span className="text-rose-500">*</span>
                  </label>
                  <textarea
                    rows={2}
                    value={formData.address}
                    onChange={(e) => setFormData({ ...formData, address: e.target.value })}
                    placeholder="Full street address and landmark for rider navigation"
                    className="w-full px-3 py-2 text-xs rounded-xl border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                  />
                  {formErrors.address && (
                    <p className="text-[11px] text-rose-600 mt-1">{formErrors.address}</p>
                  )}
                </div>

                {/* Map Pin-Drop Picker */}
                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <label className="block text-xs font-bold text-slate-700">
                      Pin Warehouse Location on Map <span className="text-rose-500">*</span>
                    </label>
                    <span className="text-[11px] font-mono text-slate-500">
                      Lat: {Number(formData.latitude).toFixed(6)}, Lng: {Number(formData.longitude).toFixed(6)}
                    </span>
                  </div>

                  <div className="rounded-xl overflow-hidden border border-slate-200 shadow-inner">
                    <LocationPickerMap
                      latitude={formData.latitude}
                      longitude={formData.longitude}
                      height="220px"
                      onPositionChange={(lat, lng) => {
                        setFormData((prev) => ({
                          ...prev,
                          latitude: lat,
                          longitude: lng,
                        }));
                      }}
                    />
                  </div>
                  {formErrors.coordinates && (
                    <p className="text-[11px] text-rose-600 mt-1">{formErrors.coordinates}</p>
                  )}
                </div>

                {/* ── WAREHOUSE PORTAL CREDENTIALS ── */}
                <div className="bg-indigo-50/50 border border-indigo-100 rounded-2xl p-4 space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <div className="p-1.5 bg-indigo-600 text-white rounded-lg">
                        <Key className="w-3.5 h-3.5" />
                      </div>
                      <div>
                        <h4 className="text-xs font-bold text-slate-900">
                          {editingWarehouse ? 'Warehouse Portal Login' : 'Set Up Warehouse Staff Login'}
                        </h4>
                        <p className="text-[11px] text-slate-500">
                          Credentials used by warehouse staff to access their dedicated operations portal
                        </p>
                      </div>
                    </div>
                    {editingWarehouse && formData.username && (
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200">
                        Login Configured
                      </span>
                    )}
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">
                    <div>
                      <label className="block text-xs font-bold text-slate-700 mb-1">
                        Operator Username <span className="text-rose-500">{editingWarehouse ? '' : '*'}</span>
                      </label>
                      <input
                        type="text"
                        value={formData.username}
                        onChange={(e) => setFormData({ ...formData, username: e.target.value })}
                        placeholder="e.g. wh_hosur_operator"
                        className="w-full px-3 py-2 text-xs rounded-xl border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                      />
                      {formErrors.username && (
                        <p className="text-[11px] text-rose-600 mt-1">{formErrors.username}</p>
                      )}
                    </div>

                    <div>
                      <label className="block text-xs font-bold text-slate-700 mb-1">
                        {editingWarehouse ? 'Update Password (leave blank to keep)' : 'Initial Password *'}
                      </label>
                      <input
                        type="password"
                        value={formData.password}
                        onChange={(e) => setFormData({ ...formData, password: e.target.value })}
                        placeholder={editingWarehouse ? '••••••••' : 'Minimum 6 characters'}
                        className="w-full px-3 py-2 text-xs rounded-xl border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-500 font-mono"
                      />
                      {formErrors.password && (
                        <p className="text-[11px] text-rose-600 mt-1">{formErrors.password}</p>
                      )}
                    </div>
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">
                      Notification / Contact Email (Optional)
                    </label>
                    <input
                      type="email"
                      value={formData.email}
                      onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                      placeholder="e.g. warehouse.hosur@sevo.com"
                      className="w-full px-3 py-2 text-xs rounded-xl border border-slate-300 bg-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                    {formErrors.email && (
                      <p className="text-[11px] text-rose-600 mt-1">{formErrors.email}</p>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-2 pt-1">
                  <label className="flex items-center gap-2 text-xs font-semibold text-slate-700 cursor-pointer select-none">
                    <input
                      type="checkbox"
                      checked={formData.is_active}
                      onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                      className="rounded border-slate-300 text-indigo-600 focus:ring-indigo-500"
                    />
                    <span>Active for rider dispatch and seller order pickups</span>
                  </label>
                </div>

                <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                  <button
                    type="button"
                    onClick={() => setModalOpen(false)}
                    className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-xl transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={saving}
                    className="inline-flex items-center gap-2 px-5 py-2 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 rounded-xl shadow-xs transition-colors"
                  >
                    {saving ? (
                      <>
                        <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                        <span>Saving...</span>
                      </>
                    ) : (
                      <>
                        <Check className="w-3.5 h-3.5" />
                        <span>{editingWarehouse ? 'Update Warehouse' : 'Create Warehouse'}</span>
                      </>
                    )}
                  </button>
                </div>
              </form>
            </div>
          </div>
        )}

        {/* ── DRAWER: WAREHOUSE DETAIL & ASSIGNED MERCHANTS ── */}
        {selectedWarehouseId && (
          <div className="fixed inset-0 z-40 overflow-hidden bg-slate-900/40 backdrop-blur-xs flex justify-end">
            <div className="bg-white w-full max-w-md h-full shadow-2xl flex flex-col animate-in slide-in-from-right duration-200">
              <div className="p-5 border-b border-slate-200 flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <div className="p-2 bg-indigo-50 text-indigo-600 rounded-xl">
                    <WarehouseIcon className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-sm font-bold text-slate-900">
                      {warehouseDetail?.name || 'Warehouse Details'}
                    </h3>
                    <p className="text-xs text-slate-400 font-mono">
                      {warehouseDetail?.code || `Warehouse #${selectedWarehouseId}`}
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => {
                    setSelectedWarehouseId(null);
                    setWarehouseDetail(null);
                  }}
                  className="p-1.5 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded-lg transition-colors"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              <div className="flex-1 overflow-y-auto p-5 space-y-6">
                {detailLoading ? (
                  <div className="p-12 text-center text-slate-400">
                    <RefreshCw className="w-6 h-6 animate-spin mx-auto mb-2 text-indigo-600" />
                    <span>Loading details...</span>
                  </div>
                ) : warehouseDetail ? (
                  <>
                    {/* Facility Info Card */}
                    <div className="bg-slate-50 p-4 rounded-xl border border-slate-200 space-y-3 text-xs">
                      <div>
                        <span className="text-[11px] font-bold text-slate-400 uppercase">Address</span>
                        <p className="font-medium text-slate-800 mt-0.5">{warehouseDetail.address}</p>
                      </div>

                      <div className="grid grid-cols-2 gap-2 pt-1 border-t border-slate-200">
                        <div>
                          <span className="text-[11px] font-bold text-slate-400 uppercase">City / Region</span>
                          <p className="font-semibold text-slate-700">
                            {warehouseDetail.city} {warehouseDetail.region ? `(${warehouseDetail.region})` : ''}
                          </p>
                        </div>
                        <div>
                          <span className="text-[11px] font-bold text-slate-400 uppercase">Status</span>
                          <p className="font-semibold text-emerald-700">
                            {warehouseDetail.is_active ? 'Active' : 'Inactive'}
                          </p>
                        </div>
                      </div>

                      <div className="pt-1 border-t border-slate-200">
                        <span className="text-[11px] font-bold text-slate-400 uppercase">GPS Pickup Coordinates</span>
                        <p className="font-mono text-slate-700 mt-0.5">
                          {Number(warehouseDetail.latitude).toFixed(6)}, {Number(warehouseDetail.longitude).toFixed(6)}
                        </p>
                      </div>
                    </div>

                    {/* Portal Login Credentials Card */}
                    <div className="bg-indigo-50/60 p-4 rounded-xl border border-indigo-100 space-y-2 text-xs">
                      <div className="flex items-center justify-between">
                        <span className="text-[11px] font-bold text-indigo-900 uppercase flex items-center gap-1.5">
                          <Key className="w-3.5 h-3.5 text-indigo-600" />
                          <span>Warehouse Portal Login</span>
                        </span>
                        {warehouseDetail.staff_login?.has_login ? (
                          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-100 text-emerald-800 border border-emerald-200">
                            Active
                          </span>
                        ) : (
                          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-100 text-amber-800 border border-amber-200">
                            No Login Configured
                          </span>
                        )}
                      </div>
                      {warehouseDetail.staff_login?.has_login ? (
                        <div className="grid grid-cols-2 gap-2 pt-1 font-mono text-[11px]">
                          <div>
                            <span className="text-[10px] text-slate-400 font-sans block">Username</span>
                            <span className="font-bold text-slate-800">{warehouseDetail.staff_login.username}</span>
                          </div>
                          <div>
                            <span className="text-[10px] text-slate-400 font-sans block">Email</span>
                            <span className="text-slate-600 truncate block">{warehouseDetail.staff_login.email || '—'}</span>
                          </div>
                        </div>
                      ) : (
                        <p className="text-[11px] text-slate-500">
                          Click "Edit Warehouse" to create login credentials for this facility's operations team.
                        </p>
                      )}
                    </div>

                    {/* Assigned Merchants List */}
                    <div className="space-y-3">
                      <div className="flex items-center justify-between">
                        <h4 className="text-xs font-bold text-slate-900 uppercase tracking-wider flex items-center gap-1.5">
                          <Store className="w-4 h-4 text-indigo-600" />
                          <span>Assigned Merchants ({warehouseDetail.sellers?.length || 0})</span>
                        </h4>
                        {!isAssigningMerchant && (
                          <button
                            type="button"
                            onClick={handleOpenAssignMerchant}
                            className="inline-flex items-center gap-1 px-2.5 py-1 text-xs font-bold text-indigo-600 hover:text-indigo-700 bg-indigo-50 hover:bg-indigo-100 rounded-lg transition-colors cursor-pointer"
                          >
                            <Plus className="w-3.5 h-3.5" />
                            <span>Add Merchant</span>
                          </button>
                        )}
                      </div>

                      {/* Assign Merchant Form / Typeahead Dropdown */}
                      {isAssigningMerchant && (
                        <div className="p-3.5 bg-slate-50 border border-indigo-200 rounded-xl space-y-3 animate-in fade-in duration-150">
                          <div className="flex items-center justify-between">
                            <span className="text-xs font-bold text-slate-800 flex items-center gap-1.5">
                              <Store className="w-3.5 h-3.5 text-indigo-600" />
                              <span>Assign Merchant Store</span>
                            </span>
                            <button
                              type="button"
                              onClick={() => {
                                setIsAssigningMerchant(false);
                                setSelectedCompany(null);
                                setAssignError(null);
                              }}
                              className="p-1 text-slate-400 hover:text-slate-600 rounded-md cursor-pointer"
                            >
                              <X className="w-4 h-4" />
                            </button>
                          </div>

                          {assignError && (
                            <div className="p-2 bg-rose-50 border border-rose-200 text-rose-700 rounded-lg text-[11px] flex items-center gap-1.5">
                              <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                              <span>{assignError}</span>
                            </div>
                          )}

                          {/* Merchant Search & Selection */}
                          <div className="space-y-1.5">
                            <label className="block text-[11px] font-bold text-slate-700">Select Merchant</label>
                            <div className="relative">
                              <Search className="w-3.5 h-3.5 absolute left-2.5 top-2.5 text-slate-400" />
                              <input
                                type="text"
                                value={companySearch}
                                onChange={(e) => handleSearchCompanies(e.target.value)}
                                placeholder="Search merchant by name or slug..."
                                className="w-full pl-8 pr-3 py-1.5 text-xs bg-white rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                              />
                            </div>

                            {/* Results List */}
                            <div className="max-h-40 overflow-y-auto border border-slate-200 rounded-lg bg-white divide-y divide-slate-100">
                              {companiesLoading ? (
                                <div className="p-3 text-center text-xs text-slate-400 flex items-center justify-center gap-1.5">
                                  <RefreshCw className="w-3.5 h-3.5 animate-spin text-indigo-600" />
                                  <span>Loading merchants...</span>
                                </div>
                              ) : companyResults.length === 0 ? (
                                <div className="p-3 text-center text-xs text-slate-400">
                                  No merchant companies found.
                                </div>
                              ) : (
                                companyResults.map((c) => {
                                  const isAlreadyThis = c.is_assigned && c.assigned_warehouse_id === warehouseDetail.id;
                                  const isSelected = selectedCompany?.id === c.id;

                                  return (
                                    <div
                                      key={c.id}
                                      onClick={() => {
                                        if (isAlreadyThis) return;
                                        setSelectedCompany(c);
                                      }}
                                      className={`p-2.5 text-xs flex items-center justify-between gap-2 transition-colors ${
                                        isAlreadyThis
                                          ? 'bg-slate-50 opacity-60 cursor-not-allowed'
                                          : isSelected
                                          ? 'bg-indigo-50 border-l-2 border-indigo-600 cursor-pointer'
                                          : 'hover:bg-slate-50 cursor-pointer'
                                      }`}
                                    >
                                      <div className="min-w-0">
                                        <p className="font-bold text-slate-900 truncate">{c.company_name}</p>
                                        <p className="text-[10px] text-slate-400 font-mono">{c.slug}</p>
                                      </div>
                                      <div className="text-right shrink-0">
                                        {isAlreadyThis ? (
                                          <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-slate-200 text-slate-600">
                                            Already Assigned
                                          </span>
                                        ) : c.is_assigned ? (
                                          <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-amber-100 text-amber-800">
                                            At: {c.assigned_warehouse_name}
                                          </span>
                                        ) : (
                                          <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-emerald-100 text-emerald-800">
                                            Unassigned
                                          </span>
                                        )}
                                      </div>
                                    </div>
                                  );
                                })
                              )}
                            </div>
                          </div>

                          {selectedCompany && (
                            <div className="p-2 bg-indigo-50/80 rounded-lg border border-indigo-100 text-[11px] text-indigo-900 flex items-center justify-between">
                              <div>
                                <span className="font-bold">Selected:</span> {selectedCompany.company_name}
                              </div>
                              {selectedCompany.is_assigned && selectedCompany.assigned_warehouse_id !== warehouseDetail.id && (
                                <span className="text-[10px] text-amber-700 font-semibold">
                                  Will reassign from {selectedCompany.assigned_warehouse_name}
                                </span>
                              )}
                            </div>
                          )}

                          {/* Notes Input */}
                          <div>
                            <label className="block text-[11px] font-bold text-slate-700 mb-1">Assignment Notes (Optional)</label>
                            <input
                              type="text"
                              value={assignmentNotes}
                              onChange={(e) => setAssignmentNotes(e.target.value)}
                              placeholder="e.g. Primary hub for Hosur produce..."
                              className="w-full px-2.5 py-1.5 text-xs bg-white rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                            />
                          </div>

                          <div className="flex items-center justify-end gap-2 pt-1 border-t border-slate-200">
                            <button
                              type="button"
                              onClick={() => {
                                setIsAssigningMerchant(false);
                                setSelectedCompany(null);
                              }}
                              className="px-3 py-1.5 text-xs font-semibold text-slate-600 hover:bg-slate-200 rounded-lg transition-colors cursor-pointer"
                            >
                              Cancel
                            </button>
                            <button
                              type="button"
                              disabled={!selectedCompany || assigningLoading}
                              onClick={handleConfirmAssignMerchant}
                              className="inline-flex items-center gap-1.5 px-4 py-1.5 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 rounded-lg transition-colors shadow-xs cursor-pointer"
                            >
                              {assigningLoading ? (
                                <>
                                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                                  <span>Assigning...</span>
                                </>
                              ) : (
                                <>
                                  <Check className="w-3.5 h-3.5" />
                                  <span>Confirm Assignment</span>
                                </>
                              )}
                            </button>
                          </div>
                        </div>
                      )}

                      {warehouseDetail.sellers?.length === 0 ? (
                        <div className="p-6 bg-slate-50 border border-slate-200 rounded-xl text-center text-slate-400 text-xs">
                          <Store className="w-6 h-6 mx-auto mb-1 text-slate-300" />
                          <span>No merchants are currently assigned to this warehouse.</span>
                        </div>
                      ) : (
                        <div className="space-y-2">
                          {warehouseDetail.sellers.map((s) => (
                            <div
                              key={s.id}
                              className="p-3 bg-white border border-slate-200 rounded-xl shadow-2xs flex items-center justify-between gap-3 text-xs group hover:border-slate-300 transition-colors"
                            >
                              <div className="min-w-0">
                                <p className="font-bold text-slate-900 truncate">{s.company_name}</p>
                                <p className="text-[11px] text-slate-400 font-mono">{s.slug}</p>
                                {s.notes && (
                                  <p className="text-[10px] text-slate-500 italic mt-0.5 truncate">"{s.notes}"</p>
                                )}
                              </div>
                              <div className="flex items-center gap-2 shrink-0">
                                <span className="text-[10px] text-slate-400">
                                  {s.assigned_at ? new Date(s.assigned_at).toLocaleDateString() : ''}
                                </span>
                                <button
                                  type="button"
                                  disabled={unassigningId === s.company_id}
                                  onClick={() => handleUnassignMerchant(s.company_id, s.company_name)}
                                  title="Unassign merchant from this warehouse"
                                  className="p-1.5 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition-colors cursor-pointer"
                                >
                                  {unassigningId === s.company_id ? (
                                    <RefreshCw className="w-3.5 h-3.5 animate-spin text-rose-600" />
                                  ) : (
                                    <Trash2 className="w-3.5 h-3.5" />
                                  )}
                                </button>
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </>
                ) : null}
              </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

export default AdminWarehousesPage;
