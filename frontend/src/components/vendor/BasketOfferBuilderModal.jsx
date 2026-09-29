import React, { useState, useEffect, useMemo, useCallback } from 'react';
import {
  X,
  Plus,
  Minus,
  Search,
  Check,
  AlertTriangle,
  Sparkles,
  Percent,
  IndianRupee,
  ShoppingBag,
  Package,
  Layers,
  ArrowRight,
  RefreshCw,
  UploadCloud,
  CheckCircle2,
  Trash2,
  Info,
} from 'lucide-react';
import {
  apiCalculateSellerBasket,
  apiCreateSellerBasket,
  apiUpdateSellerBasket,
  apiUploadSellerHubImage,
} from '../../api/workforceService.js';

export function BasketOfferBuilderModal({
  isOpen,
  onClose,
  editingBasket = null,
  onSaved,
  token,
}) {
  // ── States ────────────────────────────────────────────────────────────────
  const [loadingProducts, setLoadingProducts] = useState(false);
  const [productsList, setProductsList] = useState([]);
  const [productSearch, setProductSearch] = useState('');

  // Basket form
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [uploadingImage, setUploadingImage] = useState(false);

  // Selected items: { [productId]: quantity }
  const [selectedItems, setSelectedItems] = useState({});

  // Pricing mode & inputs
  const [pricingMode, setPricingMode] = useState('MARGIN'); // 'MARGIN' | 'FIXED_PRICE'
  const [marginPercentInput, setMarginPercentInput] = useState('15');
  const [sellingPriceInput, setSellingPriceInput] = useState('');

  // Live calculation results from server
  const [calcResult, setCalcResult] = useState({
    total_mrp: '0.00',
    total_procurement_price: '0.00',
    selling_price: '0.00',
    margin_percent: '0.00',
    profit_amount: '0.00',
    savings_vs_mrp: '0.00',
    savings_percent: 0,
    has_missing_procurement_price: false,
    missing_procurement_products: [],
  });
  const [calculating, setCalculating] = useState(false);
  const [saveLoading, setSaveLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  // ── Fetch Seller's Approved Products ──────────────────────────────────────
  const fetchApprovedProducts = useCallback(async () => {
    setLoadingProducts(true);
    try {
      const res = await fetch('/api/workforce/seller-hub/products/?status=APPROVED', {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const data = await res.json();
        const list = Array.isArray(data)
          ? data
          : Array.isArray(data?.results)
          ? data.results
          : [];
        setProductsList(list);
      }
    } catch (e) {
      console.warn('Failed to fetch approved products', e);
    } finally {
      setLoadingProducts(false);
    }
  }, [token]);

  // ── Initialize or reset when modal opens ──────────────────────────────────
  useEffect(() => {
    if (!isOpen) return;
    fetchApprovedProducts();

    if (editingBasket) {
      setTitle(editingBasket.title || '');
      setDescription(editingBasket.description || '');
      setImageUrl(editingBasket.image_url || '');
      setPricingMode(editingBasket.pricing_mode || 'MARGIN');
      setMarginPercentInput(editingBasket.margin_percent !== null && editingBasket.margin_percent !== undefined ? String(editingBasket.margin_percent) : '15');
      setSellingPriceInput(editingBasket.selling_price ? String(editingBasket.selling_price) : '');

      const initialSelected = {};
      if (Array.isArray(editingBasket.items)) {
        editingBasket.items.forEach((it) => {
          const pId = it.product || it.product_id || it.id;
          initialSelected[pId] = it.quantity || 1;
        });
      }
      setSelectedItems(initialSelected);
    } else {
      setTitle('');
      setDescription('');
      setImageUrl('');
      setSelectedItems({});
      setPricingMode('MARGIN');
      setMarginPercentInput('15');
      setSellingPriceInput('');
      setCalcResult({
        total_mrp: '0.00',
        total_procurement_price: '0.00',
        selling_price: '0.00',
        margin_percent: '0.00',
        profit_amount: '0.00',
        savings_vs_mrp: '0.00',
        savings_percent: 0,
        has_missing_procurement_price: false,
        missing_procurement_products: [],
      });
    }
    setErrorMsg('');
  }, [isOpen, editingBasket, fetchApprovedProducts]);

  // ── Selected Product IDs & Count ──────────────────────────────────────────
  const selectedProductIds = useMemo(() => {
    return Object.keys(selectedItems)
      .map(Number)
      .filter((id) => selectedItems[id] > 0);
  }, [selectedItems]);

  const distinctCount = selectedProductIds.length;

  // ── Item Selection Helpers ────────────────────────────────────────────────
  const handleToggleProduct = (prodId) => {
    setSelectedItems((prev) => {
      const next = { ...prev };
      if (next[prodId]) {
        delete next[prodId];
      } else {
        next[prodId] = 1;
      }
      return next;
    });
  };

  const handleUpdateQty = (prodId, delta) => {
    setSelectedItems((prev) => {
      const current = prev[prodId] || 0;
      const updated = current + delta;
      const next = { ...prev };
      if (updated <= 0) {
        delete next[prodId];
      } else {
        next[prodId] = updated;
      }
      return next;
    });
  };

  // ── Live Calculation (Server Preview Calculation) ─────────────────────────
  const runLiveCalculation = useCallback(
    async (mode, marginVal, priceVal, itemsMap) => {
      const itemsPayload = Object.keys(itemsMap)
        .map((k) => ({
          product_id: Number(k),
          quantity: itemsMap[k],
        }))
        .filter((it) => it.quantity > 0);

      if (itemsPayload.length === 0) {
        setCalcResult({
          total_mrp: '0.00',
          total_procurement_price: '0.00',
          selling_price: '0.00',
          margin_percent: '0.00',
          profit_amount: '0.00',
          savings_vs_mrp: '0.00',
          savings_percent: 0,
          has_missing_procurement_price: false,
          missing_procurement_products: [],
        });
        return;
      }

      setCalculating(true);
      try {
        const payload = {
          items: itemsPayload,
          pricing_mode: mode,
        };
        if (mode === 'MARGIN') {
          payload.margin_percent = marginVal !== '' ? Number(marginVal) : 15;
        } else {
          payload.selling_price = priceVal !== '' ? Number(priceVal) : 0;
        }

        const res = await apiCalculateSellerBasket(payload);
        setCalcResult(res);

        if (mode === 'MARGIN') {
          setSellingPriceInput(String(res.selling_price || ''));
        } else {
          setMarginPercentInput(String(res.margin_percent || ''));
        }
      } catch (err) {
        console.warn('Calculation error:', err);
      } finally {
        setCalculating(false);
      }
    },
    []
  );

  useEffect(() => {
    if (selectedProductIds.length === 0) return;
    const timer = setTimeout(() => {
      runLiveCalculation(pricingMode, marginPercentInput, sellingPriceInput, selectedItems);
    }, 250);
    return () => clearTimeout(timer);
  }, [selectedItems, pricingMode, runLiveCalculation]);

  const handleMarginChange = (val) => {
    setMarginPercentInput(val);
    setPricingMode('MARGIN');
    runLiveCalculation('MARGIN', val, sellingPriceInput, selectedItems);
  };

  const handleSellingPriceChange = (val) => {
    setSellingPriceInput(val);
    setPricingMode('FIXED_PRICE');
    runLiveCalculation('FIXED_PRICE', marginPercentInput, val, selectedItems);
  };

  const handleImageFileChange = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingImage(true);
    try {
      const res = await apiUploadSellerHubImage(file);
      if (res?.image_url) {
        setImageUrl(res.image_url);
      }
    } catch (err) {
      setErrorMsg(err.message || 'Image upload failed.');
    } finally {
      setUploadingImage(false);
    }
  };

  const handleSaveBasket = async (targetStatus) => {
    setErrorMsg('');
    if (!title.trim()) {
      setErrorMsg('Please enter a basket title.');
      return;
    }
    if (distinctCount < 3) {
      setErrorMsg('A basket combo offer must contain at least 3 distinct products.');
      return;
    }
    if (calcResult.has_missing_procurement_price && targetStatus === 'ACTIVE') {
      setErrorMsg(
        `Cannot activate basket: ${calcResult.missing_procurement_products.length} product(s) are missing a procurement price. Please update their procurement price in Catalog first.`
      );
      return;
    }

    setSaveLoading(true);
    try {
      const itemsPayload = Object.keys(selectedItems)
        .map((k) => ({
          product_id: Number(k),
          quantity: selectedItems[k],
        }))
        .filter((it) => it.quantity > 0);

      const payload = {
        title: title.trim(),
        description: description.trim(),
        image_url: imageUrl.trim(),
        pricing_mode: pricingMode,
        margin_percent: marginPercentInput !== '' ? Number(marginPercentInput) : null,
        selling_price: sellingPriceInput !== '' ? Number(sellingPriceInput) : null,
        items: itemsPayload,
        target_status: targetStatus,
      };

      let result;
      if (editingBasket?.id) {
        result = await apiUpdateSellerBasket(editingBasket.id, payload);
      } else {
        result = await apiCreateSellerBasket(payload);
      }

      onSaved?.(result);
      onClose();
    } catch (err) {
      setErrorMsg(err.message || 'Failed to save basket offer.');
    } finally {
      setSaveLoading(false);
    }
  };

  const filteredProducts = useMemo(() => {
    if (!productSearch.trim()) return productsList;
    const q = productSearch.toLowerCase();
    return productsList.filter(
      (p) =>
        p.title?.toLowerCase().includes(q) ||
        p.sku?.toLowerCase().includes(q) ||
        p.brand?.toLowerCase().includes(q)
    );
  }, [productsList, productSearch]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-xs animate-fade-in overflow-y-auto">
      <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl max-w-4xl w-full my-8 flex flex-col max-h-[92vh] overflow-hidden">
        {/* Header */}
        <div className="px-6 py-4 border-b border-slate-100 flex items-center justify-between bg-slate-50/50">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-emerald-100 text-emerald-700 flex items-center justify-center">
              <ShoppingBag className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-base font-bold text-slate-900">
                {editingBasket ? 'Edit Basket Combo Offer' : 'Create Basket Combo Offer'}
              </h2>
              <p className="text-xs text-slate-500">
                Bundle 3+ products into a single deal with live margin calculation
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-100 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Area */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {errorMsg && (
            <div className="p-3.5 bg-rose-50 border border-rose-200 rounded-xl flex items-start gap-2.5 text-rose-700 text-xs">
              <AlertTriangle className="w-4 h-4 shrink-0 text-rose-500 mt-0.5" />
              <div className="flex-1 font-semibold">{errorMsg}</div>
            </div>
          )}

          {/* ── STEP 1: BASKET BASIC DETAILS ──────────────────────────────── */}
          <div className="space-y-3">
            <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
              <span>1. Offer Information</span>
            </h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="space-y-1.5">
                <label className="text-xs font-bold text-slate-700">
                  Basket Title <span className="text-rose-500">*</span>
                </label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g. Monthly Grocery Essentials Bundle (10 items for ₹999)"
                  className="w-full px-3.5 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 outline-none focus:bg-white focus:border-emerald-500 font-medium"
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-xs font-bold text-slate-700">Cover Image</label>
                <div className="flex items-center gap-2">
                  <input
                    type="text"
                    value={imageUrl}
                    onChange={(e) => setImageUrl(e.target.value)}
                    placeholder="Image URL or upload a file"
                    className="flex-1 px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 outline-none focus:bg-white focus:border-emerald-500 font-medium"
                  />
                  <label className="inline-flex items-center gap-1 px-3 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs font-bold rounded-xl cursor-pointer transition-colors border border-slate-200">
                    <UploadCloud className="w-3.5 h-3.5" />
                    <span>{uploadingImage ? 'Uploading...' : 'Upload'}</span>
                    <input
                      type="file"
                      accept="image/*"
                      onChange={handleImageFileChange}
                      disabled={uploadingImage}
                      className="hidden"
                    />
                  </label>
                </div>
              </div>
            </div>

            <div className="space-y-1.5">
              <label className="text-xs font-bold text-slate-700">Description (Optional)</label>
              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder="Short customer-facing description of the combo offer deal..."
                rows={2}
                className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 outline-none focus:bg-white focus:border-emerald-500 font-medium resize-none"
              />
            </div>
          </div>

          {/* ── STEP 2: PRODUCT PICKER ────────────────────────────────────── */}
          <div className="space-y-3 pt-2 border-t border-slate-100">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
                <span>2. Select Component Products</span>
              </h3>
              <div
                className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold ${
                  distinctCount >= 3
                    ? 'bg-emerald-100 text-emerald-800 border border-emerald-300'
                    : 'bg-amber-100 text-amber-800 border border-amber-300'
                }`}
              >
                {distinctCount >= 3 ? (
                  <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
                ) : (
                  <AlertTriangle className="w-3.5 h-3.5 text-amber-600" />
                )}
                <span>
                  {distinctCount} of 3 minimum distinct products selected
                </span>
              </div>
            </div>

            {/* Product search */}
            <div className="relative">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={productSearch}
                onChange={(e) => setProductSearch(e.target.value)}
                placeholder="Filter approved catalog products by title, SKU, brand..."
                className="w-full pl-9 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 outline-none focus:bg-white focus:border-emerald-500"
              />
            </div>

            {/* Products Picker Box */}
            <div className="border border-slate-200 rounded-2xl overflow-hidden max-h-56 overflow-y-auto bg-slate-50/50 divide-y divide-slate-100">
              {loadingProducts ? (
                <div className="p-8 text-center text-slate-400 text-xs">
                  <RefreshCw className="w-5 h-5 animate-spin mx-auto mb-2 text-emerald-600" />
                  Loading your approved catalog products...
                </div>
              ) : filteredProducts.length === 0 ? (
                <div className="p-8 text-center text-slate-400 text-xs">
                  No approved products match your search.
                </div>
              ) : (
                filteredProducts.map((p) => {
                  const isSelected = !!selectedItems[p.id];
                  const qty = selectedItems[p.id] || 0;
                  const hasProcPrice = p.procurement_price !== null && p.procurement_price !== undefined;

                  return (
                    <div
                      key={p.id}
                      className={`p-3 flex items-center justify-between gap-3 transition-colors ${
                        isSelected ? 'bg-emerald-50/70' : 'hover:bg-white'
                      }`}
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        <button
                          type="button"
                          onClick={() => handleToggleProduct(p.id)}
                          className={`w-5 h-5 rounded-md flex items-center justify-center border transition-colors shrink-0 ${
                            isSelected
                              ? 'bg-emerald-600 border-emerald-600 text-white'
                              : 'border-slate-300 bg-white hover:border-emerald-500'
                          }`}
                        >
                          {isSelected && <Check className="w-3.5 h-3.5 stroke-[3]" />}
                        </button>
                        <div className="min-w-0">
                          <p className="text-xs font-bold text-slate-900 truncate">{p.title}</p>
                          <div className="flex items-center gap-2 text-[10px] text-slate-500 mt-0.5">
                            <span className="font-mono">{p.sku}</span>
                            <span>•</span>
                            <span>MRP: ₹{p.mrp}</span>
                            <span>•</span>
                            {hasProcPrice ? (
                              <span className="text-emerald-700 font-semibold">
                                Cost: ₹{p.procurement_price}
                              </span>
                            ) : (
                              <span className="text-amber-700 font-semibold bg-amber-100 px-1 rounded">
                                Missing procurement price
                              </span>
                            )}
                          </div>
                        </div>
                      </div>

                      {/* Quantity Stepper */}
                      {isSelected ? (
                        <div className="flex items-center gap-1.5 bg-white border border-emerald-300 rounded-xl px-2 py-1 shadow-2xs">
                          <button
                            type="button"
                            onClick={() => handleUpdateQty(p.id, -1)}
                            className="p-0.5 text-slate-500 hover:text-slate-800"
                          >
                            <Minus className="w-3.5 h-3.5" />
                          </button>
                          <span className="w-6 text-center text-xs font-bold font-mono text-emerald-800">
                            {qty}
                          </span>
                          <button
                            type="button"
                            onClick={() => handleUpdateQty(p.id, 1)}
                            className="p-0.5 text-slate-500 hover:text-slate-800"
                          >
                            <Plus className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      ) : (
                        <button
                          type="button"
                          onClick={() => handleToggleProduct(p.id)}
                          className="px-2.5 py-1 text-[11px] font-bold text-slate-600 hover:text-emerald-700 hover:bg-emerald-50 rounded-lg border border-slate-200 transition-colors"
                        >
                          Add
                        </button>
                      )}
                    </div>
                  );
                })
              )}
            </div>
          </div>

          {/* ── STEP 3: LIVE TWO-WAY MARGIN CALCULATOR ─────────────────────── */}
          <div className="space-y-3 pt-2 border-t border-slate-100">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
                <Percent className="w-3.5 h-3.5 text-emerald-600" />
                <span>3. Live Margin & Price Calculator</span>
              </h3>
              {calculating && (
                <span className="inline-flex items-center gap-1 text-[10px] text-emerald-600 font-semibold animate-pulse">
                  <RefreshCw className="w-3 h-3 animate-spin" />
                  Calculating...
                </span>
              )}
            </div>

            {/* Calculator Cards & Inputs */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Cost Summary Card */}
              <div className="bg-slate-50 p-4 rounded-2xl border border-slate-200 space-y-3">
                <div className="flex items-center justify-between text-xs text-slate-500">
                  <span>Total MRP (Combined Items)</span>
                  <span className="font-bold font-mono text-slate-900 text-sm">
                    ₹{calcResult.total_mrp}
                  </span>
                </div>
                <div className="flex items-center justify-between text-xs text-slate-500">
                  <span>Total Procurement Cost</span>
                  <span className="font-bold font-mono text-indigo-700 text-sm">
                    ₹{calcResult.total_procurement_price}
                  </span>
                </div>
                {calcResult.has_missing_procurement_price && (
                  <div className="p-2 bg-amber-50 border border-amber-200 rounded-xl text-[11px] text-amber-800 font-medium flex items-start gap-1.5">
                    <AlertTriangle className="w-3.5 h-3.5 text-amber-600 shrink-0 mt-0.5" />
                    <span>
                      {calcResult.missing_procurement_products.length} product(s) in this basket have no procurement price set. Margin calculation may be inaccurate.
                    </span>
                  </div>
                )}
              </div>

              {/* Two-way live inputs */}
              <div className="bg-emerald-50/50 p-4 rounded-2xl border border-emerald-200 space-y-3">
                <div className="grid grid-cols-2 gap-3">
                  <div className="space-y-1">
                    <label className="text-[11px] font-bold text-slate-700 flex items-center gap-1">
                      <Percent className="w-3 h-3 text-emerald-600" />
                      <span>Target Margin %</span>
                    </label>
                    <input
                      type="number"
                      step="0.1"
                      value={marginPercentInput}
                      onChange={(e) => handleMarginChange(e.target.value)}
                      placeholder="15"
                      className="w-full px-3 py-2 bg-white border border-emerald-300 rounded-xl text-xs font-bold font-mono text-slate-900 outline-none focus:ring-2 focus:ring-emerald-500/20"
                    />
                  </div>

                  <div className="space-y-1">
                    <label className="text-[11px] font-bold text-slate-700 flex items-center gap-1">
                      <IndianRupee className="w-3 h-3 text-emerald-600" />
                      <span>Basket Selling Price</span>
                    </label>
                    <input
                      type="number"
                      step="1"
                      value={sellingPriceInput}
                      onChange={(e) => handleSellingPriceChange(e.target.value)}
                      placeholder="999"
                      className="w-full px-3 py-2 bg-white border border-emerald-300 rounded-xl text-xs font-bold font-mono text-slate-900 outline-none focus:ring-2 focus:ring-emerald-500/20"
                    />
                  </div>
                </div>

                {/* Profit & Savings summary banner */}
                <div className="pt-2 border-t border-emerald-200/70 flex items-center justify-between text-xs">
                  <div>
                    <span className="text-[10px] text-slate-500 uppercase font-bold">Estimated Profit</span>
                    <p className="font-bold font-mono text-emerald-800 text-sm">
                      +₹{calcResult.profit_amount}
                    </p>
                  </div>
                  <div className="text-right">
                    <span className="text-[10px] text-slate-500 uppercase font-bold">Customer Saves</span>
                    <p className="font-bold font-mono text-slate-900 text-sm">
                      ₹{calcResult.savings_vs_mrp} ({calcResult.savings_percent}%)
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Footer Actions */}
        <div className="px-6 py-4 border-t border-slate-100 flex items-center justify-between bg-slate-50/50">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-bold text-slate-600 hover:text-slate-800 hover:bg-slate-100 rounded-xl transition-colors"
          >
            Cancel
          </button>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => handleSaveBasket('DRAFT')}
              disabled={saveLoading}
              className="px-4 py-2 text-xs font-bold text-slate-700 bg-white hover:bg-slate-100 border border-slate-300 rounded-xl transition-all shadow-2xs disabled:opacity-50"
            >
              Save as Draft
            </button>
            <button
              type="button"
              onClick={() => handleSaveBasket('ACTIVE')}
              disabled={saveLoading || distinctCount < 3}
              className="inline-flex items-center gap-1.5 px-4 py-2 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 rounded-xl shadow-xs transition-all disabled:opacity-50 active:scale-95"
            >
              {saveLoading ? (
                <RefreshCw className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Check className="w-3.5 h-3.5" />
              )}
              <span>Save & Activate Live</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
