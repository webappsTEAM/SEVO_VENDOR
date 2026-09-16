import React, { useEffect, useRef, useState, useCallback } from 'react';
import { CheckCircle2, MapPin, Phone, ShieldCheck, Crosshair, Navigation } from 'lucide-react';
import { loadMapsApi } from '../../../utils/loadGoogleMaps.js';

export function TechnicianArrivalView({
  job,
  technicianLocation,
  geofenceRadius = 250,
}) {
  const mapContainerRef = useRef(null);
  const mapRef = useRef(null);
  const [apiLoaded, setApiLoaded] = useState(false);
  const [resolvedCustCoords, setResolvedCustCoords] = useState(null);

  const resolveCoord = (...candidates) => {
    for (const c of candidates) {
      if (c !== null && c !== undefined && c !== '') {
        const num = parseFloat(c);
        if (!isNaN(num) && num !== 0) return num;
      }
    }
    return null;
  };

  const initialCustLat = resolveCoord(
    job?.latitude,
    job?.customer_latitude,
    job?.site_latitude,
    job?.customer_location?.latitude,
    job?.customer_address_details?.latitude,
    job?.lat
  );
  const initialCustLon = resolveCoord(
    job?.longitude,
    job?.customer_longitude,
    job?.site_longitude,
    job?.customer_location?.longitude,
    job?.customer_address_details?.longitude,
    job?.lng,
    job?.lon
  );

  const custLat = initialCustLat ?? resolvedCustCoords?.lat ?? null;
  const custLon = initialCustLon ?? resolvedCustCoords?.lng ?? null;

  const techLat = resolveCoord(technicianLocation?.latitude, technicianLocation?.lat);
  const techLon = resolveCoord(technicianLocation?.longitude, technicianLocation?.lng, technicianLocation?.lon);

  const customerName = job?.customer_name || 'Customer';
  const customerPhone = job?.phone || job?.customer_phone;
  const customerAddress = job?.address || job?.customer_address || 'Customer Authorized Address';

  const custMarkerRef = useRef(null);
  const geofenceCircleRef = useRef(null);
  const techMarkerRef = useRef(null);

  // Load Google Maps API singleton
  useEffect(() => {
    let mounted = true;
    const apiKey = import.meta.env.VITE_GOOGLE_MAPS_KEY || import.meta.env.VITE_GOOGLE_MAPS_API_KEY;
    loadMapsApi(apiKey)
      .then(() => {
        if (mounted) setApiLoaded(true);
      })
      .catch((err) => console.error('[ARRIVAL_MAP_LOAD_ERROR]', err));
    return () => {
      mounted = false;
    };
  }, []);

  // Geocoding fallback if coordinates are not in DB but address is present
  useEffect(() => {
    if (!apiLoaded || !window.google?.maps?.Geocoder) return;
    if (initialCustLat != null && initialCustLon != null) return;
    if (!customerAddress || customerAddress === 'Customer Authorized Address') return;

    try {
      const geocoder = new window.google.maps.Geocoder();
      geocoder.geocode({ address: customerAddress }, (results, status) => {
        if (status === 'OK' && results && results[0]?.geometry?.location) {
          const loc = results[0].geometry.location;
          setResolvedCustCoords({
            lat: loc.lat(),
            lng: loc.lng(),
          });
        }
      });
    } catch (e) {
      console.warn('[ARRIVAL_GEOCODE_FALLBACK_ERR]', e);
    }
  }, [apiLoaded, initialCustLat, initialCustLon, customerAddress]);

  // Center on customer site
  const handleRecenterSite = useCallback(() => {
    if (!mapRef.current) return;
    const centerLat = custLat ?? techLat ?? 12.9716;
    const centerLng = custLon ?? techLon ?? 77.5946;
    mapRef.current.panTo({ lat: centerLat, lng: centerLng });
    mapRef.current.setZoom(17);
  }, [custLat, custLon, techLat, techLon]);

  // Center on tech live location
  const handleRecenterTech = useCallback(() => {
    if (!mapRef.current || techLat == null || techLon == null) return;
    mapRef.current.panTo({ lat: techLat, lng: techLon });
    mapRef.current.setZoom(17);
  }, [techLat, techLon]);

  // Initialize contextual arrival map
  useEffect(() => {
    if (!apiLoaded || !mapContainerRef.current || mapRef.current) return;
    if (!window.google?.maps?.Map) return;

    try {
      const google = window.google;
      const centerLat = custLat ?? techLat ?? 12.9716;
      const centerLng = custLon ?? techLon ?? 77.5946;

      const map = new google.maps.Map(mapContainerRef.current, {
        center: { lat: centerLat, lng: centerLng },
        zoom: 17,
        tilt: 0,
        heading: 0,
        mapTypeControl: false,
        streetViewControl: false,
        fullscreenControl: false,
        zoomControl: true,
      });

      mapRef.current = map;

      // Trigger resize after layout finishes
      setTimeout(() => {
        if (mapRef.current && window.google?.maps) {
          window.google.maps.event.trigger(mapRef.current, 'resize');
          mapRef.current.setCenter({ lat: centerLat, lng: centerLng });
        }
      }, 300);
    } catch (err) {
      console.error('[ARRIVAL_MAP_INIT_ERROR]', err);
    }
  }, [apiLoaded, custLat, custLon, techLat, techLon]);

  // Keep map container responsive on resizing
  useEffect(() => {
    if (!mapContainerRef.current) return;
    const observer = new ResizeObserver(() => {
      if (mapRef.current && window.google?.maps) {
        window.google.maps.event.trigger(mapRef.current, 'resize');
      }
    });
    observer.observe(mapContainerRef.current);
    return () => observer.disconnect();
  }, []);

  // Update / Render Customer Pin, Geofence Circle & Tech Pin
  useEffect(() => {
    if (!apiLoaded || !mapRef.current || !window.google?.maps) return;
    const google = window.google;
    const map = mapRef.current;

    // 1. Customer Site Destination Pin
    if (custLat != null && custLon != null) {
      const custPos = { lat: custLat, lng: custLon };

      if (!custMarkerRef.current) {
        custMarkerRef.current = new google.maps.Marker({
          position: custPos,
          map,
          title: `Customer Site: ${customerAddress}`,
          icon: {
            url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(`
              <svg xmlns="http://www.w3.org/2000/svg" width="40" height="48" viewBox="0 0 40 48">
                <defs>
                  <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
                    <feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#000000" flood-opacity="0.3"/>
                  </filter>
                </defs>
                <g filter="url(#shadow)">
                  <path d="M20 0C9 0 0 9 0 20c0 14 18 27 19 28a1.5 1.5 0 0 0 2 0C22 47 40 34 40 20 40 9 31 0 20 0z" fill="#DC2626" stroke="#FFFFFF" stroke-width="2"/>
                  <circle cx="20" cy="18" r="11" fill="#FFFFFF"/>
                  <path d="M20 11l-6 5v7h4v-4h4v4h4v-7l-6-5z" fill="#DC2626"/>
                </g>
              </svg>
            `)}`,
            scaledSize: new google.maps.Size(36, 44),
            anchor: new google.maps.Point(18, 44),
          },
        });
      } else {
        custMarkerRef.current.setPosition(custPos);
      }

      // 2. Verified 250m/300m Green Geofence Circle
      if (!geofenceCircleRef.current) {
        geofenceCircleRef.current = new google.maps.Circle({
          map,
          center: custPos,
          radius: Number(geofenceRadius) || 250,
          strokeColor: '#059669',
          strokeOpacity: 0.85,
          strokeWeight: 2.5,
          fillColor: '#10B981',
          fillOpacity: 0.16,
        });
      } else {
        geofenceCircleRef.current.setCenter(custPos);
        geofenceCircleRef.current.setRadius(Number(geofenceRadius) || 250);
      }
    }

    // 3. Technician Location Marker (Blue Puck)
    if (techLat != null && techLon != null) {
      const techPos = { lat: techLat, lng: techLon };
      if (!techMarkerRef.current) {
        techMarkerRef.current = new google.maps.Marker({
          position: techPos,
          map,
          title: 'Your Location',
          icon: {
            url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(`
              <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
                <circle cx="16" cy="16" r="12" fill="#2563EB" stroke="#FFFFFF" stroke-width="3"/>
                <circle cx="16" cy="16" r="5" fill="#FFFFFF"/>
              </svg>
            `)}`,
            scaledSize: new google.maps.Size(28, 28),
            anchor: new google.maps.Point(14, 14),
          },
        });
      } else {
        techMarkerRef.current.setPosition(techPos);
      }
    }
  }, [apiLoaded, custLat, custLon, customerAddress, geofenceRadius, techLat, techLon]);

  return (
    <div className="w-full h-full flex-1 flex flex-col min-h-0 bg-slate-100 relative overflow-hidden">
      {/* ── Floating Controls Bar ── */}
      <div className="absolute top-4 left-4 right-4 z-20 flex items-center justify-between pointer-events-none">
        {/* Recenter Site & Tech Pill */}
        <div className="flex items-center gap-2 pointer-events-auto">
          <button
            type="button"
            onClick={handleRecenterSite}
            className="bg-white/95 backdrop-blur-md hover:bg-white text-slate-800 border border-slate-200/90 shadow-md px-3 py-1.5 rounded-xl text-xs font-bold flex items-center gap-1.5 cursor-pointer transition-all hover:shadow-lg active:scale-95"
            title="Recenter on Customer Site"
          >
            <MapPin className="w-3.5 h-3.5 text-rose-600" />
            <span>Customer Site</span>
          </button>

          {techLat != null && techLon != null && (
            <button
              type="button"
              onClick={handleRecenterTech}
              className="bg-white/95 backdrop-blur-md hover:bg-white text-slate-800 border border-slate-200/90 shadow-md px-3 py-1.5 rounded-xl text-xs font-bold flex items-center gap-1.5 cursor-pointer transition-all hover:shadow-lg active:scale-95"
              title="Center on My Live Location"
            >
              <Crosshair className="w-3.5 h-3.5 text-blue-600" />
              <span>My GPS</span>
            </button>
          )}
        </div>

        {/* Call Customer Quick Action */}
        {customerPhone && (
          <a
            href={`tel:${customerPhone}`}
            className="pointer-events-auto bg-white/95 backdrop-blur-md hover:bg-white text-slate-800 border border-slate-200/90 shadow-md px-3.5 py-1.5 rounded-xl text-xs font-bold flex items-center gap-1.5 cursor-pointer transition-all hover:shadow-lg active:scale-95"
          >
            <Phone className="w-3.5 h-3.5 text-emerald-600" />
            <span>Call Customer</span>
          </a>
        )}
      </div>

      {/* ── Contextual Location Map Container ── */}
      <div className="w-full flex-1 min-h-[300px] relative bg-slate-100">
        <div ref={mapContainerRef} className="w-full h-full absolute inset-0" />
      </div>

      {/* ── Customer Address Bar ── */}
      <div className="px-4 py-3 bg-white border-t border-slate-200 flex items-center justify-between text-xs text-slate-700 shrink-0 shadow-2xs z-10">
        <div className="flex items-center gap-2 min-w-0">
          <div className="p-1 rounded-md bg-rose-50 border border-rose-200 text-rose-600 shrink-0">
            <MapPin className="w-4 h-4" />
          </div>
          <div className="min-w-0">
            <span className="font-bold text-slate-900 block truncate">{customerName}</span>
            <span className="truncate text-slate-500 font-medium block text-[11px]">{customerAddress}</span>
          </div>
        </div>
        <div className="flex items-center gap-1.5 shrink-0 pl-3">
          <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
          <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-700 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded">
            On Site
          </span>
        </div>
      </div>
    </div>
  );
}

