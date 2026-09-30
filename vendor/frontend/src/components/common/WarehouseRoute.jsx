import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../context/AuthProvider.jsx';

export function WarehouseRoute({ children }) {
  const { isReady, isAuthenticated, isPlatformAdmin, isWarehouseStaff } = useAuth();
  const location = useLocation();

  if (!isReady) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-900 text-slate-100 font-sans">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin" />
          <p className="text-xs font-semibold text-slate-400">Verifying warehouse credentials...</p>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Navigate to="/workforce/login" state={{ from: location }} replace />;
  }

  const hasAccess = Boolean(isPlatformAdmin || isWarehouseStaff);
  if (!hasAccess) {
    return <Navigate to="/workforce/login" replace />;
  }

  return children;
}

export default WarehouseRoute;
