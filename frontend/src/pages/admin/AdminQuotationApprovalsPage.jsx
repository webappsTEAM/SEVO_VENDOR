/**
 * AdminQuotationApprovalsPage.jsx
 *
 * The SEVO back office's quotation approval and inspection cockpit.
 *
 *   Before the customer sees it — quotes held by the high-value threshold,
 *   CRM clearance, or the mason structural-clearance gate. Releasing sends the quote.
 *
 *   After the customer accepts — quotes awaiting SEVO's authorization. Approving
 *   creates the work booking and issues the invoice.
 *
 * Mounted at /workforce/admin/quotations.
 */

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  Calculator,
  Calendar,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  Clock,
  Eye,
  FileText,
  Layers,
  Loader2,
  MapPin,
  Phone,
  RefreshCw,
  Ruler,
  Send,
  ShieldCheck,
  User,
  X,
  XCircle,
} from 'lucide-react';
import { apiRequest } from '../../api/client.js';

function money(value) {
  return Number(value || 0).toLocaleString('en-IN', {
    style: 'currency', currency: 'INR', maximumFractionDigits: 0,
  });
}

function formatMoney(value) {
  return Number(value || 0).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function ago(iso) {
  if (!iso) return '';
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  if (seconds < 3600) return `${Math.max(1, Math.round(seconds / 60))}m ago`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)}h ago`;
  return `${Math.round(seconds / 86400)}d ago`;
}

function roundMoney(num) {
  return Math.round(Number(num || 0) * 100) / 100;
}

const TABS = [
  {
    key: 'presend',
    label: 'Held before sending',
    badgeLabel: 'Awaiting CRM Clearance',
    endpoint: '/workforce/quotes/pending-review/',
    blurb: 'Submitted by technician for CRM/Operations clearance. Releasing sends the quote to the customer.',
  },
  {
    key: 'acceptance',
    label: 'Awaiting SEVO approval',
    badgeLabel: 'Customer Accepted',
    endpoint: '/workforce/quotes/pending-approval/',
    blurb: 'The customer has accepted. Approving creates the work booking and issues the invoice.',
  },
  {
    key: 'all',
    label: 'All Quotations & History',
    badgeLabel: 'All Quotes',
    endpoint: '/workforce/quotes/',
    blurb: 'Full historical log of all drafted, sent, customer accepted, approved, and converted quotations.',
  },
];

export function AdminQuotationApprovalsPage() {
  const [tab, setTab] = useState('presend');
  const [rows, setRows] = useState([]);
  const [counts, setCounts] = useState({ acceptance: 0, presend: 0, all: 0 });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [flash, setFlash] = useState(null);
  const [expandedQuoteId, setExpandedQuoteId] = useState(null);
  const [modalQuote, setModalQuote] = useState(null);

  const active = useMemo(() => TABS.find((t) => t.key === tab) || TABS[0], [tab]);

  const loadCounts = useCallback(async () => {
    try {
      const [presendData, accData, allData] = await Promise.all([
        apiRequest('/workforce/quotes/pending-review/').catch(() => []),
        apiRequest('/workforce/quotes/pending-approval/').catch(() => []),
        apiRequest('/workforce/quotes/').catch(() => []),
      ]);
      setCounts({
        presend: Array.isArray(presendData) ? presendData.length : 0,
        acceptance: Array.isArray(accData) ? accData.length : 0,
        all: Array.isArray(allData) ? allData.length : 0,
      });
    } catch {
      // ignore count fetch errors
    }
  }, []);

  const load = useCallback(async () => {
    setIsLoading(true);
    try {
      const data = await apiRequest(active.endpoint);
      const rowList = Array.isArray(data) ? data : [];
      setRows(rowList);
      setCounts((prev) => ({ ...prev, [active.key]: rowList.length }));
      setError(null);
    } catch (err) {
      setError(err?.message || 'Could not load the approval queue.');
      setRows([]);
    } finally {
      setIsLoading(false);
      loadCounts();
    }
  }, [active, loadCounts]);

  useEffect(() => { load(); }, [load]);

  async function decide(quote, approve, forcedTab = null) {
    const activeTab = forcedTab || (quote.status === 'PENDING_REVIEW' ? 'presend' : tab);
    const verb = activeTab === 'presend'
      ? (approve ? 'release and send to customer' : 'reject')
      : (approve ? 'approve and create booking' : 'reject');

    if (!window.confirm(`${verb.charAt(0).toUpperCase() + verb.slice(1)} ${quote.quote_number}?`)) {
      return;
    }

    let notes = '';
    if (!approve) {
      const notes = window.prompt('Reason for rejection (shown in audit trail):') || '';
      if (!notes.trim()) return;
      return submitDecision(quote, false, false, notes);
    }

    const actionText = autoConvert
      ? `Approve & Convert ${quote.quote_number} directly to an active service booking?`
      : tab === 'presend'
      ? `Release ${quote.quote_number} and send to customer for approval?`
      : `Approve ${quote.quote_number} and issue invoice?`;

    if (!window.confirm(actionText)) {
      return;
    }

    return submitDecision(quote, true, autoConvert, '');
  }

  async function submitDecision(quote, approve, autoConvert, notes) {
    setBusyId(quote.id);
    try {
      const path = activeTab === 'presend'
        ? `/workforce/quotes/${quote.id}/pre-send-review/`
        : `/workforce/quotes/${quote.id}/admin-review/`;
      const result = await apiRequest(path, {
        method: 'POST',
        json: {
          action: approve ? 'APPROVE' : 'REJECT',
          notes,
          reason: notes,
          auto_convert: autoConvert,
        },
      });

      if (modalQuote?.id === quote.id) {
        setModalQuote(null);
      }

      if (result.invoice) {
        setFlash(`${quote.quote_number} approved. Invoice ${result.invoice.invoice_number} issued for ${money(result.invoice.total_amount)}.`);
      } else if (activeTab === 'presend' && approve) {
        setFlash(`${quote.quote_number} released and delivered to the customer for approval.`);
      } else {
        setFlash(`${quote.quote_number} ${approve ? 'approved' : 'rejected'}.`);
      }
      if (tab !== 'all') {
        setRows((prev) => prev.filter((r) => r.id !== quote.id));
        setCounts((prev) => ({ ...prev, [tab]: Math.max(0, (prev[tab] || 1) - 1) }));
      } else {
        load();
      }
      setError(null);
    } catch (err) {
      setError(err?.message || `Failed to process ${quote.quote_number}.`);
    } finally {
      setBusyId(null);
      loadCounts();
    }
  }

  return (
    <div className="p-4 sm:p-6 max-w-6xl mx-auto space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 tracking-tight flex items-center gap-2.5">
            <Calculator className="w-6 h-6 text-indigo-600" />
            <span>Quotation Approvals &amp; Review</span>
          </h1>
          <p className="text-sm text-slate-600 mt-1">{active.blurb}</p>
        </div>
        <button
          type="button"
          onClick={load}
          className="inline-flex items-center gap-2 text-xs font-bold text-slate-700 hover:text-slate-900 border border-slate-300 hover:border-slate-400 rounded-xl px-4 py-2.5 bg-white shadow-xs transition-all cursor-pointer self-start sm:self-auto"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${isLoading ? 'animate-spin' : ''}`} />
          <span>Refresh Queue</span>
        </button>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 border-b border-slate-200 overflow-x-auto pb-px">
        {TABS.map((t) => {
          const count = counts[t.key] ?? 0;
          const isActive = t.key === tab;
          return (
            <button
              key={t.key}
              type="button"
              onClick={() => { setTab(t.key); setFlash(null); }}
              className={`flex items-center gap-2 px-4 py-3 text-sm font-semibold border-b-2 -mb-px transition-colors whitespace-nowrap cursor-pointer ${
                isActive
                  ? 'border-indigo-600 text-indigo-600 font-bold'
                  : 'border-transparent text-slate-500 hover:text-slate-700 hover:border-slate-300'
              }`}
            >
              <span>{t.label}</span>
              <span
                className={`text-xs px-2.5 py-0.5 rounded-full font-bold ${
                  isActive
                    ? count > 0 ? 'bg-indigo-100 text-indigo-700' : 'bg-slate-100 text-slate-600'
                    : count > 0 ? 'bg-amber-100 text-amber-800' : 'bg-slate-100 text-slate-400'
                }`}
              >
                {count}
              </span>
            </button>
          );
        })}
      </div>

      {/* Flash Banner */}
      {flash && (
        <div className="bg-emerald-50 border border-emerald-200 rounded-xl p-4 flex items-center justify-between gap-3 shadow-xs animate-in fade-in">
          <div className="flex items-center gap-3">
            <CheckCircle2 className="w-5 h-5 text-emerald-600 shrink-0" />
            <p className="text-sm font-medium text-emerald-900">{flash}</p>
          </div>
          <button type="button" onClick={() => setFlash(null)} className="text-emerald-700 hover:text-emerald-900">
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      {/* Error Banner */}
      {error && (
        <div className="bg-rose-50 border border-rose-200 rounded-xl p-4 flex gap-3 shadow-xs">
          <AlertTriangle className="w-5 h-5 text-rose-600 shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm text-rose-900 font-medium">{error}</p>
            <button type="button" onClick={load} className="text-xs text-rose-700 font-bold underline mt-1 cursor-pointer">
              Try again
            </button>
          </div>
        </div>
      )}

      {/* Main List */}
      {isLoading ? (
        <div className="py-20 flex flex-col items-center justify-center space-y-3">
          <Loader2 className="w-8 h-8 animate-spin text-indigo-600" />
          <p className="text-xs font-semibold text-slate-500">Loading quotations...</p>
        </div>
      ) : rows.length === 0 ? (
        <div className="py-20 text-center bg-white border border-slate-200 rounded-2xl p-8 shadow-xs">
          <FileText className="w-12 h-12 text-slate-300 mx-auto mb-3" />
          <h3 className="text-base font-bold text-slate-800">No Quotations Pending</h3>
          <p className="text-xs text-slate-500 mt-1 max-w-md mx-auto">
            All quotations in this queue have been processed. New quotations submitted by technicians or accepted by customers will appear here.
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {rows.map((q) => {
            const isExpanded = expandedQuoteId === q.id;
            const items = Array.isArray(q.items) ? q.items : [];
            const measurements = Array.isArray(q.measurements) ? q.measurements : [];
            const totalArea = measurements.reduce((acc, m) => acc + Number(m.area || m.calculated_area || 0), 0);
            const advanceAmount = q.advance_amount ?? roundMoney((q.net_payable || q.total_amount) * 0.5);
            const balanceAmount = q.balance_amount ?? roundMoney((q.net_payable || q.total_amount) - advanceAmount);

            return (
              <div
                key={q.id}
                className="bg-white border border-slate-200 hover:border-indigo-300 rounded-2xl p-5 shadow-xs transition-all space-y-4"
              >
                {/* Top Summary Row */}
                <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-4">
                  <div
                    className="min-w-0 flex-1 cursor-pointer"
                    onClick={() => setExpandedQuoteId(isExpanded ? null : q.id)}
                  >
                    <div className="flex items-center gap-2.5 flex-wrap">
                      <span className="font-extrabold text-slate-900 text-base font-mono tracking-tight">
                        {q.quote_number}
                      </span>
                      {q.quote_version > 1 && (
                        <span className="text-[11px] font-mono bg-slate-100 text-slate-700 font-bold px-2 py-0.5 rounded border border-slate-200">
                          v{q.quote_version}
                        </span>
                      )}
                      <span className="text-xs bg-indigo-50 text-indigo-700 font-bold px-2.5 py-0.5 rounded-full border border-indigo-200">
                        {q.service_category}
                      </span>
                      {q.status && (
                        <span className={`text-[11px] px-2.5 py-0.5 rounded-full font-bold uppercase tracking-wider border ${
                          q.status === 'CUSTOMER_ACCEPTED' || q.status === 'CONVERTED' || q.status === 'ADMIN_APPROVED'
                            ? 'bg-emerald-100 text-emerald-800 border-emerald-300'
                            : q.status === 'SENT_TO_CUSTOMER' || q.status === 'SENT'
                            ? 'bg-blue-100 text-blue-800 border-blue-300'
                            : q.status === 'PENDING_REVIEW' || q.status === 'CRM_REVIEW'
                            ? 'bg-amber-100 text-amber-800 border-amber-300'
                            : q.status === 'ADMIN_REJECTED' || q.status === 'REJECTED'
                            ? 'bg-rose-100 text-rose-800 border-rose-300'
                            : q.status === 'CHANGES_REQUESTED'
                            ? 'bg-amber-100 text-amber-800 border-amber-300'
                            : q.status === 'DECLINED' || q.status === 'CUSTOMER_DECLINED'
                            ? 'bg-rose-100 text-rose-800 border-rose-300'
                            : 'bg-slate-100 text-slate-700 border-slate-200'
                        }`}>
                          {q.status === 'PENDING_REVIEW'
                            ? 'HELD FOR CRM REVIEW'
                            : q.status_display || String(q.status || '').replace(/_/g, ' ')}
                        </span>
                      )}
                      {q.requires_structural_clearance && !q.is_structurally_cleared && (
                        <span className="text-xs bg-amber-50 text-amber-800 font-bold px-2.5 py-0.5 rounded-full border border-amber-200 flex items-center gap-1">
                          <ShieldCheck className="w-3.5 h-3.5" />
                          Structural clearance needed
                        </span>
                      )}
                    </div>

                    <p className="text-sm font-bold text-slate-800 mt-1.5 flex items-center gap-2 flex-wrap">
                      <span>{q.service_name || q.title || 'Service Inspection'}</span>
                      <span className="text-slate-400">&bull;</span>
                      <span className="font-semibold text-slate-900">{q.customer_name || 'Customer'}</span>
                    </p>

                    <p className="text-xs text-slate-500 mt-1 flex items-center gap-3 flex-wrap">
                      <span>Job ID: <strong>#{q.job_id || q.job_request_id}</strong></span>
                      {q.submitted_for_approval_at && (
                        <span>&bull; Submitted {ago(q.submitted_for_approval_at)}</span>
                      )}
                      {q.customer_decided_at && (
                        <span>&bull; Accepted {ago(q.customer_decided_at)}</span>
                      )}
                      {items.length > 0 && (
                        <span className="text-indigo-600 font-semibold">&bull; {items.length} Scope Item(s)</span>
                      )}
                      {measurements.length > 0 && (
                        <span className="text-indigo-600 font-semibold">&bull; {measurements.length} Area(s) ({totalArea} sq.ft)</span>
                      )}
                    </p>
                  </div>

                  {/* Financial & Modal Action */}
                  <div className="text-right shrink-0 flex flex-col items-end">
                    <p className="text-2xl font-black text-slate-900 font-mono tracking-tight">
                      {money(q.net_payable || q.total_amount)}
                    </p>
                    <p className="text-xs text-slate-500 font-medium">incl. GST {money(q.tax_amount)}</p>
                    
                    <div className="mt-2.5 flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => setModalQuote(q)}
                        className="inline-flex items-center gap-1.5 text-xs font-bold text-indigo-600 hover:text-indigo-800 bg-indigo-50 hover:bg-indigo-100 border border-indigo-200 px-3 py-1.5 rounded-lg transition-all cursor-pointer shadow-2xs"
                      >
                        <Eye className="w-3.5 h-3.5" />
                        <span>View Full Details</span>
                      </button>
                      <button
                        type="button"
                        onClick={() => setExpandedQuoteId(isExpanded ? null : q.id)}
                        className="p-1.5 text-slate-400 hover:text-slate-700 hover:bg-slate-100 rounded-lg transition-colors cursor-pointer"
                        title={isExpanded ? 'Collapse' : 'Expand'}
                      >
                        {isExpanded ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                      </button>
                    </div>
                  </div>
                </div>

                {/* ── EXPANDED INLINE ACCORDION BREAKDOWN ── */}
                {isExpanded && (
                  <div className="pt-4 border-t border-slate-100 space-y-4 bg-slate-50/80 -mx-5 -mb-5 p-5 rounded-b-2xl animate-in fade-in">
                    {/* Key Metrics Grid */}
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 bg-white p-3.5 rounded-xl border border-slate-200 text-xs shadow-2xs">
                      <div>
                        <span className="text-slate-500 block text-[10px] uppercase font-bold">Total Quoted</span>
                        <span className="font-extrabold text-slate-900 text-sm font-mono">₹{formatMoney(q.net_payable || q.total_amount)}</span>
                      </div>
                      <div>
                        <span className="text-slate-500 block text-[10px] uppercase font-bold">50% Advance Milestone</span>
                        <span className="font-extrabold text-indigo-700 text-sm font-mono">₹{formatMoney(advanceAmount)}</span>
                      </div>
                      <div>
                        <span className="text-slate-500 block text-[10px] uppercase font-bold">50% Completion Balance</span>
                        <span className="font-extrabold text-emerald-700 text-sm font-mono">₹{formatMoney(balanceAmount)}</span>
                      </div>
                      <div>
                        <span className="text-slate-500 block text-[10px] uppercase font-bold">GST Tax (18%)</span>
                        <span className="font-extrabold text-slate-800 text-sm font-mono">₹{formatMoney(q.tax_amount)}</span>
                      </div>
                    </div>

                    {/* Room & Area Measurements */}
                    {measurements.length > 0 && (
                      <div className="bg-white rounded-xl border border-slate-200 overflow-hidden text-xs shadow-2xs">
                        <div className="bg-slate-100/90 px-4 py-2.5 font-bold text-slate-800 flex justify-between items-center">
                          <span className="flex items-center gap-1.5">
                            <Ruler className="w-4 h-4 text-indigo-600" />
                            <span>Room &amp; Surface Measurements</span>
                          </span>
                          <span className="text-indigo-700 font-mono font-black text-xs">Total Area: {totalArea} sq.ft</span>
                        </div>
                        <div className="p-3.5 space-y-2">
                          {measurements.map((m, idx) => (
                            <div key={m.id || idx} className="flex justify-between items-center py-1.5 border-b border-slate-100 last:border-0">
                              <span className="font-medium text-slate-700">
                                <strong>{m.name || `Area #${idx + 1}`}</strong>
                                {m.length && m.width ? ` (${m.length}ft × ${m.width}ft${m.height ? ` × ${m.height}ft` : ''})` : ''}
                              </span>
                              <span className="font-mono font-bold text-slate-900">{m.area || m.calculated_area} sq.ft</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Itemized Line Items */}
                    {items.length > 0 && (
                      <div className="bg-white rounded-xl border border-slate-200 overflow-hidden text-xs shadow-2xs">
                        <div className="bg-slate-100/90 px-4 py-2.5 font-bold text-slate-800 flex justify-between items-center">
                          <span className="flex items-center gap-1.5">
                            <Layers className="w-4 h-4 text-indigo-600" />
                            <span>Itemized Scope &amp; Rate-Card Breakdown</span>
                          </span>
                          <span className="text-slate-500 font-semibold">{items.length} item(s)</span>
                        </div>
                        <div className="divide-y divide-slate-100">
                          {items.map((item, idx) => (
                            <div key={item.id || idx} className="p-3.5 flex justify-between items-start gap-4 hover:bg-slate-50/60 transition-colors">
                              <div>
                                <p className="font-bold text-slate-900 text-xs">{item.name || item.description || 'Quotation Item'}</p>
                                <p className="text-[11px] text-slate-500 mt-0.5">
                                  {item.quantity} {item.unit || 'sqft'} &times; ₹{formatMoney(item.unit_price || item.rate)} / {item.unit || 'sqft'}
                                  {Number(item.tax_rate) > 0 && ` &bull; GST ${item.tax_rate}%`}
                                  {item.section && ` &bull; ${item.section}`}
                                </p>
                              </div>
                              <p className="font-mono font-black text-slate-900 text-sm shrink-0">
                                ₹{formatMoney(item.total_amount || item.line_total)}
                              </p>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Scope Notes */}
                    {q.description && (
                      <div className="bg-white p-3.5 rounded-xl border border-slate-200 text-xs shadow-2xs">
                        <span className="text-slate-500 block text-[10px] uppercase font-bold mb-1">Technician Inspection &amp; Scope Notes</span>
                        <p className="text-slate-700 leading-relaxed">{q.description}</p>
                      </div>
                    )}
                  </div>
                )}

                {/* ── ACTION BUTTONS ROW ── */}
                <div className="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-slate-100">
                  <div className="flex items-center gap-2.5 flex-wrap">
                    {q.status === 'PENDING_REVIEW' ? (
                      <>
                        <button
                          type="button"
                          disabled={busyId === q.id}
                          onClick={() => decide(q, true, 'presend')}
                          className="inline-flex items-center gap-2 rounded-xl bg-slate-900 hover:bg-slate-800 text-white text-xs font-bold px-4 py-2.5 shadow-sm transition-all disabled:opacity-40 cursor-pointer"
                        >
                          {busyId === q.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Send className="w-3.5 h-3.5" />}
                          <span>Release &amp; Send to Customer</span>
                        </button>
                        <button
                          type="button"
                          disabled={busyId === q.id}
                          onClick={() => decide(q, false, 'presend')}
                          className="inline-flex items-center gap-2 rounded-xl border border-slate-300 hover:bg-rose-50 hover:border-rose-300 hover:text-rose-700 text-slate-700 text-xs font-bold px-4 py-2.5 shadow-xs transition-all disabled:opacity-40 cursor-pointer"
                        >
                          <XCircle className="w-3.5 h-3.5" />
                          <span>Reject Quote</span>
                        </button>
                      </>
                    ) : q.status === 'CUSTOMER_ACCEPTED' || q.status === 'PENDING_ADMIN_APPROVAL' ? (
                      <>
                        <button
                          type="button"
                          disabled={busyId === q.id}
                          onClick={() => decide(q, true, 'acceptance')}
                          className="inline-flex items-center gap-2 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold px-4 py-2.5 shadow-sm transition-all disabled:opacity-40 cursor-pointer"
                        >
                          {busyId === q.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <CheckCircle2 className="w-3.5 h-3.5" />}
                          <span>Approve &amp; Issue Work Invoice</span>
                        </button>
                        <button
                          type="button"
                          disabled={busyId === q.id}
                          onClick={() => decide(q, false, 'acceptance')}
                          className="inline-flex items-center gap-2 rounded-xl border border-slate-300 hover:bg-rose-50 hover:border-rose-300 hover:text-rose-700 text-slate-700 text-xs font-bold px-4 py-2.5 shadow-xs transition-all disabled:opacity-40 cursor-pointer"
                        >
                          <XCircle className="w-3.5 h-3.5" />
                          <span>Reject</span>
                        </button>
                      </>
                    ) : (
                      <div className="flex items-center gap-2 text-xs font-semibold text-slate-600">
                        <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                        <span>Status: <strong>{q.status_display || String(q.status || '').replace(/_/g, ' ')}</strong></span>
                      </div>
                    )}
                  </div>

                  <button
                    type="button"
                    onClick={() => setModalQuote(q)}
                    className="text-xs font-bold text-indigo-600 hover:text-indigo-800 transition-colors flex items-center gap-1 cursor-pointer"
                  >
                    <Eye className="w-3.5 h-3.5" />
                    <span>Open Detailed Modal</span>
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ════════════════════════════════════════════════════════════════════════════
          DEDICATED FULL QUOTATION DETAIL & INSPECTION MODAL
         ════════════════════════════════════════════════════════════════════════════ */}
      {modalQuote && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-black/60 backdrop-blur-xs flex items-center justify-center p-3 sm:p-6 animate-in fade-in">
          <div className="bg-white w-full max-w-4xl rounded-2xl shadow-2xl border border-slate-200 flex flex-col max-h-[92vh] overflow-hidden">
            {/* Modal Header */}
            <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-indigo-600 text-white flex items-center justify-center shadow-sm">
                  <Calculator className="w-5 h-5" />
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="text-base font-bold text-slate-900 font-mono">
                      {modalQuote.quote_number}
                    </h3>
                    {modalQuote.quote_version > 1 && (
                      <span className="text-[11px] font-mono bg-indigo-100 text-indigo-800 font-bold px-2 py-0.5 rounded">
                        v{modalQuote.quote_version}
                      </span>
                    )}
                    <span className="text-xs bg-indigo-50 text-indigo-700 font-bold px-2.5 py-0.5 rounded-full border border-indigo-200">
                      {modalQuote.service_category}
                    </span>
                  </div>
                  <p className="text-xs text-slate-500 mt-0.5">
                    {modalQuote.service_name || modalQuote.title} &bull; Job #{modalQuote.job_id || modalQuote.job_request_id}
                  </p>
                </div>
              </div>
              <button
                type="button"
                onClick={() => setModalQuote(null)}
                className="p-2 text-slate-400 hover:text-slate-700 hover:bg-slate-200 rounded-xl transition-colors cursor-pointer"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Modal Body */}
            <div className="p-6 overflow-y-auto space-y-6">
              {/* Top Financial Breakdown Cards */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                <div className="bg-slate-50 p-3.5 rounded-xl border border-slate-200">
                  <span className="text-[10px] uppercase font-bold text-slate-500 block">Total Quoted (Net)</span>
                  <span className="text-lg font-black text-slate-900 font-mono">₹{formatMoney(modalQuote.net_payable || modalQuote.total_amount)}</span>
                </div>
                <div className="bg-indigo-50/60 p-3.5 rounded-xl border border-indigo-200">
                  <span className="text-[10px] uppercase font-bold text-indigo-700 block">50% Advance Milestone</span>
                  <span className="text-lg font-black text-indigo-700 font-mono">
                    ₹{formatMoney(modalQuote.advance_amount || (modalQuote.net_payable ? modalQuote.net_payable * 0.5 : 0))}
                  </span>
                </div>
                <div className="bg-emerald-50/60 p-3.5 rounded-xl border border-emerald-200">
                  <span className="text-[10px] uppercase font-bold text-emerald-700 block">50% Balance on Finish</span>
                  <span className="text-lg font-black text-emerald-700 font-mono">
                    ₹{formatMoney(modalQuote.balance_amount || (modalQuote.net_payable ? modalQuote.net_payable * 0.5 : 0))}
                  </span>
                </div>
                <div className="bg-slate-50 p-3.5 rounded-xl border border-slate-200">
                  <span className="text-[10px] uppercase font-bold text-slate-500 block">GST Tax</span>
                  <span className="text-lg font-black text-slate-800 font-mono">₹{formatMoney(modalQuote.tax_amount)}</span>
                </div>

              {/* Customer & Job Info */}
              <div className="bg-slate-50 p-4 rounded-xl border border-slate-200 grid grid-cols-1 sm:grid-cols-3 gap-4 text-xs">
                <div>
                  <span className="text-[10px] font-bold text-slate-500 uppercase block">Customer</span>
                  <span className="font-bold text-slate-900 text-sm flex items-center gap-1.5 mt-0.5">
                    <User className="w-3.5 h-3.5 text-slate-400" />
                    {modalQuote.customer_name || 'Customer'}
                  </span>
                </div>
                <div>
                  <span className="text-[10px] font-bold text-slate-500 uppercase block">Consultation Booking</span>
                  <span className="font-bold text-slate-900 text-sm flex items-center gap-1.5 mt-0.5">
                    <Calendar className="w-3.5 h-3.5 text-slate-400" />
                    Job #{modalQuote.job_id || modalQuote.job_request_id}
                  </span>
                </div>
                <div>
                  <span className="text-[10px] font-bold text-slate-500 uppercase block">Status</span>
                  <span className="font-bold text-amber-700 text-sm flex items-center gap-1.5 mt-0.5">
                    <Clock className="w-3.5 h-3.5 text-amber-600" />
                    {modalQuote.status === 'PENDING_REVIEW' ? 'Held for CRM Review' : modalQuote.status}
                  </span>
                </div>
              </div>

              {/* Surface / Area Measurements */}
              {Array.isArray(modalQuote.measurements) && modalQuote.measurements.length > 0 && (
                <div className="border border-slate-200 rounded-xl overflow-hidden shadow-2xs">
                  <div className="bg-slate-100 px-4 py-3 font-bold text-slate-800 flex justify-between items-center text-xs">
                    <span className="flex items-center gap-1.5">
                      <Ruler className="w-4 h-4 text-indigo-600" />
                      <span>Surface &amp; Room Dimensions ({modalQuote.measurements.length} Areas)</span>
                    </span>
                    <span className="font-mono font-black text-indigo-700">
                      Total: {modalQuote.measurements.reduce((acc, m) => acc + Number(m.area || m.calculated_area || 0), 0)} sq.ft
                    </span>
                  </div>
                  <div className="p-4 divide-y divide-slate-100">
                    {modalQuote.measurements.map((m, idx) => (
                      <div key={m.id || idx} className="py-2.5 flex justify-between items-center text-xs">
                        <div>
                          <p className="font-bold text-slate-900">{m.name || `Area #${idx + 1}`}</p>
                          <p className="text-[11px] text-slate-500">
                            {m.length && m.width ? `Length: ${m.length}ft &times; Width: ${m.width}ft${m.height ? ` &times; Height: ${m.height}ft` : ''}` : 'Direct area measurement'}
                          </p>
                        </div>
                        <span className="font-mono font-black text-slate-900 text-sm">{m.area || m.calculated_area} sq.ft</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Itemized Line Items */}
              {Array.isArray(modalQuote.items) && modalQuote.items.length > 0 && (
                <div className="border border-slate-200 rounded-xl overflow-hidden shadow-2xs">
                  <div className="bg-slate-100 px-4 py-3 font-bold text-slate-800 flex justify-between items-center text-xs">
                    <span className="flex items-center gap-1.5">
                      <Layers className="w-4 h-4 text-indigo-600" />
                      <span>Itemized Rate-Card &amp; Material Breakdown</span>
                    </span>
                    <span className="text-slate-500 font-semibold">{modalQuote.items.length} Item(s)</span>
                  </div>
                  <div className="divide-y divide-slate-100">
                    {modalQuote.items.map((item, idx) => (
                      <div key={item.id || idx} className="p-4 flex justify-between items-start gap-4 hover:bg-slate-50/60 transition-colors text-xs">
                        <div>
                          <p className="font-bold text-slate-900 text-sm">{item.name || item.description || 'Quotation Line Item'}</p>
                          <p className="text-[11px] text-slate-500 mt-1">
                            {item.quantity} {item.unit || 'sqft'} &times; ₹{formatMoney(item.unit_price || item.rate)} / {item.unit || 'sqft'}
                            {Number(item.tax_rate) > 0 && ` &bull; GST ${item.tax_rate}%`}
                            {item.material_source && ` &bull; Source: ${item.material_source}`}
                          </p>
                        </div>
                        <p className="font-mono font-black text-slate-900 text-base shrink-0">
                          ₹{formatMoney(item.total_amount || item.line_total)}
                        </p>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Technician Notes */}
              {modalQuote.description && (
                <div className="bg-slate-50 p-4 rounded-xl border border-slate-200 text-xs">
                  <span className="text-[10px] uppercase font-bold text-slate-500 block mb-1">Scope &amp; Inspection Findings</span>
                  <p className="text-slate-700 leading-relaxed whitespace-pre-wrap">{modalQuote.description}</p>
                </div>
              )}
            </div>

            {/* Modal Footer */}
            <div className="px-6 py-4 border-t border-slate-200 bg-slate-50 flex items-center justify-between gap-3">
              <button
                type="button"
                onClick={() => setModalQuote(null)}
                className="px-4 py-2.5 rounded-xl border border-slate-300 text-slate-700 text-xs font-bold hover:bg-slate-100 transition-colors cursor-pointer"
              >
                Close
              </button>

              <div className="flex items-center gap-2.5">
                {modalQuote.status === 'PENDING_REVIEW' ? (
                  <>
                    <button
                      type="button"
                      disabled={busyId === modalQuote.id}
                      onClick={() => decide(modalQuote, false, 'presend')}
                      className="inline-flex items-center gap-1.5 rounded-xl border border-rose-300 hover:bg-rose-50 text-rose-700 text-xs font-bold px-4 py-2.5 shadow-xs transition-all disabled:opacity-40 cursor-pointer"
                    >
                      <XCircle className="w-3.5 h-3.5" />
                      <span>Reject Quotation</span>
                    </button>
                    <button
                      type="button"
                      disabled={busyId === modalQuote.id}
                      onClick={() => decide(modalQuote, true, 'presend')}
                      className="inline-flex items-center gap-2 rounded-xl bg-slate-900 hover:bg-slate-800 text-white text-xs font-bold px-5 py-2.5 shadow-sm transition-all disabled:opacity-40 cursor-pointer"
                    >
                      {busyId === modalQuote.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Send className="w-3.5 h-3.5" />}
                      <span>Release &amp; Send to Customer</span>
                    </button>
                  </>
                ) : (
                  <button
                    type="button"
                    disabled={busyId === modalQuote.id}
                    onClick={() => decide(modalQuote, true, 'acceptance')}
                    className="inline-flex items-center gap-2 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold px-5 py-2.5 shadow-sm transition-all disabled:opacity-40 cursor-pointer"
                  >
                    {busyId === modalQuote.id ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <CheckCircle2 className="w-3.5 h-3.5" />}
                    <span>Approve &amp; Issue Invoice</span>
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default AdminQuotationApprovalsPage;
