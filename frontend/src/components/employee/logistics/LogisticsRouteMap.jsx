/**
 * LogisticsRouteMap.jsx
 *
 * Pickup + drop + live vehicle position for Goods & Transport / Packers &
 * Movers jobs, shown in the technician's job details.
 *
 * Renders NOTHING for non-logistics jobs (gated by the same isLogisticsJob()
 * used by LogisticsLegController, and again by the backend's is_logistics
 * flag, which comes from LOGISTICS_SERVICE_CATEGORIES).
 *
 * Data source: the existing /workforce/jobs/<id>/live-tracking/ endpoint
 * (apiGetJobLiveTracking), which already authorises the assigned technician
 * and returns the live position from the active JobTrackingSession (falling
 * back to user.last_known_location). pickup_location / drop_location are
 * additive fields on that response. Map rendering uses the app's existing
 * Google Maps loader (loadMapsApi) -- no new mapping dependency.
 */
import React, { useEffect, useRef, useState } from 'react';
import { MapPin, Navigation } from 'lucide-react';
import { loadMapsApi } from '../../../utils/loadGoogleMaps.js';
import { apiGetJobLiveTracking } from '../../../api/customerTrackingApi.js';
import { isLogisticsJob } from './LogisticsLegController.jsx';

const POLL_MS = 10000;

function toPoint(loc) {
  const lat = Number(loc?.latitude);
  const lng = Number(loc?.longitude);
  if (!loc || loc.latitude == null || loc.longitude == null || !Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

function dotIcon(maps, color) {
  return {
    path: maps.SymbolPath.CIRCLE,
    scale: 8,
    fillColor: color,
    fillOpacity: 1,
    strokeColor: '#ffffff',
    strokeWeight: 2,
  };
}

export function LogisticsRouteMap({ job, className = '' }) {
  const isLogistics = !!job && isLogisticsJob(job);
  const jobId = job?.id;

  const containerRef = useRef(null);
  const mapRef = useRef(null);
  const markersRef = useRef({ pickup: null, drop: null, vehicle: null });
  const fittedRef = useRef(false);

  const [tracking, setTracking] = useState(null);
  const [mapError, setMapError] = useState('');

  // Reset when switching jobs.
  useEffect(() => {
    fittedRef.current = false;
    Object.values(markersRef.current).forEach((m) => m && m.setMap(null));
    markersRef.current = { pickup: null, drop: null, vehicle: null };
    mapRef.current = null;
    setTracking(null);
  }, [jobId]);

  // Poll the existing live-tracking endpoint.
  // Guard: the backend gates live-tracking on job assignment (403 if not
  // assigned). Only poll when this job is actually assigned to the current
  // technician; for offer/unassigned logistics jobs we render the static
  // pickup/drop pins from fare_breakdown instead.
  const isAssigned = !!job?.is_assigned_to_current_employee;
  useEffect(() => {
    if (!isLogistics || !jobId || !isAssigned) return undefined;
    let cancelled = false;
    const load = () => {
      apiGetJobLiveTracking(jobId)
        .then((res) => { if (!cancelled && res) setTracking(res); })
        .catch(() => { /* keep last known data */ });
    };
    load();
    const t = setInterval(load, POLL_MS);
    return () => { cancelled = true; clearInterval(t); };
  }, [isLogistics, jobId, isAssigned]);

  // Backend is authoritative: if it says this is not a logistics job, hide.
  const backendSaysNotLogistics = tracking && tracking.is_logistics === false;

  const pickup = toPoint(tracking?.pickup_location)
    || toPoint({ latitude: job?.latitude, longitude: job?.longitude });
  const drop = toPoint(tracking?.drop_location)
    || toPoint({ latitude: job?.drop_latitude, longitude: job?.drop_longitude });
  const vehicle = toPoint(tracking?.assigned_technician?.location);

  const pickupAddress = tracking?.pickup_location?.address || job?.address || '';
  const dropAddress = tracking?.drop_location?.address || job?.drop_address || '';

  // Create/update the map and markers.
  useEffect(() => {
    if (!isLogistics || backendSaysNotLogistics || !containerRef.current) return undefined;
    if (!pickup && !drop && !vehicle) return undefined;
    let cancelled = false;
    loadMapsApi()
      .then((maps) => {
        if (cancelled || !containerRef.current) return;
        if (!mapRef.current) {
          mapRef.current = new maps.Map(containerRef.current, {
            center: pickup || drop || vehicle,
            zoom: 13,
            disableDefaultUI: true,
            zoomControl: true,
            gestureHandling: 'cooperative',
          });
        }
        const map = mapRef.current;
        const upsert = (key, pos, color, title, label) => {
          const existing = markersRef.current[key];
          if (!pos) {
            if (existing) { existing.setMap(null); markersRef.current[key] = null; }
            return;
          }
          if (existing) {
            existing.setPosition(pos);
          } else {
            markersRef.current[key] = new maps.Marker({
              position: pos, map, title, icon: dotIcon(maps, color),
              label: label ? { text: label, color: '#ffffff', fontSize: '10px', fontWeight: '700' } : undefined,
              zIndex: key === 'vehicle' ? 30 : 20,
            });
          }
        };
        upsert('pickup', pickup, '#059669', 'Pickup', 'P');
        upsert('drop', drop, '#dc2626', 'Drop', 'D');
        upsert('vehicle', vehicle, '#2563eb', 'Your live location', null);

        if (!fittedRef.current) {
          const pts = [pickup, drop, vehicle].filter(Boolean);
          if (pts.length > 1) {
            const b = new maps.LatLngBounds();
            pts.forEach((p) => b.extend(p));
            map.fitBounds(b, 40);
          } else {
            map.setCenter(pts[0]);
          }
          fittedRef.current = true;
        }
        setMapError('');
      })
      .catch((err) => { if (!cancelled) setMapError(err?.message || 'Map unavailable'); });
    return () => { cancelled = true; };
  }, [
    isLogistics, backendSaysNotLogistics,
    pickup?.lat, pickup?.lng, drop?.lat, drop?.lng, vehicle?.lat, vehicle?.lng,
  ]);

  if (!isLogistics || backendSaysNotLogistics) return null;

  const navLink = (p) => (p ? `https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}` : null);

  return (
    <div className={`p-4 bg-white border border-slate-200 rounded-xl space-y-3 ${className}`}>
      <span className="text-[10px] text-slate-400 font-bold uppercase tracking-wider flex items-center gap-1">
        <MapPin className="w-3.5 h-3.5 text-blue-600" />
        <span>Trip Map</span>
      </span>

      {mapError ? (
        <p className="text-xs text-slate-500">Map unavailable: {mapError}</p>
      ) : (pickup || drop || vehicle) ? (
        <div ref={containerRef} className="w-full h-56 rounded-lg overflow-hidden bg-slate-100" />
      ) : (
        <p className="text-xs text-slate-500">Location coordinates not available for this trip yet.</p>
      )}

      <div className="flex flex-wrap gap-3 text-[11px] font-semibold text-slate-600">
        <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-emerald-600" />Pickup</span>
        <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-red-600" />Drop</span>
        <span className="flex items-center gap-1">
          <span className="w-2.5 h-2.5 rounded-full bg-blue-600" />
          {vehicle ? 'You (live)' : 'You (no live GPS yet)'}
        </span>
      </div>

      <div className="space-y-2 text-xs">
        <div className="flex items-start justify-between gap-2">
          <p className="text-slate-700"><strong className="text-emerald-700">Pickup:</strong> {pickupAddress || 'Not provided'}</p>
          {navLink(pickup) && (
            <a href={navLink(pickup)} target="_blank" rel="noopener noreferrer" className="shrink-0 inline-flex items-center gap-1 text-sky-700 font-bold hover:underline">
              <Navigation className="w-3 h-3" />Navigate
            </a>
          )}
        </div>
        <div className="flex items-start justify-between gap-2">
          <p className="text-slate-700"><strong className="text-red-700">Drop:</strong> {dropAddress || 'Not provided'}</p>
          {navLink(drop) && (
            <a href={navLink(drop)} target="_blank" rel="noopener noreferrer" className="shrink-0 inline-flex items-center gap-1 text-sky-700 font-bold hover:underline">
              <Navigation className="w-3 h-3" />Navigate
            </a>
          )}
        </div>
      </div>
    </div>
  );
}

export default LogisticsRouteMap;
