import React, { useEffect, useRef, useState } from 'react';
import { Receipt } from 'lucide-react';
import { apiGetLogisticsExtraChargeOptions, apiReportLogisticsExtraCharge } from '../../../api/workforceService.js';

// Toll / parking receipts. Shown only when the Admin policy enables pass-through for this trip.
export function TripExtraChargeReporter({ jobId }) {
  const [opts, setOpts] = useState(null);
  const [open, setOpen] = useState(false);
  const [type, setType] = useState('');
  const [amount, setAmount] = useState('');
  const [receipt, setReceipt] = useState('');
  const [photo, setPhoto] = useState(null);
  const [busy, setBusy] = useState(false);
  const inFlight = useRef(false);
  const chargeId = useRef('');
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');

  const load = () => apiGetLogisticsExtraChargeOptions(jobId).then(setOpts).catch(() => setOpts(null));
  useEffect(() => { load(); /* eslint-disable-next-line */ }, [jobId]);

  const types = opts?.enabled ? Object.entries(opts.types || {}) : [];
  if (types.length === 0) return null;

  const max = opts.max_amount_per_item != null ? Number(opts.max_amount_per_item) : null;
  const amountNum = Number(amount);
  const amountBad = !(amountNum > 0) || (max != null && amountNum > max);

  const submit = async () => {
    if (inFlight.current) return; // double-tap guard (state updates are async)
    inFlight.current = true;
    if (!chargeId.current) chargeId.current = (globalThis.crypto?.randomUUID?.() || `${Date.now()}${Math.random().toString(36).slice(2, 10)}`).replace(/[^A-Za-z0-9]/g, '').slice(0, 32);
    setBusy(true); setErr(''); setMsg('');
    try {
      await apiReportLogisticsExtraCharge(jobId, { chargeType: type, amount, receipt, photo, chargeId: chargeId.current });
      chargeId.current = '';
      setMsg('Added. The customer pays this at actuals and you are reimbursed in full.');
      setOpen(false); setAmount(''); setReceipt(''); setPhoto(null);
      load();
    } catch (e) {
      setErr(e?.message || 'Could not add the charge. Please retry.');
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  };

  return (
    <div className="pt-1 border-t border-slate-100">
      {msg && <div className="text-xs text-emerald-700 font-semibold mb-1">{msg}</div>}
      {Number(opts.applied_total) > 0 && (
        <div className="text-xs text-slate-600 mb-1">Toll / parking added so far: Rs. {opts.applied_total}</div>
      )}
      {!open ? (
        <button type="button" onClick={() => { setOpen(true); setType(types[0][0]); }}
          className="text-xs font-bold text-sky-700 flex items-center gap-1 cursor-pointer">
          <Receipt className="w-3.5 h-3.5" /> Add toll / parking receipt
        </button>
      ) : (
        <div className="space-y-2">
          <select value={type} onChange={(e) => setType(e.target.value)} disabled={busy}
            className="w-full py-2 px-2.5 bg-white border border-slate-300 rounded-lg text-xs">
            {types.map(([code, label]) => <option key={code} value={code}>{label}</option>)}
          </select>
          <input type="number" inputMode="decimal" min="0.01" step="0.01" max={max ?? undefined} value={amount} onChange={(e) => setAmount(e.target.value)}
            placeholder="Amount on receipt (Rs.)" disabled={busy} className="w-full p-2 border border-slate-300 rounded-lg text-xs" />
          {max != null && amountNum > max && <div className="text-xs text-red-600">A single receipt cannot exceed Rs. {opts.max_amount_per_item}.</div>}
          <input type="file" accept="image/*" capture="environment" disabled={busy}
            onChange={(e) => setPhoto(e.target.files?.[0] || null)} className="w-full text-xs" />
          <input type="text" value={receipt} onChange={(e) => setReceipt(e.target.value)} maxLength={500}
            placeholder={opts.require_receipt_photo ? "Receipt number (optional)" : "Receipt number, if no photo"} className="w-full p-2 border border-slate-300 rounded-lg text-xs" />
          {err && <div className="text-xs text-red-600">{err}</div>}
          <div className="flex gap-2">
            <button type="button" onClick={submit} disabled={busy || amountBad || (opts.require_receipt_photo ? !photo : (!photo && receipt.trim().length < 2))}
              className="py-2 px-3 bg-sky-600 disabled:opacity-50 text-white font-bold text-xs rounded-lg cursor-pointer">Add charge</button>
            <button type="button" onClick={() => setOpen(false)} disabled={busy}
              className="py-2 px-3 border border-slate-300 text-xs rounded-lg cursor-pointer">Cancel</button>
          </div>
        </div>
      )}
    </div>
  );
}

export default TripExtraChargeReporter;
