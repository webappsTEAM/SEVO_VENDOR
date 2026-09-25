/**
 * CustomerQuotationDecisionPage.jsx
 * Sections:
 *  1. Quote header and status
 *  2. AC Inspection Details (brand, type, capacity, diagnostic fee) from DB
 *  3. Spare Parts and Repair Rate Card (collapsible, grouped) from DB
 *  4. Line items from the quote
 *  5. Payment schedule
 *  6. Accept / Decline / Request Changes
 */
import React, { useCallback, useEffect, useState } from "react";
import { useParams } from "react-router-dom";
import {
  AlertCircle,
  CheckCircle2,
  ChevronDown,
  ChevronUp,
  ClipboardList,
  Clock,
  FileText,
  Loader2,
  MessageSquare,
  Package,
  Settings,
  ShieldCheck,
  Wrench,
  XCircle,
  Zap,
} from "lucide-react";
import { apiRequest } from "../../api/client.js";

const WARRANTY_LABELS = {
  NONE: null,
  "5_YEAR": "5-Year Warranty",
  "10_YEAR": "10-Year Warranty",
};

const SERVICE_TYPE_LABELS = {
  SPARE_PART: "Spare Part",
  REPAIR: "Repair",
  LABOUR: "Labour",
  INSTALLATION: "Installation",
  ADJUSTMENT: "Adjustment",
  GAS_CHARGE: "Gas Charge",
};

const SERVICE_TYPE_COLORS = {
  SPARE_PART: "bg-blue-50 text-blue-700 border-blue-200",
  REPAIR: "bg-amber-50 text-amber-700 border-amber-200",
  LABOUR: "bg-purple-50 text-purple-700 border-purple-200",
  INSTALLATION: "bg-emerald-50 text-emerald-700 border-emerald-200",
  GAS_CHARGE: "bg-cyan-50 text-cyan-700 border-cyan-200",
};

const AC_TYPE_LABELS = {
  SPLIT: "Split AC", WINDOW: "Window AC",
  CASSETTE: "Cassette AC", PORTABLE: "Portable AC",
};

const AC_CAPACITY_LABELS = {
  "0.75_TON": "0.75 Ton", "1_TON": "1 Ton",
  "1.5_TON": "1.5 Ton", "2_TON": "2 Ton",
  "2.5_TON": "2.5 Ton", "3_TON": "3 Ton",
};

function money(v) {
  return Number(v || 0).toLocaleString("en-IN", {
    style: "currency", currency: "INR", maximumFractionDigits: 2,
  });
}

function formatDate(iso) {
  if (!iso) return null;
  try {
    return new Date(iso).toLocaleDateString("en-IN", {
      day: "numeric", month: "short", year: "numeric",
    });
  } catch { return null; }
}

export function CustomerQuotationDecisionPage() {
  const { token } = useParams();
  const [quote, setQuote] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);
  const [pendingAction, setPendingAction] = useState(null);
  const [notes, setNotes] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [outcome, setOutcome] = useState(null);
  const [rateCardOpen, setRateCardOpen] = useState(false);

  const load = useCallback(async () => {
    if (!token) return;
    setIsLoading(true);
    try {
      const data = await apiRequest(`/workforce/quotes/decision/${token}/`);
      setQuote(data);
      setError(null);
    } catch (err) {
      setError(err?.message || "This quotation link is not valid or has expired.");
    } finally {
      setIsLoading(false);
    }
  }, [token]);

  useEffect(() => { load(); }, [load]);

  async function submit(action, payload = {}) {
    setIsSubmitting(true);
    try {
      const result = await apiRequest(`/workforce/quotes/decision/${token}/`, {
        method: "POST",
        json: { action, ...payload },
      });
      setOutcome(result);
      setQuote((prev) => ({ ...prev, ...(result.quote || {}), can_decide: false }));
      setPendingAction(null);
      setNotes("");
    } catch (err) {
      setError(err?.message || "We could not record your decision. Please try again.");
    } finally {
      setIsSubmitting(false);
    }
  }

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50">
        <Loader2 className="w-6 h-6 animate-spin text-slate-400" />
      </div>
    );
  }

  if (error && !quote) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50 px-4">
        <div className="max-w-md w-full bg-white rounded-2xl border border-slate-200 p-8 text-center">
          <AlertCircle className="w-10 h-10 text-amber-500 mx-auto mb-4" />
          <h1 className="text-lg font-semibold text-slate-900 mb-2">
            This quotation is not available
          </h1>
          <p className="text-sm text-slate-600">{error}</p>
          <p className="text-sm text-slate-500 mt-4">
            If you were expecting a quotation, please contact the technician who visited you.
          </p>
        </div>
      </div>
    );
  }

  const items = quote?.items || [];
  const invoice = quote?.invoice;
  const advance = invoice?.advance_amount;
  const balance = invoice?.balance_amount;
  const showsSplit = Number(balance || 0) > 0;
  const acInfo = quote?.ac_inspection_details;
  const rateCard = quote?.rate_card || [];
  const totalRateItems = rateCard.reduce((acc, c) => acc + c.items.length, 0);

  return (
    <div className="min-h-screen bg-slate-50 py-6 px-4">
      <div className="max-w-2xl mx-auto space-y-4">

        {/* 1. HEADER */}
        <div className="bg-white rounded-2xl border border-slate-200 p-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <p className="text-xs uppercase tracking-wide text-slate-500 mb-1">Quotation</p>
              <h1 className="text-xl font-semibold text-slate-900">{quote.quote_number}</h1>
              <p className="text-sm text-slate-600 mt-1">
                {quote.service_name || quote.title}
                {quote.quote_version > 1 && (
                  <span className="ml-2 text-xs text-slate-500">revision {quote.quote_version}</span>
                )}
              </p>
            </div>
            <StatusBadge quote={quote} />
          </div>
          {quote.valid_until && quote.can_decide && (
            <p className="text-xs text-slate-500 mt-4 flex items-center gap-1.5">
              <Clock className="w-3.5 h-3.5" />
              Valid until {formatDate(quote.valid_until)}
            </p>
          )}
        </div>

        {outcome && (
          <div className="bg-emerald-50 border border-emerald-200 rounded-2xl p-5 flex gap-3">
            <CheckCircle2 className="w-5 h-5 text-emerald-600 shrink-0 mt-0.5" />
            <div>
              <p className="text-sm font-medium text-emerald-900">{outcome.message}</p>
              {outcome.awaiting_admin_approval && (
                <p className="text-xs text-emerald-800 mt-1">Nothing further is needed from you right now.</p>
              )}
            </div>
          </div>
        )}

        {error && quote && (
          <div className="bg-rose-50 border border-rose-200 rounded-2xl p-4 flex gap-3">
            <AlertCircle className="w-5 h-5 text-rose-600 shrink-0 mt-0.5" />
            <p className="text-sm text-rose-900">{error}</p>
          </div>
        )}

        {/* 2. AC INSPECTION DETAILS */}
        {acInfo && (
          <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden">
            <div className="px-6 py-4 border-b border-slate-100 flex items-center gap-2 bg-indigo-50/60">
              <Settings className="w-4 h-4 text-indigo-500" />
              <h2 className="text-sm font-semibold text-indigo-900">AC Inspection Details</h2>
            </div>
            <div className="px-6 py-5 grid grid-cols-2 sm:grid-cols-3 gap-4">
              {acInfo.ac_brand && <InfoCell label="Brand" value={acInfo.ac_brand} />}
              {acInfo.ac_type && (
                <InfoCell label="Type" value={AC_TYPE_LABELS[acInfo.ac_type] || acInfo.ac_type} />
              )}
              {acInfo.ac_capacity && (
                <InfoCell label="Capacity" value={AC_CAPACITY_LABELS[acInfo.ac_capacity] || acInfo.ac_capacity} />
              )}
              {acInfo.quantity > 1 && (
                <InfoCell label="Units" value={`${acInfo.quantity} AC`} />
              )}
              <InfoCell label="Diagnostic Fee" value={money(acInfo.diagnostic_fee)} highlight />
              {acInfo.customer_symptom && (
                <div className="col-span-2 sm:col-span-3">
                  <p className="text-[11px] font-medium text-slate-500 uppercase tracking-wider mb-1">Reported Issue</p>
                  <p className="text-sm text-slate-700">{acInfo.customer_symptom}</p>
                </div>
              )}
              {acInfo.customer_notes && (
                <div className="col-span-2 sm:col-span-3">
                  <p className="text-[11px] font-medium text-slate-500 uppercase tracking-wider mb-1">Notes</p>
                  <p className="text-sm text-slate-700">{acInfo.customer_notes}</p>
                </div>
              )}
            </div>
            <div className="px-6 py-3 bg-indigo-50/40 border-t border-slate-100">
              <p className="text-xs text-indigo-700">
                The diagnostic fee of <strong>{money(acInfo.diagnostic_fee)}</strong> is credited
                against the final repair cost if you accept this quotation.
              </p>
            </div>
          </div>
        )}

        {/* 3. SPARE PARTS AND RATE CARD */}
        {rateCard.length > 0 && (
          <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden">
            <button
              type="button"
              id="rate-card-toggle"
              onClick={() => setRateCardOpen((o) => !o)}
              className="w-full px-6 py-4 border-b border-slate-100 flex items-center justify-between gap-2 hover:bg-slate-50 transition-colors"
            >
              <div className="flex items-center gap-2">
                <Package className="w-4 h-4 text-amber-500" />
                <h2 className="text-sm font-semibold text-slate-900">
                  Spare Parts &amp; Repair Rate Card
                </h2>
                <span className="text-xs text-slate-500 font-normal">({totalRateItems} items)</span>
              </div>
              <div className="flex items-center gap-1 text-xs text-slate-500">
                {rateCardOpen
                  ? <><ChevronUp className="w-4 h-4" /> Hide</>
                  : <><ChevronDown className="w-4 h-4" /> View all rates</>}
              </div>
            </button>
            {!rateCardOpen && (
              <p className="px-6 py-3 text-xs text-slate-500">
                Pre-agreed rates for your AC type. Only items selected by the technician appear in the quote above.
              </p>
            )}
            {rateCardOpen && (
              <div className="divide-y divide-slate-100">
                {rateCard.map((group) => (
                  <div key={group.category}>
                    <div className="px-6 py-2.5 bg-slate-50 flex items-center gap-2">
                      <CategoryIcon category={group.category} />
                      <span className="text-xs font-bold text-slate-700 uppercase tracking-wide">
                        {group.category}
                      </span>
                    </div>
                    <div className="divide-y divide-slate-50">
                      {group.items.map((item, idx) => (
                        <div key={idx} className="px-6 py-3 flex items-center justify-between gap-4">
                          <div className="min-w-0 flex-1">
                            <div className="flex items-center gap-2 flex-wrap">
                              <p className="text-sm text-slate-800">{item.name}</p>
                              {item.service_type && item.service_type !== "ADJUSTMENT" && (
                                <span className={`text-[10px] font-medium px-2 py-0.5 rounded-full border ${
                                  SERVICE_TYPE_COLORS[item.service_type] || "bg-slate-100 text-slate-600 border-slate-200"
                                }`}>
                                  {SERVICE_TYPE_LABELS[item.service_type] || item.service_type}
                                </span>
                              )}
                            </div>
                            {item.description && (
                              <p className="text-xs text-slate-500 mt-0.5">{item.description}</p>
                            )}
                          </div>
                          <div className="text-right shrink-0">
                            {item.price === 0
                              ? <p className="text-sm font-medium text-emerald-600">Free</p>
                              : <p className="text-sm font-semibold text-slate-900">{money(item.price)}</p>}
                            {item.unit && (
                              <p className="text-[11px] text-slate-500">per {item.unit}</p>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                ))}
                <div className="px-6 py-3 bg-amber-50 border-t border-amber-100">
                  <p className="text-xs text-amber-800 flex items-start gap-1.5">
                    <ShieldCheck className="w-3.5 h-3.5 mt-0.5 shrink-0 text-amber-600" />
                    Only items the technician selects appear in your final quote. Rates are fixed with no hidden charges.
                  </p>
                </div>
              </div>
            )}
          </div>
        )}

        {/* 4. LINE ITEMS */}
        <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden">
          <div className="px-6 py-4 border-b border-slate-100 flex items-center gap-2">
            <ClipboardList className="w-4 h-4 text-slate-400" />
            <h2 className="text-sm font-medium text-slate-900">What is included in this quote</h2>
          </div>
          {items.length === 0 ? (
            <p className="px-6 py-8 text-sm text-slate-500 text-center">No line items on this quotation.</p>
          ) : (
            <div className="divide-y divide-slate-100">
              {items.map((item) => (
                <div key={item.id} className="px-6 py-4 flex justify-between gap-4">
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-slate-900">{item.name}</p>
                    {item.description && (
                      <p className="text-xs text-slate-500 mt-0.5">{item.description}</p>
                    )}
                    <p className="text-xs text-slate-500 mt-1">
                      {item.quantity} {item.unit} x {money(item.unit_price)}
                    </p>
                    {WARRANTY_LABELS[item.warranty_tier] && (
                      <span className="inline-flex items-center gap-1 mt-2 text-xs text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full">
                        <ShieldCheck className="w-3 h-3" />
                        {WARRANTY_LABELS[item.warranty_tier]}
                      </span>
                    )}
                  </div>
                  <p className="text-sm font-medium text-slate-900 whitespace-nowrap">
                    {money(item.total_amount)}
                  </p>
                </div>
              ))}
            </div>
          )}
          <div className="px-6 py-4 bg-slate-50 border-t border-slate-100 space-y-2">
            <Row label="Subtotal" value={money(quote.subtotal_amount)} />
            {Number(quote.discount_amount) > 0 && (
              <Row label="Discount" value={`- ${money(quote.discount_amount)}`} />
            )}
            <Row label="GST" value={money(quote.tax_amount)} />
            {Number(quote.inspection_fee_adjusted) > 0 && (
              <Row label="Inspection fee credited" value={`- ${money(quote.inspection_fee_adjusted)}`} />
            )}
            <div className="pt-2 border-t border-slate-200 flex justify-between">
              <span className="text-sm font-semibold text-slate-900">Total</span>
              <span className="text-lg font-semibold text-slate-900">
                {money(quote.net_payable || quote.total_amount)}
              </span>
            </div>
          </div>
        </div>

        {/* 5. PAYMENT SCHEDULE */}
        {invoice && showsSplit && (
          <div className="bg-white rounded-2xl border border-slate-200 p-6">
            <div className="flex items-center gap-2 mb-4">
              <FileText className="w-4 h-4 text-slate-400" />
              <h2 className="text-sm font-medium text-slate-900">Payment schedule</h2>
            </div>
            <div className="space-y-2">
              <Row label={`Advance (${Number(invoice.advance_percent)}%)`} value={money(advance)} emphasis />
              <Row label="Balance on completion" value={money(balance)} />
            </div>
            <p className="text-xs text-slate-500 mt-4">
              The advance covers materials bought before work begins. Work is scheduled once it is received.
            </p>
          </div>
        )}

        {/* 6. ACTIONS */}
        {quote.can_decide && !outcome && (
          <div className="bg-white rounded-2xl border border-slate-200 p-6 space-y-3">
            {pendingAction ? (
              <div className="space-y-3">
                <label className="block text-sm font-medium text-slate-900">
                  {pendingAction === "DECLINE"
                    ? "Could you tell us why? (optional)"
                    : "What would you like changed?"}
                </label>
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={3}
                  className="w-full rounded-xl border border-slate-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-slate-900/10"
                  placeholder={
                    pendingAction === "DECLINE"
                      ? "Price, timing, or anything else"
                      : "e.g. use a different brand, exclude a repair"
                  }
                />
                <div className="flex gap-2">
                  <button
                    type="button"
                    id="quote-submit-btn"
                    disabled={isSubmitting || (pendingAction === "REQUEST_CHANGES" && !notes.trim())}
                    onClick={() => submit(pendingAction, { notes, reason: pendingAction === "DECLINE" ? notes : "" })}
                    className="flex-1 rounded-xl bg-slate-900 text-white text-sm font-medium py-3 disabled:opacity-40"
                  >
                    {isSubmitting ? "Sending..." : "Send"}
                  </button>
                  <button
                    type="button"
                    onClick={() => { setPendingAction(null); setNotes(""); }}
                    className="rounded-xl border border-slate-300 text-slate-700 text-sm font-medium px-5"
                  >
                    Back
                  </button>
                </div>
              </div>
            ) : (
              <>
                <button
                  type="button"
                  id="quote-accept-btn"
                  disabled={isSubmitting}
                  onClick={() => submit("ACCEPT")}
                  className="w-full rounded-xl bg-emerald-600 text-white text-sm font-semibold py-3.5 flex items-center justify-center gap-2 disabled:opacity-40"
                >
                  <CheckCircle2 className="w-4 h-4" />
                  {isSubmitting
                    ? "Approving..."
                    : showsSplit
                      ? `Approve - advance ${money(advance)}`
                      : `Approve ${money(quote.net_payable || quote.total_amount)}`}
                </button>
                <button
                  type="button"
                  id="quote-changes-btn"
                  onClick={() => setPendingAction("REQUEST_CHANGES")}
                  className="w-full rounded-xl border border-slate-300 text-slate-800 text-sm font-medium py-3 flex items-center justify-center gap-2"
                >
                  <MessageSquare className="w-4 h-4" />
                  Request changes
                </button>
                <button
                  type="button"
                  id="quote-decline-btn"
                  onClick={() => setPendingAction("DECLINE")}
                  className="w-full text-slate-500 text-sm py-2 flex items-center justify-center gap-2"
                >
                  <XCircle className="w-4 h-4" />
                  Decline
                </button>
              </>
            )}
          </div>
        )}

        {!quote.can_decide && !outcome && (
          <div className="bg-white rounded-2xl border border-slate-200 p-6 text-center">
            <p className="text-sm text-slate-600">
              {quote.is_expired
                ? "This quotation has expired. Please ask the technician to send a fresh one."
                : "This quotation has already been actioned."}
            </p>
          </div>
        )}

        <p className="text-center text-xs text-slate-400 pb-6">
          Quotation issued by SEVO. Questions? Reply to the message this link came in.
        </p>
      </div>
    </div>
  );
}

function InfoCell({ label, value, highlight }) {
  return (
    <div>
      <p className="text-[11px] font-medium text-slate-500 uppercase tracking-wider mb-0.5">{label}</p>
      <p className={`text-sm font-semibold ${highlight ? "text-indigo-700" : "text-slate-800"}`}>
        {value}
      </p>
    </div>
  );
}

function CategoryIcon({ category }) {
  const c = (category || "").toLowerCase();
  if (c.includes("gas") || c.includes("refriger")) return <Zap className="w-3.5 h-3.5 text-cyan-500" />;
  if (c.includes("fan") || c.includes("motor")) return <Settings className="w-3.5 h-3.5 text-indigo-500" />;
  if (c.includes("install")) return <Wrench className="w-3.5 h-3.5 text-emerald-500" />;
  if (c.includes("electr")) return <Zap className="w-3.5 h-3.5 text-amber-500" />;
  return <Package className="w-3.5 h-3.5 text-slate-400" />;
}

function Row({ label, value, emphasis }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-slate-600">{label}</span>
      <span className={emphasis ? "font-semibold text-slate-900" : "text-slate-900"}>{value}</span>
    </div>
  );
}

function StatusBadge({ quote }) {
  const map = {
    SENT_TO_CUSTOMER: ["Awaiting your decision", "bg-blue-50 text-blue-700"],
    PENDING_ADMIN_APPROVAL: ["Approved - with SEVO", "bg-amber-50 text-amber-700"],
    ADMIN_APPROVED: ["Approved", "bg-emerald-50 text-emerald-700"],
    CONVERTED: ["Scheduled", "bg-emerald-50 text-emerald-700"],
    CHANGES_REQUESTED: ["Changes requested", "bg-amber-50 text-amber-700"],
    DECLINED: ["Declined", "bg-slate-100 text-slate-600"],
    ADMIN_REJECTED: ["Not approved", "bg-slate-100 text-slate-600"],
    EXPIRED: ["Expired", "bg-slate-100 text-slate-600"],
    SUPERSEDED: ["Replaced by a newer version", "bg-slate-100 text-slate-600"],
  };
  const [label, classes] = map[quote.status] || [quote.status_display || quote.status, "bg-slate-100 text-slate-600"];
  return (
    <span className={`shrink-0 text-xs font-medium px-3 py-1.5 rounded-full ${classes}`}>
      {label}
    </span>
  );
}

export default CustomerQuotationDecisionPage;
