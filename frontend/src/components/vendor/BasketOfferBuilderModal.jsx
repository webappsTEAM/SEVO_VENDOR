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
  Star,
  ChevronDown,
  ChevronUp,
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

  // Basket form
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [imageUrl, setImageUrl] = useState('');
  const [uploadingImage, setUploadingImage] = useState(false);

  // Slots state: Array of { id: string|number, slot_title: string, quantity: number, product_ids: number[], default_product_id: number|null, search: string, isOpen: boolean }
  const [slots, setSlots] = useState([]);

  // Pricing mode & inputs (Fixed selling price stays top-level)
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

      let initialSlots = [];
      if (Array.isArray(editingBasket.slots) && editingBasket.slots.length > 0) {
        initialSlots = editingBasket.slots.map((s, idx) => {
          const pids = Array.isArray(s.options) && s.options.length > 0
            ? s.options.map((o) => o.product_id || o.id)
            : (s.default_product_id ? [s.default_product_id] : []);
          const defPid = s.default_product_id || s.options?.find((o) => o.is_default)?.product_id || pids[0] || null;
          return {
            id: s.id || `slot_${idx}_${Date.now()}`,
            slot_title: s.slot_title || `Slot ${idx + 1}`,
            quantity: s.quantity || 1,
            product_ids: pids,
            default_product_id: defPid,
            search: '',
            isOpen: true,
          };
        });
      } else if (Array.isArray(editingBasket.items) && editingBasket.items.length > 0) {
        initialSlots = editingBasket.items.map((it, idx) => {
          const opts = Array.isArray(it.options) && it.options.length > 0 ? it.options : null;
          const pids = opts
            ? opts.map((o) => o.product_id || o.id)
            : [it.product || it.product_id || it.id].filter(Boolean);
          const defPid = it.default_product_id || opts?.find((o) => o.is_default)?.product_id || pids[0] || null;
          return {
            id: it.id || `slot_${idx}_${Date.now()}`,
            slot_title: it.slot_title || it.product_title || `Slot ${idx + 1}`,
            quantity: it.quantity || 1,
            product_ids: pids,
            default_product_id: defPid,
            search: '',
            isOpen: true,
          };
        });
      }

      if (initialSlots.length < 3) {
        while (initialSlots.length < 3) {
          const idx = initialSlots.length;
          initialSlots.push({
            id: `slot_${idx}_${Date.now()}`,
            slot_title: `Slot ${idx + 1}`,
            quantity: 1,
            product_ids: [],
            default_product_id: null,
            search: '',
            isOpen: true,
          });
        }
      }
      setSlots(initialSlots);
    } else {
      setTitle('');
      setDescription('');
      setImageUrl('');
      setSlots([
        { id: `slot_0_${Date.now()}`, slot_title: 'Slot 1: Choice of Brand', quantity: 1, product_ids: [], default_product_id: null, search: '', isOpen: true },
        { id: `slot_1_${Date.now()}`, slot_title: 'Slot 2: Choice of Brand', quantity: 1, product_ids: [], default_product_id: null, search: '', isOpen: true },
        { id: `slot_2_${Date.now()}`, slot_title: 'Slot 3: Choice of Brand', quantity: 1, product_ids: [], default_product_id: null, search: '', isOpen: true },
      ]);
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

  // Product map for quick lookup
  const productMap = useMemo(() => {
    const map = {};
    productsList.forEach((p) => {
      map[p.id] = p;
    });
    return map;
  }, [productsList]);

  // Valid configured slots count (slots that have at least 1 product selected)
  const validSlotsCount = useMemo(() => {
    return slots.filter((s) => s.product_ids && s.product_ids.length > 0).length;
  }, [slots]);

  // ── Slot Manipulation Helpers ─────────────────────────────────────────────
  const handleAddSlot = () => {
    const nextIdx = slots.length + 1;
    setSlots((prev) => [
      ...prev,
      {
        id: `slot_${Date.now()}_${Math.random().toString(36).substr(2, 4)}`,
        slot_title: `Slot ${nextIdx}: Choice of Brand`,
        quantity: 1,
        product_ids: [],
        default_product_id: null,
        search: '',
        isOpen: true,
      },
    ]);
  };

  const handleRemoveSlot = (slotId) => {
    if (slots.length <= 3) {
      setErrorMsg('A basket combo offer must contain at least 3 slots.');
      return;
    }
    setSlots((prev) => prev.filter((s) => s.id !== slotId));
  };

  const handleUpdateSlotTitle = (slotId, titleVal) => {
    setSlots((prev) =>
      prev.map((s) => (s.id === slotId ? { ...s, slot_title: titleVal } : s))
    );
  };

  const handleUpdateSlotQty = (slotId, delta) => {
    setSlots((prev) =>
      prev.map((s) => {
        if (s.id !== slotId) return s;
        const newQty = Math.max(1, s.quantity + delta);
        return { ...s, quantity: newQty };
      })
    );
  };

  const handleToggleSlotProduct = (slotId, prodId) => {
    setSlots((prev) =>
      prev.map((s) => {
        if (s.id !== slotId) return s;
        const exists = s.product_ids.includes(prodId);
        let nextPids = exists
          ? s.product_ids.filter((id) => id !== prodId)
          : [...s.product_ids, prodId];

        let nextDef = s.default_product_id;
        if (!nextPids.includes(nextDef)) {
          nextDef = nextPids[0] || null;
        }
        if (!nextDef && nextPids.length > 0) {
          nextDef = nextPids[0];
        }

        return {
          ...s,
          product_ids: nextPids,
          default_product_id: nextDef,
        };
      })
    );
  };

  const handleSetSlotDefaultProduct = (slotId, prodId) => {
    setSlots((prev) =>
      prev.map((s) => {
        if (s.id !== slotId) return s;
        return { ...s, default_product_id: prodId };
      })
    );
  };

  const handleUpdateSlotSearch = (slotId, query) => {
    setSlots((prev) =>
      prev.map((s) => (s.id === slotId ? { ...s, search: query } : s))
    );
  };

  const handleToggleSlotAccordion = (slotId) => {
    setSlots((prev) =>
      prev.map((s) => (s.id === slotId ? { ...s, isOpen: !s.isOpen } : s))
    );
  };

  // ── Live Calculation (Server Preview Calculation) ─────────────────────────
  const runLiveCalculation = useCallback(
    async (mode, marginVal, priceVal, currentSlots) => {
      const slotsPayload = currentSlots
        .filter((s) => s.product_ids && s.product_ids.length > 0)
        .map((s) => ({
          slot_title: s.slot_title,
          quantity: s.quantity,
          product_ids: s.product_ids,
          default_product_id: s.default_product_id || s.product_ids[0],
        }));

      if (slotsPayload.length === 0) {
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
          slots: slotsPayload,
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
    if (validSlotsCount === 0) return;
    const timer = setTimeout(() => {
      runLiveCalculation(pricingMode, marginPercentInput, sellingPriceInput, slots);
    }, 250);
    return () => clearTimeout(timer);
  }, [slots, pricingMode, validSlotsCount, runLiveCalculation]);

  const handleMarginChange = (val) => {
    setMarginPercentInput(val);
    setPricingMode('MARGIN');
    runLiveCalculation('MARGIN', val, sellingPriceInput, slots);
  };

  const handleSellingPriceChange = (val) => {
    setSellingPriceInput(val);
    setPricingMode('FIXED_PRICE');
    runLiveCalculation('FIXED_PRICE', marginPercentInput, val, slots);
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
      setErrorMsg('Please enter a basket combo title.');
      return;
    }
    if (validSlotsCount < 3) {
      setErrorMsg('A basket combo offer must contain at least 3 distinct slots with eligible products selected.');
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
      const slotsPayload = slots
        .filter((s) => s.product_ids && s.product_ids.length > 0)
        .map((s) => ({
          slot_title: s.slot_title.trim(),
          quantity: s.quantity,
          product_ids: s.product_ids,
          default_product_id: s.default_product_id || s.product_ids[0],
        }));

      const payload = {
        title: title.trim(),
        description: description.trim(),
        image_url: imageUrl.trim(),
        pricing_mode: pricingMode,
        margin_percent: marginPercentInput !== '' ? Number(marginPercentInput) : null,
        selling_price: sellingPriceInput !== '' ? Number(sellingPriceInput) : null,
        slots: slotsPayload,
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
                Create slot-based combo deals where customers choose from eligible brands & products
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
                  Combo Offer Title <span className="text-rose-500">*</span>
                </label>
                <input
                  type="text"
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g. Cooking Essentials Super Saver Combo (Oil + Salt + Atta for ₹299)"
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
                placeholder="Short customer-facing description of the combo deal..."
                rows={2}
                className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 outline-none focus:bg-white focus:border-emerald-500 font-medium resize-none"
              />
            </div>
          </div>

          {/* ── STEP 2: SLOT-BASED BUILDER ─────────────────────────────────── */}
          <div className="space-y-3 pt-2 border-t border-slate-100">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <div>
                <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
                  <Layers className="w-3.5 h-3.5 text-emerald-600" />
                  <span>2. Combo Slots & Eligible Brand Choices</span>
                </h3>
                <p className="text-[11px] text-slate-500 mt-0.5">
                  Define component slots. For each slot, select one or multiple eligible products the customer can choose from.
                </p>
              </div>
              <div
                className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold ${
                  validSlotsCount >= 3
                    ? 'bg-emerald-100 text-emerald-800 border border-emerald-300'
                    : 'bg-amber-100 text-amber-800 border border-amber-300'
                }`}
              >
                {validSlotsCount >= 3 ? (
                  <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
                ) : (
                  <AlertTriangle className="w-3.5 h-3.5 text-amber-600" />
                )}
                <span>
                  {validSlotsCount} of 3 min slots configured
                </span>
              </div>
            </div>

            {/* Slots List */}
            <div className="space-y-3">
              {slots.map((slot, sIdx) => {
                const isConfigured = slot.product_ids && slot.product_ids.length > 0;
                const slotSearchQuery = (slot.search || '').toLowerCase();
                const filteredForSlot = productsList.filter(
                  (p) =>
                    !slotSearchQuery ||
                    p.title?.toLowerCase().includes(slotSearchQuery) ||
                    p.sku?.toLowerCase().includes(slotSearchQuery) ||
                    p.brand?.toLowerCase().includes(slotSearchQuery)
                );

                return (
                  <div
                    key={slot.id}
                    className={`border rounded-2xl transition-all overflow-hidden bg-white ${
                      isConfigured
                        ? 'border-emerald-200/80 shadow-2xs'
                        : 'border-slate-200 shadow-2xs'
                    }`}
                  >
                    {/* Slot Header Bar */}
                    <div className="p-3.5 bg-slate-50/80 flex flex-wrap items-center justify-between gap-3 border-b border-slate-100">
                      <div className="flex items-center gap-2.5 flex-1 min-w-[200px]">
                        <span className="w-6 h-6 rounded-lg bg-emerald-700 text-white text-xs font-bold flex items-center justify-center shrink-0">
                          {sIdx + 1}
                        </span>
                        <input
                          type="text"
                          value={slot.slot_title}
                          onChange={(e) => handleUpdateSlotTitle(slot.id, e.target.value)}
                          placeholder={`e.g. Slot ${sIdx + 1}: Cooking Oil (1L)`}
                          className="px-2.5 py-1 bg-white border border-slate-200 rounded-lg text-xs font-bold text-slate-900 outline-none focus:border-emerald-500 flex-1 max-w-sm"
                        />
                      </div>

                      <div className="flex items-center gap-3 shrink-0">
                        {/* Quantity Stepper */}
                        <div className="flex items-center gap-1.5 bg-white border border-slate-200 rounded-lg px-2 py-0.5">
                          <span className="text-[10px] uppercase font-bold text-slate-400 mr-1">Qty</span>
                          <button
                            type="button"
                            onClick={() => handleUpdateSlotQty(slot.id, -1)}
                            className="p-0.5 text-slate-500 hover:text-slate-800"
                          >
                            <Minus className="w-3 h-3" />
                          </button>
                          <span className="w-5 text-center text-xs font-bold font-mono text-emerald-800">
                            {slot.quantity}
                          </span>
                          <button
                            type="button"
                            onClick={() => handleUpdateSlotQty(slot.id, 1)}
                            className="p-0.5 text-slate-500 hover:text-slate-800"
                          >
                            <Plus className="w-3 h-3" />
                          </button>
                        </div>

                        {/* Selected Options Count Badge */}
                        <span
                          className={`text-[11px] font-bold px-2 py-0.5 rounded-md ${
                            slot.product_ids.length > 1
                              ? 'bg-purple-100 text-purple-800'
                              : slot.product_ids.length === 1
                              ? 'bg-emerald-100 text-emerald-800'
                              : 'bg-slate-100 text-slate-500'
                          }`}
                        >
                          {slot.product_ids.length === 0
                            ? 'No options'
                            : slot.product_ids.length === 1
                            ? '1 Fixed Product'
                            : `${slot.product_ids.length} Eligible Options`}
                        </span>

                        {/* Delete Slot Button */}
                        {slots.length > 3 && (
                          <button
                            type="button"
                            onClick={() => handleRemoveSlot(slot.id)}
                            title="Remove slot"
                            className="p-1 text-slate-400 hover:text-rose-600 rounded-md hover:bg-rose-50 transition-colors"
                          >
                            <Trash2 className="w-3.5 h-3.5" />
                          </button>
                        )}

                        {/* Toggle Open/Close */}
                        <button
                          type="button"
                          onClick={() => handleToggleSlotAccordion(slot.id)}
                          className="p-1 text-slate-400 hover:text-slate-700 rounded-md hover:bg-slate-200 transition-colors"
                        >
                          {slot.isOpen ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                        </button>
                      </div>
                    </div>

                    {/* Slot Body (Product Picker for this Slot) */}
                    {slot.isOpen && (
                      <div className="p-4 space-y-3 bg-white">
                        {/* Currently Selected Options Chips */}
                        {slot.product_ids.length > 0 && (
                          <div className="space-y-1">
                            <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider">
                              Eligible Choices in this slot (Star marks default):
                            </span>
                            <div className="flex flex-wrap gap-1.5">
                              {slot.product_ids.map((pid) => {
                                const p = productMap[pid];
                                const isDef = slot.default_product_id === pid;
                                if (!p) return null;
                                return (
                                  <div
                                    key={pid}
                                    className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-xl text-xs font-medium border ${
                                      isDef
                                        ? 'bg-amber-50 border-amber-300 text-amber-900 font-bold'
                                        : 'bg-emerald-50 border-emerald-200 text-emerald-900'
                                    }`}
                                  >
                                    <button
                                      type="button"
                                      onClick={() => handleSetSlotDefaultProduct(slot.id, pid)}
                                      title={isDef ? 'Default Option' : 'Click to set as default option'}
                                      className={`p-0.5 rounded hover:scale-110 transition-transform ${
                                        isDef ? 'text-amber-500 fill-amber-500' : 'text-slate-400 hover:text-amber-500'
                                      }`}
                                    >
                                      <Star className={`w-3 h-3 ${isDef ? 'fill-amber-400 text-amber-500' : ''}`} />
                                    </button>
                                    <span className="truncate max-w-[180px]">{p.title}</span>
                                    <span className="text-[10px] text-slate-500 font-mono">₹{p.mrp}</span>
                                    <button
                                      type="button"
                                      onClick={() => handleToggleSlotProduct(slot.id, pid)}
                                      className="p-0.5 text-slate-400 hover:text-rose-600 rounded"
                                    >
                                      <X className="w-3 h-3" />
                                    </button>
                                  </div>
                                );
                              })}
                            </div>
                          </div>
                        )}

                        {/* Search in Catalog */}
                        <div className="relative">
                          <Search className="w-3.5 h-3.5 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                          <input
                            type="text"
                            value={slot.search || ''}
                            onChange={(e) => handleUpdateSlotSearch(slot.id, e.target.value)}
                            placeholder={`Search catalog products to add to ${slot.slot_title}...`}
                            className="w-full pl-8 pr-3 py-1.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 outline-none focus:bg-white focus:border-emerald-500"
                          />
                        </div>

                        {/* Product Selection List */}
                        <div className="border border-slate-100 rounded-xl overflow-hidden max-h-44 overflow-y-auto divide-y divide-slate-50 bg-slate-50/40">
                          {loadingProducts ? (
                            <div className="p-4 text-center text-slate-400 text-xs">
                              <RefreshCw className="w-4 h-4 animate-spin mx-auto mb-1 text-emerald-600" />
                              Loading catalog products...
                            </div>
                          ) : filteredForSlot.length === 0 ? (
                            <div className="p-4 text-center text-slate-400 text-xs">
                              No products found matching "{slot.search}".
                            </div>
                          ) : (
                            filteredForSlot.map((p) => {
                              const isChecked = slot.product_ids.includes(p.id);
                              const isDef = slot.default_product_id === p.id;
                              const hasProcPrice = p.procurement_price !== null && p.procurement_price !== undefined;

                              return (
                                <div
                                  key={p.id}
                                  className={`px-3 py-2 flex items-center justify-between gap-3 text-xs transition-colors ${
                                    isChecked ? 'bg-emerald-50/80 font-medium' : 'hover:bg-white'
                                  }`}
                                >
                                  <div className="flex items-center gap-2.5 min-w-0">
                                    <button
                                      type="button"
                                      onClick={() => handleToggleSlotProduct(slot.id, p.id)}
                                      className={`w-4 h-4 rounded flex items-center justify-center border transition-colors shrink-0 ${
                                        isChecked
                                          ? 'bg-emerald-600 border-emerald-600 text-white'
                                          : 'border-slate-300 bg-white hover:border-emerald-500'
                                      }`}
                                    >
                                      {isChecked && <Check className="w-3 h-3 stroke-[3]" />}
                                    </button>
                                    <div className="min-w-0">
                                      <p className="truncate text-slate-900 text-[11px] font-semibold">{p.title}</p>
                                      <div className="flex items-center gap-2 text-[10px] text-slate-500">
                                        <span className="font-mono">{p.sku}</span>
                                        <span>•</span>
                                        <span>MRP: ₹{p.mrp}</span>
                                        <span>•</span>
                                        {hasProcPrice ? (
                                          <span className="text-emerald-700">Cost: ₹{p.procurement_price}</span>
                                        ) : (
                                          <span className="text-amber-700 bg-amber-100 px-1 rounded">No cost</span>
                                        )}
                                      </div>
                                    </div>
                                  </div>

                                  <div className="flex items-center gap-1.5 shrink-0">
                                    {isChecked && (
                                      <button
                                        type="button"
                                        onClick={() => handleSetSlotDefaultProduct(slot.id, p.id)}
                                        className={`px-2 py-0.5 rounded text-[10px] font-bold border transition-colors flex items-center gap-1 ${
                                          isDef
                                            ? 'bg-amber-100 border-amber-300 text-amber-900'
                                            : 'bg-white border-slate-200 text-slate-500 hover:text-amber-700 hover:border-amber-300'
                                        }`}
                                      >
                                        <Star className={`w-2.5 h-2.5 ${isDef ? 'fill-amber-500 text-amber-500' : ''}`} />
                                        <span>{isDef ? 'Default' : 'Make Default'}</span>
                                      </button>
                                    )}
                                    <button
                                      type="button"
                                      onClick={() => handleToggleSlotProduct(slot.id, p.id)}
                                      className={`px-2 py-0.5 rounded text-[10px] font-bold transition-colors ${
                                        isChecked
                                          ? 'text-rose-600 hover:bg-rose-50'
                                          : 'text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200'
                                      }`}
                                    >
                                      {isChecked ? 'Remove' : '+ Select'}
                                    </button>
                                  </div>
                                </div>
                              );
                            })
                          )}
                        </div>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>

            {/* Add Slot Button */}
            <button
              type="button"
              onClick={handleAddSlot}
              className="w-full py-2.5 border-2 border-dashed border-emerald-300 hover:border-emerald-500 bg-emerald-50/40 hover:bg-emerald-50 text-emerald-800 font-bold text-xs rounded-2xl flex items-center justify-center gap-1.5 transition-colors"
            >
              <Plus className="w-4 h-4" />
              <span>Add Another Slot</span>
            </button>
          </div>

          {/* ── STEP 3: LIVE TWO-WAY MARGIN & PRICE CALCULATOR ──────────────── */}
          <div className="space-y-3 pt-2 border-t border-slate-100">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
                <Percent className="w-3.5 h-3.5 text-emerald-600" />
                <span>3. Live Margin & Combo Selling Price</span>
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
                  <span>Base Total MRP (Default Options)</span>
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
                      {calcResult.missing_procurement_products?.length} product(s) in this combo have no procurement price set. Margin calculation may be inaccurate.
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
                      <span>Combo Selling Price</span>
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
              disabled={saveLoading || validSlotsCount < 3}
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
