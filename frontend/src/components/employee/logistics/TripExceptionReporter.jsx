import React, { useRef, useState } from 'react';
import { AlertTriangle } from 'lucide-react';
import { apiReportLogisticsException } from '../../../api/workforceService.js';

// Which problems can be reported at which trip stage (mirrors the backend rules).
const OPTIONS = [
  { code: 'CUSTOMER_UNREACHABLE_AT_PICKUP', label: 'Customer not reachable at pickup', legs: ['EN_ROUTE_PICKUP', 'LOADING'] },
  { code: 'PICKUP_ADDRESS_ISSUE', label: 'Pickup address not found', legs: ['EN_ROUTE_PICKUP'] },
  { code: 'RECEIVER_UNAVAILABLE', label: 'Receiver not available at drop', legs: ['EN_ROUTE_DROP', 'UNLOADING'] },
  { code: 'RECEIVER_REFUSED', label: 'Receiver refused the delivery', legs: ['EN_ROUTE_DROP', 'UNLOADING'] },
  { code: 'DROP_ADDRESS_ISSUE', label: 'Drop address not found', legs: ['EN_ROUTE_DROP', 'UNLOADING'] },
];

export function TripExceptionReporter({ jobId, currentLeg }) {
  const options = OPTIONS.filter((o) => o.legs.includes(currentLeg));
  const [open, setOpen] = useState(false);
  const [code, setCode] = useState('');
  const [notes, setNotes] = useState('');
  const [busy, setBusy] = useState(false);
  const inFlight = useRef(false);
  const [msg, setMsg] = useState('');
  const [err, setErr] = useState('');
  if (options.length === 0) return null;

  const submit = async () => {
    if (inFlight.current) return; // double-tap guard (state updates are async)
    inFlight.current = true;
    setBusy(true); setErr(''); setMsg('');
    try {
      await apiReportLogisticsException(jobId, code, notes);
      setMsg('Reported. The customer has been notified and support can see it.');
      setOpen(false); setNotes('');
    } catch (e) {
      setErr(e?.message || 'Could not send the report. Please retry.');
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  };

  return (
    <div className="pt-1 border-t border-slate-100">
      {msg && <div className="text-xs text-emerald-700 font-semibold mb-1">{msg}</div>}
      {!open ? (
        <button type="button" onClick={() => { setOpen(true); setCode(options[0].code); }}
          className="text-xs font-bold text-amber-700 flex items-center gap-1 cursor-pointer">
          <AlertTriangle className="w-3.5 h-3.5" /> Report a problem with this trip
        </button>
      ) : (
        <div className="space-y-2">
          <select value={code} onChange={(e) => setCode(e.target.value)} disabled={busy}
            className="w-full py-2 px-2.5 bg-white border border-slate-300 rounded-lg text-xs">
            {options.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}
          </select>
          <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2} maxLength={500}
            placeholder="What happened? (e.g. phone switched off, gate locked)"
            className="w-full p-2 border border-slate-300 rounded-lg text-xs" />
          {err && <div className="text-xs text-red-600">{err}</div>}
          <div className="flex gap-2">
            <button type="button" onClick={submit} disabled={busy || notes.trim().length < 5}
              className="py-2 px-3 bg-amber-600 disabled:opacity-50 text-white font-bold text-xs rounded-lg cursor-pointer">Send report</button>
            <button type="button" onClick={() => setOpen(false)} disabled={busy}
              className="py-2 px-3 border border-slate-300 text-xs rounded-lg cursor-pointer">Cancel</button>
          </div>
        </div>
      )}
    </div>
  );
}

export default TripExceptionReporter;
