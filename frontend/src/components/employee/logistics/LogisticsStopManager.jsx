import React, { useState, useEffect, useCallback } from 'react';
import {
  MapPin,
  Phone,
  CheckCircle2,
  Clock,
  Navigation,
  RotateCw,
  AlertCircle,
  Flag,
  FileText,
} from 'lucide-react';
import { apiGetJobStops, apiUpdateJobStop } from '../../../api/workforceService.js';

export function LogisticsStopManager({ job, onStopsUpdated, className = '' }) {
  const [stops, setStops] = useState([]);
  const [loading, setLoading] = useState(false);
  const [actionLoadingId, setActionLoadingId] = useState(null);
  const [error, setError] = useState('');

  const loadStops = useCallback(async () => {
    if (!job?.id) return;
    try {
      setLoading(true);
      setError('');
      const data = await apiGetJobStops(job.id);
      if (data && Array.isArray(data.results)) {
        setStops(data.results);
      } else if (Array.isArray(data)) {
        setStops(data);
      }
    } catch (err) {
      // If 400 because non-logistics or 404, silently ignore or show message if explicit
      if (err?.status !== 400 && err?.status !== 404) {
        setError(err?.message || 'Failed to load trip stops.');
      }
    } finally {
      setLoading(false);
    }
  }, [job?.id]);

  useEffect(() => {
    loadStops();
  }, [loadStops]);

  // If no stops exist and trip_stop_count is 0, don't show the multi-stop card
  if (!loading && stops.length === 0 && (!job?.trip_stop_count || job.trip_stop_count === 0)) {
    return null;
  }

  const handleUpdateStop = async (stopId, completed) => {
    setActionLoadingId(stopId);
    setError('');
    try {
      await apiUpdateJobStop(job.id, stopId, completed);
      await loadStops();
      if (onStopsUpdated) {
        onStopsUpdated();
      }
    } catch (err) {
      setError(err?.message || 'Failed to update stop status.');
    } finally {
      setActionLoadingId(null);
    }
  };

  const completedCount = stops.filter((s) => s.completed_at).length;
  const totalCount = stops.length;
  const allCompleted = totalCount > 0 && completedCount === totalCount;

  return (
    <div className={`p-4 rounded-xl border border-indigo-200 bg-linear-to-b from-indigo-50/40 to-white shadow-xs space-y-3.5 ${className}`}>
      {/* Card Header */}
      <div className="flex items-center justify-between gap-2 border-b border-indigo-100 pb-2.5">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-indigo-600 text-white flex items-center justify-center shrink-0 shadow-xs">
            <Navigation className="w-4 h-4" />
          </div>
          <div>
            <div className="flex items-center gap-1.5">
              <h3 className="text-xs font-black text-slate-900 tracking-tight">
                Multi-Stop Route Itinerary
              </h3>
              <span className="text-[10px] font-bold text-indigo-800 bg-indigo-100 px-1.5 py-0.5 rounded">
                {completedCount}/{totalCount} Done
              </span>
            </div>
            <p className="text-[11px] text-slate-500">
              Operate ordered pickups, waypoints, and drop destinations
            </p>
          </div>
        </div>

        {allCompleted ? (
          <span className="text-[10px] font-mono font-black text-emerald-800 bg-emerald-100 px-2 py-1 rounded border border-emerald-300 flex items-center gap-1">
            <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
            <span>All Stops Complete</span>
          </span>
        ) : (
          <button
            type="button"
            onClick={loadStops}
            disabled={loading}
            className="text-[11px] font-bold text-indigo-600 hover:text-indigo-800 flex items-center gap-1 cursor-pointer"
          >
            <RotateCw className={`w-3 h-3 ${loading ? 'animate-spin' : ''}`} />
            <span>Refresh</span>
          </button>
        )}
      </div>

      {/* Error notification */}
      {error && (
        <div className="p-2.5 bg-rose-50 border border-rose-200 rounded-lg text-rose-800 text-[11px] font-medium flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0 text-rose-600" />
          <span>{error}</span>
        </div>
      )}

      {/* Stops List */}
      <div className="space-y-3">
        {stops.map((stop, idx) => {
          const isStopCompleted = Boolean(stop.completed_at);
          const isStopArrived = Boolean(stop.arrived_at && !stop.completed_at);
          const isActionLoading = actionLoadingId === stop.id;

          const stopType = (stop.stop_type || '').toUpperCase();
          const isPickup = stopType === 'PICKUP';
          const isDrop = stopType === 'DROP';
          const isWaypoint = !isPickup && !isDrop;

          const typeBadge = isPickup ? (
            <span className="text-[10px] font-bold text-emerald-800 bg-emerald-100 px-2 py-0.5 rounded border border-emerald-200">
              Pickup #{(stop.sequence != null ? stop.sequence : idx + 1)}
            </span>
          ) : isDrop ? (
            <span className="text-[10px] font-bold text-rose-800 bg-rose-100 px-2 py-0.5 rounded border border-rose-200">
              Drop #{(stop.sequence != null ? stop.sequence : idx + 1)}
            </span>
          ) : (
            <span className="text-[10px] font-bold text-indigo-800 bg-indigo-100 px-2 py-0.5 rounded border border-indigo-200">
              Waypoint #{(stop.sequence != null ? stop.sequence : idx + 1)}
            </span>
          );

          return (
            <div
              key={stop.id || idx}
              className={`p-3.5 rounded-xl border transition-all space-y-2.5 ${
                isStopCompleted
                  ? 'bg-emerald-50/40 border-emerald-300'
                  : isStopArrived
                  ? 'bg-amber-50/50 border-amber-300 shadow-xs'
                  : 'bg-white border-slate-200'
              }`}
            >
              {/* Header row: sequence, type, status */}
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <div className={`w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-black ${
                    isStopCompleted
                      ? 'bg-emerald-600 text-white'
                      : isStopArrived
                      ? 'bg-amber-500 text-white'
                      : 'bg-slate-200 text-slate-700'
                  }`}>
                    {stop.sequence != null ? stop.sequence : idx + 1}
                  </div>
                  {typeBadge}
                </div>

                {/* Status indicator */}
                {isStopCompleted ? (
                  <span className="text-[11px] font-bold text-emerald-800 flex items-center gap-1">
                    <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
                    <span>Completed</span>
                  </span>
                ) : isStopArrived ? (
                  <span className="text-[11px] font-bold text-amber-800 flex items-center gap-1">
                    <Clock className="w-3.5 h-3.5 text-amber-600" />
                    <span>Arrived at Stop</span>
                  </span>
                ) : (
                  <span className="text-[11px] font-bold text-slate-400">
                    Pending
                  </span>
                )}
              </div>

              {/* Address */}
              <div className="text-xs text-slate-800 font-medium leading-relaxed pl-7">
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-start gap-1.5">
                    <MapPin className="w-3.5 h-3.5 text-slate-400 shrink-0 mt-0.5" />
                    <span>{stop.address || 'Address not specified'}</span>
                  </div>
                  {stop.address && (
                    <a
                      href={`https://maps.google.com/?q=${encodeURIComponent(stop.address)}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-[11px] font-bold text-sky-700 hover:text-sky-900 shrink-0 flex items-center gap-1 hover:underline"
                    >
                      <Navigation className="w-3 h-3" />
                      <span>Map</span>
                    </a>
                  )}
                </div>
              </div>

              {/* Contact info & Notes */}
              {(stop.contact_name || stop.contact_phone || stop.notes) && (
                <div className="pl-7 space-y-1.5 pt-1 border-t border-slate-100">
                  {(stop.contact_name || stop.contact_phone) && (
                    <div className="flex items-center justify-between text-[11px]">
                      <span className="text-slate-600">
                        Contact: <strong className="text-slate-800">{stop.contact_name || 'Site Contact'}</strong>
                      </span>
                      {stop.contact_phone && (
                        <a
                          href={`tel:${stop.contact_phone}`}
                          className="px-2 py-0.5 bg-emerald-50 text-emerald-800 border border-emerald-300 rounded font-bold hover:bg-emerald-100 transition-all flex items-center gap-1"
                        >
                          <Phone className="w-3 h-3 text-emerald-600" />
                          <span>{stop.contact_phone}</span>
                        </a>
                      )}
                    </div>
                  )}

                  {stop.notes && (
                    <div className="p-2 bg-slate-50 border border-slate-200 rounded text-[11px] text-slate-600 flex items-start gap-1.5">
                      <FileText className="w-3 h-3 text-slate-400 shrink-0 mt-0.5" />
                      <span>{stop.notes}</span>
                    </div>
                  )}
                </div>
              )}

              {/* Operational Action Buttons */}
              {!isStopCompleted && (
                <div className="pl-7 pt-1 flex items-center gap-2">
                  {!isStopArrived ? (
                    <>
                      <button
                        type="button"
                        onClick={() => handleUpdateStop(stop.id, false)}
                        disabled={isActionLoading}
                        className="py-1.5 px-3 bg-amber-500 hover:bg-amber-600 active:bg-amber-700 disabled:opacity-50 text-white font-bold text-xs rounded-lg shadow-2xs transition-all flex items-center gap-1.5 cursor-pointer"
                      >
                        {isActionLoading ? (
                          <RotateCw className="w-3 h-3 animate-spin" />
                        ) : (
                          <Clock className="w-3 h-3" />
                        )}
                        <span>Mark Arrived</span>
                      </button>
                      <button
                        type="button"
                        onClick={() => handleUpdateStop(stop.id, true)}
                        disabled={isActionLoading}
                        className="py-1.5 px-3 bg-emerald-600 hover:bg-emerald-700 active:bg-emerald-800 disabled:opacity-50 text-white font-bold text-xs rounded-lg shadow-2xs transition-all flex items-center gap-1.5 cursor-pointer"
                      >
                        {isActionLoading ? (
                          <RotateCw className="w-3 h-3 animate-spin" />
                        ) : (
                          <CheckCircle2 className="w-3 h-3" />
                        )}
                        <span>Mark Completed</span>
                      </button>
                    </>
                  ) : (
                    <button
                      type="button"
                      onClick={() => handleUpdateStop(stop.id, true)}
                      disabled={isActionLoading}
                      className="py-1.5 px-4 bg-emerald-600 hover:bg-emerald-700 active:bg-emerald-800 disabled:opacity-50 text-white font-bold text-xs rounded-lg shadow-2xs transition-all flex items-center gap-1.5 cursor-pointer"
                    >
                      {isActionLoading ? (
                        <RotateCw className="w-3 h-3 animate-spin" />
                      ) : (
                        <CheckCircle2 className="w-3 h-3" />
                      )}
                      <span>Complete This Stop</span>
                    </button>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default LogisticsStopManager;
