import React, { useEffect, useState } from 'react';
import { AppShell } from '../../components/common/AppShell.jsx';
import { apiGetReport } from '../../api/workforceService.js';
import { BarChart3, Download, Filter, RefreshCw, FileText, AlertCircle } from 'lucide-react';

export function AdminReportsPage() {
  const [reportType, setReportType] = useState('employee');
  const [reportData, setReportData] = useState({ total_records: 0, rows: [] });
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);
  const [filters, setFilters] = useState({
    service: '',
    status: '',
  });

  const loadReport = async () => {
    try {
      setIsLoading(true);
      setError(null);
      const res = await apiGetReport(reportType, filters);
      setReportData(res || { total_records: 0, rows: [] });
    } catch (err) {
      setError(err?.message || 'Failed to load report data.');
      setReportData({ total_records: 0, rows: [] });
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadReport();
  }, [reportType]);

  const handleExportCSV = () => {
    if (!reportData.rows || reportData.rows.length === 0) return;
    const escapeCell = (v) => {
      if (v === null || v === undefined) return '""';
      const str = String(v).replace(/"/g, '""');
      return `"${str}"`;
    };
    const headers = Object.keys(reportData.rows[0]).map(escapeCell).join(',');
    const rows = reportData.rows.map((r) => Object.values(r).map(escapeCell).join(','));
    const csvContent = '\uFEFF' + [headers, ...rows].join('\r\n');
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', `workforce_${reportType}_report.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  };

  return (
    <AppShell breadcrumbs={[{ label: 'Home', to: '/workforce/admin' }, { label: 'Reports & Analytics' }]}>
      <div className="space-y-4 text-xs">
        {/* Top Header */}
        <div className="bg-white border border-zinc-200/90 p-5 rounded-md shadow-card flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div>
            <h1 className="text-base font-bold text-zinc-950 flex items-center gap-2 tracking-tight">
              <BarChart3 className="w-5 h-5 text-zinc-800" />
              <span>Workforce Enterprise Reporting Suite</span>
            </h1>
            <p className="text-xs text-zinc-500 mt-1 leading-relaxed">
              Query real database aggregations with multi-dimensional filtering across workforce operations.
            </p>
          </div>
          <button
            type="button"
            onClick={handleExportCSV}
            disabled={!reportData.rows || reportData.rows.length === 0}
            className="px-4 py-2 min-h-[38px] rounded-lg bg-zinc-900 hover:bg-zinc-800 active:bg-zinc-950 disabled:opacity-50 text-white font-bold text-xs shadow-xs transition-all flex items-center gap-2 cursor-pointer shrink-0"
          >
            <Download className="w-4 h-4 text-zinc-200" />
            <span>Export CSV</span>
          </button>
        </div>

        {error && (
          <div className="flex items-center justify-between p-3.5 bg-rose-50 border border-rose-200 rounded-lg text-rose-800 text-xs">
            <div className="flex items-center gap-2">
              <AlertCircle className="w-4 h-4 text-rose-600 flex-shrink-0" />
              <span>{error}</span>
            </div>
            <button
              onClick={loadReport}
              className="px-2.5 py-1 bg-rose-600 hover:bg-rose-700 text-white font-semibold rounded text-xs transition-colors"
            >
              Retry
            </button>
          </div>
        )}

        {/* Report Selector Tabs & Filter Bar */}
        <div className="bg-white border border-zinc-200/90 rounded-md p-5 shadow-card space-y-4">
          <div className="flex items-center gap-2 border-b border-zinc-200/80 pb-3 overflow-x-auto text-xs">
            {[
              { id: 'employee', label: 'Employee Roster' },
              { id: 'job', label: 'Field Jobs' },
              { id: 'compliance', label: 'Compliance Audit' },
            ].map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => setReportType(t.id)}
                className={`px-3.5 py-2 rounded-lg font-bold text-xs transition-all cursor-pointer ${
                  reportType === t.id ? 'bg-zinc-900 text-white shadow-xs' : 'bg-zinc-100 text-zinc-700 hover:bg-zinc-200'
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>

          {/* Filter Controls */}
          <div className="flex items-center gap-3 text-xs flex-wrap">
            <div className="flex items-center gap-1.5 text-zinc-700 font-bold">
              <Filter className="w-3.5 h-3.5 text-zinc-500" />
              <span>Filters:</span>
            </div>
            {reportType === 'job' && (
              <input
                type="text"
                placeholder="Service Category Filter..."
                value={filters.service}
                onChange={(e) => setFilters({ ...filters, service: e.target.value })}
                className="px-3 py-2 min-h-[38px] border border-zinc-300 rounded-lg text-xs w-56 text-zinc-900 focus:outline-none focus:ring-2 focus:ring-zinc-950/10 focus:border-zinc-900 shadow-xs"
              />
            )}
            <button
              type="button"
              onClick={loadReport}
              className="px-3.5 py-2 min-h-[38px] rounded-lg border border-zinc-300 bg-white hover:bg-zinc-50 active:bg-zinc-100 font-bold text-zinc-800 transition-all shadow-xs flex items-center gap-1.5 cursor-pointer"
            >
              <RefreshCw className="w-3.5 h-3.5 text-zinc-600" />
              <span>Apply Filters</span>
            </button>
          </div>
        </div>

        {/* Data Grid */}
        <div className="bg-white border border-zinc-200/90 rounded-md overflow-hidden shadow-card">
          <div className="bg-zinc-50/80 px-4 py-3 border-b border-zinc-200/80 font-bold text-zinc-950 text-xs flex items-center justify-between">
            <span>Query Results ({reportData.total_records || reportData.rows?.length || 0} Records)</span>
            {isLoading && <span className="text-zinc-500 font-normal">Executing database aggregate...</span>}
          </div>

          <div className="overflow-x-auto max-h-[500px]">
            {reportData.rows && reportData.rows.length > 0 ? (
              <table className="w-full text-left text-xs">
                <thead className="bg-zinc-50/60 text-zinc-500 uppercase text-[11px] font-bold border-b border-zinc-200 sticky top-0">
                  <tr>
                    {Object.keys(reportData.rows[0]).map((h) => (
                      <th key={h} className="px-4 py-3 tracking-wider">{h.replace(/_/g, ' ')}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-100">
                  {reportData.rows.map((row, i) => (
                    <tr key={i} className="hover:bg-zinc-50/80 transition-colors">
                      {Object.values(row).map((val, j) => (
                        <td key={j} className="px-4 py-3 text-zinc-700 whitespace-nowrap">{String(val || '—')}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : (
              <div className="p-12 text-center text-zinc-500 text-xs">
                {isLoading ? 'Loading records...' : 'No operational report data matched current filters.'}
              </div>
            )}
          </div>
        </div>
      </div>
    </AppShell>
  );
}

export default AdminReportsPage;
