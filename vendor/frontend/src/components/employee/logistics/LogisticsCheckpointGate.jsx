import React, { useRef, useState } from 'react';
import { FileText, RotateCw } from 'lucide-react';
import {
  apiVerifyCheckpointGps,
  apiUploadCheckpointPhoto,
  apiVerifyDeliveryOtp,
  apiResendDeliveryOtp,
} from '../../../api/workforceService.js';

// Mid-trip counterpart of the job-start "Pre-Service Verification" card:
// same card layout, same "Verify GPS" / OTP / photo rows. Shown in the leg
// controller when the next stage needs checkpoint evidence; the backend
// (services/logistics_checkpoints.py) is what actually enforces it.

const REQUIREMENT_ORDER = { gps: 0, photo: 1, otp: 2 };

function getPosition() {
  return new Promise((resolve, reject) => {
    if (!navigator?.geolocation) {
      reject(new Error('GPS is not available on this device.'));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve(pos.coords),
      () => reject(new Error('Could not read your GPS location. Allow location access and retry.')),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  });
}

export function LogisticsCheckpointGate({ jobId, targetLabel, missing, onVerified }) {
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const [otp, setOtp] = useState('');
  const fileInputs = useRef({});

  if (!missing || missing.length === 0) return null;
  const items = [...missing].sort(
    (a, b) => (REQUIREMENT_ORDER[a.requirement] ?? 9) - (REQUIREMENT_ORDER[b.requirement] ?? 9),
  );

  const run = async (key, fn) => {
    setBusy(key);
    setError('');
    setInfo('');
    try {
      const res = await fn();
      if (res?.message) setInfo(res.message);
      if (onVerified) onVerified(res);
    } catch (err) {
      setError(err?.message || 'Verification failed. Please retry.');
    } finally {
      setBusy('');
    }
  };

  const verifyGps = (checkpoint) => run(`${checkpoint}-gps`, async () => {
    const c = await getPosition();
    return apiVerifyCheckpointGps(jobId, checkpoint, c.latitude, c.longitude);
  });

  const uploadPhoto = (checkpoint, file) => {
    if (!file) return;
    run(`${checkpoint}-photo`, () => apiUploadCheckpointPhoto(jobId, checkpoint, file));
  };

  return (
    <div className="pt-2 space-y-3" data-testid="logistics-checkpoint-gate">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <FileText className="w-4 h-4 text-slate-700" />
          <h2 className="text-sm font-black text-slate-900 tracking-tight">
            Verification before {targetLabel}
          </h2>
        </div>
        <span className="text-[10px] font-bold text-rose-600 bg-rose-50 px-2 py-0.5 rounded border border-rose-200">
          All Fields Required *
        </span>
      </div>

      {error && (
        <div role="alert" className="p-2.5 bg-rose-50 border border-rose-200 rounded-lg text-rose-800 text-[11px] font-medium">
          {error}
        </div>
      )}
      {info && !error && (
        <div className="p-2.5 bg-emerald-50 border border-emerald-200 rounded-lg text-emerald-800 text-[11px] font-medium">
          {info}
        </div>
      )}

      {items.map((item, idx) => {
        const key = `${item.checkpoint}-${item.requirement}`;
        const where = item.checkpoint === 'PICKUP' ? 'pickup' : 'drop';
        return (
          <div key={key} className="p-3.5 rounded-xl border space-y-2 bg-white border-slate-200">
            <div className="flex items-center justify-between gap-2">
              <span className="text-xs font-bold text-slate-900 flex items-center gap-1">
                <span>{idx + 1}. {item.label}</span>
                <span className="text-rose-600">*</span>
              </span>

              {item.requirement === 'gps' && (
                <button
                  type="button"
                  onClick={() => verifyGps(item.checkpoint)}
                  disabled={!!busy}
                  className="px-3 py-1 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 text-white font-bold rounded text-[11px] cursor-pointer flex items-center gap-1"
                >
                  {busy === key && <RotateCw className="w-3 h-3 animate-spin" />}
                  Verify GPS
                </button>
              )}

              {item.requirement === 'photo' && (
                <>
                  <input
                    type="file"
                    accept="image/*"
                    capture="environment"
                    className="hidden"
                    ref={(el) => { fileInputs.current[key] = el; }}
                    onChange={(e) => { uploadPhoto(item.checkpoint, e.target.files?.[0]); e.target.value = ''; }}
                  />
                  <button
                    type="button"
                    onClick={() => fileInputs.current[key]?.click()}
                    disabled={!!busy}
                    className="px-3 py-1 bg-blue-600 hover:bg-blue-700 disabled:opacity-50 text-white font-bold rounded text-[11px] cursor-pointer flex items-center gap-1"
                  >
                    {busy === key && <RotateCw className="w-3 h-3 animate-spin" />}
                    Capture Photo
                  </button>
                </>
              )}

              {item.requirement === 'otp' && (
                <button
                  type="button"
                  onClick={() => run('resend', () => apiResendDeliveryOtp(jobId))}
                  disabled={!!busy}
                  className="text-[11px] font-bold text-slate-600 hover:text-slate-900 cursor-pointer disabled:opacity-50"
                >
                  Resend OTP
                </button>
              )}
            </div>

            {item.requirement === 'gps' && (
              <p className="text-[11px] text-slate-500">
                Your GPS position must be within 250m of the {where} location.
              </p>
            )}
            {item.requirement === 'photo' && (
              <p className="text-[11px] text-slate-500">
                Photo of the goods {where === 'pickup' ? 'loaded on the vehicle' : 'unloaded at the destination'}. Verify GPS first.
              </p>
            )}
            {item.requirement === 'otp' && (
              <div className="flex items-center gap-2">
                <input
                  type="text"
                  inputMode="numeric"
                  maxLength={6}
                  value={otp}
                  onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
                  placeholder="6-digit delivery OTP *"
                  aria-label="Delivery OTP"
                  className="flex-1 px-3 py-2 bg-slate-100/90 border border-slate-200 rounded-lg text-xs font-mono font-bold text-slate-900 outline-none focus:bg-white focus:border-slate-400"
                />
                <button
                  type="button"
                  onClick={() => run('otp', async () => {
                    const res = await apiVerifyDeliveryOtp(jobId, otp);
                    setOtp('');
                    return res;
                  })}
                  disabled={!!busy || otp.length !== 6}
                  className="px-5 py-2 bg-slate-200 hover:bg-slate-300 text-slate-800 font-bold text-xs rounded-lg transition-all cursor-pointer disabled:opacity-50"
                >
                  Verify
                </button>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

export default LogisticsCheckpointGate;
