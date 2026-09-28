import React, { useState, useEffect, useCallback } from 'react';
import {
  Boxes,
  Clock,
  CheckCircle2,
  XCircle,
  Search,
  Filter,
  RefreshCw,
  Package,
  Building2,
  ArrowUpRight,
  AlertTriangle,
  Info,
  ChevronRight,
  Check,
  X,
  Store,
  Calendar,
  Layers,
  MessageSquare,
  ShieldAlert,
  Printer,
  QrCode,
  ScanLine,
  Tag,
  Camera,
  CheckCheck,
  FileSpreadsheet,
} from 'lucide-react';
import {
  apiWarehouseGetInboundRequests,
  apiWarehouseDecideInboundRequest,
  apiWarehouseScanInboundUnit,
  apiWarehouseGetInboundUnits,
  apiWarehouseReportShortfall,
  apiWarehouseGetInboundLabelsPdfUrl,
} from '../../api/workforceService.js';
import { BarcodeScannerModal } from '../../components/common/BarcodeScannerModal.jsx';

const STATUS_CONFIG = {
  ALL: { label: 'All Requests', bg: 'bg-slate-100', text: 'text-slate-700', border: 'border-slate-200' },
  PENDING: { label: 'Pending Review', bg: 'bg-amber-50', text: 'text-amber-700', border: 'border-amber-200', icon: Clock },
  ACCEPTED: { label: 'In Verification (Awaiting Scan)', bg: 'bg-indigo-50', text: 'text-indigo-700', border: 'border-indigo-200', icon: RefreshCw },
  SHORT_RECEIVED: { label: 'Shortfall Reported (Pending Seller)', bg: 'bg-amber-50', text: 'text-amber-700', border: 'border-amber-200', icon: AlertTriangle },
  COMPLETED: { label: 'Completed (Live in Stock)', bg: 'bg-emerald-50', text: 'text-emerald-700', border: 'border-emerald-200', icon: CheckCircle2 },
  REJECTED_RETURN: { label: 'Shortfall Rejected (Return Staged)', bg: 'bg-rose-50', text: 'text-rose-700', border: 'border-rose-200', icon: XCircle },
  REJECTED: { label: 'Rejected', bg: 'bg-rose-50', text: 'text-rose-700', border: 'border-rose-200', icon: XCircle },
};

export function WarehouseInventoryPage() {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [searchQuery, setSearchQuery] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  // Decision Modal State
  const [selectedRequest, setSelectedRequest] = useState(null);
  const [decisionAction, setDecisionAction] = useState('ACCEPT'); // 'ACCEPT' | 'REJECT'
  const [reviewerNote, setReviewerNote] = useState('');
  const [submittingDecision, setSubmittingDecision] = useState(false);
  const [decisionError, setDecisionError] = useState(null);
  const [successToast, setSuccessToast] = useState(null);

  // Phase Y: Physical Scan Modal & Barcode Scanner State
  const [scanModalOpen, setScanModalOpen] = useState(false);
  const [scanModalRequest, setScanModalRequest] = useState(null);
  const [scanUnitsList, setScanUnitsList] = useState([]);
  const [scanModalLoading, setScanModalLoading] = useState(false);
  const [manualBarcodeInput, setManualBarcodeInput] = useState('');
  const [scanError, setScanError] = useState(null);
  const [scanSuccess, setScanSuccess] = useState(null);
  const [scanningInProgress, setScanningInProgress] = useState(false);
  const [cameraModalOpen, setCameraModalOpen] = useState(false);

  // Phase Z: Shortfall Reporting Modal State
  const [shortfallModalOpen, setShortfallModalOpen] = useState(false);
  const [shortfallModalRequest, setShortfallModalRequest] = useState(null);
  const [shortfallNote, setShortfallNote] = useState('');
  const [reportingShortfall, setReportingShortfall] = useState(false);
  const [shortfallError, setShortfallError] = useState(null);

  // Phase (Labels): Print Inbound Unit Labels Modal States
  const [showLabelsModal, setShowLabelsModal] = useState(false);
  const [labelsModalRequest, setLabelsModalRequest] = useState(null);
  const [labelsPaperSize, setLabelsPaperSize] = useState('a4');

  // Fetch Requests
  const fetchRequests = useCallback(async () => {
    try {
      setError(null);
      const params = {};
      if (statusFilter !== 'ALL') {
        params.status = statusFilter;
      }
      if (searchQuery.trim()) {
        params.search = searchQuery.trim();
      }

      const res = await apiWarehouseGetInboundRequests(params);
      const data = res.results || res || [];
      setRequests(data);
    } catch (err) {
      console.error('Failed to load inbound requests:', err);
      setError(err.message || 'Failed to load inbound requests');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [statusFilter, searchQuery]);

  useEffect(() => {
    setLoading(true);
    fetchRequests();
  }, [fetchRequests]);

  const handleManualRefresh = () => {
    setRefreshing(true);
    fetchRequests();
  };

  const openDecisionModal = (req, action) => {
    setSelectedRequest(req);
    setDecisionAction(action);
    setReviewerNote(action === 'ACCEPT' ? 'Dock intake slot confirmed.' : '');
    setDecisionError(null);
  };

  const closeDecisionModal = () => {
    setSelectedRequest(null);
    setReviewerNote('');
    setDecisionError(null);
  };

  const handleConfirmDecision = async (e) => {
    e.preventDefault();
    if (!selectedRequest) return;

    setSubmittingDecision(true);
    setDecisionError(null);

    try {
      await apiWarehouseDecideInboundRequest(
        selectedRequest.id,
        decisionAction,
        reviewerNote.trim()
      );

      setSuccessToast(
        `Inbound Request #${selectedRequest.id} successfully ${
          decisionAction === 'ACCEPT' ? 'ACCEPTED' : 'REJECTED'
        }. ${decisionAction === 'ACCEPT' ? 'Unique unit barcodes have been generated for physical scan-in.' : ''}`
      );
      setTimeout(() => setSuccessToast(null), 5000);
      closeDecisionModal();
      fetchRequests();
    } catch (err) {
      console.error('Failed to submit decision:', err);
      setDecisionError(err.message || 'Failed to submit decision. Please try again.');
    } finally {
      setSubmittingDecision(false);
    }
  };

  // Phase Y: Open Physical Unit Scan Modal
  const handleOpenScanModal = async (req) => {
    setScanModalRequest(req);
    setScanModalOpen(true);
    setScanModalLoading(true);
    setScanError(null);
    setScanSuccess(null);
    setManualBarcodeInput('');

    try {
      const res = await apiWarehouseGetInboundUnits(req.id);
      setScanUnitsList(res.units || []);
    } catch (err) {
      console.error('Failed to load request units:', err);
      setScanError(err.message || 'Failed to load unit barcodes.');
    } finally {
      setScanModalLoading(false);
    }
  };

  const handleCloseScanModal = () => {
    setScanModalOpen(false);
    setScanModalRequest(null);
    setScanUnitsList([]);
    setScanError(null);
    setScanSuccess(null);
    setManualBarcodeInput('');
    fetchRequests();
  };

  // Phase Y: Process a Scanned Barcode (from Camera, File, or Manual Input)
  const handleProcessScan = async (scannedCode) => {
    if (!scanModalRequest || !scannedCode) return;
    const cleanCode = scannedCode.trim();
    if (!cleanCode) return;

    setScanningInProgress(true);
    setScanError(null);
    setScanSuccess(null);

    try {
      const res = await apiWarehouseScanInboundUnit(scanModalRequest.id, cleanCode);

      // Update unit status locally in list
      setScanUnitsList((prev) =>
        prev.map((u) => (u.id === res.scanned_unit.id ? res.scanned_unit : u))
      );

      // Update parent modal request object state
      setScanModalRequest((prev) => ({
        ...prev,
        status: res.request_status,
        received_units_count: res.received_units_count,
        total_units_count: res.total_units_count,
        pending_units_count: res.pending_units_count,
        is_fully_received: res.is_complete,
      }));

      if (res.is_complete) {
        setScanSuccess(
          `Intake Complete! Unit #${res.scanned_unit.unit_number} verified. All ${res.total_units_count} units are received. Product is now LIVE in inventory!`
        );
      } else {
        setScanSuccess(
          `Unit #${res.scanned_unit.unit_number} verified! (${res.received_units_count} of ${res.total_units_count} scanned)`
        );
      }

      setManualBarcodeInput('');
    } catch (err) {
      console.error('Scan verification error:', err);
      setScanError(err.message || 'Scan verification failed.');
    } finally {
      setScanningInProgress(false);
    }
  };

  // Phase Y & Seller Labels: Download / Print PDF Label Sheet
  const handleOpenLabelsModal = (req) => {
    setLabelsModalRequest(req);
    setLabelsPaperSize('a4');
    setShowLabelsModal(true);
  };

  const handlePrintLabelsPdf = (format = labelsPaperSize) => {
    if (!labelsModalRequest) return;
    const url = apiWarehouseGetInboundLabelsPdfUrl(labelsModalRequest.id, format);
    window.open(url, '_blank');
  };

  // Phase Z: Open and Confirm Shortfall Reporting
  const handleOpenShortfallModal = (req) => {
    setShortfallModalRequest(req);
    const total = req.total_units_count || req.requested_quantity;
    const received = req.received_units_count || (scanUnitsList.filter((u) => u.status === 'RECEIVED').length) || 0;
    setShortfallNote(`Warehouse verified ${received} of ${total} units. Short by ${total - received} units.`);
    setShortfallError(null);
    setShortfallModalOpen(true);
  };

  const handleConfirmReportShortfall = async (e) => {
    e.preventDefault();
    if (!shortfallModalRequest) return;

    setReportingShortfall(true);
    setShortfallError(null);

    try {
      await apiWarehouseReportShortfall(shortfallModalRequest.id, shortfallNote.trim());
      setSuccessToast(`Shortfall for Inbound Request #${shortfallModalRequest.id} successfully reported to seller.`);
      setShortfallModalOpen(false);
      setShortfallModalRequest(null);
      if (scanModalOpen) {
        setScanModalOpen(false);
      }
      fetchRequests();
    } catch (err) {
      console.error('Failed to report shortfall:', err);
      setShortfallError(err.message || 'Failed to report shortfall.');
    } finally {
      setReportingShortfall(false);
    }
  };

  // Metrics computation
  const metrics = {
    total: requests.length,
    pending: requests.filter((r) => r.status === 'PENDING').length,
    accepted: requests.filter((r) => r.status === 'ACCEPTED').length,
    shortfall: requests.filter((r) => r.status === 'SHORT_RECEIVED').length,
    completed: requests.filter((r) => r.status === 'COMPLETED').length,
    rejected: requests.filter((r) => r.status === 'REJECTED' || r.status === 'REJECTED_RETURN').length,
  };

  return (
    <div className="space-y-6 max-w-6xl mx-auto pb-12">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-xl font-black text-slate-900 flex items-center gap-2.5">
            <Boxes className="w-6 h-6 text-indigo-600" />
            <span>Warehouse Inbound Stock & Physical Scan-In</span>
          </h2>
          <p className="text-xs text-slate-500 mt-1">
            Review merchant replenishment shipments, print per-unit Code128 barcodes, and scan-in physical stock for Fulfilled by Sevo (FBS) items.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={handleManualRefresh}
            disabled={refreshing || loading}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-white hover:bg-slate-50 border border-slate-200 text-xs font-semibold text-slate-700 rounded-lg shadow-xs transition"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${refreshing ? 'animate-spin' : ''}`} />
            <span>Refresh</span>
          </button>
        </div>
      </div>

      {/* Success Toast */}
      {successToast && (
        <div className="p-3.5 bg-emerald-50 border border-emerald-200 rounded-xl text-emerald-700 text-xs font-medium flex items-center justify-between shadow-xs">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-emerald-600" />
            <span>{successToast}</span>
          </div>
          <button onClick={() => setSuccessToast(null)} className="text-emerald-700 hover:text-emerald-900">
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {/* Error Message */}
      {error && (
        <div className="p-4 bg-rose-50 border border-rose-200 rounded-xl text-rose-700 text-xs flex items-center gap-2 shadow-xs">
          <AlertTriangle className="w-4 h-4 shrink-0 text-rose-600" />
          <span>{error}</span>
        </div>
      )}

      {/* KPI Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
        <div
          onClick={() => setStatusFilter('ALL')}
          className={`p-3.5 rounded-2xl border cursor-pointer transition shadow-xs ${
            statusFilter === 'ALL'
              ? 'bg-indigo-50/60 border-indigo-300 ring-1 ring-indigo-500/30'
              : 'bg-white border-slate-200 hover:border-slate-300'
          }`}
        >
          <span className="text-[11px] font-bold text-slate-500 uppercase tracking-wider">Total Requests</span>
          <div className="text-xl font-black text-slate-900 mt-1">{metrics.total}</div>
        </div>

        <div
          onClick={() => setStatusFilter('PENDING')}
          className={`p-3.5 rounded-2xl border cursor-pointer transition shadow-xs ${
            statusFilter === 'PENDING'
              ? 'bg-amber-50 border-amber-300 ring-1 ring-amber-500/30'
              : 'bg-white border-slate-200 hover:border-slate-300'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-bold text-amber-700 uppercase tracking-wider">Pending Action</span>
            <Clock className="w-3.5 h-3.5 text-amber-600" />
          </div>
          <div className="text-xl font-black text-amber-700 mt-1">{metrics.pending}</div>
        </div>

        <div
          onClick={() => setStatusFilter('ACCEPTED')}
          className={`p-3.5 rounded-2xl border cursor-pointer transition shadow-xs ${
            statusFilter === 'ACCEPTED'
              ? 'bg-indigo-50 border-indigo-300 ring-1 ring-indigo-500/30'
              : 'bg-white border-slate-200 hover:border-slate-300'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-bold text-indigo-700 uppercase tracking-wider">Scanning Intake</span>
            <ScanLine className="w-3.5 h-3.5 text-indigo-600" />
          </div>
          <div className="text-xl font-black text-indigo-700 mt-1">{metrics.accepted}</div>
        </div>

        <div
          onClick={() => setStatusFilter('COMPLETED')}
          className={`p-3.5 rounded-2xl border cursor-pointer transition shadow-xs ${
            statusFilter === 'COMPLETED'
              ? 'bg-emerald-50 border-emerald-300 ring-1 ring-emerald-500/30'
              : 'bg-white border-slate-200 hover:border-slate-300'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-bold text-emerald-700 uppercase tracking-wider">Verified Live</span>
            <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
          </div>
          <div className="text-xl font-black text-emerald-700 mt-1">{metrics.completed}</div>
        </div>

        <div
          onClick={() => setStatusFilter('REJECTED')}
          className={`p-3.5 rounded-2xl border cursor-pointer transition shadow-xs ${
            statusFilter === 'REJECTED'
              ? 'bg-rose-50 border-rose-300 ring-1 ring-rose-500/30'
              : 'bg-white border-slate-200 hover:border-slate-300'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-bold text-rose-700 uppercase tracking-wider">Rejected</span>
            <XCircle className="w-3.5 h-3.5 text-rose-600" />
          </div>
          <div className="text-xl font-black text-rose-700 mt-1">{metrics.rejected}</div>
        </div>
      </div>

      {/* Filters & Search */}
      <div className="flex flex-col sm:flex-row items-center gap-3 bg-white p-3 rounded-2xl border border-slate-200 shadow-xs">
        <div className="relative flex-1 w-full">
          <Search className="w-4 h-4 absolute left-3 top-2.5 text-slate-400" />
          <input
            type="text"
            placeholder="Search by SKU, product title, merchant name, or barcode..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-3 py-1.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 placeholder-slate-400 focus:bg-white focus:outline-none focus:border-indigo-500"
          />
        </div>

        <div className="flex items-center gap-2 w-full sm:w-auto">
          <Filter className="w-4 h-4 text-slate-400 hidden sm:block" />
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="bg-white border border-slate-200 rounded-xl text-xs text-slate-700 px-3 py-1.5 focus:outline-none focus:border-indigo-500 shadow-xs"
          >
            <option value="ALL">All Statuses</option>
            <option value="PENDING">Pending Review</option>
            <option value="ACCEPTED">In Verification / Scanning</option>
            <option value="COMPLETED">Completed / Live in Stock</option>
            <option value="REJECTED">Rejected</option>
          </select>
        </div>
      </div>

      {/* Requests Table */}
      {loading ? (
        <div className="p-12 text-center bg-white rounded-2xl border border-slate-200 shadow-xs">
          <RefreshCw className="w-6 h-6 text-indigo-600 animate-spin mx-auto mb-2" />
          <p className="text-xs text-slate-500">Loading inbound stock requests...</p>
        </div>
      ) : requests.length === 0 ? (
        <div className="p-12 text-center bg-white rounded-2xl border border-slate-200 space-y-2 shadow-xs">
          <Package className="w-10 h-10 text-slate-400 mx-auto" />
          <h4 className="text-sm font-bold text-slate-900">No Inbound Requests Found</h4>
          <p className="text-xs text-slate-500 max-w-sm mx-auto">
            {statusFilter !== 'ALL'
              ? `There are currently no inbound storage requests with status '${statusFilter}'.`
              : 'Merchant inbound replenishment storage requests will appear here when sellers request FBS warehouse intake.'}
          </p>
        </div>
      ) : (
        <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden shadow-xs">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs text-slate-700">
              <thead className="bg-slate-50 text-[11px] uppercase font-bold text-slate-600 border-b border-slate-200">
                <tr>
                  <th className="py-3 px-4">Req # / Product</th>
                  <th className="py-3 px-4">Merchant Store</th>
                  <th className="py-3 px-4 text-center">Requested Units</th>
                  <th className="py-3 px-4">Status & Scan Progress</th>
                  <th className="py-3 px-4">Notes & Reviewer Comments</th>
                  <th className="py-3 px-4 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200">
                {requests.map((req) => {
                  const statusInfo = STATUS_CONFIG[req.status] || STATUS_CONFIG.ALL;
                  const isPending = req.status === 'PENDING';
                  const isAccepted = req.status === 'ACCEPTED';
                  const isCompleted = req.status === 'COMPLETED';

                  const total = req.total_units_count || req.requested_quantity;
                  const received = req.received_units_count || 0;
                  const percent = total > 0 ? Math.round((received / total) * 100) : 0;

                  return (
                    <tr key={req.id} className="hover:bg-slate-50/80 transition-colors">
                      {/* Product & Inbound ID */}
                      <td className="py-3.5 px-4">
                        <div className="flex items-start gap-3">
                          <div className="w-9 h-9 rounded-xl bg-slate-100 border border-slate-200 flex items-center justify-center shrink-0 text-slate-400 font-bold overflow-hidden">
                            {req.product_image_url ? (
                              <img
                                src={req.product_image_url}
                                alt={req.product_title}
                                className="w-full h-full object-cover rounded-xl"
                              />
                            ) : (
                              <Package className="w-4 h-4" />
                            )}
                          </div>
                          <div className="min-w-0">
                            <div className="flex items-center gap-1.5">
                              <span className="font-mono text-[10px] font-bold text-indigo-700 bg-indigo-50 px-1.5 py-0.5 rounded border border-indigo-200">
                                #{req.id}
                              </span>
                              <span className="font-bold text-slate-900 text-xs truncate max-w-[200px]">
                                {req.product_title}
                              </span>
                            </div>
                            <div className="text-[10px] font-mono text-slate-500 mt-0.5">
                              SKU: <span className="text-slate-700 font-bold">{req.product_sku}</span> • Price: ₹{req.product_selling_price}
                            </div>
                          </div>
                        </div>
                      </td>

                      {/* Merchant Store */}
                      <td className="py-3.5 px-4">
                        <div className="flex items-center gap-1.5 font-bold text-slate-900">
                          <Store className="w-3.5 h-3.5 text-indigo-600" />
                          <span>{req.company_name}</span>
                        </div>
                        <div className="text-[10px] text-slate-500 mt-0.5">
                          By: {req.requested_by_name || 'Store Manager'}
                        </div>
                      </td>

                      {/* Requested Quantity */}
                      <td className="py-3.5 px-4 text-center">
                        <span className="inline-flex items-center px-2.5 py-1 rounded-lg bg-slate-100 text-slate-900 border border-slate-200 font-black text-sm">
                          {req.requested_quantity}
                        </span>
                        <div className="text-[10px] text-slate-500 mt-0.5 font-medium">Units</div>
                      </td>

                      {/* Status & Scan Progress */}
                      <td className="py-3.5 px-4">
                        {isPending && (
                          <span
                            className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold border ${statusInfo.bg} ${statusInfo.text} ${statusInfo.border}`}
                          >
                            <Clock className="w-3 h-3" />
                            <span>Pending Review</span>
                          </span>
                        )}

                        {isAccepted && (
                          <div className="space-y-1.5 min-w-[150px]">
                            <div className="flex items-center justify-between gap-2 text-[10px]">
                              <span className="inline-flex items-center gap-1 font-bold text-indigo-700">
                                <ScanLine className="w-3 h-3 text-indigo-600" />
                                <span>Scanning In Progress</span>
                              </span>
                              <span className="font-mono font-bold text-slate-800">
                                {received} / {total} ({percent}%)
                              </span>
                            </div>
                            <div className="w-full bg-slate-100 rounded-full h-1.5 overflow-hidden border border-slate-200">
                              <div
                                className="bg-indigo-600 h-1.5 rounded-full transition-all duration-300"
                                style={{ width: `${percent}%` }}
                              />
                            </div>
                          </div>
                        )}

                        {req.status === 'SHORT_RECEIVED' && (
                          <div className="space-y-1 min-w-[150px]">
                            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold border bg-amber-50 text-amber-700 border-amber-200">
                              <AlertTriangle className="w-3 h-3" />
                              <span>Shortfall Reported</span>
                            </span>
                            <div className="text-[10px] text-amber-800 font-mono pl-1">
                              {req.confirmed_quantity || received} / {total} units confirmed (Waiting for seller)
                            </div>
                          </div>
                        )}

                        {isCompleted && (
                          <div className="space-y-1 min-w-[150px]">
                            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold border bg-emerald-50 text-emerald-700 border-emerald-200">
                              <CheckCircle2 className="w-3 h-3" />
                              <span>Live in Warehouse Stock</span>
                            </span>
                            <div className="text-[10px] text-emerald-700 font-bold pl-1 font-mono">
                              {req.confirmed_quantity != null && req.confirmed_quantity < req.requested_quantity
                                ? `${req.confirmed_quantity} of ${req.requested_quantity} units live (Partial)`
                                : `${total} / ${total} units verified`}
                            </div>
                          </div>
                        )}

                        {req.status === 'REJECTED_RETURN' && (
                          <div className="space-y-1 min-w-[150px]">
                            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold border bg-rose-50 text-rose-700 border-rose-200">
                              <XCircle className="w-3 h-3" />
                              <span>Shortfall Rejected</span>
                            </span>
                            <div className="text-[10px] text-rose-700 font-medium pl-1">
                              Staged for return to seller
                            </div>
                          </div>
                        )}

                        {req.status === 'REJECTED' && (
                          <span
                            className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold border ${statusInfo.bg} ${statusInfo.text} ${statusInfo.border}`}
                          >
                            <XCircle className="w-3 h-3" />
                            <span>Rejected</span>
                          </span>
                        )}
                      </td>

                      {/* Notes & Timestamp */}
                      <td className="py-3.5 px-4 max-w-xs">
                        <div className="space-y-1">
                          {req.seller_note && (
                            <div className="text-[11px] text-slate-700 bg-slate-50 p-2 rounded-lg border border-slate-200">
                              <span className="text-[10px] font-bold text-slate-500 block">Seller Note:</span>
                              "{req.seller_note}"
                            </div>
                          )}

                          {req.shortfall_note && (
                            <div className="text-[11px] text-amber-800 bg-amber-50 p-2 rounded-lg border border-amber-200">
                              <span className="text-[10px] font-bold text-amber-700 block">Shortfall Note:</span>
                              "{req.shortfall_note}"
                            </div>
                          )}

                          {req.reviewer_note && !req.shortfall_note && (
                            <div className="text-[11px] text-amber-800 bg-amber-50 p-2 rounded-lg border border-amber-200">
                              <span className="text-[10px] font-bold text-amber-700 block">Reviewer Note:</span>
                              "{req.reviewer_note}"
                            </div>
                          )}

                          <div className="text-[10px] text-slate-400 pt-0.5">
                            Created: {new Date(req.created_at).toLocaleDateString()} {new Date(req.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </div>
                        </div>
                      </td>

                      {/* Action Buttons */}
                      <td className="py-3.5 px-4 text-right">
                        {isPending && (
                          <div className="flex items-center justify-end gap-2">
                            <button
                              onClick={() => openDecisionModal(req, 'ACCEPT')}
                              className="px-2.5 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-1 shadow-xs"
                            >
                              <Check className="w-3.5 h-3.5" />
                              <span>Accept</span>
                            </button>
                            <button
                              onClick={() => openDecisionModal(req, 'REJECT')}
                              className="px-2.5 py-1.5 bg-white hover:bg-rose-50 text-rose-700 hover:text-rose-800 border border-slate-200 hover:border-rose-300 rounded-xl text-xs font-bold transition flex items-center gap-1 shadow-xs"
                            >
                              <X className="w-3.5 h-3.5" />
                              <span>Reject</span>
                            </button>
                          </div>
                        )}

                        {isAccepted && (
                          <div className="flex items-center justify-end gap-2">
                            <button
                              onClick={() => handleOpenLabelsModal(req)}
                              title="Print Unit Barcode Labels"
                              className="p-1.5 bg-white hover:bg-slate-50 text-slate-700 border border-slate-200 rounded-xl text-xs font-bold transition flex items-center gap-1 shadow-xs"
                            >
                              <Printer className="w-3.5 h-3.5 text-indigo-600" />
                              <span className="hidden sm:inline">Labels</span>
                            </button>

                            <button
                              onClick={() => handleOpenShortfallModal(req)}
                              title="Report missing units & request seller decision"
                              className="px-2.5 py-1.5 bg-white hover:bg-amber-50 text-amber-700 border border-slate-200 hover:border-amber-300 rounded-xl text-xs font-bold transition flex items-center gap-1 shadow-xs"
                            >
                              <AlertTriangle className="w-3.5 h-3.5 text-amber-600" />
                              <span className="hidden sm:inline">Shortfall</span>
                            </button>

                            <button
                              onClick={() => handleOpenScanModal(req)}
                              className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-1.5 shadow-xs"
                            >
                              <ScanLine className="w-3.5 h-3.5" />
                              <span>Scan Units</span>
                            </button>
                          </div>
                        )}

                        {req.status === 'SHORT_RECEIVED' && (
                          <div className="flex items-center justify-end gap-2">
                            <button
                              onClick={() => handleOpenScanModal(req)}
                              className="px-2.5 py-1.5 bg-white hover:bg-amber-50 text-amber-700 border border-slate-200 hover:border-amber-300 rounded-xl text-xs font-bold transition flex items-center gap-1 shadow-xs"
                            >
                              <ScanLine className="w-3.5 h-3.5 text-amber-600" />
                              <span>Inspect Units</span>
                            </button>
                          </div>
                        )}

                        {isCompleted && (
                          <div className="flex items-center justify-end gap-2">
                            <button
                              onClick={() => handleOpenLabelsModal(req)}
                              title="Print Unit Barcode Labels"
                              className="p-1.5 bg-white hover:bg-slate-50 text-slate-700 border border-slate-200 rounded-xl text-xs font-bold transition flex items-center gap-1 shadow-xs"
                            >
                              <Printer className="w-3.5 h-3.5 text-indigo-600" />
                              <span className="hidden sm:inline">Labels</span>
                            </button>

                            <button
                              onClick={() => handleOpenScanModal(req)}
                              className="px-2.5 py-1.5 bg-white hover:bg-emerald-50 text-emerald-700 border border-slate-200 hover:border-emerald-300 rounded-xl text-xs font-bold transition flex items-center gap-1 shadow-xs"
                            >
                              <CheckCheck className="w-3.5 h-3.5 text-emerald-600" />
                              <span>View Units</span>
                            </button>
                          </div>
                        )}

                        {req.status === 'REJECTED_RETURN' && (
                          <div className="text-[11px] text-rose-700 font-medium flex items-center justify-end gap-1">
                            <XCircle className="w-3.5 h-3.5" /> Staged Return
                          </div>
                        )}

                        {req.status === 'REJECTED' && (
                          <div className="text-[11px] text-rose-700 font-medium flex items-center justify-end gap-1">
                            <XCircle className="w-3.5 h-3.5" /> Closed
                          </div>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Decision Modal (Accept/Reject) */}
      {selectedRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs animate-fadeIn">
          <div className="bg-white border border-slate-200 rounded-2xl max-w-lg w-full p-6 shadow-2xl space-y-4 text-slate-800">
            <div className="flex items-center justify-between border-b border-slate-200 pb-3">
              <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                {decisionAction === 'ACCEPT' ? (
                  <>
                    <CheckCircle2 className="w-5 h-5 text-emerald-600" />
                    <span>Accept Inbound Storage Request</span>
                  </>
                ) : (
                  <>
                    <XCircle className="w-5 h-5 text-rose-600" />
                    <span>Reject Inbound Storage Request</span>
                  </>
                )}
              </h3>
              <button onClick={closeDecisionModal} className="text-slate-400 hover:text-slate-600 p-1">
                <X className="w-4 h-4" />
              </button>
            </div>

            {decisionError && (
              <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-700 text-xs flex items-center gap-2 shadow-xs">
                <AlertTriangle className="w-4 h-4 shrink-0 text-rose-600" />
                <span>{decisionError}</span>
              </div>
            )}

            {/* Request Summary */}
            <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200 space-y-2 text-xs">
              <div className="flex justify-between">
                <span className="text-slate-500">Product:</span>
                <span className="font-bold text-slate-900">{selectedRequest.product_title}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">SKU:</span>
                <span className="font-mono text-slate-700 font-semibold">{selectedRequest.product_sku}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Merchant Store:</span>
                <span className="font-bold text-indigo-700">{selectedRequest.company_name}</span>
              </div>
              {/* Phase AA: Show seller-selected target warehouse so staff confirm they're reviewing the right facility */}
              <div className="flex justify-between">
                <span className="text-slate-500">Target Warehouse:</span>
                <span className="font-bold text-emerald-700">
                  {selectedRequest.warehouse_name || `WH-${selectedRequest.warehouse}`}
                  {selectedRequest.warehouse_city ? ` • ${selectedRequest.warehouse_city}` : ''}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Units Requested:</span>
                <span className="font-black text-amber-700 text-sm">{selectedRequest.requested_quantity} units</span>
              </div>
              {selectedRequest.seller_note && (
                <div className="pt-2 border-t border-slate-200 text-[11px] text-slate-700">
                  <span className="text-slate-500 font-bold block">Merchant Note:</span>
                  "{selectedRequest.seller_note}"
                </div>
              )}
            </div>

            <form onSubmit={handleConfirmDecision} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  {decisionAction === 'ACCEPT'
                    ? 'Intake / Dock Note (Optional)'
                    : 'Rejection Reason / Constraint (Visible to Merchant)'}
                </label>
                <textarea
                  rows={3}
                  value={reviewerNote}
                  onChange={(e) => setReviewerNote(e.target.value)}
                  placeholder={
                    decisionAction === 'ACCEPT'
                      ? 'e.g., Dock 2 allocated for Tuesday morning intake...'
                      : 'e.g., Capacity constraint: dry spice zone full until next week...'
                  }
                  className="w-full px-3 py-2 bg-white border border-slate-300 rounded-xl text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
                />
              </div>

              <div className="flex items-center justify-end gap-3 pt-2">
                <button
                  type="button"
                  onClick={closeDecisionModal}
                  disabled={submittingDecision}
                  className="px-4 py-2 bg-white hover:bg-slate-50 text-xs font-bold text-slate-700 border border-slate-200 rounded-xl shadow-xs transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submittingDecision}
                  className={`px-4 py-2 rounded-xl text-xs font-bold text-white transition flex items-center gap-1.5 shadow-xs ${
                    decisionAction === 'ACCEPT'
                      ? 'bg-emerald-600 hover:bg-emerald-700'
                      : 'bg-rose-600 hover:bg-rose-700'
                  }`}
                >
                  {submittingDecision ? (
                    <>
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                      <span>Submitting...</span>
                    </>
                  ) : (
                    <>
                      {decisionAction === 'ACCEPT' ? <Check className="w-3.5 h-3.5" /> : <X className="w-3.5 h-3.5" />}
                      <span>Confirm {decisionAction === 'ACCEPT' ? 'Acceptance' : 'Rejection'}</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ════════════════════════════════════════════════════════════════════ */}
      {/* PHASE Y: PHYSICAL SCAN-IN & UNIT VERIFICATION MODAL                  */}
      {/* ════════════════════════════════════════════════════════════════════ */}
      {scanModalOpen && scanModalRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs animate-fadeIn">
          <div className="bg-white border border-slate-200 rounded-2xl max-w-2xl w-full max-h-[90vh] flex flex-col shadow-2xl overflow-hidden text-slate-800">
            {/* Modal Header */}
            <div className="p-5 border-b border-slate-200 flex items-center justify-between bg-slate-50/60">
              <div className="flex items-center gap-2.5">
                <div className="w-9 h-9 rounded-xl bg-indigo-50 text-indigo-700 border border-indigo-200 flex items-center justify-center">
                  <ScanLine className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-sm font-bold text-slate-900 flex items-center gap-2">
                    <span>Physical Scan-In Verification</span>
                    <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-indigo-50 text-indigo-700 border border-indigo-200 font-bold">
                      Req #{scanModalRequest.id}
                    </span>
                  </h3>
                  <p className="text-[11px] text-slate-500 mt-0.5">
                    Scan each individual unit's Code128 barcode before flipping the batch live
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={() => handleOpenLabelsModal(scanModalRequest)}
                  className="px-2.5 py-1.5 bg-white hover:bg-slate-50 border border-slate-200 rounded-xl text-xs font-bold text-slate-700 shadow-xs transition flex items-center gap-1.5"
                >
                  <Printer className="w-3.5 h-3.5 text-indigo-600" />
                  <span>Print Labels PDF</span>
                </button>
                <button onClick={handleCloseScanModal} className="text-slate-400 hover:text-slate-600 p-1">
                  <X className="w-5 h-5" />
                </button>
              </div>
            </div>

            {/* Modal Scrollable Body */}
            <div className="p-6 overflow-y-auto space-y-4 flex-1">
              {/* Product Info & Live Progress Strip */}
              <div className="p-4 bg-slate-50 rounded-xl border border-slate-200 space-y-3">
                <div className="flex items-start justify-between">
                  <div>
                    <h4 className="font-bold text-slate-900 text-xs">{scanModalRequest.product_title}</h4>
                    <div className="text-[11px] font-mono text-slate-500 mt-0.5">
                      SKU: <span className="text-slate-700 font-bold">{scanModalRequest.product_sku}</span> • Merchant:{' '}
                      <span className="text-indigo-700 font-bold">{scanModalRequest.company_name}</span>
                    </div>
                  </div>
                  <div className="text-right">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-slate-500">Total Requested</span>
                    <div className="font-black text-amber-700 text-sm font-mono">
                      {scanModalRequest.requested_quantity} Units
                    </div>
                  </div>
                </div>

                {/* Progress Bar */}
                {(() => {
                  const total = scanUnitsList.length || scanModalRequest.requested_quantity || 1;
                  const received = scanUnitsList.filter((u) => u.status === 'RECEIVED').length;
                  const percent = Math.round((received / total) * 100);
                  const isDone = received >= total && total > 0;

                  return (
                    <div className="space-y-1.5 pt-1">
                      <div className="flex items-center justify-between text-xs">
                        <span className="font-bold text-slate-700 flex items-center gap-1.5">
                          {isDone ? (
                            <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                          ) : (
                            <ScanLine className="w-4 h-4 text-indigo-600" />
                          )}
                          <span>
                            {isDone ? 'All Units Verified & Received' : 'Scanning Progress'}
                          </span>
                        </span>
                        <span className="font-mono font-black text-indigo-700 text-xs">
                          {received} of {total} Units ({percent}%)
                        </span>
                      </div>
                      <div className="w-full bg-slate-200 rounded-full h-2.5 overflow-hidden border border-slate-300">
                        <div
                          className={`h-2.5 rounded-full transition-all duration-300 ${
                            isDone ? 'bg-emerald-500' : 'bg-indigo-600'
                          }`}
                          style={{ width: `${percent}%` }}
                        />
                      </div>
                    </div>
                  );
                })()}
              </div>

              {/* Success / Error Banners */}
              {scanSuccess && (
                <div className="p-3.5 bg-emerald-50 border border-emerald-200 rounded-xl text-emerald-700 text-xs flex items-center gap-2.5 animate-fadeIn font-medium shadow-xs">
                  <CheckCircle2 className="w-4 h-4 shrink-0 text-emerald-600" />
                  <span>{scanSuccess}</span>
                </div>
              )}

              {scanError && (
                <div className="p-3.5 bg-rose-50 border border-rose-200 rounded-xl text-rose-700 text-xs flex items-center gap-2.5 animate-fadeIn font-medium shadow-xs">
                  <AlertTriangle className="w-4 h-4 shrink-0 text-rose-600" />
                  <span>{scanError}</span>
                </div>
              )}

              {/* Barcode Scanner Input Controls */}
              <div className="p-4 bg-slate-50 rounded-xl border border-slate-200 space-y-3">
                <div className="flex items-center justify-between">
                  <label className="text-xs font-bold text-slate-700 flex items-center gap-1.5">
                    <QrCode className="w-4 h-4 text-indigo-600" />
                    <span>Scan Unit Barcode</span>
                  </label>

                  <button
                    type="button"
                    onClick={() => setCameraModalOpen(true)}
                    className="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-1.5 shadow-xs"
                  >
                    <Camera className="w-3.5 h-3.5" />
                    <span>Open Camera Scanner</span>
                  </button>
                </div>

                <form
                  onSubmit={(e) => {
                    e.preventDefault();
                    handleProcessScan(manualBarcodeInput);
                  }}
                  className="flex gap-2"
                >
                  <input
                    type="text"
                    value={manualBarcodeInput}
                    onChange={(e) => setManualBarcodeInput(e.target.value)}
                    placeholder="Scan or type unit barcode (e.g. SEVO-INB-0001-001-A1B2C3)..."
                    disabled={scanningInProgress}
                    autoFocus
                    className="flex-1 px-3.5 py-2 bg-white border border-slate-300 rounded-xl text-xs text-slate-900 font-mono placeholder-slate-400 focus:outline-none focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
                  />
                  <button
                    type="submit"
                    disabled={scanningInProgress || !manualBarcodeInput.trim()}
                    className="px-4 py-2 bg-slate-900 hover:bg-indigo-600 text-white rounded-xl text-xs font-bold transition disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1.5 shadow-xs"
                  >
                    {scanningInProgress ? (
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                    ) : (
                      <Check className="w-3.5 h-3.5" />
                    )}
                    <span>Verify Scan</span>
                  </button>
                </form>
              </div>

              {/* Units Table */}
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <h4 className="text-xs font-bold uppercase tracking-wider text-slate-600">
                    Generated Unit Serial Barcodes ({scanUnitsList.length})
                  </h4>
                  <span className="text-[11px] text-slate-500">
                    {scanUnitsList.filter((u) => u.status === 'RECEIVED').length} verified of {scanUnitsList.length} total
                  </span>
                </div>

                {scanModalLoading ? (
                  <div className="p-8 text-center text-slate-500">
                    <RefreshCw className="w-5 h-5 animate-spin mx-auto mb-1 text-indigo-600" />
                    <span className="text-xs">Loading unit barcodes...</span>
                  </div>
                ) : (
                  <div className="border border-slate-200 rounded-xl overflow-hidden max-h-64 overflow-y-auto shadow-xs">
                    <table className="w-full text-left text-xs">
                      <thead className="bg-slate-50 text-[10px] uppercase font-bold text-slate-600 sticky top-0 border-b border-slate-200">
                        <tr>
                          <th className="py-2.5 px-3">Unit #</th>
                          <th className="py-2.5 px-3">Serial Barcode</th>
                          <th className="py-2.5 px-3">Status</th>
                          <th className="py-2.5 px-3">Verified At / By</th>
                          <th className="py-2.5 px-3 text-right">Action</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-200 text-slate-700 font-medium font-mono text-[11px]">
                        {scanUnitsList.map((unit) => {
                          const isReceived = unit.status === 'RECEIVED';

                          return (
                            <tr
                              key={unit.id}
                              className={isReceived ? 'bg-emerald-50/50' : 'hover:bg-slate-50/80 transition-colors'}
                            >
                              <td className="py-2 px-3 font-bold text-slate-800">
                                Unit {unit.unit_number}
                              </td>
                              <td className="py-2 px-3">
                                <span className="text-indigo-700 font-bold bg-indigo-50 px-2 py-0.5 rounded border border-indigo-200">
                                  {unit.barcode}
                                </span>
                              </td>
                              <td className="py-2 px-3">
                                {isReceived ? (
                                  <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                                    <CheckCircle2 className="w-3 h-3" />
                                    <span>RECEIVED</span>
                                  </span>
                                ) : (
                                  <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold bg-slate-100 text-slate-600 border border-slate-200">
                                    <Clock className="w-3 h-3" />
                                    <span>PENDING</span>
                                  </span>
                                )}
                              </td>
                              <td className="py-2 px-3 text-[10px] text-slate-500 font-sans">
                                {isReceived ? (
                                  <div>
                                    <span className="text-slate-800 font-medium">
                                      {new Date(unit.scanned_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                                    </span>
                                    <span className="text-slate-400 block text-[9px]">
                                      by {unit.scanned_by_name || 'Warehouse Staff'}
                                    </span>
                                  </div>
                                ) : (
                                  <span className="text-slate-400">—</span>
                                )}
                              </td>
                              <td className="py-2 px-3 text-right">
                                {!isReceived && (
                                  <button
                                    onClick={() => handleProcessScan(unit.barcode)}
                                    disabled={scanningInProgress}
                                    className="px-2 py-1 bg-white hover:bg-indigo-50 text-indigo-700 hover:text-indigo-800 rounded text-[10px] font-bold transition border border-slate-200 hover:border-indigo-300 shadow-xs"
                                  >
                                    Simulate Scan
                                  </button>
                                )}
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

            {/* Modal Footer */}
            <div className="p-4 border-t border-slate-200 bg-slate-50/60 flex items-center justify-between">
              <div className="text-[11px] text-slate-600 font-medium">
                {scanModalRequest.is_fully_received || scanModalRequest.status === 'COMPLETED' ? (
                  <span className="text-emerald-700 font-bold flex items-center gap-1">
                    <CheckCircle2 className="w-4 h-4 text-emerald-600" /> All units received • Live stock updated
                  </span>
                ) : scanModalRequest.status === 'SHORT_RECEIVED' ? (
                  <span className="text-amber-700 font-bold flex items-center gap-1">
                    <AlertTriangle className="w-4 h-4 text-amber-600" /> Shortfall reported • Waiting for merchant decision
                  </span>
                ) : (
                  <span>Scanning in progress • Units verified one-by-one.</span>
                )}
              </div>

              <div className="flex items-center gap-2">
                {scanModalRequest.status === 'ACCEPTED' && !scanModalRequest.is_fully_received && (
                  <button
                    onClick={() => handleOpenShortfallModal(scanModalRequest)}
                    className="px-3 py-2 bg-white hover:bg-amber-50 text-amber-700 border border-slate-200 hover:border-amber-300 text-xs font-bold rounded-xl shadow-xs transition flex items-center gap-1.5"
                  >
                    <AlertTriangle className="w-3.5 h-3.5 text-amber-600" />
                    <span>Report Shortfall & Close</span>
                  </button>
                )}

                <button
                  onClick={handleCloseScanModal}
                  className="px-4 py-2 bg-white hover:bg-slate-50 border border-slate-200 text-xs font-bold text-slate-700 rounded-xl shadow-xs transition"
                >
                  Close Window
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ════════════════════════════════════════════════════════════════════ */}
      {/* PHASE Z: REPORT SHORTFALL MODAL                                     */}
      {/* ════════════════════════════════════════════════════════════════════ */}
      {shortfallModalOpen && shortfallModalRequest && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs animate-fadeIn">
          <div className="bg-white border border-amber-300 rounded-2xl max-w-lg w-full p-6 shadow-2xl space-y-4 text-slate-800">
            <div className="flex items-center justify-between border-b border-slate-200 pb-3">
              <h3 className="text-base font-bold text-slate-900 flex items-center gap-2">
                <AlertTriangle className="w-5 h-5 text-amber-600" />
                <span>Report Intake Shortfall & Request Seller Decision</span>
              </h3>
              <button
                onClick={() => setShortfallModalOpen(false)}
                className="text-slate-400 hover:text-slate-600 p-1"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {shortfallError && (
              <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-rose-700 text-xs flex items-center gap-2 shadow-xs">
                <AlertTriangle className="w-4 h-4 shrink-0 text-rose-600" />
                <span>{shortfallError}</span>
              </div>
            )}

            <div className="p-4 bg-slate-50 rounded-xl border border-slate-200 space-y-2 text-xs">
              <div className="flex justify-between font-mono">
                <span className="text-slate-500">Inbound Request:</span>
                <span className="font-bold text-slate-900">#{shortfallModalRequest.id}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Product:</span>
                <span className="font-bold text-slate-800 text-right">{shortfallModalRequest.product_title}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-slate-500">Merchant Store:</span>
                <span className="font-bold text-indigo-700">{shortfallModalRequest.company_name}</span>
              </div>
              <div className="flex justify-between font-mono pt-1 border-t border-slate-200">
                <span className="text-slate-500">Requested vs Verified:</span>
                <span className="font-bold text-amber-700">
                  {shortfallModalRequest.received_units_count || (scanUnitsList.filter((u) => u.status === 'RECEIVED').length)} of {shortfallModalRequest.total_units_count || shortfallModalRequest.requested_quantity} Units Verified
                </span>
              </div>
            </div>

            <form onSubmit={handleConfirmReportShortfall} className="space-y-3">
              <div>
                <label className="block text-xs font-bold text-slate-700 mb-1">
                  Warehouse Shortfall Explanation / Note to Seller <span className="text-rose-500">*</span>
                </label>
                <textarea
                  rows={3}
                  required
                  value={shortfallNote}
                  onChange={(e) => setShortfallNote(e.target.value)}
                  placeholder="Explain why fewer units were received (e.g., Only 3 units in parcel box, packaging damaged, etc.)..."
                  className="w-full px-3.5 py-2.5 bg-white border border-slate-300 rounded-xl text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-amber-500 focus:ring-2 focus:ring-amber-500/20"
                />
              </div>

              <div className="p-3 bg-amber-50 border border-amber-200 rounded-xl text-[11px] text-amber-800 space-y-1">
                <span className="font-bold block text-amber-900">What happens next:</span>
                <p>
                  1. The request status will move to <strong>SHORT_RECEIVED</strong>.
                </p>
                <p>
                  2. The merchant will receive a shortfall notice with options to <strong>Accept Partial</strong> (go live with verified units) or <strong>Reject Batch</strong> (stage for return).
                </p>
              </div>

              <div className="flex items-center justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setShortfallModalOpen(false)}
                  className="px-4 py-2 bg-white hover:bg-slate-50 border border-slate-200 text-slate-700 rounded-xl text-xs font-bold shadow-xs transition"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={reportingShortfall || !shortfallNote.trim()}
                  className="px-5 py-2 bg-amber-600 hover:bg-amber-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-1.5 shadow-xs disabled:opacity-50"
                >
                  {reportingShortfall ? (
                    <>
                      <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                      <span>Reporting Shortfall...</span>
                    </>
                  ) : (
                    <>
                      <AlertTriangle className="w-3.5 h-3.5" />
                      <span>Confirm & Report Shortfall</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* MODAL: PRINT INBOUND UNIT LABELS (MULTI-FORMAT) */}
      {showLabelsModal && labelsModalRequest && (
        <div className="fixed inset-0 z-50 bg-slate-900/40 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto">
          <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl w-full max-w-lg overflow-hidden text-slate-800 animate-in fade-in zoom-in-95 duration-150">
            {/* Header */}
            <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50/60">
              <div className="flex items-center gap-2.5">
                <div className="w-8 h-8 rounded-xl bg-indigo-50 text-indigo-700 flex items-center justify-center font-bold border border-indigo-200">
                  <Printer className="w-4 h-4" />
                </div>
                <div>
                  <h3 className="font-bold text-slate-900 text-sm">Print Unit Barcode Labels</h3>
                  <p className="text-[11px] text-slate-500">
                    Request #{labelsModalRequest.id} &bull; {labelsModalRequest.requested_quantity} Unit Labels
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setShowLabelsModal(false)}
                className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-100 transition"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Body */}
            <div className="p-6 space-y-4">
              {/* Product & Warehouse Info */}
              <div className="p-3.5 bg-slate-50 border border-slate-200 rounded-xl space-y-2">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <div className="font-bold text-slate-900 text-xs">{labelsModalRequest.product_title}</div>
                    <div className="text-[11px] font-mono text-slate-500 mt-0.5">
                      SKU: <span className="font-bold text-slate-700">{labelsModalRequest.product_sku}</span>
                    </div>
                  </div>
                  <span className="px-2.5 py-1 rounded-md bg-indigo-50 text-indigo-700 font-bold text-xs font-mono border border-indigo-200 shrink-0">
                    {labelsModalRequest.requested_quantity} Units
                  </span>
                </div>
                <div className="text-[11px] text-slate-500 border-t border-slate-200 pt-2 flex items-center justify-between">
                  <span>Merchant: <b className="text-slate-800">{labelsModalRequest.company_name}</b></span>
                  <span>Warehouse: <b className="text-slate-800">{labelsModalRequest.warehouse_name}</b></span>
                </div>
              </div>

              {/* Paper Size / Format Selector */}
              <div className="space-y-2.5">
                <label className="block text-xs font-bold text-slate-700">
                  Select Printer Type & Paper Format
                </label>
                <div className="grid grid-cols-1 gap-2">
                  {[
                    {
                      id: 'a4',
                      name: 'A4 Sheet (Multi-Label Grid)',
                      desc: '2-column grid layout with multiple unit labels per page. For laser/inkjet printers.',
                      badge: 'Standard A4',
                    },
                    {
                      id: 'thermal_4x6',
                      name: 'Thermal 4×6 in (Roll Label)',
                      desc: '1 unit label per page (101.6 × 152.4 mm). Standard shipping & warehouse label roll.',
                      badge: 'Thermal 4x6"',
                    },
                    {
                      id: 'thermal_2x1',
                      name: 'Thermal 2×1 in (Barcode Sticker)',
                      desc: '1 compact barcode label per page (50.8 × 25.4 mm). For retail & item barcode stickers.',
                      badge: 'Thermal 2x1"',
                    },
                  ].map((opt) => (
                    <label
                      key={opt.id}
                      className={`flex items-start gap-3 p-3 rounded-xl border cursor-pointer transition shadow-xs ${
                        labelsPaperSize === opt.id
                          ? 'bg-indigo-50/70 border-indigo-500 ring-1 ring-indigo-500'
                          : 'bg-white border-slate-200 hover:border-slate-300 hover:bg-slate-50/50'
                      }`}
                    >
                      <input
                        type="radio"
                        name="whLabelPaperFormat"
                        value={opt.id}
                        checked={labelsPaperSize === opt.id}
                        onChange={(e) => setLabelsPaperSize(e.target.value)}
                        className="mt-0.5 text-indigo-600 focus:ring-indigo-500 bg-white border-slate-300"
                      />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between">
                          <span className="text-xs font-bold text-slate-900">{opt.name}</span>
                          <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-slate-100 text-slate-700 font-semibold border border-slate-200">
                            {opt.badge}
                          </span>
                        </div>
                        <p className="text-[11px] text-slate-500 mt-0.5">{opt.desc}</p>
                      </div>
                    </label>
                  ))}
                </div>
              </div>

              {/* Footer Buttons */}
              <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-200">
                <button
                  type="button"
                  onClick={() => setShowLabelsModal(false)}
                  className="px-4 py-2 bg-white hover:bg-slate-50 border border-slate-200 text-slate-700 rounded-xl text-xs font-bold shadow-xs transition"
                >
                  Close
                </button>
                <button
                  type="button"
                  onClick={() => handlePrintLabelsPdf(labelsPaperSize)}
                  className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-1.5 shadow-xs"
                >
                  <Printer className="w-3.5 h-3.5" />
                  <span>Generate & Print PDF</span>
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Barcode Camera Scanner Modal */}
      <BarcodeScannerModal
        isOpen={cameraModalOpen}
        onClose={() => setCameraModalOpen(false)}
        onScan={(decodedBarcode) => {
          handleProcessScan(decodedBarcode);
        }}
        title={`Scan Inbound Unit Barcode (Req #${scanModalRequest?.id || ''})`}
        description="Aim your camera at the Code128 unit label or upload a photo to verify unit intake"
      />
    </div>
  );
}

export default WarehouseInventoryPage;
