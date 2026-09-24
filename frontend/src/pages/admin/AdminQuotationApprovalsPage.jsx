/**
 * AdminQuotationApprovalsPage.jsx
 *
 * The SEVO back office's quotation approval queues with full itemized details:
 *
 *   1. Held before sending (Pre-send review):
 *      Quotes held above review threshold or needing clearance. Releasing sends the
 *      quotation to the customer and synchronizes ServiceRequest database state
 *      (cart_data, quote_number, total_amount, status='quotation_sent') for customer approval.
 *      Also supports direct conversion to active service booking.
 *
 *   2. Awaiting SEVO approval (Customer accepted):
 *      The customer has accepted. Approving creates the work booking and issues invoice.
 *
 * Mounted at /workforce/admin/quotations.
 */

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  FileText,
  Layers,
  Loader2,
  RefreshCw,
  Send,
  ShieldCheck,
  Tag,
  User,
  Wrench,
  XCircle,
} from 'lucide-react';
import { apiRequest } from '../../api/client.js';

function money(value) {
  return Number(value || 0).toLocaleString('en-IN', {
    style: 'currency', currency: 'INR', maximumFractionDigits: 0,
  });
}

function ago(iso) {
  if (!iso) return '';
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  if (seconds < 3600) return `${Math.max(1, Math.round(seconds / 60))}m ago`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)}h ago`;
  return `${Math.round(seconds / 86400)}d ago`;
}

const TABS = [
  {
    key: 'presend',
    label: 'Held before sending',
    endpoint: '/workforce/quotes/pending-review/',
    blurb: 'Quotation submitted by technician. Releasing synchronizes DB cart_data and sends the quote to customer for approval.',
  },
  {
    key: 'acceptance',
    label: 'Awaiting SEVO approval',
    endpoint: '/workforce/quotes/pending-approval/',
    blurb: 'The customer has accepted. Approving creates the work booking and issues the invoice.',
  },
];

export function AdminQuotationApprovalsPage() {
  const [tab, setTab] = useState('presend');
  const [rows, setRows] = useState([]);
  const [expandedIds, setExpandedIds] = useState(new Set());
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [flash, setFlash] = useState(null);

  const active = useMemo(() => TABS.find((t) => t.key === tab), [tab]);

  const load = useCallback(async () => {
    setIsLoading(true);
    try {
      const data = await apiRequest(active.endpoint);
      const list = Array.isArray(data) ? data : [];
      setRows(list);
      // Auto-expand all items so admin immediately sees full details
      setExpandedIds(new Set(list.map((q) => q.id)));
      setError(null);
    } catch (err) {
      setError(err?.message || 'Could not load the approval queue.');
      setRows([]);
    } finally {
      setIsLoading(false);
    }
  }, [active]);

  useEffect(() => { load(); }, [load]);

  const toggleExpand = (id) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  async function decide(quote, approve, autoConvert = false) {
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
      const path = tab === 'presend'
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

      if (result.auto_converted || (approve && autoConvert)) {
        setFlash(`${quote.quote_number} approved and converted to active service booking #${result.work_job_id || quote.job_id}!`);
      } else if (result.invoice) {
        setFlash(`${quote.quote_number} approved. Invoice ${result.invoice.invoice_number} issued for ${money(result.invoice.total_amount)}.`);
      } else if (tab === 'presend' && approve) {
        setFlash(`${quote.quote_number} released and published to customer for approval. Service cart saved in database!`);
      } else {
        setFlash(`${quote.quote_number} ${approve ? 'approved' : 'rejected'}.`);
      }
      setRows((prev) => prev.filter((r) => r.id !== quote.id));
      setError(null);
    } catch (err) {
      setError(err?.message || `Failed to process ${quote.quote_number}.`);
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="p-6 max-w-5xl mx-auto space-y-6">
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-slate-900 dark:text-white">Quotation Approvals</h1>
          <p className="text-sm text-slate-600 dark:text-slate-400 mt-1">{active.blurb}</p>
        </div>
        <button
          type="button"
          onClick={load}
          className="inline-flex items-center gap-2 text-sm text-slate-700 dark:text-slate-200 border border-slate-300 dark:border-slate-700 rounded-xl px-4 py-2 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors shadow-sm"
        >
          <RefreshCw className={`w-4 h-4 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
      </div>

      {/* Tabs */}
      <div className="flex gap-2 border-b border-slate-200 dark:border-slate-800">
        {TABS.map((t) => (
          <button
            key={t.key}
            type="button"
            onClick={() => { setTab(t.key); setFlash(null); }}
            className={`px-5 py-3 text-sm font-semibold border-b-2 -mb-px transition-colors ${
              t.key === tab
                ? 'border-blue-600 text-blue-600 dark:text-blue-400 dark:border-blue-400'
                : 'border-transparent text-slate-500 hover:text-slate-800 dark:hover:text-slate-200'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {/* Flash Banner */}
      {flash && (
        <div className="bg-emerald-50 dark:bg-emerald-950/40 border border-emerald-200 dark:border-emerald-800 rounded-xl p-4 flex gap-3 animate-in fade-in">
          <CheckCircle2 className="w-5 h-5 text-emerald-600 dark:text-emerald-400 shrink-0 mt-0.5" />
          <p className="text-sm font-medium text-emerald-900 dark:text-emerald-200">{flash}</p>
        </div>
      )}

      {/* Error Banner */}
      {error && (
        <div className="bg-rose-50 dark:bg-rose-950/40 border border-rose-200 dark:border-rose-800 rounded-xl p-4 flex gap-3 animate-in fade-in">
          <AlertTriangle className="w-5 h-5 text-rose-600 dark:text-rose-400 shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm font-medium text-rose-900 dark:text-rose-200">{error}</p>
            <button type="button" onClick={load} className="text-xs font-semibold text-rose-700 dark:text-rose-300 underline mt-1">
              Try again
            </button>
          </div>
        </div>
      )}

      {/* Content */}
      {isLoading ? (
        <div className="py-20 flex flex-col items-center justify-center text-slate-400 gap-3">
          <Loader2 className="w-6 h-6 animate-spin text-blue-600" />
          <span className="text-sm font-medium">Loading quotations...</span>
        </div>
      ) : rows.length === 0 ? (
        <div className="py-20 text-center border-2 border-dashed border-slate-200 dark:border-slate-800 rounded-2xl">
          <FileText className="w-10 h-10 text-slate-300 dark:text-slate-600 mx-auto mb-3" />
          <p className="text-base font-semibold text-slate-700 dark:text-slate-300">Nothing waiting in this queue</p>
          <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">All quotations have been processed or released.</p>
        </div>
      ) : (
        <div className="space-y-4">
          {rows.map((q) => {
            const isExpanded = expandedIds.has(q.id);
            const items = Array.isArray(q.items) ? q.items : [];
            const ac = q.ac_details;
            const matSubtotal = q.estimated_materials_cost || items.reduce((acc, it) => {
              const sec = String(it.section || '').toUpperCase();
              return (!['LABOUR', 'LABOR', 'SERVICE', 'ADJUSTMENT'].includes(sec) && it.item_type !== 'labor')
                ? acc + (parseFloat(it.total_amount) || 0)
                : acc;
            }, 0);
            const labSubtotal = q.estimated_labor_cost || items.reduce((acc, it) => {
              const sec = String(it.section || '').toUpperCase();
              return (['LABOUR', 'LABOR', 'SERVICE', 'ADJUSTMENT'].includes(sec) || it.item_type === 'labor')
                ? acc + (parseFloat(it.total_amount) || 0)
                : acc;
            }, 0);

            return (
              <div
                key={q.id}
                className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl shadow-sm hover:shadow-md transition-all overflow-hidden"
              >
                {/* Header Summary */}
                <div className="p-5 flex flex-wrap items-start justify-between gap-4 bg-slate-50/50 dark:bg-slate-800/30 border-b border-slate-100 dark:border-slate-800">
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-base font-bold text-slate-900 dark:text-white">
                        {q.quote_number}
                      </span>
                      {q.quote_version > 1 && (
                        <span className="text-[11px] font-bold bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 px-2 py-0.5 rounded-full">
                          v{q.quote_version}
                        </span>
                      )}
                      <span className="text-[11px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-300">
                        {tab === 'presend' ? 'Held for Pre-send Review' : (q.status_display || q.status)}
                      </span>
                      {q.requires_structural_clearance && !q.is_structurally_cleared && (
                        <span className="text-[11px] font-bold bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300 px-2 py-0.5 rounded-full">
                          Structural clearance needed
                        </span>
                      )}
                    </div>

                    <p className="text-sm font-semibold text-slate-800 dark:text-slate-200 mt-1">
                      {q.service_name || q.title || 'AC Inspection & Estimation'}
                    </p>

                    <div className="flex items-center gap-3 text-xs text-slate-500 dark:text-slate-400 mt-1.5 flex-wrap">
                      <span className="inline-flex items-center gap-1 font-medium">
                        <User className="w-3.5 h-3.5 text-slate-400" />
                        {q.customer_name || 'Customer'}
                      </span>
                      {q.technician_name && (
                        <span className="inline-flex items-center gap-1 font-medium text-slate-600 dark:text-slate-300">
                          <Wrench className="w-3.5 h-3.5 text-blue-500" />
                          {q.technician_name}
                        </span>
                      )}
                      <span className="inline-flex items-center gap-1">
                        <Tag className="w-3.5 h-3.5 text-slate-400" />
                        Job #{q.job_id} &middot; {q.service_category}
                      </span>
                      {q.updated_at && (
                        <span>&middot; updated {ago(q.updated_at)}</span>
                      )}
                    </div>
                  </div>

                  {/* Net Amount & Toggle */}
                  <div className="flex items-center gap-4">
                    <div className="text-right shrink-0">
                      <p className="text-xl font-extrabold text-slate-900 dark:text-white">
                        {money(q.net_payable || q.total_amount)}
                      </p>
                      <p className="text-xs text-slate-500 dark:text-slate-400">
                        incl. GST {money(q.tax_amount)}
                      </p>
                    </div>

                    <button
                      type="button"
                      onClick={() => toggleExpand(q.id)}
                      className="p-2 rounded-xl text-slate-500 hover:text-slate-800 dark:hover:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
                      title={isExpanded ? 'Hide details' : 'Show details'}
                    >
                      {isExpanded ? <ChevronUp className="w-5 h-5" /> : <ChevronDown className="w-5 h-5" />}
                    </button>
                  </div>
                </div>

                {/* Full Details Section */}
                {isExpanded && (
                  <div className="p-5 space-y-5 bg-white dark:bg-slate-900">
                    {/* AC Details if present */}
                    {ac && (
                      <div className="p-4 rounded-xl bg-slate-50 dark:bg-slate-800/60 border border-slate-200 dark:border-slate-700/80">
                        <h4 className="text-xs font-bold uppercase tracking-wider text-slate-600 dark:text-slate-300 mb-3 flex items-center gap-1.5">
                          <Layers className="w-4 h-4 text-blue-500" />
                          AC Inspection & Unit Specifications
                        </h4>
                        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                          <div>
                            <span className="text-slate-500 dark:text-slate-400 block text-[11px]">Brand / Make</span>
                            <span className="font-semibold text-slate-800 dark:text-slate-200">{ac.ac_brand || 'General / Multi'}</span>
                          </div>
                          <div>
                            <span className="text-slate-500 dark:text-slate-400 block text-[11px]">AC Type</span>
                            <span className="font-semibold text-slate-800 dark:text-slate-200">{ac.ac_type || 'Split AC'}</span>
                          </div>
                          <div>
                            <span className="text-slate-500 dark:text-slate-400 block text-[11px]">Tonnage / Qty</span>
                            <span className="font-semibold text-slate-800 dark:text-slate-200">
                              {ac.ac_capacity ? ac.ac_capacity.replace(/_/g, ' ') : '1.5 TON'} ({ac.ac_quantity || 1} Unit)
                            </span>
                          </div>
                          <div>
                            <span className="text-slate-500 dark:text-slate-400 block text-[11px]">Inspection Fee</span>
                            <span className="font-semibold text-emerald-600 dark:text-emerald-400">
                              {q.customer_inspection?.diagnostic_fee ? `₹${q.customer_inspection.diagnostic_fee} (Credited)` : 'Credited / Waived'}
                            </span>
                          </div>
                        </div>

                        {ac.customer_symptom && (
                          <div className="mt-3 pt-3 border-t border-slate-200 dark:border-slate-700/60 text-xs">
                            <span className="text-slate-500 dark:text-slate-400 font-medium">Customer Reported Symptom: </span>
                            <span className="font-medium text-slate-800 dark:text-slate-200">{ac.customer_symptom}</span>
                          </div>
                        )}
                      </div>
                    )}

                    {/* Line Items Table */}
                    <div>
                      <h4 className="text-xs font-bold uppercase tracking-wider text-slate-600 dark:text-slate-300 mb-2 flex items-center justify-between">
                        <span>Quoted Line Items ({items.length})</span>
                        <span className="text-[11px] font-normal text-slate-500">From Rate Card & Technician Findings</span>
                      </h4>

                      {items.length === 0 ? (
                        <p className="text-xs text-slate-500 py-3 italic">No line items recorded on this quote.</p>
                      ) : (
                        <div className="border border-slate-200 dark:border-slate-700 rounded-xl overflow-hidden shadow-sm">
                          <table className="w-full text-left text-xs">
                            <thead className="bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 font-semibold border-b border-slate-200 dark:border-slate-700">
                              <tr>
                                <th className="p-3">Scope / Item</th>
                                <th className="p-3">Category</th>
                                <th className="p-3 text-center">Qty & Unit</th>
                                <th className="p-3 text-right">Unit Rate</th>
                                <th className="p-3 text-right">Tax (GST)</th>
                                <th className="p-3 text-right">Line Total</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100 dark:divide-slate-800 bg-white dark:bg-slate-900">
                              {items.map((item, idx) => {
                                const isLabor = ['LABOUR', 'LABOR', 'SERVICE', 'ADJUSTMENT'].includes(String(item.section || '').toUpperCase()) || item.item_type === 'labor';
                                const isGas = item.item_type === 'gas' || String(item.name || '').toLowerCase().includes('gas');
                                const tag = isLabor ? 'LABOUR' : isGas ? 'GAS CHARGE' : 'SPARE PART';
                                const tagClass = isLabor
                                  ? 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300'
                                  : isGas
                                  ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-300'
                                  : 'bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-300';

                                return (
                                  <tr key={item.id || idx} className="hover:bg-slate-50/60 dark:hover:bg-slate-800/40 transition-colors">
                                    <td className="p-3 font-medium text-slate-900 dark:text-slate-100">
                                      {item.name}
                                      {item.description && (
                                        <p className="text-[11px] text-slate-500 dark:text-slate-400 font-normal mt-0.5">{item.description}</p>
                                      )}
                                    </td>
                                    <td className="p-3">
                                      <span className={`text-[10px] font-bold px-2 py-0.5 rounded ${tagClass}`}>
                                        {tag}
                                      </span>
                                    </td>
                                    <td className="p-3 text-center text-slate-700 dark:text-slate-300">
                                      {item.quantity} {item.unit || 'unit'}
                                    </td>
                                    <td className="p-3 text-right text-slate-700 dark:text-slate-300 font-mono">
                                      ₹{Number(item.unit_price || 0).toLocaleString()}
                                    </td>
                                    <td className="p-3 text-right text-slate-500 font-mono">
                                      {item.tax_rate || 18}%
                                    </td>
                                    <td className="p-3 text-right font-bold text-slate-900 dark:text-slate-100 font-mono">
                                      ₹{Number(item.total_amount || 0).toLocaleString()}
                                    </td>
                                  </tr>
                                );
                              })}
                            </tbody>
                          </table>
                        </div>
                      )}
                    </div>

                    {/* Financial Summary Cards */}
                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 p-4 rounded-xl bg-slate-50 dark:bg-slate-800/40 border border-slate-200 dark:border-slate-700/80">
                      <div>
                        <span className="text-[11px] font-medium text-slate-500 dark:text-slate-400 block">Materials / Parts</span>
                        <span className="text-sm font-bold text-slate-800 dark:text-slate-200">
                          {money(matSubtotal)}
                        </span>
                      </div>
                      <div>
                        <span className="text-[11px] font-medium text-slate-500 dark:text-slate-400 block">Labour Subtotal</span>
                        <span className="text-sm font-bold text-slate-800 dark:text-slate-200">
                          {money(labSubtotal)}
                        </span>
                      </div>
                      <div>
                        <span className="text-[11px] font-medium text-slate-500 dark:text-slate-400 block">GST Tax (18%)</span>
                        <span className="text-sm font-bold text-slate-800 dark:text-slate-200">
                          {money(q.tax_amount)}
                        </span>
                      </div>
                      <div>
                        <span className="text-[11px] font-medium text-slate-500 dark:text-slate-400 block">Net Customer Total</span>
                        <span className="text-base font-extrabold text-blue-600 dark:text-blue-400">
                          {money(q.net_payable || q.total_amount)}
                        </span>
                      </div>
                    </div>

                    {/* Dual Action Decision Bar */}
                    <div className="pt-3 border-t border-slate-100 dark:border-slate-800 flex flex-wrap items-center justify-between gap-3">
                      <div className="text-xs text-slate-500 dark:text-slate-400 flex items-center gap-1.5">
                        <ShieldCheck className="w-4 h-4 text-emerald-500" />
                        {tab === 'presend'
                          ? 'Releasing sends to customer & saves items into ServiceRequest database for customer approval.'
                          : 'Approving converts quotation into confirmed booking and generates invoice.'}
                      </div>

                      <div className="flex items-center gap-2 flex-wrap">
                        {tab === 'presend' ? (
                          <>
                            {/* Primary Action: Release & Send to Customer */}
                            <button
                              type="button"
                              disabled={busyId === q.id}
                              onClick={() => decide(q, true, false)}
                              className="inline-flex items-center gap-2 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold px-4 py-2.5 shadow-sm shadow-emerald-600/20 disabled:opacity-40 transition-colors cursor-pointer"
                              title="Release and send to customer for approval (saves service cart in DB)"
                            >
                              {busyId === q.id ? (
                                <Loader2 className="w-4 h-4 animate-spin" />
                              ) : (
                                <Send className="w-4 h-4" />
                              )}
                              Release & Send to Customer
                            </button>

                            {/* Secondary Action: Direct Convert to Service Booking */}
                            <button
                              type="button"
                              disabled={busyId === q.id}
                              onClick={() => decide(q, true, true)}
                              className="inline-flex items-center gap-2 rounded-xl bg-blue-600 hover:bg-blue-700 text-white text-xs font-bold px-4 py-2.5 shadow-sm shadow-blue-600/20 disabled:opacity-40 transition-colors cursor-pointer"
                              title="Directly approve and convert into an active service booking"
                            >
                              <CheckCircle2 className="w-4 h-4" />
                              Approve & Convert to Service
                            </button>
                          </>
                        ) : (
                          /* Acceptance tab action */
                          <button
                            type="button"
                            disabled={busyId === q.id}
                            onClick={() => decide(q, true, false)}
                            className="inline-flex items-center gap-2 rounded-xl bg-slate-900 hover:bg-slate-800 text-white text-xs font-bold px-4 py-2.5 shadow-sm disabled:opacity-40 transition-colors cursor-pointer"
                          >
                            {busyId === q.id ? (
                              <Loader2 className="w-4 h-4 animate-spin" />
                            ) : (
                              <CheckCircle2 className="w-4 h-4" />
                            )}
                            Approve & Issue Invoice
                          </button>
                        )}

                        {/* Reject / Send Back Action */}
                        <button
                          type="button"
                          disabled={busyId === q.id}
                          onClick={() => decide(q, false, false)}
                          className="inline-flex items-center gap-1.5 rounded-xl border border-rose-300 dark:border-rose-800 text-rose-700 dark:text-rose-400 hover:bg-rose-50 dark:hover:bg-rose-950/40 text-xs font-semibold px-3 py-2.5 disabled:opacity-40 transition-colors cursor-pointer"
                          title="Reject or request revisions"
                        >
                          <XCircle className="w-4 h-4" />
                          Reject
                        </button>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default AdminQuotationApprovalsPage;
