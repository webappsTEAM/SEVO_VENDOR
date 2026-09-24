import React, { useState, useEffect, useRef } from 'react';
import {
  X,
  Plus,
  Trash2,
  Save,
  Send,
  Calculator,
  Ruler,
  Layers,
  FileText,
  CheckCircle2,
  AlertCircle,
  AlertTriangle,
  Clock,
  Sparkles,
  ShieldCheck,
  ChevronRight,
  ChevronLeft,
} from 'lucide-react';
import PaintingInspectionForm from './PaintingInspectionForm.jsx';
import MasonInspectionForm from './MasonInspectionForm.jsx';
import {
  apiGetRateCards,
  apiPriceRateCardLine,
  apiGetQuoteDetail,
  apiCreateQuote,
  apiUpdateQuoteDraft,
  apiBulkSaveQuoteItems,
  apiBulkSaveQuoteMeasurements,
  apiSaveQuoteInspection,
  apiSendQuoteToCustomer,
  apiSubmitQuoteToCRM,
} from '../../api/workforceService.js';

/**
 * How a rate card prices, in the dropdown. "₹0/sqft" was shown for every flat,
 * banded, tiered and quote-only item, which is not what any of them cost.
 */
function describeRate(rc) {
  switch (rc.pricing_model) {
    case 'PER_UNIT':
      return `₹${Number(rc.default_rate || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}/${rc.unit}`;
    case 'FLAT':
      return `₹${Number(rc.default_rate || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} flat`;
    case 'TIERED': {
      const rates = Object.values(rc.pricing_config?.tiers || {});
      return rates.length ? `₹${Math.min(...rates).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}–₹${Math.max(...rates).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}/${rc.unit}` : 'tiered';
    }
    case 'CAPACITY_BAND':
    case 'SIZE_BAND':
      return 'priced by size';
    case 'QUOTE_ONLY':
      return 'priced on site';
    default:
      return `₹${Number(rc.default_rate || 0).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}/${rc.unit}`;
  }
}

export function formatCurrency(val) {
  const num = Number(val || 0);
  return num.toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

export default function QuotationBuilderModal({
  job,
  quoteId = null,
  isOpen,
  onClose,
  onQuoteSaved,
}) {
  const [step, setStep] = useState(1);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState(null);
  const [successMsg, setSuccessMsg] = useState(null);

  const [activeQuoteId, setActiveQuoteId] = useState(quoteId);
  const [quoteNumber, setQuoteNumber] = useState('');
  const [quoteVersion, setQuoteVersion] = useState(1);
  const [quoteStatus, setQuoteStatus] = useState('DRAFT');

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [inspectionFeeAdjusted, setInspectionFeeAdjusted] = useState(0);

  const [inspectionData, setInspectionData] = useState({});
  const [measurements, setMeasurements] = useState([]);
  const [items, setItems] = useState([]);
  const [rateCards, setRateCards] = useState([]);
  // Line indexes currently being re-priced by the server, so the UI can say
  // "working" instead of showing a stale figure as if it were final.
  const [pricingIndexes, setPricingIndexes] = useState([]);

  const isPainting =
    job?.service_category?.toLowerCase().includes('painting') ||
    job?.issue_title?.toLowerCase().includes('painting');

  const isMason =
    job?.service_category?.toLowerCase().includes('mason') ||
    job?.issue_title?.toLowerCase().includes('mason') ||
    job?.issue_title?.toLowerCase().includes('brick') ||
    job?.issue_title?.toLowerCase().includes('plaster');

  const isReadOnly = Boolean(
    quoteStatus &&
    quoteStatus !== 'DRAFT' &&
    quoteStatus !== 'CHANGES_REQUESTED'
  );

  const hasInitializedRef = useRef(false);
  const jobId = job?.id;

  // Load existing quote or initialize from job once when modal opens
  useEffect(() => {
    if (!isOpen) {
      hasInitializedRef.current = false;
      return;
    }
    if (hasInitializedRef.current) return;
    hasInitializedRef.current = true;

    const loadData = async () => {
      setLoading(true);
      setError(null);
      try {
        // Load rate cards
        const categoryParam = isPainting ? 'painting' : isMason ? 'mason' : '';
        const rCards = await apiGetRateCards(categoryParam);
        setRateCards(rCards || []);

        const targetQuoteId = quoteId || activeQuoteId;
        if (targetQuoteId) {
          const detail = await apiGetQuoteDetail(targetQuoteId);
          setActiveQuoteId(detail.id);
          setQuoteNumber(detail.quote_number || '');
          setQuoteVersion(detail.quote_version || 1);
          setQuoteStatus(detail.status || 'DRAFT');
          setTitle(detail.title || '');
          setDescription(detail.description || '');
          setInspectionFeeAdjusted(detail.inspection_fee_adjusted || 0);
          setItems(detail.items || []);
          setMeasurements(detail.measurements || []);

          if (detail.painting_details) {
            setInspectionData(detail.painting_details);
          } else if (detail.mason_details) {
            setInspectionData(detail.mason_details);
          }
        } else if (job) {
          setTitle(`Quotation for ${job.issue_title || job.service_category}`);
          setDescription(`Site inspection and estimation for ${job.customer_name || 'Customer'}.`);
          setItems([]);
        }
      } catch (err) {
        console.error('Failed to load quotation builder data:', err);
        setError(err.message || 'Failed to initialize quotation data.');
      } finally {
        setLoading(false);
      }
    };

    loadData();
  }, [isOpen, quoteId, jobId]);

  // Live total calculations
  const calculateTotals = () => {
    let subtotal = 0;
    let totalDiscount = 0;
    let totalTax = 0;
    let materialsCost = 0;
    let laborCost = 0;

    items.forEach((item) => {
      const qty = parseFloat(item.quantity) || 0;
      const price = parseFloat(item.unit_price) || 0;
      const disc = parseFloat(item.discount_amount) || 0;
      const taxRate = parseFloat(item.tax_rate) || 18;

      const gross = qty * price;
      const net = Math.max(0, gross - disc);
      const tax = net * (taxRate / 100);

      subtotal += net;
      totalDiscount += disc;
      totalTax += tax;

      if (item.section === 'MATERIAL') {
        materialsCost += net;
      } else if (item.section === 'LABOUR') {
        laborCost += net;
      }
    });

    const grandTotal = subtotal + totalTax;
    const netPayable = Math.max(0, grandTotal - (parseFloat(inspectionFeeAdjusted) || 0));

    return {
      subtotal: Math.round(subtotal * 100) / 100,
      totalDiscount: Math.round(totalDiscount * 100) / 100,
      totalTax: Math.round(totalTax * 100) / 100,
      grandTotal: Math.round(grandTotal * 100) / 100,
      netPayable: Math.round(netPayable * 100) / 100,
      materialsCost: Math.round(materialsCost * 100) / 100,
      laborCost: Math.round(laborCost * 100) / 100,
    };
  };

  const totals = calculateTotals();

  // Add line item
  const handleAddItem = (section = 'MATERIAL') => {
    setItems([
      ...items,
      {
        id: `temp_${Date.now()}`,
        section,
        name: '',
        description: '',
        quantity: 1,
        unit: isPainting ? 'sqft' : 'sqft',
        unit_price: 0,
        tax_rate: 18,
        discount_amount: 0,
        material_source: 'CALTRACK',
      },
    ]);
  };

  // Add line item from Rate Card select
  const handleSelectRateCardItem = (rcId) => {
    const rc = rateCards.find((r) => r.id === parseInt(rcId));
    if (!rc) return;

    const tiers = Object.keys(rc.pricing_config?.tiers || {});
    const next = {
      id: `temp_${Date.now()}`,
      rate_card_id: rc.id,
      pricing_model: rc.pricing_model,
      pricing_tiers: tiers,
      pricing_tier: tiers.length === 1 ? tiers[0] : '',
      minimum_quantity: parseFloat(rc.minimum_quantity) || 0,
      pricing_note: '',
      pricing_error: '',
      section: rc.section,
      name: rc.item_name,
      description: rc.description || '',
      quantity: rc.minimum_quantity > 0 ? parseFloat(rc.minimum_quantity) : 1,
      unit: rc.unit,
      // Left at zero until the server prices it. Showing default_rate here
      // would be a lie for every banded, tiered, flat or quote-only item.
      unit_price: 0,
      total_amount: 0,
      tax_rate: parseFloat(rc.tax_rate) || 18,
      discount_amount: 0,
      material_source: 'CALTRACK',
      warranty_tier: rc.warranty_tier || 'NONE',
      advance_percent: rc.advance_percent,
    };

    const nextIndex = items.length;
    setItems([...items, next]);

    if (rc.pricing_model === 'QUOTE_ONLY') {
      // No standard rate exists; the technician sets the price.
      handleUpdateItem(nextIndex, 'pricing_note', 'No standard rate — enter the price for this site.');
    } else if (rc.pricing_model === 'TIERED' && !next.pricing_tier) {
      handleUpdateItem(nextIndex, 'pricing_note', 'Choose a specification to price this line.');
    } else {
      repriceLine(nextIndex, next);
    }
  };

  /**
   * Ask the backend what this line costs.
   *
   * Slab, capacity-band, size-band and minimum-quantity rules live in one
   * place on the server (services/rate_card_pricing.py). Reimplementing them
   * in the browser would mean two sets of prices that drift apart, and the
   * customer would be shown whichever one the UI happened to compute.
   */
  const repriceLine = async (index, itemOverride = null) => {
    const item = itemOverride || items[index];
    if (!item?.rate_card_id || item.pricing_model === 'QUOTE_ONLY') return;

    setPricingIndexes((prev) => [...new Set([...prev, index])]);
    try {
      const priced = await apiPriceRateCardLine(
        item.rate_card_id,
        item.quantity,
        item.pricing_tier || null
      );
      setItems((prev) => {
        const updated = [...prev];
        if (!updated[index]) return prev;
        updated[index] = {
          ...updated[index],
          unit_price: priced.unit_price,
          total_amount: priced.line_total,
          tax_rate: priced.tax_rate,
          warranty_tier: priced.warranty_tier || updated[index].warranty_tier,
          pricing_note: priced.note || '',
          pricing_error: '',
        };
        return updated;
      });
    } catch (err) {
      // The refusal message is the useful part -- "minimum 500 sqft", "choose a
      // specification" -- so it is shown on the line rather than swallowed.
      setItems((prev) => {
        const updated = [...prev];
        if (!updated[index]) return prev;
        updated[index] = {
          ...updated[index],
          unit_price: 0,
          total_amount: 0,
          pricing_error: err?.message || 'Could not price this line.',
          pricing_note: '',
        };
        return updated;
      });
    } finally {
      setPricingIndexes((prev) => prev.filter((i) => i !== index));
    }
  };

  const handleUpdateItem = (index, field, value) => {
    setItems((prev) => {
      const updated = [...prev];
      if (!updated[index]) return prev;
      updated[index] = { ...updated[index], [field]: value };
      return updated;
    });
  };

  // Quantity and specification are the two inputs that change the price, so
  // both re-ask the server. Debounced: a technician typing "450" should cause
  // one request, not three.
  const repriceTimersRef = useRef({});
  const handlePricedFieldChange = (index, field, value) => {
    handleUpdateItem(index, field, value);
    const timers = repriceTimersRef.current;
    if (timers[index]) clearTimeout(timers[index]);
    timers[index] = setTimeout(() => {
      setItems((current) => {
        const item = current[index];
        if (item?.rate_card_id && item.pricing_model !== 'QUOTE_ONLY') {
          repriceLine(index, { ...item, [field]: value });
        }
        return current;
      });
    }, 400);
  };

  // The advance the customer must pay up front is the largest any line demands:
  // one waterproofing line in an otherwise ordinary painting quote still needs
  // materials bought before work starts.
  const suggestedAdvancePercent = items.reduce((highest, item) => {
    const pct = parseFloat(item.advance_percent);
    return Number.isFinite(pct) && pct > highest ? pct : highest;
  }, 0) || null;

  const pricingProblems = items.filter((i) => i.pricing_error);

  const handleRemoveItem = (index) => {
    setItems(items.filter((_, idx) => idx !== index));
  };

  // Measurement management
  const handleAddMeasurement = () => {
    setMeasurements((prev) => [
      ...prev,
      {
        name: `Area #${prev.length + 1}`,
        measurement_type: 'area',
        length: '',
        width: '',
        height: '',
        area: 0,
        unit: 'sqft',
        notes: '',
      },
    ]);
  };

  // Single functional updater — avoids the React-batching race condition where
  // two synchronous setMeasurements calls (for width + height) each close over
  // the same stale array and the second one silently overwrites the first.
  const handleUpdateMeasurement = (index, fields) => {
    setMeasurements((prev) => {
      const updated = [...prev];
      const item = { ...updated[index], ...fields };

      // Auto-compute area whenever length, width, or height changes
      const len = parseFloat(item.length) || 0;
      const hgt = parseFloat(item.height) || 0;
      const wid = parseFloat(item.width) || 0;
      if (len > 0 && hgt > 0) {
        item.area = Math.round(len * hgt * 100) / 100;
      } else if (len > 0 && wid > 0) {
        item.area = Math.round(len * wid * 100) / 100;
      } else {
        item.area = 0;
      }

      updated[index] = item;
      return updated;
    });
  };

  const handleRemoveMeasurement = (index) => {
    setMeasurements(measurements.filter((_, idx) => idx !== index));
  };

  // Save Draft to Backend
  const handleSaveDraft = async () => {
    // A line the rate card refused has no price. Saving it would send the
    // customer a quotation with a zero on it, so the refusal is surfaced here
    // instead of being discovered after the quote has gone out.
    if (pricingProblems.length > 0) {
      setError(
        `${pricingProblems.length} line item${pricingProblems.length > 1 ? 's have' : ' has'} `
        + `an unresolved pricing problem: ${pricingProblems[0].pricing_error}`
      );
      return;
    }

    setSaving(true);
    setError(null);
    setSuccessMsg(null);

    try {
      let currentId = activeQuoteId;

      if (!currentId) {
        // Create initial draft quote
        const created = await apiCreateQuote({
          job_id: job.id,
          title: title || `Quotation for ${job.issue_title}`,
          description,
          service_category: job.service_category,
          service_name: job.issue_title,
          inspection_fee: job.total_amount || 0,
          painting_details: isPainting ? inspectionData : undefined,
          mason_details: isMason ? inspectionData : undefined,
          // Highest advance any selected item demands. Null leaves the
          // category's own policy in charge.
          advance_percent: suggestedAdvancePercent,
        });
        currentId = created.id;
        setActiveQuoteId(created.id);
        setQuoteNumber(created.quote_number);
      } else {
        await apiUpdateQuoteDraft(currentId, {
          title,
          description,
          inspection_fee_adjusted: inspectionFeeAdjusted,
          structural_impact: inspectionData.structural_impact || 'NONE',
          advance_percent: suggestedAdvancePercent,
        });
      }

      // Save Line Items in bulk
      // Only the fields the API accepts are sent -- the pricing_* keys are
      // builder state for showing the technician why a line costs what it
      // does, not part of the quotation.
      if (items.length > 0) {
        await apiBulkSaveQuoteItems(
          currentId,
          items.map((i) => ({
            section: i.section,
            name: i.name,
            description: i.description,
            item_type: i.item_type || 'item',
            quantity: i.quantity,
            unit: i.unit,
            unit_price: i.unit_price,
            tax_rate: i.tax_rate,
            discount_amount: i.discount_amount,
            total_amount: i.total_amount,
            material_source: i.material_source,
            is_customer_supplied: Boolean(i.is_customer_supplied),
            warranty_tier: i.warranty_tier || 'NONE',
            notes: i.notes || '',
            sort_order: i.sort_order,
          }))
        );
      }

      // Save Measurements
      if (measurements.length > 0) {
        await apiBulkSaveQuoteMeasurements(currentId, measurements);
      }

      // Save Inspection details
      if (Object.keys(inspectionData).length > 0) {
        await apiSaveQuoteInspection(currentId, {
          painting_details: isPainting ? inspectionData : undefined,
          mason_details: isMason ? inspectionData : undefined,
        });
      }

      setSuccessMsg('Draft quotation saved successfully!');
      if (onQuoteSaved) onQuoteSaved(currentId);
      setTimeout(() => setSuccessMsg(null), 3000);
      return currentId;
    } catch (err) {
      console.error('Failed to save draft quote:', err);
      setError(err.message || 'Failed to save quotation draft.');
      return null;
    } finally {
      setSaving(false);
    }
  };

  // Send Quote to Customer
  const handleSendQuote = async () => {
    setSending(true);
    setError(null);
    setSuccessMsg(null);

    try {
      const currentId = await handleSaveDraft();
      if (!currentId) {
        throw new Error('Please save quotation before sending.');
      }

      const res = await apiSendQuoteToCustomer(currentId);
      setSuccessMsg(res.message || 'Quotation successfully sent to customer!');
      setQuoteStatus('SENT_TO_CUSTOMER');

      if (onQuoteSaved) onQuoteSaved(currentId);
      setTimeout(() => {
        onClose();
      }, 2000);
    } catch (err) {
      console.error('Failed to send quote:', err);
      setError(err.message || 'Failed to send quotation to customer.');
    } finally {
      setSending(false);
    }
  };

  // Submit Quote to CRM for Review
  const handleSubmitToCRM = async () => {
    setSending(true);
    setError(null);
    setSuccessMsg(null);

    try {
      const currentId = await handleSaveDraft();
      if (!currentId) {
        throw new Error('Please save quotation before submitting.');
      }

      const res = await apiSubmitQuoteToCRM(currentId);
      setSuccessMsg(res.message || 'Quotation submitted to CRM / Operations for review!');
      setQuoteStatus('PENDING_APPROVAL');

      if (onQuoteSaved) onQuoteSaved(currentId);
      setTimeout(() => {
        onClose();
      }, 2000);
    } catch (err) {
      console.error('Failed to submit quote to CRM:', err);
      setError(err.message || 'Failed to submit quotation to CRM.');
    } finally {
      setSending(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto bg-black/60 backdrop-blur-sm flex items-center justify-center p-3 sm:p-6">
      <div className="bg-white dark:bg-gray-900 w-full max-w-4xl rounded-2xl shadow-2xl border border-gray-200 dark:border-gray-800 flex flex-col max-h-[92vh] overflow-hidden animate-in fade-in zoom-in-95 duration-150">
        {/* Header */}
        <div className="px-6 py-4 border-b border-gray-200 dark:border-gray-800 flex items-center justify-between bg-gray-50/80 dark:bg-gray-800/50">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-blue-600/10 dark:bg-blue-400/10 text-blue-600 dark:text-blue-400 flex items-center justify-center">
              <Calculator className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-base font-bold text-gray-900 dark:text-gray-100">
                  {quoteNumber ? `${quoteNumber} (v${quoteVersion})` : 'New Quotation Builder'}
                </h3>
                <span
                  className={`text-[11px] font-semibold px-2 py-0.5 rounded-full uppercase tracking-wider ${
                    quoteStatus === 'SENT_TO_CUSTOMER'
                      ? 'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300'
                      : quoteStatus === 'CUSTOMER_ACCEPTED'
                      ? 'bg-green-100 text-green-800 dark:bg-green-900/40 dark:text-green-300'
                      : 'bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300'
                  }`}
                >
                  {quoteStatus.replace(/_/g, ' ')}
                </span>
              </div>
              <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                {job?.issue_title || 'Site Inspection'} • {job?.customer_name || 'Customer'}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <div className="hidden sm:flex flex-col items-end px-3 py-1 bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 shadow-sm">
              <span className="text-[10px] uppercase font-bold text-gray-400">Estimated Total</span>
              <span className="text-sm font-extrabold text-blue-600 dark:text-blue-400">
                ₹{formatCurrency(totals.netPayable)}
              </span>
            </div>

            <button
              onClick={onClose}
              className="p-2 rounded-lg text-gray-400 hover:text-gray-600 dark:hover:text-gray-200 hover:bg-gray-100 dark:hover:bg-gray-800"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Stepper Tabs */}
        <div className="px-6 py-2.5 bg-gray-100/70 dark:bg-gray-800/40 border-b border-gray-200 dark:border-gray-800 flex items-center justify-between text-xs font-medium overflow-x-auto">
          {[
            { num: 1, label: '1. Site Inspection', icon: Layers },
            { num: 2, label: '2. Measurements', icon: Ruler },
            { num: 3, label: '3. Line Items & Pricing', icon: Calculator },
            { num: 4, label: '4. Review & Finalize', icon: FileText },
          ].map((s) => {
            const Icon = s.icon;
            const isActive = step === s.num;
            return (
              <button
                key={s.num}
                onClick={() => setStep(s.num)}
                className={`flex items-center gap-2 px-3 py-1.5 rounded-lg transition-all ${
                  isActive
                    ? 'bg-white dark:bg-gray-800 text-blue-600 dark:text-blue-400 font-semibold shadow-sm border border-gray-200 dark:border-gray-700'
                    : 'text-gray-500 hover:text-gray-700 dark:hover:text-gray-300'
                }`}
              >
                <Icon className="w-3.5 h-3.5" />
                <span>{s.label}</span>
              </button>
            );
          })}
        </div>

        {/* Read-Only Status Banner */}
        {isReadOnly && (
          <div className="mx-6 mt-4 p-3 rounded-xl bg-blue-50 dark:bg-blue-950/40 border border-blue-200 dark:border-blue-800/60 flex items-center justify-between gap-3 text-xs text-blue-900 dark:text-blue-300">
            <div className="flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4 text-blue-600 shrink-0" />
              <span>
                {quoteStatus === 'CUSTOMER_ACCEPTED' || quoteStatus === 'CONVERTED'
                  ? 'Quotation has been accepted by customer and is locked for execution.'
                  : quoteStatus === 'SENT_TO_CUSTOMER'
                  ? 'Quotation has been delivered to customer and is awaiting decision.'
                  : `Quotation is in ${quoteStatus.replace(/_/g, ' ')} state (Read-Only).`}
              </span>
            </div>
          </div>
        )}

        {/* Messages */}
        {error && (
          <div className="mx-6 mt-4 p-3 rounded-xl bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-800/60 flex items-center gap-2.5 text-xs text-red-800 dark:text-red-300">
            <AlertCircle className="w-4 h-4 shrink-0 text-red-600" />
            <span>{error}</span>
          </div>
        )}

        {successMsg && (
          <div className="mx-6 mt-4 p-3 rounded-xl bg-green-50 dark:bg-green-950/40 border border-green-200 dark:border-green-800/60 flex items-center gap-2.5 text-xs text-green-800 dark:text-green-300">
            <CheckCircle2 className="w-4 h-4 shrink-0 text-green-600" />
            <span>{successMsg}</span>
          </div>
        )}

        {/* Body Content */}
        <div className="p-6 overflow-y-auto flex-1 space-y-6">
          {loading ? (
            <div className="py-16 text-center text-gray-500 text-sm">
              <div className="w-8 h-8 border-2 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto mb-3" />
              Loading quotation parameters & rate cards...
            </div>
          ) : (
            <>
              {/* STEP 1: Inspection Form */}
              {step === 1 && (
                <div className="space-y-4">
                  {isPainting ? (
                    <PaintingInspectionForm data={inspectionData} onChange={setInspectionData} />
                  ) : isMason ? (
                    <MasonInspectionForm data={inspectionData} onChange={setInspectionData} />
                  ) : (
                    <div className="space-y-4">
                      <div>
                        <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
                          Quotation Title
                        </label>
                        <input
                          type="text"
                          value={title}
                          onChange={(e) => setTitle(e.target.value)}
                          className="w-full text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2.5"
                        />
                      </div>
                      <div>
                        <label className="block text-xs font-semibold text-gray-700 dark:text-gray-300 mb-1.5">
                          Scope & Findings
                        </label>
                        <textarea
                          rows={3}
                          value={description}
                          onChange={(e) => setDescription(e.target.value)}
                          className="w-full text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2.5"
                        />
                      </div>
                    </div>
                  )}
                </div>
              )}

              {/* STEP 2: Measurements */}
              {step === 2 && (
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <h4 className="text-sm font-bold text-gray-900 dark:text-gray-100">
                        Site Dimensions & Area Measurements
                      </h4>
                      <p className="text-xs text-gray-500">
                        Record dimensions for roofs, walls, rooms, or slab areas.
                      </p>
                    </div>
                    {!isReadOnly && (
                      <button
                        onClick={handleAddMeasurement}
                        className="inline-flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg bg-blue-50 text-blue-600 hover:bg-blue-100 dark:bg-blue-900/30 dark:text-blue-400 cursor-pointer"
                      >
                        <Plus className="w-3.5 h-3.5" />
                        Add Area
                      </button>
                    )}
                  </div>

                  {measurements.length === 0 ? (
                    <div className="py-8 text-center text-xs text-gray-400 border-2 border-dashed border-gray-200 dark:border-gray-700 rounded-xl">
                      No measurements added yet. Click &quot;Add Area&quot; to record dimensions.
                    </div>
                  ) : (
                    <div className="space-y-3">
                      {measurements.map((m, idx) => (
                        <div
                          key={m.id || idx}
                          className="p-4 rounded-xl border border-gray-200 dark:border-gray-700 bg-gray-50/50 dark:bg-gray-800/50 space-y-3 shadow-xs"
                        >
                          <div className="flex items-center justify-between gap-3">
                            <input
                              type="text"
                              disabled={isReadOnly}
                              value={m.name ?? ''}
                              onChange={(e) => handleUpdateMeasurement(idx, { name: e.target.value })}
                              placeholder="Area / Location (e.g. Terrace Slab, North Wall)"
                              className="text-xs font-bold text-gray-900 dark:text-gray-100 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg px-3 py-1.5 flex-1 outline-none focus:ring-1 focus:ring-blue-500"
                            />
                            {!isReadOnly && (
                              <button
                                type="button"
                                onClick={() => handleRemoveMeasurement(idx)}
                                className="p-1.5 text-gray-400 hover:text-red-600 rounded-lg hover:bg-red-50 dark:hover:bg-red-950/40 cursor-pointer transition-colors"
                                title="Remove Measurement"
                              >
                                <Trash2 className="w-4 h-4" />
                              </button>
                            )}
                          </div>

                          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
                            <div>
                              <label className="block text-[10px] uppercase font-bold text-gray-400 mb-1">
                                Length (ft)
                              </label>
                              <input
                                type="number"
                                step="0.1"
                                min="0"
                                disabled={isReadOnly}
                                value={m.length ?? ''}
                                onChange={(e) => handleUpdateMeasurement(idx, { length: e.target.value })}
                                placeholder="0.0"
                                className="w-full rounded-lg border border-gray-200 dark:border-gray-700 p-2 bg-white dark:bg-gray-800 text-xs font-semibold focus:ring-1 focus:ring-blue-500 focus:outline-none"
                              />
                            </div>

                            <div>
                              <label className="block text-[10px] uppercase font-bold text-gray-400 mb-1">
                                Width / Height (ft)
                              </label>
                              {/* Single onChange — merges width+height in one setMeasurements call
                                  to avoid React batching silently dropping one of two concurrent updates */}
                              <input
                                type="number"
                                step="0.1"
                                min="0"
                                disabled={isReadOnly}
                                value={m.width ?? m.height ?? ''}
                                onChange={(e) =>
                                  handleUpdateMeasurement(idx, {
                                    width: e.target.value,
                                    height: e.target.value,
                                  })
                                }
                                placeholder="0.0"
                                className="w-full rounded-lg border border-gray-200 dark:border-gray-700 p-2 bg-white dark:bg-gray-800 text-xs font-semibold focus:ring-1 focus:ring-blue-500 focus:outline-none"
                              />
                            </div>

                            <div>
                              <label className="block text-[10px] uppercase font-bold text-gray-400 mb-1">
                                Unit
                              </label>
                              <input
                                type="text"
                                disabled={isReadOnly}
                                value={m.unit ?? 'sqft'}
                                onChange={(e) => handleUpdateMeasurement(idx, { unit: e.target.value })}
                                className="w-full rounded-lg border border-gray-200 dark:border-gray-700 p-2 bg-white dark:bg-gray-800 text-xs font-semibold focus:ring-1 focus:ring-blue-500 focus:outline-none"
                              />
                            </div>

                            <div>
                              <label className="block text-[10px] uppercase font-bold text-gray-400 mb-1">
                                Computed Area
                              </label>
                              <div className="p-2 rounded-lg bg-blue-50 dark:bg-blue-950/40 border border-blue-200 dark:border-blue-800 text-blue-700 dark:text-blue-300 font-extrabold text-xs flex items-center justify-between">
                                <span>{m.area ?? 0}</span>
                                <span className="text-[10px] font-normal uppercase text-blue-500">{m.unit ?? 'sqft'}</span>
                              </div>
                            </div>
                          </div>

                          <div>
                            <input
                              type="text"
                              disabled={isReadOnly}
                              value={m.notes ?? ''}
                              onChange={(e) => handleUpdateMeasurement(idx, { notes: e.target.value })}
                              placeholder="Optional notes (e.g. cracked plaster, 2 coats required)..."
                              className="w-full text-xs text-gray-600 dark:text-gray-400 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg px-3 py-1.5 outline-none focus:ring-1 focus:ring-blue-500"
                            />
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {/* STEP 3: Line Items & Rate Cards */}
              {step === 3 && (
                <div className="space-y-5">
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 bg-blue-50/50 dark:bg-blue-950/20 p-3.5 rounded-xl border border-blue-100 dark:border-blue-900/40">
                    <div>
                      <h4 className="text-xs font-bold text-blue-900 dark:text-blue-200">
                        Add from Approved Rate Card Catalog
                      </h4>
                      <p className="text-[11px] text-blue-700 dark:text-blue-300">
                        Select pre-approved standard rates for material, labour, and logistics.
                      </p>
                    </div>

                    <select
                      onChange={(e) => {
                        if (e.target.value) {
                          handleSelectRateCardItem(e.target.value);
                          e.target.value = '';
                        }
                      }}
                      defaultValue=""
                      className="text-xs rounded-lg border border-blue-300 dark:border-blue-700 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 px-3 py-2 focus:ring-2 focus:ring-blue-500 focus:outline-none"
                    >
                      <option value="" disabled>
                        + Choose approved item...
                      </option>
                      {rateCards.map((rc) => (
                        <option key={rc.id} value={rc.id}>
                          [{rc.section}] {rc.item_name} — {describeRate(rc)}
                        </option>
                      ))}
                    </select>
                  </div>

                  {/* Items List */}
                  <div className="space-y-3">
                    {items.map((item, idx) => (
                      <div
                        key={item.id || idx}
                        className="p-4 rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800/80 shadow-sm space-y-3"
                      >
                        <div className="grid grid-cols-1 sm:grid-cols-12 gap-3 items-center">
                          <div className="sm:col-span-3">
                            <label className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                              Section
                            </label>
                            <select
                              value={item.section || 'MATERIAL'}
                              onChange={(e) => handleUpdateItem(idx, 'section', e.target.value)}
                              className="w-full text-xs font-semibold rounded-lg border border-gray-300 dark:border-gray-600 bg-gray-50 dark:bg-gray-800 p-2"
                            >
                              <option value="MATERIAL">Material</option>
                              <option value="LABOUR">Labour</option>
                              <option value="SURFACE_PREP">Surface Prep</option>
                              <option value="EQUIPMENT">Equipment & Scaffolding</option>
                              <option value="TRANSPORT">Transport & Logistics</option>
                              <option value="OTHER">Other</option>
                            </select>
                          </div>

                          <div className="sm:col-span-5">
                            <label className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                              Item Name / Scope
                            </label>
                            <input
                              type="text"
                              value={item.name}
                              onChange={(e) => handleUpdateItem(idx, 'name', e.target.value)}
                              placeholder="e.g. Premium Acrylic Emulsion"
                              className="w-full text-xs font-semibold rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2 focus:ring-1 focus:ring-blue-500"
                            />
                          </div>

                          {item.pricing_tiers?.length > 0 && (
                            <div className="sm:col-span-3">
                              <label className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                                Specification
                              </label>
                              <select
                                value={item.pricing_tier || ''}
                                onChange={(e) =>
                                  handlePricedFieldChange(idx, 'pricing_tier', e.target.value)
                                }
                                className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2"
                              >
                                <option value="">Choose…</option>
                                {item.pricing_tiers.map((t) => (
                                  <option key={t} value={t}>{t}</option>
                                ))}
                              </select>
                            </div>
                          )}

                          <div className="sm:col-span-2">
                            <label className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                              Quantity
                            </label>
                            <input
                              type="number"
                              step="0.1"
                              value={item.quantity || ''}
                              onChange={(e) =>
                                handlePricedFieldChange(idx, 'quantity', parseFloat(e.target.value) || 0)
                              }
                              className="w-full text-xs font-medium rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2"
                            />
                          </div>

                          <div className="sm:col-span-2">
                            <label className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                              Unit
                            </label>
                            <input
                              type="text"
                              value={item.unit || 'sqft'}
                              onChange={(e) => handleUpdateItem(idx, 'unit', e.target.value)}
                              className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2"
                            />
                          </div>
                        </div>

                        <div className="grid grid-cols-1 sm:grid-cols-12 gap-3 items-center pt-1 border-t border-gray-100 dark:border-gray-700/60">
                          <div className="sm:col-span-3">
                            <label className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                              Rate (₹)
                              {item.rate_card_id && item.pricing_model !== 'QUOTE_ONLY' && (
                                <span className="ml-1 font-normal normal-case text-gray-400">
                                  set by rate card
                                </span>
                              )}
                            </label>
                            <input
                              type="number"
                              step="0.1"
                              value={item.unit_price || ''}
                              disabled={Boolean(item.rate_card_id) && item.pricing_model !== 'QUOTE_ONLY'}
                              onChange={(e) =>
                                handleUpdateItem(idx, 'unit_price', parseFloat(e.target.value) || 0)
                              }
                              className="w-full text-xs font-medium rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2 disabled:bg-gray-100 disabled:text-gray-500 dark:disabled:bg-gray-900"
                            />
                          </div>

                          <div className="sm:col-span-3">
                            <label className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                              Discount (₹)
                            </label>
                            <input
                              type="number"
                              step="0.1"
                              value={item.discount_amount || ''}
                              onChange={(e) =>
                                handleUpdateItem(idx, 'discount_amount', parseFloat(e.target.value) || 0)
                              }
                              className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2"
                            />
                          </div>

                          <div className="sm:col-span-3">
                            <label className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                              Tax (GST %)
                            </label>
                            <input
                              type="number"
                              value={item.tax_rate ?? 18}
                              onChange={(e) =>
                                handleUpdateItem(idx, 'tax_rate', parseFloat(e.target.value) || 0)
                              }
                              className="w-full text-xs rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-2"
                            />
                          </div>

                          <div className="sm:col-span-2 text-right">
                            <span className="block text-[10px] font-bold text-gray-400 uppercase mb-1">
                              Net Total
                            </span>
                            <span className="text-xs font-extrabold text-gray-900 dark:text-gray-100">
                              {pricingIndexes.includes(idx) ? (
                                <span className="text-gray-400 font-medium">pricing…</span>
                              ) : (
                                <>
                                  ₹
                                  {formatCurrency(
                                    Math.max(0, (item.quantity || 1) * (item.unit_price || 0) - (item.discount_amount || 0))
                                  )}
                                </>
                              )}
                            </span>
                          </div>

                          <div className="sm:col-span-1 flex justify-end">
                            <button
                              onClick={() => handleRemoveItem(idx)}
                              className="p-1.5 text-gray-400 hover:text-red-600 rounded-lg hover:bg-red-50 dark:hover:bg-red-950/40"
                            >
                              <Trash2 className="w-4 h-4" />
                            </button>
                          </div>
                        </div>

                        {/* What the rate card decided about this line, or why it
                            refused. Shown here rather than on save so the
                            technician finds out while they can still change it. */}
                        {(item.pricing_error || item.pricing_note || item.warranty_tier !== 'NONE') && (
                          <div className="pt-2 border-t border-gray-100 dark:border-gray-700/60 space-y-1.5">
                            {item.pricing_error && (
                              <p className="text-[11px] text-red-600 dark:text-red-400 font-medium flex items-start gap-1.5">
                                <AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-px" />
                                {item.pricing_error}
                              </p>
                            )}
                            {!item.pricing_error && item.pricing_note && (
                              <p className="text-[11px] text-gray-500 dark:text-gray-400">
                                {item.pricing_note}
                              </p>
                            )}
                            {item.warranty_tier && item.warranty_tier !== 'NONE' && (
                              <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-emerald-700 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-950/40 px-2 py-0.5 rounded-full">
                                {item.warranty_tier === '10_YEAR' ? '10-Year Warranty' : '5-Year Warranty'}
                              </span>
                            )}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>

                  <button
                    onClick={() => handleAddItem('MATERIAL')}
                    className="inline-flex items-center gap-1.5 text-xs font-semibold px-3.5 py-2 rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-200 hover:bg-gray-50"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    + Add Custom Line Item
                  </button>
                </div>
              )}

              {/* STEP 4: Review & Finalize */}
              {step === 4 && (
                <div className="space-y-6">
                  <div className="p-5 rounded-2xl border border-gray-200 dark:border-gray-700 bg-gray-50/70 dark:bg-gray-800/40 space-y-4">
                    <div className="flex items-center justify-between border-b border-gray-200 dark:border-gray-700 pb-3">
                      <div>
                        <h4 className="text-sm font-bold text-gray-900 dark:text-gray-100">
                          {title || `Quotation for ${job?.issue_title}`}
                        </h4>
                        <p className="text-xs text-gray-500 mt-0.5">{job?.address}</p>
                      </div>
                      <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-300">
                        {quoteNumber || 'DRAFT'}
                      </span>
                    </div>

                    <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-xs">
                      <div>
                        <span className="text-gray-500 dark:text-gray-400 block text-[11px]">Material Subtotal</span>
                        <span className="font-bold text-gray-900 dark:text-gray-100 text-sm">
                          ₹{formatCurrency(totals.materialsCost)}
                        </span>
                      </div>
                      <div>
                        <span className="text-gray-500 dark:text-gray-400 block text-[11px]">Labour Subtotal</span>
                        <span className="font-bold text-gray-900 dark:text-gray-100 text-sm">
                          ₹{formatCurrency(totals.laborCost)}
                        </span>
                      </div>
                      <div>
                        <span className="text-gray-500 dark:text-gray-400 block text-[11px]">GST / Tax (18%)</span>
                        <span className="font-bold text-gray-900 dark:text-gray-100 text-sm">
                          ₹{formatCurrency(totals.totalTax)}
                        </span>
                      </div>
                      <div>
                        <span className="text-gray-500 dark:text-gray-400 block text-[11px]">Gross Total</span>
                        <span className="font-bold text-gray-900 dark:text-gray-100 text-sm">
                          ₹{formatCurrency(totals.grandTotal)}
                        </span>
                      </div>
                    </div>

                    <div className="pt-3 border-t border-gray-200 dark:border-gray-700 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                      <div className="flex items-center gap-2">
                        <label className="text-xs font-medium text-gray-600 dark:text-gray-300">
                          Adjust Inspection Fee (₹):
                        </label>
                        <input
                          type="number"
                          value={inspectionFeeAdjusted}
                          onChange={(e) => setInspectionFeeAdjusted(parseFloat(e.target.value) || 0)}
                          className="w-24 text-xs font-semibold rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 p-1.5 text-right"
                        />
                      </div>

                      <div className="flex items-center gap-3">
                        <span className="text-xs font-bold text-gray-700 dark:text-gray-300">Net Payable:</span>
                        <span className="text-xl font-black text-blue-600 dark:text-blue-400">
                          ₹{formatCurrency(totals.netPayable)}
                        </span>
                      </div>
                    </div>

                    {/* Multi-Day Contracting Advance Policy Display */}
                    <div className="bg-indigo-50/80 dark:bg-indigo-950/40 border border-indigo-200 dark:border-indigo-800/60 rounded-xl p-3 flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                      <div>
                        <div className="text-xs font-bold text-indigo-900 dark:text-indigo-200 flex items-center gap-1.5">
                          <ShieldCheck className="w-4 h-4 text-indigo-600 dark:text-indigo-400" />
                          Commercial Milestone Terms (50% Advance)
                        </div>
                        <p className="text-[11px] text-indigo-700 dark:text-indigo-300">
                          50% advance is required before work starts. Remaining 50% is billed upon verified completion.
                        </p>
                      </div>
                      <div className="flex items-center gap-4 text-right">
                        <div>
                          <span className="text-[10px] uppercase font-bold text-indigo-500 block">50% Advance</span>
                          <span className="text-sm font-extrabold text-indigo-800 dark:text-indigo-200">
                            ₹{formatCurrency(totals.netPayable * 0.5)}
                          </span>
                        </div>
                        <div>
                          <span className="text-[10px] uppercase font-bold text-gray-500 block">Final Balance</span>
                          <span className="text-sm font-extrabold text-gray-700 dark:text-gray-300">
                            ₹{formatCurrency(totals.netPayable - (totals.netPayable * 0.5))}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Summary of Items */}
                  <div>
                    <h5 className="text-xs font-bold text-gray-700 dark:text-gray-300 uppercase tracking-wider mb-2">
                      Line Items Breakdown ({items.length})
                    </h5>
                    <div className="divide-y divide-gray-100 dark:divide-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl overflow-hidden text-xs">
                      {items.map((item, idx) => (
                        <div key={idx} className="p-3 flex items-center justify-between bg-white dark:bg-gray-800">
                          <div>
                            <span className="text-[10px] font-bold text-blue-600 dark:text-blue-400 mr-2">
                              [{item.section}]
                            </span>
                            <span className="font-medium text-gray-900 dark:text-gray-100">{item.name}</span>
                            <span className="text-gray-400 text-[11px] ml-2">
                              ({item.quantity} {item.unit} @ ₹{formatCurrency(item.unit_price)})
                            </span>
                          </div>
                          <span className="font-bold text-gray-900 dark:text-gray-100">
                            ₹
                            {formatCurrency(
                              Math.max(0, (item.quantity || 1) * (item.unit_price || 0) - (item.discount_amount || 0))
                            )}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              )}
            </>
          )}
        </div>

        {/* Footer Navigation */}
        <div className="px-6 py-4 border-t border-gray-200 dark:border-gray-800 bg-gray-50/80 dark:bg-gray-800/50 flex items-center justify-between">
          <div>
            {step > 1 ? (
              <button
                onClick={() => setStep(step - 1)}
                className="inline-flex items-center gap-1.5 text-xs font-semibold px-4 py-2 rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-200 hover:bg-gray-50"
              >
                <ChevronLeft className="w-4 h-4" />
                Previous
              </button>
            ) : (
              <span />
            )}
          </div>

          <div className="flex items-center gap-3">
            {!isReadOnly && (
              <button
                onClick={handleSaveDraft}
                disabled={saving || sending}
                className="inline-flex items-center gap-1.5 text-xs font-semibold px-4 py-2 rounded-xl border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-200 hover:bg-gray-50 shadow-sm disabled:opacity-50 cursor-pointer"
              >
                <Save className="w-4 h-4 text-gray-500" />
                {saving ? 'Saving...' : 'Save Draft'}
              </button>
            )}

            {step < 4 ? (
              <button
                onClick={() => setStep(step + 1)}
                className="inline-flex items-center gap-1.5 text-xs font-semibold px-5 py-2 rounded-xl bg-blue-600 text-white hover:bg-blue-700 shadow-md shadow-blue-600/20 cursor-pointer"
              >
                Next Step
                <ChevronRight className="w-4 h-4" />
              </button>
            ) : isReadOnly ? (
              <button
                onClick={onClose}
                className="inline-flex items-center gap-1.5 text-xs font-bold px-5 py-2 rounded-xl bg-slate-700 text-white hover:bg-slate-800 shadow-md cursor-pointer"
              >
                Close View
              </button>
            ) : (
              <>
                <button
                  onClick={handleSubmitToCRM}
                  disabled={sending || saving || items.length === 0}
                  className="inline-flex items-center gap-1.5 text-xs font-bold px-4 py-2 rounded-xl bg-indigo-600 text-white hover:bg-indigo-700 shadow-md shadow-indigo-600/20 disabled:opacity-50 cursor-pointer"
                >
                  <Sparkles className="w-4 h-4" />
                  {sending ? 'Submitting...' : 'Submit to CRM'}
                </button>
                <button
                  onClick={handleSendQuote}
                  disabled={sending || saving || items.length === 0}
                  className="inline-flex items-center gap-1.5 text-xs font-bold px-5 py-2 rounded-xl bg-green-600 text-white hover:bg-green-700 shadow-md shadow-green-600/20 disabled:opacity-50 cursor-pointer"
                >
                  <Send className="w-4 h-4" />
                  {sending ? 'Sending...' : 'Send Quote to Customer'}
                </button>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
