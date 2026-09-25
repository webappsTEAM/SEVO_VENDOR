import React, { useState } from 'react';
import {
  X,
  PauseCircle,
  PlayCircle,
  AlertTriangle,
  Calendar,
  Clock,
  FileText,
  CheckCircle2,
} from 'lucide-react';
import { apiHoldJob, apiResumeJob } from '../../api/workforceService.js';

export default function JobHoldModal({
  job,
  isOpen,
  onClose,
  onSuccess,
}) {
  const [isHoldMode, setIsHoldMode] = useState(true);
  const [reasonCategory, setReasonCategory] = useState('MATERIAL_DELAY');
  const [reasonText, setReasonText] = useState('');
  const [expectedResumeDate, setExpectedResumeDate] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [successMsg, setSuccessMsg] = useState(null);

  if (!isOpen || !job) return null;

  const isCurrentlyOnHold = job.status === 'ON_HOLD' || job.is_on_hold;

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSuccessMsg(null);

    try {
      if (isCurrentlyOnHold) {
        // Resume job
        const res = await apiResumeJob(job.id, {
          resume_notes: reasonText || 'Work resumed on site',
        });
        setSuccessMsg(res.message || 'Job has been resumed successfully!');
      } else {
        // Put job on hold
        if (!reasonText) {
          throw new Error('Please provide a specific reason for pausing work.');
        }
        const res = await apiHoldJob(job.id, {
          reason_category: reasonCategory,
          reason_text: reasonText,
          expected_resume_date: expectedResumeDate || undefined,
        });
        setSuccessMsg(res.message || 'Job has been placed on hold.');
      }

      if (onSuccess) onSuccess();
      setTimeout(() => {
        onClose();
      }, 1500);
    } catch (err) {
      console.error('Job hold/resume action failed:', err);
      setError(err.message || 'Action failed. Please try again.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto bg-black/60 backdrop-blur-sm flex items-center justify-center p-3 sm:p-6">
      <div className="bg-white dark:bg-gray-900 w-full max-w-lg rounded-2xl shadow-2xl border border-gray-200 dark:border-gray-800 flex flex-col overflow-hidden animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-800 flex items-center justify-between bg-gray-50/80 dark:bg-gray-800/50">
          <div className="flex items-center gap-3">
            <div
              className={`w-10 h-10 rounded-xl flex items-center justify-center ${
                isCurrentlyOnHold
                  ? 'bg-green-600/10 text-green-600 dark:bg-green-400/10 dark:text-green-400'
                  : 'bg-amber-600/10 text-amber-600 dark:bg-amber-400/10 dark:text-amber-400'
              }`}
            >
              {isCurrentlyOnHold ? (
                <PlayCircle className="w-5 h-5" />
              ) : (
                <PauseCircle className="w-5 h-5" />
              )}
            </div>
            <div>
              <h3 className="text-base font-bold text-gray-900 dark:text-gray-100">
                {isCurrentlyOnHold ? 'Resume Multi-Day Job' : 'Place Job On Hold'}
              </h3>
              <p className="text-xs text-gray-500 dark:text-gray-400">
                Job #{job.id} • {job.customer_name || 'Customer'}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 p-1.5 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content & Form */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {error && (
            <div className="p-3 bg-red-50 dark:bg-red-950/30 border border-red-200 dark:border-red-800 rounded-xl flex items-start gap-2.5 text-xs text-red-700 dark:text-red-300">
              <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5 text-red-500" />
              <span>{error}</span>
            </div>
          )}

          {successMsg && (
            <div className="p-3 bg-green-50 dark:bg-green-950/30 border border-green-200 dark:border-green-800 rounded-xl flex items-start gap-2.5 text-xs text-green-700 dark:text-green-300">
              <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5 text-green-500" />
              <span>{successMsg}</span>
            </div>
          )}

          {!isCurrentlyOnHold ? (
            <>
              <div>
                <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
                  Hold Reason Category
                </label>
                <select
                  value={reasonCategory}
                  onChange={(e) => setReasonCategory(e.target.value)}
                  className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2.5 focus:ring-2 focus:ring-amber-500 focus:outline-none"
                >
                  <option value="MATERIAL_DELAY">Material / Paint Supply Delay</option>
                  <option value="WEATHER_DELAY">Weather / Heavy Rain Delay</option>
                  <option value="CUSTOMER_REQUEST">Customer Requested Temporary Pause</option>
                  <option value="SITE_INACCESSIBLE">Site Inaccessible / Power/Water Outage</option>
                  <option value="OTHER">Other Operational Reason</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
                  Expected Resume Date (Optional)
                </label>
                <input
                  type="date"
                  value={expectedResumeDate}
                  onChange={(e) => setExpectedResumeDate(e.target.value)}
                  className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2.5 focus:ring-2 focus:ring-amber-500 focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
                  Specific Reason & Explanation <span className="text-red-500">*</span>
                </label>
                <textarea
                  rows={3}
                  required
                  value={reasonText}
                  onChange={(e) => setReasonText(e.target.value)}
                  placeholder="Explain why the multi-day work is paused (e.g. Waiting for waterproofing primer to dry thoroughly / client traveling)."
                  className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 p-3 focus:ring-2 focus:ring-amber-500 focus:outline-none"
                />
              </div>
            </>
          ) : (
            <div>
              <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
                Resume Notes & Progress Plan
              </label>
              <textarea
                rows={3}
                value={reasonText}
                onChange={(e) => setReasonText(e.target.value)}
                placeholder="e.g. Weather cleared; resumed 2nd coat application today."
                className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 p-3 focus:ring-2 focus:ring-green-500 focus:outline-none"
              />
            </div>
          )}

          {/* Footer Actions */}
          <div className="pt-3 border-t border-gray-200 dark:border-gray-800 flex items-center justify-end gap-3">
            <button
              type="button"
              onClick={onClose}
              className="text-xs font-semibold px-4 py-2 rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading}
              className={`text-xs font-bold px-5 py-2 rounded-xl text-white shadow-md disabled:opacity-50 cursor-pointer ${
                isCurrentlyOnHold
                  ? 'bg-green-600 hover:bg-green-700 shadow-green-600/20'
                  : 'bg-amber-600 hover:bg-amber-700 shadow-amber-600/20'
              }`}
            >
              {loading
                ? 'Processing...'
                : isCurrentlyOnHold
                ? 'Resume Job Work'
                : 'Confirm Hold'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
