import React from 'react';
import { NavLink, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthProvider.jsx';
import {
  Warehouse as WarehouseIcon,
  Home,
  PackageCheck,
  Undo2,
  Boxes,
  BarChart3,
  Building2,
  Grid3X3,
  LogOut,
  MapPin,
  ShieldCheck,
  Bell,
  User,
  ChevronRight,
} from 'lucide-react';

export function WarehouseLayout() {
  const { user, logout, isPlatformAdmin } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const handleLogout = async () => {
    await logout();
    navigate('/workforce/login');
  };

  const navItems = [
    {
      to: '/workforce/warehouse/home',
      label: 'Home',
      icon: Home,
    },
    {
      to: '/workforce/warehouse/orders',
      label: 'Orders',
      icon: PackageCheck,
      badge: 'Live',
    },
    {
      to: '/workforce/warehouse/returns',
      label: 'Returns',
      icon: Undo2,
    },
    {
      to: '/workforce/warehouse/inventory',
      label: 'Inventory',
      icon: Boxes,
    },
    {
      to: '/workforce/warehouse/reports',
      label: 'Reports & Quality',
      icon: BarChart3,
    },
    {
      to: '/workforce/warehouse/profile',
      label: 'Warehouse Profile',
      icon: Building2,
    },
    {
      to: '/workforce/warehouse/rack-view',
      label: 'Rack Visualization',
      icon: Grid3X3,
    },
  ];

  const warehouseName = user?.warehouseName || user?.warehouse?.name || 'Fulfilment Hub';
  const warehouseCode = user?.warehouseCode || user?.warehouse?.code || (user?.warehouseId ? `WH-${user.warehouseId}` : 'WH-MAIN');

  return (
    <div className="flex h-screen bg-slate-50 font-sans antialiased text-slate-800">
      {/* ── SIDEBAR ── */}
      <aside className="w-64 bg-white border-r border-slate-200 flex flex-col shrink-0 shadow-xs">
        {/* Brand Header */}
        <div className="p-4 border-b border-slate-200 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-indigo-600 flex items-center justify-center text-white shadow-xs">
              <WarehouseIcon className="w-5 h-5" />
            </div>
            <div className="min-w-0">
              <h1 className="text-xs font-black uppercase tracking-wider text-slate-900 truncate">
                SEVO Logistics
              </h1>
              <div className="flex items-center gap-1.5 mt-0.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
                <span className="text-[10px] font-bold text-slate-500 uppercase tracking-wide">
                  Warehouse Portal
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Current Facility Card */}
        <div className="p-3 mx-3 my-3 bg-indigo-50/60 rounded-xl border border-indigo-100">
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-bold uppercase tracking-wider text-indigo-700">
              Assigned Facility
            </span>
            <span className="text-[10px] font-mono font-bold bg-indigo-100 text-indigo-700 px-1.5 py-0.5 rounded border border-indigo-200">
              {warehouseCode}
            </span>
          </div>
          <p className="text-xs font-bold text-slate-900 mt-1 truncate" title={warehouseName}>
            {warehouseName}
          </p>
          <div className="flex items-center gap-1 text-[10px] text-slate-600 mt-1">
            <MapPin className="w-3 h-3 text-indigo-600 shrink-0" />
            <span className="truncate">{user?.city || 'Distribution Hub'}</span>
          </div>
        </div>

        {/* Navigation Links */}
        <nav className="flex-1 px-3 py-2 space-y-1 overflow-y-auto">
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = location.pathname === item.to || (item.to !== '/workforce/warehouse/home' && location.pathname.startsWith(item.to));
            return (
              <NavLink
                key={item.to}
                to={item.to}
                className={`flex items-center justify-between px-3 py-2.5 rounded-xl text-xs font-semibold transition-all group ${
                  isActive
                    ? 'bg-indigo-600 text-white shadow-xs font-semibold'
                    : 'text-slate-600 hover:text-slate-900 hover:bg-slate-100 font-medium'
                }`}
              >
                <div className="flex items-center gap-2.5">
                  <Icon className={`w-4 h-4 transition-colors ${isActive ? 'text-white' : 'text-slate-400 group-hover:text-indigo-600'}`} />
                  <span>{item.label}</span>
                </div>
                {item.badge && (
                  <span className={`text-[9px] font-bold uppercase px-1.5 py-0.5 rounded-full ${
                    isActive ? 'bg-indigo-700 text-white' : 'bg-emerald-50 text-emerald-700 border border-emerald-200'
                  }`}>
                    {item.badge}
                  </span>
                )}
              </NavLink>
            );
          })}
        </nav>

        {/* Admin Quick Switch (if platform admin) */}
        {isPlatformAdmin && (
          <div className="p-3 mx-3 mb-2 bg-amber-50 border border-amber-200 rounded-xl text-center">
            <p className="text-[10px] font-bold text-amber-800 uppercase">Platform Admin View</p>
            <button
              type="button"
              onClick={() => navigate('/workforce/admin/warehouses')}
              className="mt-1.5 w-full text-[11px] font-bold text-amber-900 bg-amber-100/80 hover:bg-amber-200/80 py-1 px-2 rounded-lg border border-amber-300 transition-colors"
            >
              Back to Admin Panel
            </button>
          </div>
        )}

        {/* User Account & Logout Footer */}
        <div className="p-3 border-t border-slate-200 bg-slate-50/80">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2.5 min-w-0">
              <div className="w-8 h-8 rounded-lg bg-indigo-50 border border-indigo-100 flex items-center justify-center text-indigo-600 font-bold text-xs shrink-0">
                <User className="w-4 h-4 text-indigo-600" />
              </div>
              <div className="min-w-0">
                <p className="text-xs font-bold text-slate-900 truncate">{user?.username || 'Operator'}</p>
                <p className="text-[10px] text-slate-500 truncate">{user?.email || 'Warehouse Staff'}</p>
              </div>
            </div>
            <button
              type="button"
              onClick={handleLogout}
              className="p-1.5 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition-colors shrink-0"
              title="Sign Out"
            >
              <LogOut className="w-4 h-4" />
            </button>
          </div>
        </div>
      </aside>

      {/* ── MAIN CONTENT OUTLET ── */}
      <div className="flex-1 flex flex-col min-w-0 overflow-y-auto bg-slate-50">
        <header className="h-14 border-b border-slate-200 bg-white px-6 flex items-center justify-between shrink-0 sticky top-0 z-10 shadow-xs">
          <div className="flex items-center gap-2 text-xs font-medium text-slate-500">
            <span>Warehouse Portal</span>
            <ChevronRight className="w-3.5 h-3.5 text-slate-400" />
            <span className="text-slate-900 font-semibold">{warehouseName}</span>
          </div>
          <div className="flex items-center gap-3">
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
              Facility Operational
            </span>
          </div>
        </header>

        <main className="flex-1 p-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

export default WarehouseLayout;
