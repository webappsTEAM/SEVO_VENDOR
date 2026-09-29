/**
 * logisticsNav.js
 *
 * Pure helpers for a multi-stop Goods & Transport / Packers & Movers trip:
 * which stop the driver should head to next, and Google Maps navigation links that use the
 * stop's exact coordinates (never a re-geocoded address). Mirrors the Customer backend's
 * tracking rule so the driver and the customer always look at the same target:
 *   before pickup is done          -> the pickup
 *   heading out (EN_ROUTE_DROP / IN_TRANSIT) -> the next unfinished stop, Pickup -> Stop 1..n -> Drop
 *   at / after the drop            -> the drop
 */

export const OUTBOUND_LEGS = new Set(['EN_ROUTE_DROP', 'IN_TRANSIT']);
export const POST_PICKUP_LEGS = new Set([
  'EN_ROUTE_DROP', 'UNLOADING', 'DELIVERED', 'IN_TRANSIT', 'ARRIVED_DROP', 'REASSEMBLY', 'UNPACKING', 'COMPLETED',
]);
// Google Maps directions URLs accept at most 9 waypoints.
export const MAX_URL_WAYPOINTS = 9;

export function stopPoint(stop) {
  if (!stop || stop.latitude == null || stop.longitude == null) return null;
  const lat = Number(stop.latitude);
  const lng = Number(stop.longitude);
  return Number.isFinite(lat) && Number.isFinite(lng) ? { lat, lng } : null;
}

export function sortStops(stops) {
  return [...(Array.isArray(stops) ? stops : [])].sort((a, b) => (a.sequence ?? 0) - (b.sequence ?? 0));
}

/** The stop the driver should navigate to now, or null when the stop list is unavailable. */
export function nextTargetStop(stops, leg) {
  const list = sortStops(stops);
  if (!list.length) return null;
  const legKey = String(leg || '').trim().toUpperCase();
  const type = (s) => String(s.stop_type || '').toUpperCase();
  if (!POST_PICKUP_LEGS.has(legKey)) {
    return list.find((s) => type(s) === 'PICKUP') || list[0];
  }
  if (OUTBOUND_LEGS.has(legKey)) {
    const pending = list.find((s) => type(s) !== 'PICKUP' && !s.completed_at);
    if (pending) return pending;
  }
  const drops = list.filter((s) => type(s) === 'DROP');
  return drops.length ? drops[drops.length - 1] : list[list.length - 1];
}

export function navUrl(point) {
  return point ? `https://www.google.com/maps/dir/?api=1&destination=${point.lat},${point.lng}&travelmode=driving` : null;
}

/** One link for the whole remaining route: origin = current position (Maps default), waypoints in order. */
export function routeUrl(points) {
  const pts = (points || []).filter(Boolean);
  if (pts.length < 2) return navUrl(pts[0] || null);
  const dest = pts[pts.length - 1];
  const via = pts.slice(0, -1).slice(0, MAX_URL_WAYPOINTS);
  return `https://www.google.com/maps/dir/?api=1&destination=${dest.lat},${dest.lng}`
    + `&waypoints=${via.map((p) => `${p.lat},${p.lng}`).join('%7C')}&travelmode=driving`;
}

/** Points still to visit, in order, starting from the current target. */
export function remainingPoints(stops, leg) {
  const list = sortStops(stops);
  const target = nextTargetStop(list, leg);
  if (!target) return [];
  const from = list.findIndex((s) => s.id === target.id || s.sequence === target.sequence);
  return list.slice(Math.max(0, from)).filter((s) => !s.completed_at || s === target).map(stopPoint).filter(Boolean);
}
