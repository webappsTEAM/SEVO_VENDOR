import React, { useState } from 'react';
import {
  ShoppingBag,
  Plus,
  Edit2,
  Play,
  Pause,
  Trash2,
  Package,
  Layers,
  Sparkles,
  Percent,
  CheckCircle2,
  AlertTriangle,
  Clock,
  ChevronDown,
  ChevronUp,
  RefreshCw,
} from 'lucide-react';
import {
  apiActivateSellerBasket,
  apiPauseSellerBasket,
  apiDeleteSellerBasket,
} from '../../api/workforceService.js';

export function SellerBasketOffersTab({
  baskets = [],
  loading = false,
  onRefresh,
  onOpenCreate,
  onOpenEdit,
  setSuccessMsg,
  setErrorMsg,
}) {
  const [expandedBasketId, setExpandedBasketId] = useState(null);
  const [actionLoadingId, setActionLoadingId] = useState(null);

  const toggleExpand = (id) => {
    setExpandedBasketId((prev) => (prev === id ? null : id));
  };

  const handleActivate = async (basket) => {
    setActionLoadingId(basket.id);
    try {
      await apiActivateSellerBasket(basket.id);
      setSuccessMsg?.(`Basket offer "${basket.title}" is now active on the marketplace.`);
      onRefresh?.();
    } catch (err) {
      setErrorMsg?.(err.message || 'Failed to activate basket offer.');
    } finally {
      setActionLoadingId(null);
    }
  };

  const handlePause = async (basket) => {
    setActionLoadingId(basket.id);
    try {
      await apiPauseSellerBasket(basket.id);
      setSuccessMsg?.(`Basket offer "${basket.title}" is paused.`);
      onRefresh?.();
    } catch (err) {
      setErrorMsg?.(err.message || 'Failed to pause basket offer.');
    } finally {
      setActionLoadingId(null);
    }
  };

  const handleDelete = async (basket) => {
    if (!window.confirm(`Are you sure you want to delete basket offer "${basket.title}"?`)) {
      return;
    }
    setActionLoadingId(basket.id);
    try {
      await apiDeleteSellerBasket(basket.id);
      setSuccessMsg?.(`Basket offer "${basket.title}" deleted.`);
      onRefresh?.();
    } catch (err) {
      setErrorMsg?.(err.message || 'Failed to delete basket offer.');
    } finally {
      setActionLoadingId(null);
    }
  };

  const getStatusBadge = (status) => {
    switch (status) {
      case 'ACTIVE':
        return (
          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-emerald-100 text-emerald-800 border border-emerald-300">
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-600 animate-pulse" />
            Active on Marketplace
          </span>
        );
      case 'PAUSED':
        return (
          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-amber-100 text-amber-800 border border-amber-300">
            <Pause className="w-3 h-3 text-amber-600" />
            Paused by Seller
          </span>
        );
      case 'OUT_OF_STOCK':
        return (
          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-rose-100 text-rose-800 border border-rose-300">
            <AlertTriangle className="w-3 h-3 text-rose-600" />
            Out of Stock
          </span>
        );
      case 'DRAFT':
      default:
        return (
          <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-[11px] font-bold bg-slate-100 text-slate-700 border border-slate-300">
            <Clock className="w-3 h-3 text-slate-500" />
            Draft
          </span>
        );
    }
  };

  return (
    <div className="space-y-4">
      {/* Tab Header Banner */}
      <div className="bg-gradient-to-r from-emerald-900 to-slate-900 rounded-2xl p-5 text-white flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 shadow-sm">
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <span className="px-2 py-0.5 bg-emerald-500/20 border border-emerald-400/40 rounded-md text-[10px] font-bold uppercase tracking-wider text-emerald-300">
              Bundle & Save Engine
            </span>
          </div>
          <h2 className="text-base font-bold tracking-tight">Basket Offers & Combo Bundles</h2>
          <p className="text-xs text-slate-300 max-w-xl">
            Create combo bundles with 3 or more approved products. Set your margin % or fixed price, and sell them directly on Sevo Mart.
          </p>
        </div>

        <button
          type="button"
          onClick={onOpenCreate}
          className="inline-flex items-center gap-1.5 px-4 py-2.5 bg-emerald-500 hover:bg-emerald-400 text-slate-950 text-xs font-bold rounded-xl transition-all shadow-md active:scale-95 shrink-0"
        >
          <Plus className="w-4 h-4 stroke-[3]" />
          <span>Add Basket Offer</span>
        </button>
      </div>

      {/* Content List */}
      {loading ? (
        <div className="bg-white p-16 rounded-2xl border border-slate-200 text-center space-y-3">
          <RefreshCw className="w-8 h-8 text-emerald-600 animate-spin mx-auto" />
          <p className="text-xs font-semibold text-slate-500">Loading basket combo offers...</p>
        </div>
      ) : baskets.length === 0 ? (
        <div className="bg-white p-16 rounded-2xl border border-slate-200 text-center space-y-4">
          <div className="w-12 h-12 bg-emerald-50 rounded-2xl text-emerald-600 flex items-center justify-center mx-auto border border-emerald-100">
            <ShoppingBag className="w-6 h-6" />
          </div>
          <div className="space-y-1">
            <h3 className="text-sm font-bold text-slate-900">No Basket Offers Created Yet</h3>
            <p className="text-xs text-slate-500 max-w-md mx-auto">
              Boost your store's average order value by bundling popular items together at an attractive combo price.
            </p>
          </div>
          <button
            type="button"
            onClick={onOpenCreate}
            className="inline-flex items-center gap-1.5 px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold rounded-xl shadow-xs transition-all"
          >
            <Plus className="w-4 h-4" />
            <span>Create Your First Basket Offer</span>
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4">
          {baskets.map((basket) => {
            const isExpanded = expandedBasketId === basket.id;
            const isActionLoading = actionLoadingId === basket.id;
            const savingsAmt = Math.max(0, Number(basket.total_mrp) - Number(basket.selling_price));
            const savingsPct =
              Number(basket.total_mrp) > 0
                ? Math.round((savingsAmt / Number(basket.total_mrp)) * 100)
                : 0;

            return (
              <div
                key={basket.id}
                className="bg-white rounded-2xl border border-slate-200 shadow-2xs overflow-hidden transition-all hover:border-slate-300"
              >
                <div className="p-5 flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
                  {/* Left: Info */}
                  <div className="flex items-start gap-4 min-w-0 flex-1">
                    {basket.image_url ? (
                      <img
                        src={basket.image_url}
                        alt={basket.title}
                        className="w-16 h-16 rounded-xl object-cover border border-slate-200 shrink-0"
                      />
                    ) : (
                      <div className="w-16 h-16 rounded-xl bg-emerald-50 border border-emerald-100 flex items-center justify-center text-emerald-700 shrink-0">
                        <ShoppingBag className="w-7 h-7" />
                      </div>
                    )}

                    <div className="min-w-0 space-y-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <h3 className="text-sm font-bold text-slate-900 truncate">{basket.title}</h3>
                        {getStatusBadge(basket.status)}
                      </div>
                      {basket.description && (
                        <p className="text-xs text-slate-500 line-clamp-1">{basket.description}</p>
                      )}
                      <div className="flex flex-wrap items-center gap-3 text-xs text-slate-500 pt-0.5">
                        <span className="font-semibold text-slate-700 flex items-center gap-1">
                          <Layers className="w-3.5 h-3.5 text-slate-400" />
                          {basket.items?.length || 0} Products Included
                        </span>
                        <span>•</span>
                        <span className="text-emerald-700 font-semibold">
                          {basket.available_stock !== undefined
                            ? `${basket.available_stock} combos available`
                            : 'In Stock'}
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Middle: Financials */}
                  <div className="flex items-center gap-6 bg-slate-50 px-4 py-2.5 rounded-xl border border-slate-100 self-stretch md:self-auto justify-between md:justify-start">
                    <div>
                      <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">
                        Combo Price
                      </span>
                      <div className="flex items-baseline gap-1.5">
                        <span className="text-lg font-black font-mono text-emerald-700">
                          ₹{basket.selling_price}
                        </span>
                        <span className="text-xs font-mono text-slate-400 line-through">
                          ₹{basket.total_mrp}
                        </span>
                      </div>
                    </div>

                    <div className="text-right">
                      <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">
                        Margin / Savings
                      </span>
                      <div className="flex items-center justify-end gap-1.5 mt-0.5">
                        <span className="px-1.5 py-0.2 rounded-md bg-emerald-100 text-emerald-800 text-[11px] font-bold font-mono">
                          {basket.margin_percent !== null ? `${basket.margin_percent}%` : 'Fixed'}
                        </span>
                        <span className="text-xs font-semibold text-slate-600">
                          Save ₹{savingsAmt.toFixed(0)} ({savingsPct}%)
                        </span>
                      </div>
                    </div>
                  </div>

                  {/* Right: Actions */}
                  <div className="flex items-center gap-2 self-end md:self-auto">
                    <button
                      type="button"
                      onClick={() => toggleExpand(basket.id)}
                      className="p-2 text-slate-500 hover:text-slate-800 hover:bg-slate-100 rounded-xl transition-colors border border-slate-200"
                      title="View component items"
                    >
                      {isExpanded ? (
                        <ChevronUp className="w-4 h-4" />
                      ) : (
                        <ChevronDown className="w-4 h-4" />
                      )}
                    </button>

                    <button
                      type="button"
                      onClick={() => onOpenEdit?.(basket)}
                      disabled={isActionLoading}
                      className="p-2 text-slate-600 hover:text-slate-900 hover:bg-slate-100 rounded-xl transition-colors border border-slate-200"
                      title="Edit basket"
                    >
                      <Edit2 className="w-4 h-4" />
                    </button>

                    {basket.status === 'ACTIVE' ? (
                      <button
                        type="button"
                        onClick={() => handlePause(basket)}
                        disabled={isActionLoading}
                        className="inline-flex items-center gap-1 px-3 py-2 text-xs font-bold text-amber-700 bg-amber-50 hover:bg-amber-100 border border-amber-200 rounded-xl transition-colors shadow-2xs"
                        title="Pause offer"
                      >
                        <Pause className="w-3.5 h-3.5" />
                        <span>Pause</span>
                      </button>
                    ) : (
                      <button
                        type="button"
                        onClick={() => handleActivate(basket)}
                        disabled={isActionLoading}
                        className="inline-flex items-center gap-1 px-3 py-2 text-xs font-bold text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 rounded-xl transition-colors shadow-2xs"
                        title="Activate offer"
                      >
                        <Play className="w-3.5 h-3.5 fill-current" />
                        <span>Activate</span>
                      </button>
                    )}

                    <button
                      type="button"
                      onClick={() => handleDelete(basket)}
                      disabled={isActionLoading}
                      className="p-2 text-rose-500 hover:text-rose-700 hover:bg-rose-50 rounded-xl transition-colors border border-slate-200"
                      title="Delete basket"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                {/* Expandable Items Preview */}
                {isExpanded && (
                  <div className="px-5 py-4 border-t border-slate-100 bg-slate-50/70">
                    <h4 className="text-[11px] font-bold uppercase tracking-wider text-slate-400 mb-3">
                      Included Component Products ({basket.items?.length || 0})
                    </h4>
                    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                      {basket.items?.map((item) => (
                        <div
                          key={item.id}
                          className="bg-white p-3 rounded-xl border border-slate-200 flex items-center justify-between gap-3 text-xs"
                        >
                          <div className="min-w-0">
                            <p className="font-bold text-slate-800 truncate">{item.title}</p>
                            <p className="text-[11px] font-mono text-slate-400">
                              SKU: {item.sku} • MRP: ₹{item.mrp}
                            </p>
                          </div>
                          <span className="px-2 py-0.5 bg-emerald-100 text-emerald-800 font-bold font-mono rounded-lg shrink-0">
                            Qty: {item.quantity}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
