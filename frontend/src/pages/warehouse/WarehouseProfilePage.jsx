import React, { useState, useEffect } from 'react';
import { useAuth } from '../../context/AuthProvider.jsx';
import { apiWarehouseGetProfile, apiWarehouseUpdateProfile } from '../../api/workforceService.js';
import {
  Building2,
  MapPin,
  Phone,
  Store,
  Key,
  Check,
  RefreshCw,
  Edit2,
  AlertCircle,
  CheckCircle2,
  Globe,
  Navigation,
} from 'lucide-react';

export function WarehouseProfilePage() {
  const { user } = useAuth();

  const [profile, setProfile] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [editing, setEditing] = useState(false);
  const [error, setError] = useState('');
  const [successMsg, setSuccessMsg] = useState('');

  const [formData, setFormData] = useState({
    contact_phone: '',
    address: '',
    city: '',
    region: '',
  });

  const fetchProfile = async () => {
    setLoading(true);
    setError('');
    try {
      const data = await apiWarehouseGetProfile();
      setProfile(data);
      setFormData({
        contact_phone: data.contact_phone || '',
        address: data.address || '',
        city: data.city || '',
        region: data.region || '',
      });
    } catch (err) {
      console.error('Failed to load warehouse profile:', err);
      setError('Unable to load warehouse facility profile.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchProfile();
  }, []);

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError('');
    setSuccessMsg('');
    try {
      const updated = await apiWarehouseUpdateProfile({
        contact_phone: formData.contact_phone.trim(),
        address: formData.address.trim(),
        city: formData.city.trim(),
        region: formData.region.trim(),
      });
      setProfile(updated);
      setEditing(false);
      setSuccessMsg('Facility profile updated successfully.');
    } catch (err) {
      console.error('Failed to update warehouse profile:', err);
      setError('Failed to update warehouse details.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-6 max-w-5xl mx-auto">
      {/* ── HEADER ── */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-xl font-black text-slate-900 flex items-center gap-2.5">
            <Building2 className="w-6 h-6 text-indigo-600" />
            <span>Warehouse Facility Profile</span>
          </h2>
          <p className="text-xs text-slate-500 mt-1">
            Facility operating details, rider dispatch coordinates, and assigned merchants
          </p>
        </div>

        <div className="flex items-center gap-2">
          {!editing ? (
            <button
              type="button"
              onClick={() => setEditing(true)}
              className="inline-flex items-center gap-2 px-3.5 py-2 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl transition-colors shadow-xs"
            >
              <Edit2 className="w-3.5 h-3.5" />
              <span>Edit Details</span>
            </button>
          ) : (
            <button
              type="button"
              onClick={() => setEditing(false)}
              className="px-3.5 py-2 text-xs font-bold text-slate-700 hover:text-slate-900 bg-white border border-slate-200 rounded-xl shadow-xs transition-colors"
            >
              Cancel
            </button>
          )}
        </div>
      </div>

      {error && (
        <div className="p-4 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700 flex items-center gap-2">
          <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {successMsg && (
        <div className="p-4 bg-emerald-50 border border-emerald-200 rounded-xl text-xs text-emerald-700 flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0" />
          <span>{successMsg}</span>
        </div>
      )}

      {loading ? (
        <div className="p-12 text-center text-slate-500 bg-white border border-slate-200 rounded-2xl shadow-xs">
          <RefreshCw className="w-6 h-6 animate-spin mx-auto mb-2 text-indigo-600" />
          <span>Loading facility information...</span>
        </div>
      ) : profile ? (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Main Info Card */}
          <div className="lg:col-span-2 space-y-6">
            <div className="bg-white border border-slate-200 rounded-2xl p-6 space-y-5 shadow-xs">
              <div className="flex items-center justify-between border-b border-slate-200 pb-4">
                <div className="flex items-center gap-3">
                  <div className="w-12 h-12 rounded-2xl bg-indigo-50 border border-indigo-100 flex items-center justify-center text-indigo-600 font-bold">
                    <Building2 className="w-6 h-6" />
                  </div>
                  <div>
                    <h3 className="text-base font-black text-slate-900">{profile.name}</h3>
                    <p className="text-xs font-mono text-indigo-600">{profile.code || `WH-${profile.id}`}</p>
                  </div>
                </div>
                <span className="px-3 py-1 rounded-full text-xs font-bold bg-emerald-50 text-emerald-700 border border-emerald-200 flex items-center gap-1.5">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
                  {profile.is_active ? 'Active Hub' : 'Inactive'}
                </span>
              </div>

              {!editing ? (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-xs">
                  <div className="space-y-1">
                    <span className="text-[10px] font-bold uppercase text-slate-400">Street Address</span>
                    <p className="font-medium text-slate-800">{profile.address || '—'}</p>
                  </div>

                  <div className="space-y-1">
                    <span className="text-[10px] font-bold uppercase text-slate-400">City / Operating Zone</span>
                    <p className="font-medium text-slate-800">
                      {profile.city} {profile.region ? `(${profile.region})` : ''}
                    </p>
                  </div>

                  <div className="space-y-1">
                    <span className="text-[10px] font-bold uppercase text-slate-400">Facility Phone</span>
                    <p className="font-mono text-slate-800">{profile.contact_phone || '—'}</p>
                  </div>

                  <div className="space-y-1">
                    <span className="text-[10px] font-bold uppercase text-slate-400">GPS Pickup Coordinates</span>
                    <p className="font-mono text-indigo-600 font-semibold">
                      {Number(profile.latitude).toFixed(6)}, {Number(profile.longitude).toFixed(6)}
                    </p>
                  </div>
                </div>
              ) : (
                <form onSubmit={handleSave} className="space-y-4 text-xs">
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    <div>
                      <label className="block text-slate-700 font-bold mb-1">City</label>
                      <input
                        type="text"
                        value={formData.city}
                        onChange={(e) => setFormData({ ...formData, city: e.target.value })}
                        className="w-full px-3 py-2 bg-white border border-slate-300 rounded-xl text-slate-900 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                      />
                    </div>
                    <div>
                      <label className="block text-slate-700 font-bold mb-1">Region / State</label>
                      <input
                        type="text"
                        value={formData.region}
                        onChange={(e) => setFormData({ ...formData, region: e.target.value })}
                        className="w-full px-3 py-2 bg-white border border-slate-300 rounded-xl text-slate-900 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-slate-700 font-bold mb-1">Facility Contact Phone</label>
                    <input
                      type="text"
                      value={formData.contact_phone}
                      onChange={(e) => setFormData({ ...formData, contact_phone: e.target.value })}
                      placeholder="+91 98765 43210"
                      className="w-full px-3 py-2 bg-white border border-slate-300 rounded-xl text-slate-900 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                  </div>

                  <div>
                    <label className="block text-slate-700 font-bold mb-1">Street Address</label>
                    <textarea
                      rows={2}
                      value={formData.address}
                      onChange={(e) => setFormData({ ...formData, address: e.target.value })}
                      className="w-full px-3 py-2 bg-white border border-slate-300 rounded-xl text-slate-900 focus:outline-none focus:ring-2 focus:ring-indigo-500"
                    />
                  </div>

                  <div className="flex items-center justify-end gap-2 pt-2">
                    <button
                      type="button"
                      onClick={() => setEditing(false)}
                      className="px-4 py-2 text-xs font-bold text-slate-700 hover:text-slate-900 bg-white border border-slate-200 rounded-xl shadow-xs"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      disabled={saving}
                      className="inline-flex items-center gap-2 px-5 py-2 text-xs font-bold text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl shadow-xs transition-colors"
                    >
                      {saving ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : <Check className="w-3.5 h-3.5" />}
                      <span>Save Changes</span>
                    </button>
                  </div>
                </form>
              )}
            </div>

            {/* Assigned Merchants List */}
            <div className="bg-white border border-slate-200 rounded-2xl p-6 space-y-4 shadow-xs">
              <div className="flex items-center justify-between">
                <h4 className="text-xs font-bold uppercase tracking-wider text-slate-900 flex items-center gap-2">
                  <Store className="w-4 h-4 text-amber-600" />
                  <span>Assigned Merchants ({profile.sellers?.length || 0})</span>
                </h4>
              </div>

              {profile.sellers?.length === 0 ? (
                <div className="p-6 bg-slate-50 border border-slate-200 rounded-xl text-center text-slate-500 text-xs">
                  No merchant sellers are assigned to this warehouse.
                </div>
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                  {profile.sellers.map((s) => (
                    <div
                      key={s.id}
                      className="p-3.5 bg-slate-50 border border-slate-200 rounded-xl flex items-center justify-between gap-3 text-xs"
                    >
                      <div className="min-w-0">
                        <p className="font-bold text-slate-900 truncate">{s.company_name}</p>
                        <p className="text-[10px] text-slate-500 font-mono">Company ID #{s.company_id}</p>
                      </div>
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-700 border border-indigo-200 shrink-0">
                        {s.business_type || 'Merchant'}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Right Sidebar: Operations Staff & Metadata */}
          <div className="space-y-6">
            <div className="bg-white border border-slate-200 rounded-2xl p-5 space-y-4 shadow-xs text-xs">
              <span className="text-[11px] font-bold uppercase tracking-wider text-indigo-600 flex items-center gap-2">
                <Key className="w-3.5 h-3.5" />
                <span>Portal Operator Account</span>
              </span>

              <div className="p-3.5 bg-slate-50 rounded-xl border border-slate-200 space-y-2">
                <div>
                  <span className="text-[10px] text-slate-500 uppercase font-bold">Logged In Username</span>
                  <p className="font-mono font-bold text-slate-900 mt-0.5">{user?.username}</p>
                </div>
                <div>
                  <span className="text-[10px] text-slate-500 uppercase font-bold">Account Role</span>
                  <p className="text-slate-700 mt-0.5">Warehouse Operations Staff</p>
                </div>
                <div>
                  <span className="text-[10px] text-slate-500 uppercase font-bold">Facility Scoping</span>
                  <p className="font-mono text-emerald-700 font-bold mt-0.5">
                    Isolated to Warehouse #{profile.id}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

export default WarehouseProfilePage;
