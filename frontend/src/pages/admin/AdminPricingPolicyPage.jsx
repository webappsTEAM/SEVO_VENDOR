/**
 * AdminPricingPolicyPage.jsx
 *
 * Where the SEVO admin sets the commercial rules that used to be constants in
 * the code: what a site visit costs, when a quote needs review before the
 * customer sees it, and how much of an invoice is payable up front.
 *
 * One row per service category. Mounted at /workforce/admin/pricing.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, CheckCircle2, Loader2, RefreshCw, Save } from 'lucide-react';
import { apiRequest } from '../../api/client.js';

const MODES = [
  { value: 'FREE', label: 'Always free' },
  { value: 'FLAT', label: 'Flat fee' },
  { value: 'DISTANCE_BAND', label: 'Free within radius, fee beyond' },
];

export function AdminPricingPolicyPage() {
  const [policies, setPolicies] = useState([]);
  const [drafts, setDrafts] = useState({});
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);
  const [savingId, setSavingId] = useState(null);
  const [flash, setFlash] = useState(null);

  const load = useCallback(async () => {
    setIsLoading(true);
    try {
      const data = await apiRequest('/workforce/settings/pricing-policies/');
      const rows = Array.isArray(data) ? data : [];
      setPolicies(rows);
      setDrafts(Object.fromEntries(rows.map((p) => [p.id, { ...p }])));
      setError(null);
    } catch (err) {
      setError(err?.message || 'Could not load pricing policies.');
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  function edit(id, field, value) {
    setDrafts((prev) => ({ ...prev, [id]: { ...prev[id], [field]: value } }));
  }

  function isDirty(p) {
    const d = drafts[p.id];
    if (!d) return false;
    return Object.keys(d).some((k) => String(d[k]) !== String(p[k]));
  }

  async function save(policy) {
    const d = drafts[policy.id];
    setSavingId(policy.id);
    try {
      const updated = await apiRequest(`/workforce/settings/pricing-policies/${policy.id}/`, {
        method: 'PATCH',
        json: {
          display_name: d.display_name,
          consultation_fee_mode: d.consultation_fee_mode,
          consultation_fee_amount: d.consultation_fee_amount,
          free_radius_km: d.free_radius_km,
          beyond_radius_amount: d.beyond_radius_amount,
          high_value_review_threshold:
            d.high_value_review_threshold === '' || d.high_value_review_threshold === null
              ? null
              : d.high_value_review_threshold,
          requires_admin_approval: !!d.requires_admin_approval,
          advance_percent: d.advance_percent,
          allow_customer_supplied_materials: !!d.allow_customer_supplied_materials,
          is_active: !!d.is_active,
          waiting_free_loading_minutes: blankToNull(d.waiting_free_loading_minutes),
          waiting_free_unloading_minutes: blankToNull(d.waiting_free_unloading_minutes),
          waiting_charge_per_minute:
            d.waiting_charge_per_minute === '' || d.waiting_charge_per_minute == null
              ? 0
              : d.waiting_charge_per_minute,
          waiting_charge_cap: blankToNull(d.waiting_charge_cap),
          // Blank is sent as null; the backend resets it to the default (5).
          technician_free_cancel_minutes: blankToNull(d.technician_free_cancel_minutes),
        },
      });
      setPolicies((prev) => prev.map((p) => (p.id === updated.id ? updated : p)));
      setDrafts((prev) => ({ ...prev, [updated.id]: { ...updated } }));
      setFlash(`${updated.display_name || updated.service_category} saved.`);
      setError(null);
    } catch (err) {
      setError(err?.message || 'Could not save this policy.');
    } finally {
      setSavingId(null);
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold text-slate-900">Pricing &amp; approval rules</h1>
          <p className="text-sm text-slate-600 mt-1">
            Applies to new quotations and bookings. Invoices already issued keep the
            figures they were issued with.
          </p>
        </div>
        <button
          type="button"
          onClick={load}
          className="inline-flex items-center gap-2 text-sm text-slate-600 border border-slate-300 rounded-lg px-3 py-2"
        >
          <RefreshCw className={`w-4 h-4 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
      </div>

      {flash && (
        <div className="mb-4 bg-emerald-50 border border-emerald-200 rounded-xl p-4 flex gap-3">
          <CheckCircle2 className="w-5 h-5 text-emerald-600 shrink-0 mt-0.5" />
          <p className="text-sm text-emerald-900">{flash}</p>
        </div>
      )}

      {error && (
        <div className="mb-4 bg-rose-50 border border-rose-200 rounded-xl p-4 flex gap-3">
          <AlertTriangle className="w-5 h-5 text-rose-600 shrink-0 mt-0.5" />
          <div className="flex-1">
            <p className="text-sm text-rose-900">{error}</p>
            <button type="button" onClick={load} className="text-sm text-rose-700 underline mt-1">
              Try again
            </button>
          </div>
        </div>
      )}

      {isLoading ? (
        <div className="py-16 flex justify-center">
          <Loader2 className="w-5 h-5 animate-spin text-slate-400" />
        </div>
      ) : policies.length === 0 ? (
        <p className="py-16 text-center text-sm text-slate-500">
          No pricing policies configured.
        </p>
      ) : (
        <div className="space-y-4">
          {policies.map((p) => {
            const d = drafts[p.id] || p;
            const dirty = isDirty(p);
            return (
              <div key={p.id} className="bg-white border border-slate-200 rounded-xl p-5">
                <div className="flex items-center justify-between mb-4">
                  <div>
                    <h2 className="font-medium text-slate-900">
                      {p.display_name || p.service_category}
                    </h2>
                    <p className="text-xs text-slate-500">{p.service_category}</p>
                  </div>
                  <button
                    type="button"
                    disabled={!dirty || savingId === p.id}
                    onClick={() => save(p)}
                    className="inline-flex items-center gap-2 rounded-lg bg-slate-900 text-white text-sm font-medium px-4 py-2 disabled:opacity-30"
                  >
                    {savingId === p.id
                      ? <Loader2 className="w-4 h-4 animate-spin" />
                      : <Save className="w-4 h-4" />}
                    Save
                  </button>
                </div>

                <div className="grid gap-4 sm:grid-cols-2">
                  <Field label="Consultation fee">
                    <select
                      value={d.consultation_fee_mode}
                      onChange={(e) => edit(p.id, 'consultation_fee_mode', e.target.value)}
                      className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
                    >
                      {MODES.map((m) => (
                        <option key={m.value} value={m.value}>{m.label}</option>
                      ))}
                    </select>
                  </Field>

                  {d.consultation_fee_mode === 'FLAT' && (
                    <Field label="Fee amount (₹)">
                      <NumberInput
                        value={d.consultation_fee_amount}
                        onChange={(v) => edit(p.id, 'consultation_fee_amount', v)}
                      />
                    </Field>
                  )}

                  {d.consultation_fee_mode === 'DISTANCE_BAND' && (
                    <>
                      <Field label="Free within (km)">
                        <NumberInput
                          value={d.free_radius_km}
                          onChange={(v) => edit(p.id, 'free_radius_km', v)}
                        />
                      </Field>
                      <Field label="Fee beyond that (₹)">
                        <NumberInput
                          value={d.beyond_radius_amount}
                          onChange={(v) => edit(p.id, 'beyond_radius_amount', v)}
                        />
                      </Field>
                    </>
                  )}

                  <Field
                    label="Review quotes above (₹)"
                    hint="Blank means no pre-send review for this category."
                  >
                    <NumberInput
                      value={d.high_value_review_threshold ?? ''}
                      onChange={(v) => edit(p.id, 'high_value_review_threshold', v)}
                      allowEmpty
                    />
                  </Field>

                  <Field label="Advance payable (%)" hint="100 bills the whole invoice up front.">
                    <NumberInput
                      value={d.advance_percent}
                      onChange={(v) => edit(p.id, 'advance_percent', v)}
                    />
                  </Field>
                </div>

                {/* GT audit fix: this fieldset used to render for EVERY
                    service category's pricing policy (HVAC, plumbing,
                    etc.), showing "loading/unloading" waiting-charge fields
                    that make no sense outside Goods Transport. Scoped to the
                    distance-priced GT categories (Mini Truck, Two Wheeler --
                    previously Mini Truck only, leaving admins unable to see
                    or configure Two Wheeler's waiting-charge estimate at
                    all). The copy was also confirmed misleading: these
                    fields drive only the technician app's live estimate
                    display (services/waiting_charges.py) -- the customer's
                    actual GT waiting/detention charge is billed from a
                    separate policy in the Customer app (Settings > (Django)
                    Admin > Service Requests > GT Waiting Charge Policies),
                    which should be kept in step with these numbers by
                    whoever sets them. */}
                {['goods_transport_truck', 'goods_transport_two_wheeler'].includes(String(p.service_category || '').trim().toLowerCase()) && (
                  <fieldset className="mt-4 border-t border-slate-100 pt-4">
                    <legend className="text-sm font-medium text-slate-900 mb-1">
                      Goods Transport waiting time (driver app estimate)
                    </legend>
                    <p className="text-xs text-slate-500 mb-3">
                      Measured from the driver's loading/unloading status updates and shown to
                      the driver as a live estimate while the trip is in progress. Leave the
                      free-minute fields blank or the rate at 0 to show no charge. This does
                      <strong> not </strong> bill the customer by itself -- the customer's actual
                      delivery invoice is billed from the separate GT Waiting Charge Policy in
                      the Customer app's admin. Keep both configured with the same free minutes
                      and rate so the driver's estimate matches what the customer is actually
                      charged.
                    </p>
                    <div className="grid gap-4 sm:grid-cols-2">
                      <Field label="Free loading time (min)" hint="Blank disables the loading estimate.">
                        <NumberInput
                          step="1"
                          value={d.waiting_free_loading_minutes ?? ''}
                          onChange={(v) => edit(p.id, 'waiting_free_loading_minutes', v)}
                          allowEmpty
                        />
                      </Field>
                      <Field label="Free unloading time (min)" hint="Blank disables the unloading estimate.">
                        <NumberInput
                          step="1"
                          value={d.waiting_free_unloading_minutes ?? ''}
                          onChange={(v) => edit(p.id, 'waiting_free_unloading_minutes', v)}
                          allowEmpty
                        />
                      </Field>
                      <Field label="Charge per extra minute (₹)">
                        <NumberInput
                          value={d.waiting_charge_per_minute ?? 0}
                          onChange={(v) => edit(p.id, 'waiting_charge_per_minute', v)}
                        />
                      </Field>
                      <Field label="Maximum waiting charge (₹)" hint="Blank means no cap.">
                        <NumberInput
                          value={d.waiting_charge_cap ?? ''}
                          onChange={(v) => edit(p.id, 'waiting_charge_cap', v)}
                          allowEmpty
                        />
                      </Field>
                    </div>
                  </fieldset>
                )}

                <fieldset className="mt-4 border-t border-slate-100 pt-4">
                  <legend className="text-sm font-medium text-slate-900 mb-1">
                    Technician cancellation
                  </legend>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <Field
                      label="Free cancellation window (min)"
                      hint="Minutes after accepting during which the technician can cancel without penalty. Blank resets to 5."
                    >
                      <NumberInput
                        step="1"
                        value={d.technician_free_cancel_minutes ?? ''}
                        onChange={(v) => edit(p.id, 'technician_free_cancel_minutes', v)}
                        allowEmpty
                      />
                    </Field>
                  </div>
                </fieldset>

                <div className="mt-4 space-y-2 border-t border-slate-100 pt-4">
                  <Toggle
                    checked={!!d.requires_admin_approval}
                    onChange={(v) => edit(p.id, 'requires_admin_approval', v)}
                    label="SEVO approves accepted quotes before work is scheduled"
                  />
                  <Toggle
                    checked={!!d.allow_customer_supplied_materials}
                    onChange={(v) => edit(p.id, 'allow_customer_supplied_materials', v)}
                    label="Allow customer-supplied materials"
                    hint="Off by default — customer-supplied material voids the workmanship warranty."
                  />
                  <Toggle
                    checked={!!d.is_active}
                    onChange={(v) => edit(p.id, 'is_active', v)}
                    label="Policy active"
                  />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function Field({ label, hint, children }) {
  return (
    <div>
      <label className="block text-sm font-medium text-slate-700 mb-1.5">{label}</label>
      {children}
      {hint && <p className="text-xs text-slate-500 mt-1">{hint}</p>}
    </div>
  );
}

function blankToNull(v) {
  return v === '' || v === null || v === undefined ? null : v;
}

function NumberInput({ value, onChange, allowEmpty, step = '0.01' }) {
  return (
    <input
      type="number"
      step={step}
      min="0"
      value={value === null || value === undefined ? '' : value}
      onChange={(e) => onChange(e.target.value === '' && allowEmpty ? '' : e.target.value)}
      className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm"
    />
  );
}

function Toggle({ checked, onChange, label, hint }) {
  return (
    <label className="flex items-start gap-3 cursor-pointer">
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        className="mt-0.5 w-4 h-4 rounded border-slate-300"
      />
      <span>
        <span className="text-sm text-slate-800">{label}</span>
        {hint && <span className="block text-xs text-slate-500">{hint}</span>}
      </span>
    </label>
  );
}

export default AdminPricingPolicyPage;
