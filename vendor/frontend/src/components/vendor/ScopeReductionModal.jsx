import React, { useState } from 'react';
import {
  X,
  MinusCircle,
  FileText,
  AlertTriangle,
  CheckCircle2,
  DollarSign,
  ShieldCheck,
} from 'lucide-react';
import { apiSubmitScopeReduction } from '../../api/workforceService.js';

export default function ScopeReductionModal({
  job,
  isOpen,
  onClose,
  onSuccess,
}) {
  const [reason, setReason] = useState('');
  const [reductionAmount, setReductionAmount] = useState('');
  const [itemsRemovedText, setItemsRemovedText] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [successMsg, setSuccessMsg] = useState(null);

  if (!isOpen || !job) return null;

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSuccessMsg(null);

    const amount = parseFloat(reductionAmount);
    if (!amount || amount <= 0) {
      setError('Please enter a valid scope reduction amount (greater than 0).');
      setLoading(false);
      return;
    }

    try {
      const res = await apiSubmitScopeReduction(job.id, {
        reason: reason || 'Customer requested scope reduction',
        reduction_amount: amount,
        items_removed_summary: itemsRemovedText || undefined,
      });

      setSuccessMsg(res.message || 'Scope reduction request submitted successfully!');
      if (onSuccess) onSuccess();
      setTimeout(() => {
        onClose();
      }, 1800);
    } catch (err) {
      console.error('Scope reduction request failed:', err);
      setError(err.message || 'Failed to submit scope reduction.');
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
            <div className="w-10 h-10 rounded-xl bg-purple-600/10 text-purple-600 dark:bg-purple-400/10 dark:text-purple-400 flex items-center justify-center">
              <MinusCircle className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base font-bold text-gray-900 dark:text-gray-100">
                Scope & Line Item Reduction
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
          <div className="bg-purple-50/70 dark:bg-purple-950/30 border border-purple-200 dark:border-purple-800/50 rounded-xl p-3 flex items-start gap-2.5 text-xs text-purple-800 dark:text-purple-300">
            <ShieldCheck className="w-4 h-4 shrink-0 mt-0.5 text-purple-600" />
            <div>
              <span className="font-semibold">Financial Integrity Rule:</span> Scope reductions reduce the total and remaining balance without modifying historical 50% advance deposits paid by the client.
            </div>
          </div>

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

          <div>
            <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
              Deduction / Reduction Amount (₹) <span className="text-red-500">*</span>
            </label>
            <input
              type="number"
              step="1"
              min="1"
              required
              value={reductionAmount}
              onChange={(e) => setReductionAmount(e.target.value)}
              placeholder="e.g. 3500"
              className="w-full text-sm font-semibold rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2.5 focus:ring-2 focus:ring-purple-500 focus:outline-none"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
              Removed Items / Scope Summary
            </label>
            <input
              type="text"
              value={itemsRemovedText}
              onChange={(e) => setItemsRemovedText(e.target.value)}
              placeholder="e.g. Balcony wall texture skipped; Kitchen 1 coat cancelled"
              className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2.5 focus:ring-2 focus:ring-purple-500 focus:outline-none"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
              Reason for Reduction <span className="text-red-500">*</span>
            </label>
            <textarea
              rows={3}
              required
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Provide reason why work scope was downscaled on site."
              className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 p-3 focus:ring-2 focus:ring-purple-500 focus:outline-none"
            />
          </div>

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
              className="text-xs font-bold px-5 py-2 rounded-xl bg-purple-600 text-white hover:bg-purple-700 shadow-md shadow-purple-600/20 disabled:opacity-50 cursor-pointer"
            >
              {loading ? 'Submitting...' : 'Submit Scope Reduction'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
