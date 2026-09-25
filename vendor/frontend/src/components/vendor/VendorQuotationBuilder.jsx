import React, { useState, useEffect, useMemo } from 'react';
import {
  X,
  Plus,
  Trash2,
  FileSpreadsheet,
  Send,
  Save,
  CheckCircle2,
  AlertCircle,
  Percent,
  Receipt,
  Calendar,
  ShieldAlert,
  Loader2,
  Tag,
  ShieldCheck,
  ChevronRight,
  Sparkles,
} from 'lucide-react';
import {
  apiSaveQuotation,
  apiSendQuotation,
  apiSubmitQuotationForReview,
} from '../../api/vendorEstimationService.js';

const QUICK_ITEM_TEMPLATES = [
  { title: 'R32 Refrigerant Gas Refill (Up to 1kg)', item_type: 'GAS', unit_price: 1850, quantity: 1, unit: 'kg', category_name_snapshot: 'Gas & Leakage' },
  { title: 'R410A Refrigerant Gas Refill (Up to 1kg)', item_type: 'GAS', unit_price: 1950, quantity: 1, unit: 'kg', category_name_snapshot: 'Gas & Leakage' },
  { title: 'Gas Leakage Repair & Nitrogen Pressure Brazing', item_type: 'LABOR', unit_price: 650, quantity: 1, unit: 'job', category_name_snapshot: 'Gas & Leakage' },
  { title: 'Inverter AC Dual Run Capacitor (45/5 uF)', item_type: 'PART', unit_price: 850, quantity: 1, unit: 'pc', category_name_snapshot: 'Electrical & PCB' },
  { title: 'Inverter PCB Motherboard Repair & Servicing', item_type: 'PART', unit_price: 2450, quantity: 1, unit: 'unit', category_name_snapshot: 'Electrical & PCB' },
  { title: 'Condenser Fan Motor Replacement', item_type: 'PART', unit_price: 1650, quantity: 1, unit: 'pc', category_name_snapshot: 'Motor & Fan' },
  { title: 'Chemical Jet Foam Deep Coil Wash', item_type: 'LABOR', unit_price: 799, quantity: 1, unit: 'service', category_name_snapshot: 'Servicing & Cleaning' },
  { title: 'Drain Pipe Flushing & Tray Re-alignment', item_type: 'LABOR', unit_price: 350, quantity: 1, unit: 'service', category_name_snapshot: 'Servicing & Cleaning' },
];

export default function VendorQuotationBuilder({
  estimation,
  isOpen,
  onClose,
  onQuotationSent,
}) {
  const [items, setItems] = useState([]);
  const [applyGst, setApplyGst] = useState(true);
  const [taxRatePercent, setTaxRatePercent] = useState(18);
  const [discountAmount, setDiscountAmount] = useState(0);
  const [validUntil, setValidUntil] = useState('');
  const [notes, setNotes] = useState('Includes 90-day CalServices warranty on all replacement parts and labor.');
  const [saving, setSaving] = useState(false);
  const [submittingReview, setSubmittingReview] = useState(false);
  const [showSubmitModal, setShowSubmitModal] = useState(false);
  const [createdQuote, setCreatedQuote] = useState(null);
  const [error, setError] = useState(null);
  const [selectedCategoryTab, setSelectedCategoryTab] = useState('ALL');

  // Rate card snapshot from the DB
  const rateCardSnapshot = estimation?.rate_card_snapshot || [];

  // Group rate card items by category
  const categories = useMemo(() => {
    if (!rateCardSnapshot || rateCardSnapshot.length === 0) return [];
    const catMap = {};
    rateCardSnapshot.forEach((item) => {
      const cat = item.category || 'Standard Repairs';
      if (!catMap[cat]) catMap[cat] = [];
      catMap[cat].push(item);
    });
    return Object.entries(catMap).map(([name, itemList]) => ({ name, items: itemList }));
  }, [rateCardSnapshot]);

  useEffect(() => {
    if (isOpen) {
      setError(null);
      setShowSubmitModal(false);

      // Default valid until: 7 days from today
      const d = new Date();
      d.setDate(d.getDate() + 7);
      setValidUntil(d.toISOString().split('T')[0]);

      // Check if existing quote exists to preload
      const latest = estimation?.latest_quotation || (estimation?.quotations && estimation.quotations[0]);
      if (latest && latest.items && latest.items.length > 0) {
        setItems(
          latest.items.map((it) => ({
            rate_item_id: it.rate_item_id || null,
            category_name_snapshot: it.category_name_snapshot || it.category || '',
            item_name_snapshot: it.item_name_snapshot || it.title || it.service_name || '',
            title: it.service_name || it.title || it.item_name_snapshot,
            item_type: it.item_type || 'LABOR',
            quantity: Number(it.quantity) || 1,
            unit: it.unit || 'unit',
            unit_price: Number(it.unit_price) || Number(it.unit_price_snapshot) || 0,
          }))
        );
        setTaxRatePercent(latest.tax_amount > 0 ? 18 : 0);
        setApplyGst(latest.tax_amount > 0);
        setDiscountAmount(Number(latest.discount_amount) || 0);
        setNotes(latest.notes || notes);
        setCreatedQuote(latest);
      } else {
        // Preload based on inspection findings if available
        if (estimation?.findings && estimation.findings.length > 0) {
          const generatedItems = estimation.findings.map((f) => {
            // Check if matching snapshot item exists
            const matchedSnapshot = rateCardSnapshot.find(
              (r) =>
                r.item_name.toLowerCase().includes(f.finding_type?.toLowerCase()) ||
                f.title.toLowerCase().includes(r.item_name.toLowerCase())
            );

            if (matchedSnapshot) {
              return {
                rate_item_id: matchedSnapshot.id,
                category_name_snapshot: matchedSnapshot.category,
                item_name_snapshot: matchedSnapshot.item_name,
                title: matchedSnapshot.item_name,
                item_type: matchedSnapshot.service_type === 'PART' ? 'PART' : 'LABOR',
                quantity: Number(f.quantity) || 1,
                unit: matchedSnapshot.unit || f.unit || 'unit',
                unit_price: Number(matchedSnapshot.price) || 650,
              };
            }

            let p = 650;
            let itType = 'LABOR';
            if (f.finding_type?.toLowerCase().includes('gas')) {
              p = 1850;
              itType = 'GAS';
            } else if (
              f.finding_type?.toLowerCase().includes('pcb') ||
              f.finding_type?.toLowerCase().includes('motor')
            ) {
              p = 1950;
              itType = 'PART';
            } else if (f.finding_type?.toLowerCase().includes('coil')) {
              p = 799;
              itType = 'LABOR';
            }
            return {
              rate_item_id: null,
              category_name_snapshot: f.finding_type || 'AC Repair',
              item_name_snapshot: f.recommended_action || f.title,
              title: f.recommended_action || f.title,
              item_type: itType,
              quantity: Number(f.quantity) || 1,
              unit: f.unit || 'unit',
              unit_price: p,
            };
          });
          setItems(generatedItems);
        } else {
          // Default starting line item
          setItems([
            {
              rate_item_id: null,
              category_name_snapshot: 'General Labor',
              item_name_snapshot: 'AC Diagnosis & Remedial Service',
              title: 'AC Diagnosis & Remedial Service',
              item_type: 'LABOR',
              quantity: 1,
              unit: 'job',
              unit_price: 650,
            },
          ]);
        }
      }
    }
  }, [isOpen, estimation, rateCardSnapshot]);

  // Real-time calculations
  const subtotal = useMemo(() => {
    return items.reduce((sum, it) => sum + (Number(it.quantity) || 0) * (Number(it.unit_price) || 0), 0);
  }, [items]);

  const taxAmount = useMemo(() => {
    if (!applyGst) return 0;
    return Math.round(subtotal * (Number(taxRatePercent) / 100) * 100) / 100;
  }, [subtotal, applyGst, taxRatePercent]);

  const grandTotal = useMemo(() => {
    const tot = subtotal + taxAmount - (Number(discountAmount) || 0);
    return Math.max(0, Math.round(tot * 100) / 100);
  }, [subtotal, taxAmount, discountAmount]);

  if (!isOpen) return null;

  const handleAddItem = (type = 'LABOR') => {
    setItems([
      ...items,
      {
        rate_item_id: null,
        category_name_snapshot: 'Custom',
        item_name_snapshot: type === 'GAS' ? 'Refrigerant Gas' : type === 'PART' ? 'Spare Component' : 'Labor Service',
        title: type === 'GAS' ? 'Refrigerant Gas' : type === 'PART' ? 'Spare Component' : 'Labor Service',
        item_type: type,
        quantity: 1,
        unit: 'unit',
        unit_price: 500,
      },
    ]);
  };

  const handleAddSnapshotItem = (snap) => {
    const itemName = snap.item_name || snap.item_name_snapshot || '';
    const itemPrice = Number(snap.price ?? snap.price_snapshot ?? 0);
    const itemUnit = snap.unit || snap.unit_snapshot || 'unit';
    const itemCategory = snap.category || snap.category_name_snapshot || 'General';
    const rateId = snap.rate_item_id || snap.id;

    // Check if item already exists in quote
    const existingIndex = items.findIndex(
      (it) => (rateId && it.rate_item_id === rateId) || it.title === itemName
    );
    if (existingIndex >= 0) {
      // Increment quantity
      const updated = [...items];
      updated[existingIndex].quantity = (Number(updated[existingIndex].quantity) || 1) + 1;
      setItems(updated);
    } else {
      setItems([
        ...items,
        {
          rate_item_id: rateId,
          category_name_snapshot: itemCategory,
          item_name_snapshot: itemName,
          title: itemName,
          item_type: snap.service_type === 'PART' ? 'PART' : itemName.toLowerCase().includes('gas') ? 'GAS' : 'LABOR',
          quantity: 1,
          unit: itemUnit,
          unit_price: itemPrice,
        },
      ]);
    }
  };

  const handleQuickAdd = (tpl) => {
    setItems([...items, { ...tpl, item_name_snapshot: tpl.title }]);
  };

  const handleRemoveItem = (index) => {
    setItems(items.filter((_, idx) => idx !== index));
  };

  const handleItemChange = (index, field, val) => {
    const updated = [...items];
    let parsedVal = val;
    if (field === 'quantity') {
      parsedVal = val === '' ? '' : Math.max(0.1, parseFloat(val) || 0);
    } else if (field === 'unit_price') {
      parsedVal = val === '' ? '' : Math.max(0, parseFloat(val) || 0);
    }
    updated[index] = { ...updated[index], [field]: parsedVal };
    if (field === 'title') {
      updated[index].item_name_snapshot = val;
    }
    if (field === 'unit_price') {
      updated[index].unit_price_snapshot = parsedVal;
    }
    setItems(updated);
  };

  const handleSaveDraft = async () => {
    if (items.length === 0) {
      setError('Please add at least one line item.');
      return;
    }

    setSaving(true);
    setError(null);
    try {
      const payload = {
        valid_until: validUntil,
        tax_rate_percent: applyGst ? Number(taxRatePercent) || 0 : 0,
        discount_amount: Number(discountAmount) || 0,
        notes: notes,
        items: items.map((it) => ({
          rate_item_id: it.rate_item_id || null,
          category_name_snapshot: it.category_name_snapshot || '',
          item_name_snapshot: it.item_name_snapshot || it.title,
          title: it.title,
          item_type: it.item_type || 'LABOR',
          quantity: Math.max(0.1, Number(it.quantity) || 1),
          unit: it.unit || 'unit',
          unit_price: Math.max(0, Number(it.unit_price) || 0),
        })),
      };

      const res = await apiSaveQuotation(estimation.id, payload);
      const latestQ = res?.data?.latest_quotation || (res?.data?.quotations && res.data.quotations[0]);
      setCreatedQuote(latestQ);
      return latestQ;
    } catch (err) {
      setError(err.message || 'Failed to save quotation draft.');
      return null;
    } finally {
      setSaving(false);
    }
  };

  const handleSubmitForReview = async () => {
    setSubmittingReview(true);
    setError(null);
    try {
      // 1. Save draft first
      const quote = await handleSaveDraft();
      const quoteId = quote?.id || createdQuote?.id;

      if (!quoteId) {
        throw new Error('Unable to resolve quotation ID for submission.');
      }

      // 2. Submit for Admin Review
      const res = await apiSubmitQuotationForReview(estimation.id, quoteId);
      setShowSubmitModal(false);
      onQuotationSent?.(res?.data || res);
      onClose();
    } catch (err) {
      setError(err.message || 'Failed to submit quotation for admin review.');
    } finally {
      setSubmittingReview(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 bg-zinc-950/70 backdrop-blur-xs animate-in fade-in overflow-y-auto">
      <div className="relative w-full max-w-5xl bg-white rounded-2xl shadow-2xl border border-zinc-200 overflow-hidden my-auto max-h-[94vh] flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-zinc-100 bg-zinc-50 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-emerald-600 text-white flex items-center justify-center shadow-xs">
              <FileSpreadsheet className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-sm sm:text-base font-bold text-zinc-900">
                  Technician Estimation Quotation Builder
                </h2>
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-50 text-emerald-700 border border-emerald-200">
                  Rate-Card Verified
                </span>
              </div>
              <p className="text-xs text-zinc-500">
                Job #{estimation?.request_id} • Customer: {estimation?.customer_name} • {estimation?.ac_details?.ac_brand} ({estimation?.ac_details?.ac_capacity?.replace(/_/g, ' ') || '1.5 Ton'})
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-zinc-400 hover:text-zinc-700 hover:bg-zinc-200 transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6 text-xs">
          {error && (
            <div className="p-3 bg-red-50 border border-red-200 rounded-xl flex items-center gap-2 text-red-700 font-medium">
              <AlertCircle className="w-4 h-4 shrink-0 text-red-500" />
              <span>{error}</span>
            </div>
          )}

          {/* Rate Card Snapshot Catalog Selector */}
          <div className="p-4 bg-slate-50 border border-slate-200 rounded-xl space-y-3">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <Tag className="w-4 h-4 text-emerald-600" />
                <span className="font-bold text-slate-900 uppercase tracking-wider text-[11px]">
                  Authorized Service Rate Card Catalog (Snapshotted for this Booking)
                </span>
              </div>
              <span className="text-[11px] text-slate-500">
                Pick required repair parts & labor found during inspection
              </span>
            </div>

            {/* Category tabs */}
            {categories.length > 0 ? (
              <div className="space-y-2.5">
                <div className="flex items-center gap-1.5 overflow-x-auto pb-1">
                  <button
                    type="button"
                    onClick={() => setSelectedCategoryTab('ALL')}
                    className={`px-3 py-1 rounded-lg text-[11px] font-bold transition-all ${
                      selectedCategoryTab === 'ALL'
                        ? 'bg-slate-900 text-white'
                        : 'bg-white text-slate-700 hover:bg-slate-100 border border-slate-200'
                    }`}
                  >
                    All Items ({rateCardSnapshot.length})
                  </button>
                  {categories.map((cat, idx) => (
                    <button
                      key={idx}
                      type="button"
                      onClick={() => setSelectedCategoryTab(cat.name)}
                      className={`px-3 py-1 rounded-lg text-[11px] font-bold whitespace-nowrap transition-all ${
                        selectedCategoryTab === cat.name
                          ? 'bg-slate-900 text-white'
                          : 'bg-white text-slate-700 hover:bg-slate-100 border border-slate-200'
                      }`}
                    >
                      {cat.name} ({cat.items.length})
                    </button>
                  ))}
                </div>

                {/* Catalog items list */}
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 max-h-44 overflow-y-auto pr-1">
                  {(selectedCategoryTab === 'ALL'
                    ? rateCardSnapshot
                    : categories.find((c) => c.name === selectedCategoryTab)?.items || []
                  ).map((snapItem, sIdx) => {
                    const isAdded = items.some((it) => it.rate_item_id === snapItem.id || it.title === snapItem.item_name);
                    return (
                      <div
                        key={sIdx}
                        onClick={() => handleAddSnapshotItem(snapItem)}
                        className={`p-2.5 rounded-lg border flex items-center justify-between cursor-pointer transition-all ${
                          isAdded
                            ? 'bg-emerald-50/70 border-emerald-300 text-emerald-950'
                            : 'bg-white border-slate-200 hover:border-slate-300 hover:bg-slate-100/60 text-slate-800'
                        }`}
                      >
                        <div className="min-w-0 pr-2">
                          <span className="text-[11px] font-bold block truncate">{snapItem.item_name}</span>
                          <span className="text-[10px] text-slate-500 block truncate">
                            {snapItem.category} • {snapItem.unit || 'unit'}
                          </span>
                        </div>
                        <div className="flex items-center gap-1.5 shrink-0">
                          <span className="font-mono font-bold text-xs text-slate-900">
                            ₹{Number(snapItem.price).toLocaleString('en-IN')}
                          </span>
                          <button
                            type="button"
                            className={`w-6 h-6 rounded-md flex items-center justify-center font-bold text-xs ${
                              isAdded ? 'bg-emerald-600 text-white' : 'bg-slate-200 text-slate-700'
                            }`}
                          >
                            <Plus className="w-3.5 h-3.5" />
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            ) : (
              /* Fallback presets if snapshot empty */
              <div className="flex flex-wrap gap-1.5">
                {QUICK_ITEM_TEMPLATES.map((tpl, tIdx) => (
                  <button
                    key={tIdx}
                    type="button"
                    onClick={() => handleQuickAdd(tpl)}
                    className="px-2.5 py-1 text-[11px] font-medium bg-white hover:bg-zinc-100 text-zinc-700 rounded-lg border border-zinc-200 flex items-center gap-1 transition-colors"
                  >
                    <Plus className="w-3 h-3 text-zinc-400" />
                    <span>{tpl.title}</span>
                    <strong className="text-zinc-900 font-mono">₹{tpl.unit_price}</strong>
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Line Items Table */}
          <div className="border border-zinc-200 rounded-xl overflow-hidden shadow-xs">
            <div className="bg-zinc-50 px-4 py-2.5 border-b border-zinc-200 flex items-center justify-between">
              <span className="font-bold text-zinc-800 text-[11px] uppercase tracking-wider">
                Quotation Line Items ({items.length})
              </span>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => handleAddItem('LABOR')}
                  className="px-2.5 py-1 bg-white border border-zinc-300 hover:bg-zinc-100 text-zinc-700 font-bold rounded-lg flex items-center gap-1"
                >
                  <Plus className="w-3 h-3" /> Add Custom Labor
                </button>
                <button
                  type="button"
                  onClick={() => handleAddItem('PART')}
                  className="px-2.5 py-1 bg-white border border-zinc-300 hover:bg-zinc-100 text-zinc-700 font-bold rounded-lg flex items-center gap-1"
                >
                  <Plus className="w-3 h-3" /> Add Custom Part
                </button>
                <button
                  type="button"
                  onClick={() => handleAddItem('GAS')}
                  className="px-2.5 py-1 bg-white border border-zinc-300 hover:bg-zinc-100 text-zinc-700 font-bold rounded-lg flex items-center gap-1"
                >
                  <Plus className="w-3 h-3" /> Add Gas
                </button>
              </div>
            </div>

            <div className="divide-y divide-zinc-100">
              {items.length === 0 ? (
                <div className="p-8 text-center text-zinc-400">
                  No repair items selected. Click catalog items above to add to the quotation.
                </div>
              ) : (
                items.map((item, idx) => {
                  const lineTotal = (Number(item.quantity) || 0) * (Number(item.unit_price) || 0);
                  return (
                    <div
                      key={idx}
                      className="p-3 bg-white hover:bg-zinc-50/50 flex flex-col sm:flex-row sm:items-center gap-2.5"
                    >
                      {/* Item Type Badge */}
                      <select
                        value={item.item_type}
                        onChange={(e) => handleItemChange(idx, 'item_type', e.target.value)}
                        className="w-24 text-[10px] font-bold uppercase px-2 py-1 bg-zinc-100 border border-zinc-200 rounded-md"
                      >
                        <option value="LABOR">LABOR</option>
                        <option value="PART">PART</option>
                        <option value="GAS">GAS</option>
                        <option value="OTHER">OTHER</option>
                      </select>

                      {/* Title Description */}
                      <div className="flex-1">
                        <input
                          type="text"
                          value={item.title}
                          onChange={(e) => handleItemChange(idx, 'title', e.target.value)}
                          placeholder="Service / Component title"
                          className="w-full px-2.5 py-1 border border-zinc-200 rounded-md text-xs font-medium"
                        />
                        {item.category_name_snapshot && (
                          <span className="text-[10px] text-zinc-400 block mt-0.5">
                            Category: {item.category_name_snapshot}
                          </span>
                        )}
                      </div>

                      {/* Quantity & Unit */}
                      <div className="flex items-center gap-1.5 w-28">
                        <input
                          type="number"
                          min="1"
                          step="0.5"
                          value={item.quantity}
                          onChange={(e) => handleItemChange(idx, 'quantity', e.target.value)}
                          className="w-14 px-2 py-1 border border-zinc-200 rounded-md text-xs text-center font-mono"
                        />
                        <input
                          type="text"
                          value={item.unit}
                          onChange={(e) => handleItemChange(idx, 'unit', e.target.value)}
                          placeholder="unit"
                          className="w-12 px-1.5 py-1 border border-zinc-200 rounded-md text-[11px] text-zinc-500 text-center"
                        />
                      </div>

                      {/* Unit Price */}
                      <div className="flex items-center gap-1 w-28">
                        <span className="text-zinc-400 font-mono">₹</span>
                        <input
                          type="number"
                          min="0"
                          step="10"
                          value={item.unit_price}
                          onChange={(e) => handleItemChange(idx, 'unit_price', e.target.value)}
                          className="w-full px-2 py-1 border border-zinc-200 rounded-md text-xs font-mono font-bold"
                        />
                      </div>

                      {/* Line Total */}
                      <div className="w-24 text-right font-mono font-bold text-zinc-900 pr-1">
                        ₹{lineTotal.toLocaleString('en-IN', { minimumFractionDigits: 2 })}
                      </div>

                      {/* Remove */}
                      <button
                        type="button"
                        onClick={() => handleRemoveItem(idx)}
                        className="p-1 rounded text-zinc-400 hover:text-red-600 hover:bg-red-50 transition-colors"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  );
                })
              )}
            </div>
          </div>

          {/* Pricing Summary & Taxes */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6 bg-zinc-50/80 p-4 rounded-xl border border-zinc-200">
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-bold text-zinc-700 mb-1">
                  Quotation Validity
                </label>
                <div className="relative">
                  <input
                    type="date"
                    value={validUntil}
                    onChange={(e) => setValidUntil(e.target.value)}
                    className="w-full px-3 py-1.5 bg-white border border-zinc-200 rounded-lg text-xs"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-zinc-700 mb-1">
                  Customer Guarantee & Warranty Terms
                </label>
                <textarea
                  rows={2}
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  className="w-full p-2.5 bg-white border border-zinc-200 rounded-lg text-xs"
                />
              </div>
            </div>

            {/* Calculations Panel */}
            <div className="space-y-2.5 self-center bg-white p-4 rounded-xl border border-zinc-200 shadow-xs">
              <div className="flex justify-between items-center text-zinc-600">
                <span>Subtotal (Base Services & Parts)</span>
                <span className="font-mono font-semibold text-zinc-900">
                  ₹{subtotal.toLocaleString('en-IN', { minimumFractionDigits: 2 })}
                </span>
              </div>

              <div className="flex justify-between items-center py-1 border-y border-zinc-100">
                <div className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    id="gstToggle"
                    checked={applyGst}
                    onChange={(e) => setApplyGst(e.target.checked)}
                    className="rounded text-emerald-600 focus:ring-emerald-500"
                  />
                  <label htmlFor="gstToggle" className="text-xs font-medium text-zinc-700 cursor-pointer">
                    Apply 18% GST ({applyGst ? 'CGST 9% + SGST 9%' : 'Exempt'})
                  </label>
                </div>
                <span className="font-mono font-semibold text-zinc-900">
                  ₹{taxAmount.toLocaleString('en-IN', { minimumFractionDigits: 2 })}
                </span>
              </div>

              <div className="flex justify-between items-center text-zinc-600">
                <span>Special Goodwill Discount</span>
                <div className="flex items-center gap-1 w-24">
                  <span className="text-zinc-400 font-mono">₹</span>
                  <input
                    type="number"
                    min="0"
                    value={discountAmount}
                    onChange={(e) => setDiscountAmount(e.target.value)}
                    className="w-full text-right px-1.5 py-0.5 border border-zinc-200 rounded text-xs font-mono"
                  />
                </div>
              </div>

              <div className="pt-2 border-t-2 border-zinc-900 flex justify-between items-center">
                <div>
                  <span className="text-xs font-bold text-zinc-900 block">Grand Total</span>
                  <span className="text-[10px] text-zinc-500">Authorized Quotation</span>
                </div>
                <span className="text-base font-black font-mono text-emerald-600">
                  ₹{grandTotal.toLocaleString('en-IN', { minimumFractionDigits: 2 })}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-zinc-100 bg-zinc-50 flex items-center justify-between shrink-0">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-medium text-zinc-600 hover:text-zinc-900 hover:bg-zinc-200 rounded-xl transition-colors"
          >
            Cancel
          </button>
          <div className="flex items-center gap-3">
            <button
              type="button"
              disabled={saving}
              onClick={handleSaveDraft}
              className="px-4 py-2 text-xs font-semibold text-zinc-700 bg-white border border-zinc-300 hover:bg-zinc-100 disabled:opacity-50 rounded-xl shadow-xs flex items-center gap-1.5 transition-colors"
            >
              {saving ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Save className="w-3.5 h-3.5" />}
              <span>Save Draft</span>
            </button>
            <button
              type="button"
              onClick={() => setShowSubmitModal(true)}
              className="px-5 py-2 text-xs font-bold text-white bg-blue-600 hover:bg-blue-700 rounded-xl shadow-sm flex items-center gap-2 transition-colors"
            >
              <ShieldCheck className="w-4 h-4" />
              <span>Submit for Admin Review</span>
            </button>
          </div>
        </div>

        {/* Submit for Admin Review Confirmation Modal */}
        {showSubmitModal && (
          <div className="absolute inset-0 z-50 flex items-center justify-center p-4 bg-zinc-950/60 backdrop-blur-xs animate-in fade-in">
            <div className="bg-white rounded-xl max-w-sm w-full p-5 space-y-4 shadow-2xl border border-zinc-200 text-center">
              <div className="w-12 h-12 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center mx-auto">
                <ShieldCheck className="w-6 h-6" />
              </div>
              <div>
                <h3 className="text-sm font-bold text-zinc-900">
                  Submit Quotation for Customer Admin Review?
                </h3>
                <p className="text-xs text-zinc-500 mt-1 leading-relaxed">
                  Quotation total of <strong className="text-zinc-900 font-mono">₹{grandTotal.toLocaleString('en-IN', { minimumFractionDigits: 2 })}</strong> will be submitted to the Customer Admin for verification before being sent to {estimation?.customer_name}.
                </p>
              </div>
              <div className="flex items-center justify-center gap-2.5 pt-2">
                <button
                  type="button"
                  onClick={() => setShowSubmitModal(false)}
                  className="px-3.5 py-1.5 text-xs font-semibold text-zinc-600 hover:bg-zinc-100 rounded-lg"
                >
                  Back to Editing
                </button>
                <button
                  type="button"
                  disabled={submittingReview}
                  onClick={handleSubmitForReview}
                  className="px-4 py-1.5 text-xs font-bold text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50 rounded-lg flex items-center gap-1.5"
                >
                  {submittingReview ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Send className="w-3.5 h-3.5" />}
                  <span>{submittingReview ? 'Submitting...' : 'Confirm & Submit'}</span>
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
