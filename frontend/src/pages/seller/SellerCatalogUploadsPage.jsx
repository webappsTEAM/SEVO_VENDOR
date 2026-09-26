import React, { useState, useEffect, useMemo, useRef, useCallback } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { Sidebar } from '../../components/common/Sidebar.jsx';
import { useAuth } from '../../context/AuthProvider.jsx';
import {
  UploadCloud,
  FileSpreadsheet,
  Plus,
  Search,
  Filter,
  CheckCircle2,
  AlertCircle,
  Clock,
  PauseCircle,
  XCircle,
  FileEdit,
  Trash2,
  Send,
  Eye,
  Download,
  Layers,
  ArrowRight,
  Sparkles,
  ChevronDown,
  RefreshCw,
  Image as ImageIcon,
  Tag,
  ShieldCheck,
  Building2,
  Info,
  Check,
  X,
  History,
  AlertTriangle,
  FileCheck,
  ChevronRight,
  RotateCcw,
  Scan,
  Barcode as BarcodeIcon,
  Warehouse as WarehouseIcon,
  Truck,
  PackageCheck,
  Boxes,
  Package,
  Printer,
} from 'lucide-react';
import { BarcodeScannerModal } from '../../components/common/BarcodeScannerModal.jsx';
import { BarcodeRenderer } from '../../components/common/BarcodeRenderer.jsx';
import {
  apiSellerGetAssignedWarehouse,
  apiSellerGetInboundRequests,
  apiSellerCreateInboundRequest,
  apiSellerDecideShortfall,
  apiSellerGetEligibleWarehouses,
  apiSellerGetInventoryBalance,
  apiSellerGetInboundLabelsPdfUrl,
} from '../../api/workforceService.js';


const STATUS_CONFIG = {
  ALL: { label: 'All Products', bg: 'bg-slate-100', text: 'text-slate-700', border: 'border-slate-200' },
  DRAFT: { label: 'Draft', bg: 'bg-slate-100', text: 'text-slate-600', border: 'border-slate-300', icon: FileEdit },
  SUBMITTED: { label: 'Awaiting approval', bg: 'bg-blue-50', text: 'text-blue-700', border: 'border-blue-200', icon: Send },
  UNDER_REVIEW: { label: 'Under review', bg: 'bg-amber-50', text: 'text-amber-700', border: 'border-amber-200', icon: Clock },
  CHANGES_REQUESTED: { label: 'Changes requested', bg: 'bg-orange-50', text: 'text-orange-700', border: 'border-orange-200', icon: AlertTriangle },
  APPROVED: { label: 'Approved', bg: 'bg-emerald-50', text: 'text-emerald-700', border: 'border-emerald-200', icon: CheckCircle2 },
  REJECTED: { label: 'Rejected', bg: 'bg-rose-50', text: 'text-rose-700', border: 'border-rose-200', icon: XCircle },
  PAUSED: { label: 'Paused', bg: 'bg-zinc-100', text: 'text-zinc-600', border: 'border-zinc-300', icon: PauseCircle },
};

export function SellerCatalogUploadsPage() {
  const { user, token, isPlatformAdmin, isAdmin } = useAuth();
  const [searchParams, setSearchParams] = useSearchParams();

  // Active view: 'catalog' | 'bulk_upload' | 'batches' | 'inbound_requests'
  const [activeTab, setActiveTab] = useState(searchParams.get('tab') || 'catalog');
  const [statusFilter, setStatusFilter] = useState('ALL');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [searchQuery, setSearchQuery] = useState('');

  // Data states
  const [products, setProducts] = useState([]);
  const [leafCategories, setLeafCategories] = useState([]);
  const [batches, setBatches] = useState([]);
  const [allInboundRequests, setAllInboundRequests] = useState([]);
  const [inboundTabStatusFilter, setInboundTabStatusFilter] = useState('ALL');
  const [metrics, setMetrics] = useState({
    catalogs_awaiting_approval: 0,
    approved_products: 0,
    draft_products: 0,
    changes_requested: 0,
    rejected_products: 0,
    paused_products: 0,
    total_products: 0,
  });

  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [error, setError] = useState(null);
  const [successMessage, setSuccessMessage] = useState(null);

  // Phase X: Inbound Stock Request Modal States
  const [showInboundModal, setShowInboundModal] = useState(false);
  const [inboundModalProduct, setInboundModalProduct] = useState(null);
  const [assignedWarehouseInfo, setAssignedWarehouseInfo] = useState(null);
  const [inboundProductRequests, setInboundProductRequests] = useState([]);
  const [inboundForm, setInboundForm] = useState({ requested_quantity: '', seller_note: '' });
  const [inboundLoading, setInboundLoading] = useState(false);
  const [inboundSubmitting, setInboundSubmitting] = useState(false);
  const [inboundError, setInboundError] = useState(null);
  // Phase AA: Warehouse picker + balance display
  const [eligibleWarehouses, setEligibleWarehouses] = useState([]);
  const [selectedWarehouseId, setSelectedWarehouseId] = useState('');
  const [inventoryBalance, setInventoryBalance] = useState(null); // { on_hand_qty, unit, warehouse_name }
  const [balanceLoading, setBalanceLoading] = useState(false);

  // Phase Z: Shortfall Decision Modal States
  const [showShortfallDecisionModal, setShowShortfallDecisionModal] = useState(false);
  const [shortfallDecisionRequest, setShortfallDecisionRequest] = useState(null);
  const [shortfallDecisionAction, setShortfallDecisionAction] = useState('ACCEPT'); // 'ACCEPT' | 'REJECT'
  const [sellerShortfallNote, setSellerShortfallNote] = useState('');
  const [shortfallDecisionSubmitting, setShortfallDecisionSubmitting] = useState(false);
  const [shortfallDecisionError, setShortfallDecisionError] = useState(null);

  // Phase (Seller Labels): Print Inbound Unit Labels Modal States
  const [showLabelsModal, setShowLabelsModal] = useState(false);
  const [labelsModalRequest, setLabelsModalRequest] = useState(null);
  const [labelsPaperSize, setLabelsPaperSize] = useState('a4');

  // Modals state
  const [showProductModal, setShowProductModal] = useState(false);
  const [showBarcodeScanner, setShowBarcodeScanner] = useState(false);
  const [editingProduct, setEditingProduct] = useState(null);
  const [productForm, setProductForm] = useState({
    title: '',
    brand: '',
    sku: '',
    barcode: '',
    fulfillment_method: 'SELF_SHIP',
    category: '',
    unit: 'piece',
    pack_size: '1',
    mrp: '',
    selling_price: '',
    tax_rate: '0.00',
    hsn_code: '',
    storage_info: '',
    expiry_info: '',
    description: '',
    images: [],
    status: 'DRAFT',
  });
  const [formErrors, setFormErrors] = useState({});

  // Review Decision Modal (Superadmin / Admin)
  const [showReviewModal, setShowReviewModal] = useState(false);
  const [selectedProductForReview, setSelectedProductForReview] = useState(null);
  const [reviewAction, setReviewAction] = useState('approve'); // approve, reject, request_changes, pause
  const [reviewNote, setReviewNote] = useState('');

  // Detail & Audit Log Modal
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [detailedProduct, setDetailedProduct] = useState(null);

  // Bulk Upload state
  const [uploadFile, setUploadFile] = useState(null);
  const [previewResult, setPreviewResult] = useState(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [importLoading, setImportLoading] = useState(false);
  const fileInputRef = useRef(null);

  // Fetch initial data
  const fetchData = async () => {
    setLoading(true);
    setError(null);
    try {
      const authHeader = { Authorization: `Bearer ${token}` };

      // Fetch products, categories, metrics, and batches in parallel
      const [prodRes, catRes, metRes, batRes] = await Promise.all([
        fetch('/api/workforce/seller-hub/products/', { headers: authHeader }),
        fetch('/api/workforce/seller-hub/categories/active/', { headers: authHeader }),
        fetch('/api/workforce/seller-hub/metrics/', { headers: authHeader }),
        fetch('/api/workforce/seller-hub/products/batches/', { headers: authHeader }),
      ]);

      if (!prodRes.ok) throw new Error('Failed to load products');
      const prodData = await prodRes.json();
      setProducts(prodData || []);

      if (catRes.ok) {
        const catData = await catRes.json();
        setLeafCategories(catData || []);
      }

      if (metRes.ok) {
        const metData = await metRes.json();
        setMetrics(metData);
      }

      if (batRes.ok) {
        const batData = await batRes.json();
        setBatches(batData || []);
      }
    } catch (err) {
      console.error('Error fetching catalog data:', err);
      setError(err.message || 'Failed to load catalog records');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (token) {
      fetchData();
    }
  }, [token]);

  // Filtered Products
  const filteredProducts = useMemo(() => {
    return products.filter((p) => {
      // Status filter
      if (statusFilter !== 'ALL' && p.status !== statusFilter) return false;
      // Category filter
      if (categoryFilter && String(p.category) !== String(categoryFilter)) return false;
      // Search query
      if (searchQuery.trim()) {
        const q = searchQuery.toLowerCase();
        const matchesTitle = p.title?.toLowerCase().includes(q);
        const matchesSku = p.sku?.toLowerCase().includes(q);
        const matchesBrand = p.brand?.toLowerCase().includes(q);
        const matchesBarcode = p.barcode?.toLowerCase().includes(q);
        if (!matchesTitle && !matchesSku && !matchesBrand && !matchesBarcode) return false;
      }
      return true;
    });
  }, [products, statusFilter, categoryFilter, searchQuery]);

  // Phase X: Inbound Requests Handlers
  const fetchAllInboundRequests = useCallback(async () => {
    try {
      const res = await apiSellerGetInboundRequests();
      setAllInboundRequests(Array.isArray(res) ? res : res.results || []);
    } catch (err) {
      console.error('Failed to load all inbound requests:', err);
    }
  }, []);

  useEffect(() => {
    if (activeTab === 'inbound_requests') {
      fetchAllInboundRequests();
    }
  }, [activeTab, fetchAllInboundRequests]);

  const handleOpenInboundModal = async (product) => {
    setInboundModalProduct(product);
    setInboundForm({ requested_quantity: '', seller_note: '' });
    setInboundError(null);
    setSelectedWarehouseId('');
    setInventoryBalance(null);
    setShowInboundModal(true);
    setInboundLoading(true);

    try {
      const [whRes, reqsRes, eligibleRes] = await Promise.all([
        apiSellerGetAssignedWarehouse().catch(() => ({ assigned: false, warehouse: null })),
        apiSellerGetInboundRequests({ product_id: product.id }).catch(() => []),
        apiSellerGetEligibleWarehouses().catch(() => ({ warehouses: [], count: 0 })),
      ]);
      setAssignedWarehouseInfo(whRes);
      setInboundProductRequests(Array.isArray(reqsRes) ? reqsRes : reqsRes.results || []);

      const whList = eligibleRes?.warehouses || (Array.isArray(eligibleRes) ? eligibleRes : []);
      setEligibleWarehouses(whList);

      // Preselect assigned warehouse if present in eligible list, or first eligible warehouse
      if (whRes?.assigned && whRes?.warehouse?.id) {
        const assignedId = String(whRes.warehouse.id);
        const match = whList.find((w) => String(w.id) === assignedId);
        if (match) {
          setSelectedWarehouseId(assignedId);
        } else if (whList.length > 0) {
          setSelectedWarehouseId(String(whList[0].id));
        }
      } else if (whList.length > 0) {
        setSelectedWarehouseId(String(whList[0].id));
      }
    } catch (err) {
      console.error('Failed to load inbound modal data:', err);
      setInboundError(err.message || 'Failed to load warehouse data');
    } finally {
      setInboundLoading(false);
    }
  };

  // Phase AA: Fetch inventory balance whenever product or warehouse selection changes
  useEffect(() => {
    if (!showInboundModal || !inboundModalProduct || !selectedWarehouseId) {
      setInventoryBalance(null);
      return;
    }
    let cancelled = false;
    const fetchBalance = async () => {
      setBalanceLoading(true);
      try {
        const res = await apiSellerGetInventoryBalance(inboundModalProduct.id, selectedWarehouseId);
        if (!cancelled) setInventoryBalance(res);
      } catch {
        if (!cancelled) setInventoryBalance(null);
      } finally {
        if (!cancelled) setBalanceLoading(false);
      }
    };
    fetchBalance();
    return () => { cancelled = true; };
  }, [showInboundModal, inboundModalProduct?.id, selectedWarehouseId]);

  const handleSubmitInboundRequest = async (e) => {
    e.preventDefault();
    if (!inboundModalProduct) return;

    if (!selectedWarehouseId) {
      setInboundError('Please select a target warehouse facility.');
      return;
    }

    const qty = parseInt(inboundForm.requested_quantity, 10);
    if (!qty || qty <= 0) {
      setInboundError('Please enter a valid requested quantity greater than 0.');
      return;
    }

    setInboundSubmitting(true);
    setInboundError(null);

    try {
      const targetWarehouseId = parseInt(selectedWarehouseId, 10);
      await apiSellerCreateInboundRequest({
        product_id: inboundModalProduct.id,
        warehouse_id: targetWarehouseId,
        requested_quantity: qty,
        seller_note: inboundForm.seller_note.trim(),
      });

      const chosenWh = eligibleWarehouses.find((w) => String(w.id) === String(selectedWarehouseId));
      const chosenName = chosenWh ? chosenWh.name : (assignedWarehouseInfo?.warehouse?.name || 'warehouse');

      setSuccessMessage(`Inbound storage request for ${qty} units submitted to ${chosenName} successfully!`);
      setTimeout(() => setSuccessMessage(null), 4500);

      // Refresh product requests list in modal and global list
      const reqsRes = await apiSellerGetInboundRequests({ product_id: inboundModalProduct.id });
      setInboundProductRequests(Array.isArray(reqsRes) ? reqsRes : reqsRes.results || []);
      setInboundForm({ requested_quantity: '', seller_note: '' });
      fetchAllInboundRequests();
    } catch (err) {
      console.error('Failed to submit inbound request:', err);
      setInboundError(err.message || 'Failed to submit inbound request.');
    } finally {
      setInboundSubmitting(false);
    }
  };

  // Phase Z: Shortfall Decision Handlers
  const handleOpenShortfallDecisionModal = (req, action) => {
    setShortfallDecisionRequest(req);
    setShortfallDecisionAction(action);
    setSellerShortfallNote(
      action === 'ACCEPT'
        ? 'Partial delivery accepted. Proceeding live with verified stock.'
        : 'Batch rejected due to delivery shortfall. Please stage for return.'
    );
    setShortfallDecisionError(null);
    setShowShortfallDecisionModal(true);
  };

  const handleConfirmShortfallDecision = async (e) => {
    e.preventDefault();
    if (!shortfallDecisionRequest) return;

    setShortfallDecisionSubmitting(true);
    setShortfallDecisionError(null);

    try {
      await apiSellerDecideShortfall(
        shortfallDecisionRequest.id,
        shortfallDecisionAction,
        sellerShortfallNote.trim()
      );

      const msg =
        shortfallDecisionAction === 'ACCEPT'
          ? `Partial intake of ${shortfallDecisionRequest.confirmed_quantity || shortfallDecisionRequest.received_units_count} units accepted and is now LIVE in store inventory!`
          : `Shortfall batch for Inbound Req #${shortfallDecisionRequest.id} rejected. Return record staged for warehouse.`;

      setSuccessMessage(msg);
      setTimeout(() => setSuccessMessage(null), 5000);
      setShowShortfallDecisionModal(false);
      setShortfallDecisionRequest(null);
      fetchAllInboundRequests();
      fetchData();
    } catch (err) {
      console.error('Failed to record shortfall decision:', err);
      setShortfallDecisionError(err.message || 'Failed to record shortfall decision.');
    } finally {
      setShortfallDecisionSubmitting(false);
    }
  };

  const handleOpenLabelsModal = (req) => {
    setLabelsModalRequest(req);
    setLabelsPaperSize('a4');
    setShowLabelsModal(true);
  };

  const handlePrintLabelsPdf = (format = labelsPaperSize) => {
    if (!labelsModalRequest) return;
    const url = apiSellerGetInboundLabelsPdfUrl(labelsModalRequest.id, format);
    window.open(url, '_blank');
  };

  // Meesho Category Picker states (Step 1)
  const [productModalStep, setProductModalStep] = useState(1); // 1: Select Category, 2: Add Product Details
  const [pickerSearch, setPickerSearch] = useState('');
  const [pickerSearchResults, setPickerSearchResults] = useState([]);
  const [pickerSearchLoading, setPickerSearchLoading] = useState(false);
  const [pickerColumns, setPickerColumns] = useState([]); // Array of column arrays: [[rootCats], [subCats], [leafCats]]
  const [pickerSelectedPath, setPickerSelectedPath] = useState([]); // Selected category object per column
  const [pickerSelectedLeaf, setPickerSelectedLeaf] = useState(null); // The final selected leaf category
  const [pickerCache, setPickerCache] = useState({}); // { [parentId || 'root']: Array<Category> }
  const [pickerColumnLoading, setPickerColumnLoading] = useState({}); // { [colIndex]: boolean }
  const [pickerErrors, setPickerErrors] = useState({}); // { [colIndex]: string | null }
  const [categoryWarning, setCategoryWarning] = useState(null);
  const pickerSearchTimerRef = useRef(null);
  const pickerSelectedPathRef = useRef(pickerSelectedPath);
  pickerSelectedPathRef.current = pickerSelectedPath;

  // Load a column for parentId (or 'root' if null)
  const loadPickerColumn = async (parentId = null, colIndex = 0, forceRefresh = false) => {
    const cacheKey = parentId ? String(parentId) : 'root';
    if (!forceRefresh && pickerCache[cacheKey]) {
      setPickerColumns((prev) => {
        const next = prev.slice(0, colIndex);
        next[colIndex] = pickerCache[cacheKey];
        return next;
      });
      return pickerCache[cacheKey];
    }

    setPickerColumnLoading((prev) => ({ ...prev, [colIndex]: true }));
    setPickerErrors((prev) => ({ ...prev, [colIndex]: null }));
    try {
      const url = parentId
        ? `/api/workforce/seller-hub/catalog/categories/?parent_id=${parentId}`
        : '/api/workforce/seller-hub/catalog/categories/?parent_id=null';
      const res = await fetch(url, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const raw = await res.json();
        const items = Array.isArray(raw) ? raw : (raw?.results || []);
        setPickerCache((prev) => ({ ...prev, [cacheKey]: items }));
        setPickerColumns((prev) => {
          const next = prev.slice(0, colIndex);
          next[colIndex] = items;
          return next;
        });
        return items;
      } else {
        const errText = `Failed to load categories (HTTP ${res.status})`;
        setPickerErrors((prev) => ({ ...prev, [colIndex]: errText }));
      }
    } catch (e) {
      console.error('Error fetching category column', e);
      setPickerErrors((prev) => ({ ...prev, [colIndex]: e.message || 'Network connection failed' }));
    } finally {
      setPickerColumnLoading((prev) => ({ ...prev, [colIndex]: false }));
    }
    return [];
  };

  const lastFocusRefetchTimeRef = useRef(0);

  // In-place background refresh of root categories without resetting drill-down
  const refetchRootColumnInPlace = useCallback(async () => {
    try {
      const res = await fetch('/api/workforce/seller-hub/catalog/categories/?parent_id=null', {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const raw = await res.json();
        const freshRoots = Array.isArray(raw) ? raw : (raw?.results || []);
        setPickerCache((prev) => ({ ...prev, root: freshRoots }));
        setPickerColumns((prev) => {
          const next = [...prev];
          next[0] = freshRoots;
          return next;
        });

        // Check if previously selected root still exists and is not deactivated
        const currentPath = pickerSelectedPathRef.current;
        if (currentPath && currentPath.length > 0) {
          const selectedRoot = currentPath[0];
          const foundRoot = (freshRoots || []).find((r) => r.id === selectedRoot.id);
          const isGone = !foundRoot || foundRoot.is_active === false;
          if (isGone) {
            setPickerSelectedLeaf(null);
            setPickerSelectedPath([]);
            setPickerColumns((prevCols) => [prevCols[0] || freshRoots]);
            setCategoryWarning('The previously selected root category is no longer active.');
          }
        }
      }
    } catch (e) {
      console.error('In-place root category refetch error', e);
    }
  }, [token]);

  // Refetch root categories in-place when tab regains focus while modal is open
  useEffect(() => {
    if (!showProductModal || productModalStep !== 1) return;

    const handleTabFocus = () => {
      const now = Date.now();
      if (now - lastFocusRefetchTimeRef.current < 2000) return; // Deduplicate within 2s
      lastFocusRefetchTimeRef.current = now;

      if (document.visibilityState === 'visible' && !pickerSearch.trim()) {
        refetchRootColumnInPlace();
      }
    };

    window.addEventListener('focus', handleTabFocus);
    document.addEventListener('visibilitychange', handleTabFocus);
    return () => {
      window.removeEventListener('focus', handleTabFocus);
      document.removeEventListener('visibilitychange', handleTabFocus);
    };
  }, [showProductModal, productModalStep, pickerSearch, refetchRootColumnInPlace]);

  const handleRefreshPicker = () => {
    setPickerCache({});
    setPickerSelectedPath([]);
    setPickerSelectedLeaf(null);
    loadPickerColumn(null, 0, true);
  };

  // Handle category search input
  const handlePickerSearchChange = (text) => {
    setPickerSearch(text);
    if (pickerSearchTimerRef.current) clearTimeout(pickerSearchTimerRef.current);
    const q = text.trim();
    if (q.length >= 2) {
      setPickerSearchLoading(true);
      pickerSearchTimerRef.current = setTimeout(async () => {
        try {
          const res = await fetch(`/api/workforce/seller-hub/catalog/categories/?q=${encodeURIComponent(q)}`, {
            headers: { Authorization: `Bearer ${token}` },
          });
          if (res.ok) {
            const data = await res.json();
            setPickerSearchResults(data || []);
          }
        } catch (e) {
          console.error('Category search error', e);
        } finally {
          setPickerSearchLoading(false);
        }
      }, 250);
    } else {
      setPickerSearchResults([]);
      setPickerSearchLoading(false);
    }
  };

  // Handle selecting a category from cascading column
  const handleColumnItemClick = (cat, colIndex) => {
    const nextPath = pickerSelectedPath.slice(0, colIndex);
    nextPath[colIndex] = cat;
    setPickerSelectedPath(nextPath);

    if (cat.has_children) {
      setPickerSelectedLeaf(null);
      loadPickerColumn(cat.id, colIndex + 1);
    } else {
      setPickerSelectedLeaf(cat);
      setPickerColumns((prev) => prev.slice(0, colIndex + 1));
    }
  };

  // Handle selecting a category from search results
  const handleSearchResultClick = (cat) => {
    if (!cat.is_leaf) return;
    setPickerSelectedLeaf(cat);
    setPickerSelectedPath(cat.path || [cat]);
    setPickerSearch('');
    setPickerSearchResults([]);
  };

  // Open single product creator / editor
  const handleOpenProductModal = (prod = null) => {
    setFormErrors({});
    setCategoryWarning(null);
    setPickerSearch('');
    setPickerSearchResults([]);

    if (prod) {
      setEditingProduct(prod);
      setProductForm({
        title: prod.title || '',
        brand: prod.brand || '',
        sku: prod.sku || '',
        barcode: prod.barcode || '',
        fulfillment_method: prod.fulfillment_method || 'SELF_SHIP',
        category: prod.category || '',
        unit: prod.unit || 'piece',
        pack_size: prod.pack_size || '1',
        mrp: prod.mrp || '',
        selling_price: prod.selling_price || '',
        tax_rate: prod.tax_rate || '0.00',
        hsn_code: prod.hsn_code || '',
        storage_info: prod.storage_info || '',
        expiry_info: prod.expiry_info || '',
        description: prod.description || '',
        images: prod.primary_image ? [prod.primary_image] : [],
        status: prod.status || 'DRAFT',
      });

      // Match category details or path
      const matched = leafCategories.find((c) => c.id === prod.category);
      if (matched) {
        setPickerSelectedLeaf(matched);
        setPickerSelectedPath(matched.path || [matched]);
      } else {
        setPickerSelectedLeaf({
          id: prod.category,
          name: prod.category_name || `Category #${prod.category}`,
          path_string: prod.category_path || `Category #${prod.category}`,
          is_leaf: true,
        });
      }
      // Opens on step 2 for edit
      setProductModalStep(2);
    } else {
      setEditingProduct(null);
      setPickerSelectedLeaf(null);
      setPickerSelectedPath([]);
      setPickerCache({});
      setPickerColumns([]);
      setPickerErrors({});
      setProductForm({
        title: '',
        brand: '',
        sku: '',
        barcode: '',
        fulfillment_method: 'SELF_SHIP',
        category: '',
        unit: 'piece',
        pack_size: '1',
        mrp: '',
        selling_price: '',
        tax_rate: '0.00',
        hsn_code: '',
        storage_info: '',
        expiry_info: '',
        description: '',
        images: [],
        status: 'DRAFT',
      });
      // Opens on step 1 for add product and fetches fresh root categories
      setProductModalStep(1);
      loadPickerColumn(null, 0, true);
    }
    setShowProductModal(true);
  };

  const handleCloseProductModal = () => {
    setShowProductModal(false);
    setEditingProduct(null);
    setPickerSelectedLeaf(null);
    setPickerSelectedPath([]);
    setCategoryWarning(null);
  };

  // Image upload handler
  const handleImageFileUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.size > 5 * 1024 * 1024) {
      alert('Image file size must be less than 5MB');
      return;
    }

    const formData = new FormData();
    formData.append('image', file);

    try {
      setActionLoading(true);
      const res = await fetch('/api/workforce/seller-hub/products/upload-image/', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: formData,
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Failed to upload image');
      setProductForm((prev) => ({
        ...prev,
        images: [...prev.images, data.image_url],
      }));
    } catch (err) {
      alert(err.message || 'Image upload failed');
    } finally {
      setActionLoading(false);
    }
  };

  // Save product form (Draft or Submit)
  const handleSaveProduct = async (submitNow = false) => {
    setFormErrors({});
    const errors = {};

    if (!productForm.title.trim()) errors.title = 'Product title is required';
    if (!productForm.sku.trim()) errors.sku = 'SKU is required';
    if (!productForm.category) errors.category = 'Category is required';
    if (!productForm.mrp || Number(productForm.mrp) <= 0) errors.mrp = 'Valid MRP is required';
    if (!productForm.selling_price || Number(productForm.selling_price) <= 0) errors.selling_price = 'Valid selling price is required';
    if (Number(productForm.selling_price) > Number(productForm.mrp)) {
      errors.selling_price = 'Selling price cannot exceed MRP';
    }
    if (submitNow && productForm.images.length === 0) {
      errors.images = 'At least one product image is required to submit for review';
    }

    if (Object.keys(errors).length > 0) {
      setFormErrors(errors);
      return;
    }

    setActionLoading(true);
    try {
      const payload = {
        ...productForm,
        status: submitNow ? 'SUBMITTED' : (editingProduct ? productForm.status : 'DRAFT'),
      };

      const url = editingProduct
        ? `/api/workforce/seller-hub/products/${editingProduct.id}/`
        : '/api/workforce/seller-hub/products/';
      const method = editingProduct ? 'PATCH' : 'POST';

      const res = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify(payload),
      });

      const data = await res.json();
      if (!res.ok) {
        if (data.details) {
          setFormErrors(data.details);
        }
        throw new Error(data.error || 'Failed to save product');
      }

      setSuccessMessage(data.message || 'Product saved successfully!');
      setShowProductModal(false);
      fetchData();
      setTimeout(() => setSuccessMessage(null), 4000);
    } catch (err) {
      alert(err.message || 'Failed to save product');
    } finally {
      setActionLoading(false);
    }
  };

  // Submit product for review
  const handleSubmitProduct = async (prodId) => {
    if (!confirm('Are you sure you want to submit this product for catalog review?')) return;
    setActionLoading(true);
    try {
      const res = await fetch(`/api/workforce/seller-hub/products/${prodId}/submit/`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Failed to submit product');
      setSuccessMessage(data.message);
      fetchData();
      setTimeout(() => setSuccessMessage(null), 4000);
    } catch (err) {
      alert(err.message);
    } finally {
      setActionLoading(false);
    }
  };

  // Delete product
  const handleDeleteProduct = async (prodId, title) => {
    if (!confirm(`Are you sure you want to delete '${title}'? This action cannot be undone.`)) return;
    setActionLoading(true);
    try {
      const res = await fetch(`/api/workforce/seller-hub/products/${prodId}/`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Failed to delete product');
      setSuccessMessage(data.message);
      fetchData();
      setTimeout(() => setSuccessMessage(null), 4000);
    } catch (err) {
      alert(err.message);
    } finally {
      setActionLoading(false);
    }
  };

  // Open Product Detail Modal
  const handleOpenDetailModal = async (prodId) => {
    try {
      const res = await fetch(`/api/workforce/seller-hub/products/${prodId}/`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = await res.json();
      if (res.ok) {
        setDetailedProduct(data);
        setShowDetailModal(true);
      }
    } catch (err) {
      console.error('Error opening detail modal:', err);
    }
  };

  // Admin Review Decision Handler
  const handleOpenReviewModal = (prod) => {
    setSelectedProductForReview(prod);
    setReviewAction('approve');
    setReviewNote('');
    setShowReviewModal(true);
  };

  const handleExecuteReviewDecision = async () => {
    if (!selectedProductForReview) return;
    if (['reject', 'request_changes', 'pause'].includes(reviewAction) && !reviewNote.trim()) {
      alert('Please enter a feedback reason/note for this decision.');
      return;
    }

    setActionLoading(true);
    try {
      const res = await fetch(`/api/workforce/seller-hub/products/${selectedProductForReview.id}/review/`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          action: reviewAction,
          note: reviewNote.trim(),
        }),
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Failed to execute review decision');

      setSuccessMessage(data.message);
      setShowReviewModal(false);
      fetchData();
      setTimeout(() => setSuccessMessage(null), 4000);
    } catch (err) {
      alert(err.message);
    } finally {
      setActionLoading(false);
    }
  };

  // Bulk Upload Handlers
  const handleSelectBulkFile = (e) => {
    const file = e.target.files?.[0];
    if (file) {
      setUploadFile(file);
      setPreviewResult(null);
    }
  };

  const handleValidatePreview = async () => {
    if (!uploadFile) return;
    setPreviewLoading(true);
    try {
      const formData = new FormData();
      formData.append('file', uploadFile);

      const res = await fetch('/api/workforce/seller-hub/products/bulk-upload/?preview=true', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: formData,
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Failed to parse file');
      setPreviewResult(data);
    } catch (err) {
      alert(err.message);
    } finally {
      setPreviewLoading(false);
    }
  };

  const handleConfirmBulkImport = async () => {
    if (!uploadFile) return;
    setImportLoading(true);
    try {
      const formData = new FormData();
      formData.append('file', uploadFile);

      const res = await fetch('/api/workforce/seller-hub/products/bulk-upload/', {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}` },
        body: formData,
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'Bulk import failed');

      setSuccessMessage(data.message);
      setUploadFile(null);
      setPreviewResult(null);
      setActiveTab('catalog');
      fetchData();
      setTimeout(() => setSuccessMessage(null), 5000);
    } catch (err) {
      alert(err.message);
    } finally {
      setImportLoading(false);
    }
  };

  const handleDownloadTemplate = () => {
    window.open('/api/workforce/seller-hub/products/template/', '_blank');
  };

  return (
    <div className="flex min-h-screen bg-slate-100 font-sans text-slate-800">
      <Sidebar />

      <main className="flex-1 min-w-0 flex flex-col">
        {/* Header */}
        <header className="bg-white border-b border-slate-200 sticky top-0 z-10 px-8 py-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 shadow-xs">
          <div className="flex items-center gap-3">
            <span className="p-2.5 bg-emerald-50 text-emerald-600 rounded-xl border border-emerald-200">
              <UploadCloud className="w-5 h-5" />
            </span>
            <div>
              <h1 className="text-xl font-bold text-slate-900 tracking-tight">Catalog Uploads & Products</h1>
              <p className="text-xs text-slate-500 mt-0.5">
                Single item creator, bulk CSV/Excel feeds, leaf category tagging, and admin verification workflow
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => handleOpenProductModal()}
              className="inline-flex items-center gap-1.5 px-3.5 py-2 text-xs font-bold text-white bg-emerald-600 hover:bg-emerald-700 rounded-lg shadow-xs transition-colors"
            >
              <Plus className="w-4 h-4" />
              <span>Add Single Product</span>
            </button>
            <button
              onClick={() => setActiveTab('bulk_upload')}
              className={`inline-flex items-center gap-1.5 px-3.5 py-2 text-xs font-semibold rounded-lg border transition-colors ${
                activeTab === 'bulk_upload'
                  ? 'bg-indigo-600 text-white border-indigo-600'
                  : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50'
              }`}
            >
              <FileSpreadsheet className="w-4 h-4 text-indigo-500" />
              <span>Bulk Feed</span>
            </button>
            <button
              onClick={fetchData}
              className="p-2 text-slate-500 hover:text-slate-800 bg-white border border-slate-200 hover:bg-slate-50 rounded-lg transition-colors"
              title="Refresh catalog"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-emerald-600' : ''}`} />
            </button>
          </div>
        </header>

        {/* Global Notification Banner */}
        {successMessage && (
          <div className="mx-8 mt-4 p-3.5 bg-emerald-50 border border-emerald-200 text-emerald-900 rounded-xl text-xs font-medium flex items-center justify-between shadow-xs">
            <div className="flex items-center gap-2">
              <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0" />
              <span>{successMessage}</span>
            </div>
            <button onClick={() => setSuccessMessage(null)} className="text-emerald-700 hover:text-emerald-900">
              <X className="w-4 h-4" />
            </button>
          </div>
        )}

        {/* Content Body */}
        <div className="p-8 max-w-7xl w-full mx-auto space-y-6">
          {/* Top Real Metrics Cards */}
          <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-6 gap-3.5">
            <div
              onClick={() => { setStatusFilter('ALL'); setActiveTab('catalog'); }}
              className={`p-3.5 bg-white rounded-xl border cursor-pointer transition-all ${
                statusFilter === 'ALL' && activeTab === 'catalog'
                  ? 'border-slate-900 ring-2 ring-slate-900/10 shadow-xs'
                  : 'border-slate-200 hover:border-slate-300'
              }`}
            >
              <span className="text-[11px] font-semibold text-slate-500">Total Items</span>
              <p className="text-2xl font-black text-slate-900 font-mono mt-1">{metrics.total_products}</p>
              <span className="text-[10px] text-slate-400">All registered</span>
            </div>

            <div
              onClick={() => { setStatusFilter('APPROVED'); setActiveTab('catalog'); }}
              className={`p-3.5 bg-white rounded-xl border cursor-pointer transition-all ${
                statusFilter === 'APPROVED' && activeTab === 'catalog'
                  ? 'border-emerald-600 ring-2 ring-emerald-600/10 shadow-xs'
                  : 'border-slate-200 hover:border-emerald-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-semibold text-emerald-700">Approved</span>
                <CheckCircle2 className="w-3.5 h-3.5 text-emerald-600" />
              </div>
              <p className="text-2xl font-black text-emerald-900 font-mono mt-1">{metrics.approved_products}</p>
              <span className="text-[10px] text-emerald-600">Verified & Active</span>
            </div>

            <div
              onClick={() => { setStatusFilter('SUBMITTED'); setActiveTab('catalog'); }}
              className={`p-3.5 bg-white rounded-xl border cursor-pointer transition-all ${
                statusFilter === 'SUBMITTED' && activeTab === 'catalog'
                  ? 'border-blue-600 ring-2 ring-blue-600/10 shadow-xs'
                  : 'border-slate-200 hover:border-blue-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-semibold text-blue-700">Awaiting Review</span>
                <Clock className="w-3.5 h-3.5 text-blue-600" />
              </div>
              <p className="text-2xl font-black text-blue-900 font-mono mt-1">{metrics.catalogs_awaiting_approval}</p>
              <span className="text-[10px] text-blue-600">Submitted Queue</span>
            </div>

            <div
              onClick={() => { setStatusFilter('CHANGES_REQUESTED'); setActiveTab('catalog'); }}
              className={`p-3.5 bg-white rounded-xl border cursor-pointer transition-all ${
                statusFilter === 'CHANGES_REQUESTED' && activeTab === 'catalog'
                  ? 'border-orange-500 ring-2 ring-orange-500/10 shadow-xs'
                  : 'border-slate-200 hover:border-orange-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-semibold text-orange-700">Action Required</span>
                <AlertTriangle className="w-3.5 h-3.5 text-orange-600" />
              </div>
              <p className="text-2xl font-black text-orange-900 font-mono mt-1">{metrics.changes_requested}</p>
              <span className="text-[10px] text-orange-600">Changes Requested</span>
            </div>

            <div
              onClick={() => { setStatusFilter('DRAFT'); setActiveTab('catalog'); }}
              className={`p-3.5 bg-white rounded-xl border cursor-pointer transition-all ${
                statusFilter === 'DRAFT' && activeTab === 'catalog'
                  ? 'border-slate-600 ring-2 ring-slate-600/10 shadow-xs'
                  : 'border-slate-200 hover:border-slate-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-semibold text-slate-600">Drafts</span>
                <FileEdit className="w-3.5 h-3.5 text-slate-500" />
              </div>
              <p className="text-2xl font-black text-slate-800 font-mono mt-1">{metrics.draft_products}</p>
              <span className="text-[10px] text-slate-500">Unsubmitted items</span>
            </div>

            <div
              onClick={() => { setStatusFilter('REJECTED'); setActiveTab('catalog'); }}
              className={`p-3.5 bg-white rounded-xl border cursor-pointer transition-all ${
                statusFilter === 'REJECTED' && activeTab === 'catalog'
                  ? 'border-rose-500 ring-2 ring-rose-500/10 shadow-xs'
                  : 'border-slate-200 hover:border-rose-300'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-semibold text-rose-700">Rejected</span>
                <XCircle className="w-3.5 h-3.5 text-rose-600" />
              </div>
              <p className="text-2xl font-black text-rose-900 font-mono mt-1">{metrics.rejected_products}</p>
              <span className="text-[10px] text-rose-600">Format / Compliance</span>
            </div>
          </div>

          {/* Navigation View Tabs */}
          <div className="flex items-center justify-between border-b border-slate-200 pb-2">
            <div className="flex items-center gap-2">
              <button
                onClick={() => setActiveTab('catalog')}
                className={`px-4 py-2 text-xs font-bold rounded-lg transition-all ${
                  activeTab === 'catalog'
                    ? 'bg-slate-900 text-white shadow-xs'
                    : 'text-slate-600 hover:text-slate-900 hover:bg-slate-200/60'
                }`}
              >
                Product Catalog ({products.length})
              </button>
              <button
                onClick={() => setActiveTab('bulk_upload')}
                className={`px-4 py-2 text-xs font-bold rounded-lg transition-all ${
                  activeTab === 'bulk_upload'
                    ? 'bg-slate-900 text-white shadow-xs'
                    : 'text-slate-600 hover:text-slate-900 hover:bg-slate-200/60'
                }`}
              >
                Bulk CSV / Excel Ingestion
              </button>
              <button
                onClick={() => setActiveTab('batches')}
                className={`px-4 py-2 text-xs font-bold rounded-lg transition-all ${
                  activeTab === 'batches'
                    ? 'bg-slate-900 text-white shadow-xs'
                    : 'text-slate-600 hover:text-slate-900 hover:bg-slate-200/60'
                }`}
              >
                Upload Batches ({batches.length})
              </button>
              <button
                onClick={() => {
                  setActiveTab('inbound_requests');
                  fetchAllInboundRequests();
                }}
                className={`px-4 py-2 text-xs font-bold rounded-lg transition-all flex items-center gap-1.5 ${
                  activeTab === 'inbound_requests'
                    ? 'bg-indigo-900 text-white shadow-xs'
                    : 'text-indigo-700 hover:text-indigo-900 hover:bg-indigo-50'
                }`}
              >
                <Boxes className="w-3.5 h-3.5" />
                <span>Warehouse Storage Requests ({allInboundRequests.length})</span>
              </button>
            </div>

            {/* Category Directory Link */}
            <Link
              to="/workforce/admin/seller-hub/categories"
              className="text-xs font-semibold text-emerald-700 hover:text-emerald-900 flex items-center gap-1"
            >
              <Layers className="w-3.5 h-3.5" />
              <span>Seller Hub Categories ({leafCategories.length} Leaf Available)</span>
            </Link>
          </div>

          {/* ════════════════════════════════════════════════════════════════════ */}
          {/* TAB 1: PRODUCT CATALOG LIST                                        */}
          {/* ════════════════════════════════════════════════════════════════════ */}
          {activeTab === 'catalog' && (
            <div className="space-y-4">
              {/* Notice: Only approved products appear in Inventory */}
              <div className="p-3.5 bg-blue-50/80 border border-blue-200 rounded-xl flex items-center justify-between text-xs text-blue-900 shadow-2xs">
                <div className="flex items-center gap-2.5">
                  <Info className="w-4 h-4 text-blue-600 shrink-0" />
                  <span>
                    <strong>Catalog Approval Notice:</strong> Only approved products appear in Inventory. Submitted products require admin review before opening stock can be managed.
                  </span>
                </div>
                <Link to="/workforce/seller-hub/inventory" className="text-blue-700 hover:text-blue-900 font-bold shrink-0 ml-2">
                  Inventory &rarr;
                </Link>
              </div>

              {/* Search & Status Filters Bar */}
              <div className="p-4 bg-white rounded-2xl border border-slate-200 shadow-xs flex flex-col md:flex-row items-center justify-between gap-3">
                {/* Search input */}
                <div className="relative w-full md:w-80">
                  <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                  <input
                    type="text"
                    placeholder="Search by Title, SKU, Brand, Barcode..."
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    className="w-full pl-9 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500"
                  />
                  {searchQuery && (
                    <button
                      onClick={() => setSearchQuery('')}
                      className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                    >
                      <X className="w-3.5 h-3.5" />
                    </button>
                  )}
                </div>

                {/* Filters */}
                <div className="flex items-center gap-2 w-full md:w-auto overflow-x-auto">
                  <select
                    value={categoryFilter}
                    onChange={(e) => setCategoryFilter(e.target.value)}
                    className="px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs font-medium text-slate-700 focus:outline-none focus:ring-2 focus:ring-emerald-500/20"
                  >
                    <option value="">All Categories</option>
                    {leafCategories.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.path}
                      </option>
                    ))}
                  </select>

                  <select
                    value={statusFilter}
                    onChange={(e) => setStatusFilter(e.target.value)}
                    className="px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs font-semibold text-slate-700 focus:outline-none focus:ring-2 focus:ring-emerald-500/20"
                  >
                    <option value="ALL">All Statuses</option>
                    <option value="DRAFT">Draft</option>
                    <option value="SUBMITTED">Awaiting approval</option>
                    <option value="UNDER_REVIEW">Under review</option>
                    <option value="CHANGES_REQUESTED">Changes requested</option>
                    <option value="APPROVED">Approved</option>
                    <option value="REJECTED">Rejected</option>
                    <option value="PAUSED">Paused</option>
                  </select>
                </div>
              </div>

              {/* Products Table */}
              <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
                {loading ? (
                  <div className="p-12 text-center text-slate-400 flex flex-col items-center justify-center gap-3">
                    <RefreshCw className="w-6 h-6 animate-spin text-emerald-600" />
                    <span className="text-xs font-medium">Loading store products...</span>
                  </div>
                ) : filteredProducts.length === 0 ? (
                  <div className="p-12 text-center flex flex-col items-center justify-center">
                    <div className="w-14 h-14 bg-slate-50 border border-slate-200 rounded-2xl flex items-center justify-center text-slate-400 mb-3 shadow-xs">
                      <ImageIcon className="w-7 h-7 text-slate-400" />
                    </div>
                    <h3 className="text-sm font-bold text-slate-800">No products found</h3>
                    <p className="text-xs text-slate-500 mt-1 max-w-sm">
                      {searchQuery || statusFilter !== 'ALL' || categoryFilter
                        ? 'No products matched your search or status filter criteria.'
                        : 'Your store catalog is currently empty. Click below to add your first product or use bulk CSV ingestion.'}
                    </p>
                    <div className="mt-5 flex items-center gap-2">
                      <button
                        onClick={() => handleOpenProductModal()}
                        className="px-4 py-2 bg-emerald-600 text-white rounded-lg text-xs font-bold shadow-xs hover:bg-emerald-700"
                      >
                        Add First Product
                      </button>
                      <button
                        onClick={() => setActiveTab('bulk_upload')}
                        className="px-4 py-2 bg-slate-100 text-slate-700 rounded-lg text-xs font-bold hover:bg-slate-200"
                      >
                        Upload Bulk File
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full text-left text-xs">
                      <thead className="bg-slate-50/80 border-b border-slate-200 text-slate-500 font-semibold uppercase tracking-wider text-[10px]">
                        <tr>
                          <th className="px-4 py-3.5">Product & SKU</th>
                          <th className="px-4 py-3.5">Category</th>
                          <th className="px-4 py-3.5">Pricing</th>
                          <th className="px-4 py-3.5">Pack & Tax</th>
                          <th className="px-4 py-3.5">Status & Review</th>
                          <th className="px-4 py-3.5 text-right">Actions</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium">
                        {filteredProducts.map((p) => {
                          const statusConf = STATUS_CONFIG[p.status] || STATUS_CONFIG.DRAFT;
                          const StatusIcon = statusConf.icon || Info;
                          const discountPercent =
                            p.mrp > p.selling_price
                              ? Math.round(((p.mrp - p.selling_price) / p.mrp) * 100)
                              : 0;

                          return (
                            <tr key={p.id} className="hover:bg-slate-50/80 transition-colors">
                              {/* Product Info */}
                              <td className="px-4 py-3.5">
                                <div className="flex items-center gap-3">
                                  <div className="w-12 h-12 rounded-xl bg-slate-100 border border-slate-200 shrink-0 overflow-hidden flex items-center justify-center">
                                    {p.primary_image ? (
                                      <img
                                        src={p.primary_image}
                                        alt={p.title}
                                        className="w-full h-full object-cover"
                                        onError={(e) => {
                                          e.target.style.display = 'none';
                                        }}
                                      />
                                    ) : (
                                      <ImageIcon className="w-5 h-5 text-slate-300" />
                                    )}
                                  </div>
                                  <div className="min-w-0 max-w-xs">
                                    <span className="font-bold text-slate-900 block truncate text-xs" title={p.title}>
                                      {p.title}
                                    </span>
                                    <div className="flex items-center gap-1.5 mt-0.5 text-[11px] text-slate-500 font-mono">
                                      <span className="bg-slate-100 px-1.5 py-0.2 rounded text-slate-700 font-bold">
                                        {p.sku}
                                      </span>
                                      {p.brand && <span>• {p.brand}</span>}
                                    </div>
                                    <div className="flex items-center gap-1.5 mt-1 flex-wrap">
                                      {p.fulfillment_method === 'FULFILLED_BY_SEVO' ? (
                                        <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-bold bg-indigo-50 text-indigo-700 border border-indigo-200" title="Fulfilled by Sevo (FBS) - Stock held at Sevo warehouse">
                                          <WarehouseIcon className="w-3 h-3 text-indigo-500" />
                                          <span>FBS</span>
                                        </span>
                                      ) : (
                                        <span className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium bg-slate-100 text-slate-600 border border-slate-200" title="Self-Ship - Seller direct fulfillment">
                                          <Truck className="w-3 h-3 text-slate-400" />
                                          <span>Self-Ship</span>
                                        </span>
                                      )}
                                      {p.barcode && (
                                        <div className="flex items-center gap-1 text-[10px] font-mono text-emerald-700 bg-emerald-50 border border-emerald-200/80 px-1.5 py-0.5 rounded" title={`Barcode: ${p.barcode}`}>
                                          <BarcodeIcon className="w-3 h-3 text-emerald-600 shrink-0" />
                                          <span>{p.barcode}</span>
                                        </div>
                                      )}
                                    </div>
                                  </div>
                                </div>
                              </td>

                              {/* Category */}
                              <td className="px-4 py-3.5">
                                <span
                                  className="inline-flex items-center gap-1 px-2.5 py-1 bg-slate-100 text-slate-700 rounded-lg text-[11px] font-medium max-w-[200px] truncate"
                                  title={p.category_path || p.category_name}
                                >
                                  <Layers className="w-3 h-3 text-slate-400 shrink-0" />
                                  <span className="truncate">{p.category_path || p.category_name || 'Leaf Category'}</span>
                                </span>
                              </td>

                              {/* Pricing */}
                              <td className="px-4 py-3.5">
                                <div className="space-y-0.5">
                                  <div className="flex items-center gap-1.5 font-bold text-slate-900">
                                    <span className="text-emerald-700 text-xs">₹{p.selling_price}</span>
                                    {discountPercent > 0 && (
                                      <span className="text-[10px] text-slate-400 line-through">
                                        ₹{p.mrp}
                                      </span>
                                    )}
                                  </div>
                                  {discountPercent > 0 && (
                                    <span className="text-[10px] font-bold text-emerald-700 bg-emerald-50 border border-emerald-200 px-1.5 py-0.2 rounded">
                                      {discountPercent}% OFF
                                    </span>
                                  )}
                                </div>
                              </td>

                              {/* Pack & Tax */}
                              <td className="px-4 py-3.5 text-slate-600">
                                <p className="text-[11px]">
                                  {p.pack_size} {p.unit}
                                </p>
                                <p className="text-[10px] text-slate-400 font-mono">
                                  GST: {p.tax_rate}% {p.hsn_code ? `• HSN: ${p.hsn_code}` : ''}
                                </p>
                              </td>

                              {/* Status & Review Notes */}
                              <td className="px-4 py-3.5">
                                <div className="space-y-1">
                                  <span
                                    className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-[10px] font-bold border ${statusConf.bg} ${statusConf.text} ${statusConf.border}`}
                                  >
                                    <StatusIcon className="w-3 h-3 shrink-0" />
                                    <span>{statusConf.label}</span>
                                  </span>

                                  {/* Review feedback alert for rejected/changes requested */}
                                  {(p.rejection_reason || p.admin_review_note) && ['REJECTED', 'CHANGES_REQUESTED'].includes(p.status) && (
                                    <div
                                      className="text-[10px] text-rose-700 bg-rose-50 border border-rose-200 p-1.5 rounded-lg max-w-xs line-clamp-2"
                                      title={p.rejection_reason || p.admin_review_note}
                                    >
                                      <span className="font-bold text-rose-900">
                                        {p.status === 'REJECTED' ? 'Rejection Reason:' : 'Changes Needed:'}
                                      </span>{' '}
                                      {p.rejection_reason || p.admin_review_note}
                                    </div>
                                  )}
                                </div>
                              </td>

                              {/* Actions */}
                              <td className="px-4 py-3.5 text-right">
                                <div className="flex items-center justify-end gap-1.5">
                                  {/* Request Storage Action (Phase X - For Approved FBS Products) */}
                                  {p.fulfillment_method === 'FULFILLED_BY_SEVO' && p.status === 'APPROVED' && (
                                    <button
                                      onClick={() => handleOpenInboundModal(p)}
                                      className="inline-flex items-center gap-1 px-2.5 py-1 text-[11px] font-bold bg-indigo-50 text-indigo-700 hover:bg-indigo-100 border border-indigo-200 rounded-lg transition-colors shadow-xs"
                                      title="Request Warehouse Storage / Intake for this FBS product"
                                    >
                                      <WarehouseIcon className="w-3.5 h-3.5 text-indigo-600" />
                                      <span>Request Storage</span>
                                    </button>
                                  )}

                                  {/* View Detail & Audit Log */}
                                  <button
                                    onClick={() => handleOpenDetailModal(p.id)}
                                    className="p-1.5 text-slate-500 hover:text-slate-800 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors"
                                    title="View Audit Timeline & Details"
                                  >
                                    <History className="w-3.5 h-3.5" />
                                  </button>

                                  {/* Edit & Resubmit Action for Rejected / Changes Requested */}
                                  {['REJECTED', 'CHANGES_REQUESTED'].includes(p.status) && (
                                    <button
                                      onClick={() => handleOpenProductModal(p)}
                                      className="inline-flex items-center gap-1 px-2.5 py-1 text-[11px] font-bold bg-amber-50 text-amber-800 hover:bg-amber-100 border border-amber-300 rounded-lg transition-colors"
                                      title="Edit details and resubmit for approval"
                                    >
                                      <RotateCcw className="w-3 h-3 text-amber-600" />
                                      <span>Edit & Resubmit</span>
                                    </button>
                                  )}

                                  {/* Submit for Review (if Draft or Paused) */}
                                  {['DRAFT', 'PAUSED'].includes(p.status) && (
                                    <button
                                      onClick={() => handleSubmitProduct(p.id)}
                                      className="inline-flex items-center gap-1 px-2.5 py-1 text-[11px] font-bold bg-blue-50 text-blue-700 hover:bg-blue-100 border border-blue-200 rounded-lg transition-colors"
                                      title="Submit product for approval"
                                    >
                                      <Send className="w-3 h-3" />
                                      <span>Submit</span>
                                    </button>
                                  )}

                                  {/* Edit Product */}
                                  <button
                                    onClick={() => handleOpenProductModal(p)}
                                    className="p-1.5 text-slate-600 hover:text-slate-900 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors"
                                    title="Edit Product Details"
                                  >
                                    <FileEdit className="w-3.5 h-3.5" />
                                  </button>

                                  {/* Admin Review Action Button */}
                                  {(isPlatformAdmin || isAdmin) && (
                                    <button
                                      onClick={() => handleOpenReviewModal(p)}
                                      className="px-2.5 py-1 text-[11px] font-bold bg-purple-50 text-purple-700 hover:bg-purple-100 border border-purple-200 rounded-lg transition-colors"
                                      title="Review Product Status"
                                    >
                                      Review
                                    </button>
                                  )}

                                  {/* Delete (if draft or rejected) */}
                                  {['DRAFT', 'REJECTED'].includes(p.status) && (
                                    <button
                                      onClick={() => handleDeleteProduct(p.id, p.title)}
                                      className="p-1.5 text-rose-500 hover:text-rose-700 bg-rose-50 hover:bg-rose-100 rounded-lg transition-colors"
                                      title="Delete Product"
                                    >
                                      <Trash2 className="w-3.5 h-3.5" />
                                    </button>
                                  )}
                                </div>
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* ════════════════════════════════════════════════════════════════════ */}
          {/* TAB 2: BULK CSV / EXCEL INGESTION                                  */}
          {/* ════════════════════════════════════════════════════════════════════ */}
          {activeTab === 'bulk_upload' && (
            <div className="space-y-6">
              {/* Instructions Banner */}
              <div className="p-6 bg-gradient-to-r from-indigo-50/80 via-white to-purple-50/60 rounded-2xl border border-indigo-100 shadow-xs flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
                <div className="flex items-start gap-4">
                  <div className="p-3 bg-indigo-600 text-white rounded-2xl shrink-0 shadow-xs">
                    <FileSpreadsheet className="w-6 h-6" />
                  </div>
                  <div>
                    <h3 className="font-bold text-slate-900 text-sm">Bulk Catalog Spreadsheet Ingestion</h3>
                    <p className="text-xs text-slate-600 mt-1 max-w-2xl leading-relaxed">
                      Download the standardized template, fill in your product catalog items with their leaf category slugs, pricing, and image URLs, then upload below. Use the preview validator to test for SKU conflicts or missing leaf categories before importing.
                    </p>
                  </div>
                </div>

                <button
                  onClick={handleDownloadTemplate}
                  className="inline-flex items-center gap-2 px-4 py-2.5 bg-white border border-indigo-200 text-indigo-700 hover:bg-indigo-50 font-bold text-xs rounded-xl shadow-xs shrink-0 transition-colors"
                >
                  <Download className="w-4 h-4" />
                  <span>Download CSV Template</span>
                </button>
              </div>

              {/* Upload Dropzone */}
              <div className="p-8 bg-white rounded-2xl border-2 border-dashed border-slate-200 hover:border-indigo-400 transition-colors text-center flex flex-col items-center justify-center">
                <input
                  type="file"
                  ref={fileInputRef}
                  onChange={handleSelectBulkFile}
                  accept=".csv, .xlsx, .xls"
                  className="hidden"
                />

                <div className="w-16 h-16 bg-indigo-50 rounded-2xl flex items-center justify-center text-indigo-600 mb-3 shadow-xs">
                  <UploadCloud className="w-8 h-8" />
                </div>

                {uploadFile ? (
                  <div className="space-y-2">
                    <p className="text-xs font-bold text-slate-900 flex items-center justify-center gap-1.5">
                      <FileSpreadsheet className="w-4 h-4 text-emerald-600" />
                      <span>{uploadFile.name}</span>
                      <span className="text-slate-400 font-normal">({Math.round(uploadFile.size / 1024)} KB)</span>
                    </p>
                    <div className="flex items-center justify-center gap-2 mt-4">
                      <button
                        onClick={handleValidatePreview}
                        disabled={previewLoading}
                        className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold shadow-xs transition-colors"
                      >
                        {previewLoading ? 'Validating File...' : 'Validate & Preview'}
                      </button>
                      <button
                        onClick={() => { setUploadFile(null); setPreviewResult(null); }}
                        className="px-3 py-2 bg-slate-100 hover:bg-slate-200 text-slate-600 rounded-xl text-xs font-bold"
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                ) : (
                  <div>
                    <p className="text-xs font-bold text-slate-800">
                      Drag and drop your completed catalog file here, or{' '}
                      <button
                        onClick={() => fileInputRef.current?.click()}
                        className="text-indigo-600 hover:underline"
                      >
                        browse from computer
                      </button>
                    </p>
                    <p className="text-[11px] text-slate-400 mt-1">Supports CSV, XLSX up to 500 rows per batch</p>
                  </div>
                )}
              </div>

              {/* Validation Preview Result Container */}
              {previewResult && (
                <div className="p-6 bg-white rounded-2xl border border-slate-200 shadow-xs space-y-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <h4 className="font-bold text-slate-900 text-sm">Batch Validation Results</h4>
                      <p className="text-xs text-slate-500 mt-0.5">
                        Total Rows: <span className="font-bold font-mono text-slate-800">{previewResult.total_rows}</span> • Valid:{' '}
                        <span className="font-bold font-mono text-emerald-700">{previewResult.valid_rows_count}</span> • Errors:{' '}
                        <span className="font-bold font-mono text-rose-700">{previewResult.invalid_rows_count}</span>
                      </p>
                    </div>

                    <button
                      onClick={handleConfirmBulkImport}
                      disabled={!previewResult.can_import || importLoading}
                      className={`px-5 py-2.5 rounded-xl text-xs font-bold flex items-center gap-2 shadow-xs transition-colors ${
                        previewResult.can_import
                          ? 'bg-emerald-600 hover:bg-emerald-700 text-white'
                          : 'bg-slate-200 text-slate-400 cursor-not-allowed'
                      }`}
                    >
                      <CheckCircle2 className="w-4 h-4" />
                      <span>{importLoading ? 'Importing Products...' : 'Confirm & Import Valid Rows'}</span>
                    </button>
                  </div>

                  {/* Errors Breakdown Alert */}
                  {previewResult.errors?.length > 0 && (
                    <div className="p-4 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-900 space-y-2">
                      <div className="font-bold flex items-center gap-1.5 text-rose-800">
                        <AlertCircle className="w-4 h-4" />
                        <span>Validation Errors Detected ({previewResult.errors.length} rows)</span>
                      </div>
                      <div className="max-h-40 overflow-y-auto space-y-1 text-[11px] divide-y divide-rose-100">
                        {previewResult.errors.map((err, i) => (
                          <div key={i} className="pt-1">
                            <span className="font-bold">Row {err.row} ({err.sku}):</span> {err.errors.join(', ')}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Preview Items Table */}
                  <div className="border border-slate-200 rounded-xl overflow-x-auto">
                    <table className="w-full text-left text-xs">
                      <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold text-[10px] uppercase">
                        <tr>
                          <th className="px-3 py-2">Row</th>
                          <th className="px-3 py-2">Title</th>
                          <th className="px-3 py-2">SKU</th>
                          <th className="px-3 py-2">Category</th>
                          <th className="px-3 py-2">MRP / Price</th>
                          <th className="px-3 py-2">Status</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium">
                        {previewResult.items?.map((item, idx) => (
                          <tr key={idx} className={item.has_errors ? 'bg-rose-50/40' : ''}>
                            <td className="px-3 py-2 text-slate-400 font-mono text-[10px]">{item.row_number}</td>
                            <td className="px-3 py-2 font-bold text-slate-900">{item.title}</td>
                            <td className="px-3 py-2 font-mono text-[11px] text-slate-600">{item.sku}</td>
                            <td className="px-3 py-2 text-slate-600">{item.category_name}</td>
                            <td className="px-3 py-2 font-mono">
                              ₹{item.selling_price} / <span className="text-slate-400">₹{item.mrp}</span>
                            </td>
                            <td className="px-3 py-2">
                              {item.has_errors ? (
                                <span className="text-[10px] font-bold text-rose-700 bg-rose-50 border border-rose-200 px-2 py-0.5 rounded-full">
                                  Error
                                </span>
                              ) : (
                                <span className="text-[10px] font-bold text-emerald-700 bg-emerald-50 border border-emerald-200 px-2 py-0.5 rounded-full">
                                  Valid
                                </span>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* ════════════════════════════════════════════════════════════════════ */}
          {/* TAB 3: UPLOAD BATCHES HISTORY                                      */}
          {/* ════════════════════════════════════════════════════════════════════ */}
          {activeTab === 'batches' && (
            <div className="bg-white rounded-2xl border border-slate-200 shadow-xs overflow-hidden">
              <div className="p-4 border-b border-slate-100 flex items-center justify-between">
                <h3 className="font-bold text-slate-900 text-xs uppercase tracking-wider">
                  Bulk Catalog Feed History
                </h3>
              </div>

              {batches.length === 0 ? (
                <div className="p-12 text-center text-slate-400 flex flex-col items-center justify-center">
                  <FileSpreadsheet className="w-8 h-8 text-slate-300 mb-2" />
                  <p className="text-xs font-bold text-slate-700">No batch history recorded yet</p>
                  <p className="text-[11px] text-slate-400 mt-0.5">Uploaded CSV and Excel batches will appear here.</p>
                </div>
              ) : (
                <table className="w-full text-left text-xs">
                  <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold text-[10px] uppercase">
                    <tr>
                      <th className="px-4 py-3">Batch ID & File</th>
                      <th className="px-4 py-3">Uploaded By</th>
                      <th className="px-4 py-3">Total Rows</th>
                      <th className="px-4 py-3">Imported</th>
                      <th className="px-4 py-3">Status</th>
                      <th className="px-4 py-3">Date</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100 font-medium">
                    {batches.map((b) => (
                      <tr key={b.id} className="hover:bg-slate-50/80">
                        <td className="px-4 py-3 font-bold text-slate-900">
                          #{b.id} • {b.file_name}
                        </td>
                        <td className="px-4 py-3 text-slate-600">{b.uploaded_by_name}</td>
                        <td className="px-4 py-3 font-mono">{b.total_rows}</td>
                        <td className="px-4 py-3 font-mono text-emerald-700 font-bold">{b.imported_rows}</td>
                        <td className="px-4 py-3">
                          <span
                            className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${
                              b.status === 'COMPLETED'
                                ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                                : b.status === 'FAILED'
                                ? 'bg-rose-50 text-rose-700 border-rose-200'
                                : 'bg-amber-50 text-amber-700 border-amber-200'
                            }`}
                          >
                            {b.status}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-slate-400 font-mono text-[11px]">
                          {new Date(b.created_at).toLocaleDateString()}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          )}

          {/* ════════════════════════════════════════════════════════════════════ */}
          {/* TAB 4: WAREHOUSE STORAGE REQUESTS (PHASE X)                         */}
          {/* ════════════════════════════════════════════════════════════════════ */}
          {activeTab === 'inbound_requests' && (
            <div className="space-y-4">
              <div className="p-4 bg-indigo-50/70 border border-indigo-100 rounded-xl flex items-start gap-3">
                <Boxes className="w-5 h-5 text-indigo-700 shrink-0 mt-0.5" />
                <div className="text-xs text-indigo-900 space-y-0.5">
                  <span className="font-bold">Fulfilled by Sevo (FBS) Stock Inbound Requests</span>
                  <p className="text-indigo-700">
                    Track the status of replenishment storage requests sent to your assigned fulfillment warehouse.
                    Once approved by warehouse staff, units are marked awaiting physical delivery receipt.
                  </p>
                </div>
              </div>

              {/* Status Filter Chips */}
              <div className="flex items-center gap-2">
                {['ALL', 'PENDING', 'ACCEPTED', 'SHORT_RECEIVED', 'COMPLETED', 'REJECTED'].map((st) => (
                  <button
                    key={st}
                    onClick={() => setInboundTabStatusFilter(st)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-bold transition-all border ${
                      inboundTabStatusFilter === st
                        ? 'bg-indigo-900 text-white border-indigo-900 shadow-xs'
                        : 'bg-white text-slate-600 border-slate-200 hover:bg-slate-50'
                    }`}
                  >
                    {st === 'ALL'
                      ? 'All Requests'
                      : st === 'PENDING'
                      ? 'Pending Review'
                      : st === 'ACCEPTED'
                      ? 'In Verification / Receiving'
                      : st === 'SHORT_RECEIVED'
                      ? 'Shortfall Reported'
                      : st === 'COMPLETED'
                      ? 'Completed / Live'
                      : 'Rejected'}
                    {' '}
                    ({st === 'ALL'
                      ? allInboundRequests.length
                      : st === 'REJECTED'
                      ? allInboundRequests.filter((r) => r.status === 'REJECTED' || r.status === 'REJECTED_RETURN').length
                      : allInboundRequests.filter((r) => r.status === st).length})
                  </button>
                ))}
              </div>

              {allInboundRequests.length === 0 ? (
                <div className="p-12 text-center bg-white rounded-2xl border border-slate-200 space-y-2">
                  <Boxes className="w-8 h-8 text-slate-400 mx-auto" />
                  <p className="text-sm font-bold text-slate-800">No Warehouse Storage Requests</p>
                  <p className="text-xs text-slate-500 max-w-md mx-auto">
                    To request storage at Sevo's warehouse, make sure your product has fulfillment method set to "Fulfilled by Sevo (FBS)" and click "Request Storage" on the Product Catalog tab.
                  </p>
                </div>
              ) : (
                <div className="bg-white rounded-2xl border border-slate-200 overflow-hidden shadow-xs">
                  <div className="overflow-x-auto">
                    <table className="w-full text-left text-xs">
                      <thead className="bg-slate-50 border-b border-slate-200 text-slate-500 font-semibold text-[10px] uppercase">
                        <tr>
                          <th className="px-4 py-3">Req ID / Date</th>
                          <th className="px-4 py-3">Product</th>
                          <th className="px-4 py-3">Assigned Warehouse</th>
                          <th className="px-4 py-3 text-center">Requested Units</th>
                          <th className="px-4 py-3">Intake & Scan Progress</th>
                          <th className="px-4 py-3">Notes & Actions</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-100 font-medium">
                        {allInboundRequests
                          .filter((r) => {
                            if (inboundTabStatusFilter === 'ALL') return true;
                            if (inboundTabStatusFilter === 'REJECTED') return r.status === 'REJECTED' || r.status === 'REJECTED_RETURN';
                            return r.status === inboundTabStatusFilter;
                          })
                          .map((req) => {
                            const total = req.total_units_count || req.requested_quantity;
                            const received = req.received_units_count || 0;
                            const confirmed = req.confirmed_quantity != null ? req.confirmed_quantity : received;
                            const percent = total > 0 ? Math.round((received / total) * 100) : 0;
                            const isShortfall = req.status === 'SHORT_RECEIVED';

                            return (
                              <tr key={req.id} className={`hover:bg-slate-50/60 transition ${isShortfall ? 'bg-amber-50/30' : ''}`}>
                                <td className="px-4 py-3 text-slate-500 font-mono text-[11px]">
                                  <div className="font-bold text-slate-900">#{req.id}</div>
                                  <div className="text-[10px] text-slate-400 mt-0.5">
                                    {new Date(req.created_at).toLocaleDateString()} {new Date(req.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                                  </div>
                                </td>
                                <td className="px-4 py-3">
                                  <div className="font-bold text-slate-900">{req.product_title}</div>
                                  <div className="text-[10px] font-mono text-slate-500">SKU: {req.product_sku}</div>
                                </td>
                                <td className="px-4 py-3 text-slate-700">
                                  <div className="font-semibold">{req.warehouse_name}</div>
                                  <div className="text-[10px] text-slate-400">{req.warehouse_city}</div>
                                </td>
                                <td className="px-4 py-3 text-center">
                                  <span className="inline-block px-2.5 py-1 rounded-md bg-indigo-50 text-indigo-800 font-black font-mono text-xs">
                                    {req.requested_quantity}
                                  </span>
                                </td>
                                <td className="px-4 py-3">
                                  {req.status === 'PENDING' && (
                                    <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold border bg-amber-50 text-amber-700 border-amber-200">
                                      <Clock className="w-3 h-3" />
                                      <span>Pending Review</span>
                                    </span>
                                  )}
                                  {req.status === 'ACCEPTED' && (
                                    <div className="space-y-1.5">
                                      <div className="flex items-center justify-between gap-2">
                                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold border bg-blue-50 text-blue-700 border-blue-200">
                                          <RefreshCw className="w-2.5 h-2.5 animate-spin" />
                                          <span>Receiving Units</span>
                                        </span>
                                        <button
                                          type="button"
                                          onClick={() => handleOpenLabelsModal(req)}
                                          title="Print unit barcode labels"
                                          className="inline-flex items-center gap-1 px-2 py-0.5 bg-white hover:bg-indigo-50 text-slate-700 hover:text-indigo-600 border border-slate-200 hover:border-indigo-300 rounded-md text-[10px] font-bold transition"
                                        >
                                          <Printer className="w-3 h-3 text-indigo-600" />
                                          <span>Labels</span>
                                        </button>
                                      </div>
                                      <div className="flex items-center justify-between gap-2">
                                        <div className="w-32 bg-slate-100 rounded-full h-1.5 overflow-hidden">
                                          <div
                                            className="bg-blue-600 h-1.5 rounded-full transition-all duration-300"
                                            style={{ width: `${percent}%` }}
                                          />
                                        </div>
                                        <span className="text-[10px] font-mono font-bold text-slate-700">
                                          {received} of {total} ({percent}%)
                                        </span>
                                      </div>
                                    </div>
                                  )}
                                  {req.status === 'SHORT_RECEIVED' && (
                                    <div className="space-y-1.5">
                                      <div className="flex items-center justify-between gap-2">
                                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold border bg-amber-50 text-amber-800 border-amber-300">
                                          <AlertTriangle className="w-3 h-3 text-amber-600" />
                                          <span>Shortfall ({confirmed}/{total})</span>
                                        </span>
                                        <button
                                          type="button"
                                          onClick={() => handleOpenLabelsModal(req)}
                                          title="Print unit barcode labels"
                                          className="inline-flex items-center gap-1 px-2 py-0.5 bg-white hover:bg-indigo-50 text-slate-700 hover:text-indigo-600 border border-slate-200 hover:border-indigo-300 rounded-md text-[10px] font-bold transition"
                                        >
                                          <Printer className="w-3 h-3 text-indigo-600" />
                                          <span>Labels</span>
                                        </button>
                                      </div>
                                      <div className="text-[10px] font-semibold text-rose-600 pl-1">
                                        {total - confirmed} units missing from shipment
                                      </div>
                                    </div>
                                  )}
                                  {req.status === 'COMPLETED' && (
                                    <div className="space-y-1">
                                      <div className="flex items-center justify-between gap-2">
                                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold border bg-emerald-50 text-emerald-700 border-emerald-200">
                                          <CheckCircle2 className="w-3 h-3 text-emerald-600" />
                                          <span>Live in Stock</span>
                                        </span>
                                        <button
                                          type="button"
                                          onClick={() => handleOpenLabelsModal(req)}
                                          title="Print unit barcode labels"
                                          className="inline-flex items-center gap-1 px-2 py-0.5 bg-white hover:bg-indigo-50 text-slate-700 hover:text-indigo-600 border border-slate-200 hover:border-indigo-300 rounded-md text-[10px] font-bold transition"
                                        >
                                          <Printer className="w-3 h-3 text-indigo-600" />
                                          <span>Labels</span>
                                        </button>
                                      </div>
                                      <div className="text-[10px] text-emerald-700 font-bold pl-1 font-mono">
                                        {req.confirmed_quantity != null && req.confirmed_quantity < req.requested_quantity
                                          ? `${req.confirmed_quantity} of ${req.requested_quantity} units verified (Partial)`
                                          : `${total} / ${total} units verified`}
                                      </div>
                                    </div>
                                  )}
                                  {req.status === 'REJECTED_RETURN' && (
                                    <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold border bg-rose-50 text-rose-700 border-rose-200">
                                      <XCircle className="w-3 h-3" />
                                      <span>Shortfall Rejected (Return Staged)</span>
                                    </span>
                                  )}
                                  {req.status === 'REJECTED' && (
                                    <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold border bg-rose-50 text-rose-700 border-rose-200">
                                      <XCircle className="w-3 h-3" />
                                      <span>Rejected</span>
                                    </span>
                                  )}
                                </td>
                                <td className="px-4 py-3 text-xs max-w-xs space-y-2">
                                  {req.seller_note && (
                                    <div className="text-[11px] text-slate-600">
                                      <span className="font-semibold text-slate-400">Your Note:</span> "{req.seller_note}"
                                    </div>
                                  )}
                                  {req.shortfall_note && (
                                    <div className="text-[11px] p-2 bg-amber-50 border border-amber-200 rounded-lg text-amber-900 space-y-1">
                                      <span className="font-bold block text-[10px] text-amber-800 uppercase tracking-wider flex items-center gap-1">
                                        <AlertTriangle className="w-3 h-3 text-amber-600" />
                                        Warehouse Shortfall Notice:
                                      </span>
                                      <p className="text-[11px]">"{req.shortfall_note}"</p>
                                    </div>
                                  )}
                                  {req.reviewer_note && !req.shortfall_note && (
                                    <div className={`text-[11px] p-1.5 rounded border ${
                                      req.status === 'COMPLETED' || req.status === 'ACCEPTED'
                                        ? 'bg-emerald-50 text-emerald-800 border-emerald-200'
                                        : 'bg-rose-50 text-rose-800 border-rose-200'
                                    }`}>
                                      <span className="font-bold block text-[10px] uppercase tracking-wider">
                                        {req.status === 'REJECTED' ? 'Rejection Reason:' : 'Warehouse Note:'}
                                      </span>
                                      "{req.reviewer_note}"
                                    </div>
                                  )}

                                  {/* Shortfall Decision Action Buttons */}
                                  {req.status === 'SHORT_RECEIVED' && (
                                    <div className="flex items-center gap-2 pt-1">
                                      <button
                                        onClick={() => handleOpenShortfallDecisionModal(req, 'ACCEPT')}
                                        className="px-2.5 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg text-xs font-bold transition flex items-center gap-1 shadow-xs"
                                      >
                                        <Check className="w-3.5 h-3.5" />
                                        <span>Accept Partial ({confirmed} Units)</span>
                                      </button>
                                      <button
                                        onClick={() => handleOpenShortfallDecisionModal(req, 'REJECT')}
                                        className="px-2.5 py-1.5 bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200 rounded-lg text-xs font-bold transition flex items-center gap-1"
                                      >
                                        <X className="w-3.5 h-3.5" />
                                        <span>Reject Batch</span>
                                      </button>
                                    </div>
                                  )}
                                </td>
                              </tr>
                            );
                          })}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>

        {/* ════════════════════════════════════════════════════════════════════ */}
        {/* MODAL 1: ADD / EDIT SINGLE PRODUCT (MEESHO 2-STEP WORKFLOW)         */}
        {/* ════════════════════════════════════════════════════════════════════ */}
        {showProductModal && (
          <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto">
            <div
              className={`bg-white rounded-2xl border border-slate-200 shadow-2xl w-full my-8 overflow-hidden animate-in fade-in zoom-in-95 duration-150 ${
                productModalStep === 1 ? 'max-w-4xl' : 'max-w-2xl'
              }`}
            >
              {/* Modal Header */}
              <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50/50">
                <div className="flex items-center gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-emerald-100 text-emerald-800 flex items-center justify-center font-bold">
                    {productModalStep === 1 ? <Layers className="w-4 h-4" /> : <Tag className="w-4 h-4" />}
                  </div>
                  <div>
                    <h3 className="font-bold text-slate-900 text-sm">
                      {editingProduct
                        ? `Edit Product: ${editingProduct.title}`
                        : productModalStep === 1
                        ? 'Select Product Category (Step 1 of 2)'
                        : 'Add Product Details (Step 2 of 2)'}
                    </h3>
                    <p className="text-[11px] text-slate-500">
                      {productModalStep === 1
                        ? 'Browse cascading department columns or search to pick the exact leaf category'
                        : 'Fill in pricing, packaging specs, and grocery inventory specifications'}
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => handleCloseProductModal()}
                  className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-100"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* ───────────────────────────────────────────────────────────── */}
              {/* STEP 1: MEESHO-STYLE CASCADING CATEGORY PICKER                */}
              {/* ───────────────────────────────────────────────────────────── */}
              {productModalStep === 1 ? (
                <div className="p-6 space-y-4">
                  {/* Top Search Category Input with Refresh Button */}
                  <div className="flex items-center gap-2">
                    <div className="relative flex-1">
                      <div className="relative flex items-center">
                        <Search className="w-4 h-4 text-slate-400 absolute left-3.5 pointer-events-none" />
                        <input
                          type="text"
                          placeholder="Search Category (Try Milk, Rice, Oil, Vegetables, Biscuits and more...)"
                          value={pickerSearch}
                          onChange={(e) => handlePickerSearchChange(e.target.value)}
                          className="w-full pl-10 pr-10 py-2.5 bg-slate-50 hover:bg-slate-100/80 focus:bg-white border border-slate-200 focus:border-emerald-500 rounded-xl text-xs text-slate-800 transition-colors shadow-2xs"
                        />
                        {pickerSearch && (
                          <button
                            type="button"
                            onClick={() => {
                              setPickerSearch('');
                              setPickerSearchResults([]);
                            }}
                            className="absolute right-3 text-slate-400 hover:text-slate-600"
                          >
                            <X className="w-4 h-4" />
                          </button>
                        )}
                      </div>

                      {/* Search Results Dropdown Overlay */}
                      {pickerSearch.trim().length >= 2 && (
                        <div className="absolute top-full left-0 right-0 mt-1.5 bg-white rounded-xl border border-slate-200 shadow-xl z-20 max-h-64 overflow-y-auto">
                          {pickerSearchLoading ? (
                            <div className="p-4 text-center text-slate-400 text-xs flex items-center justify-center gap-2">
                              <RefreshCw className="w-3.5 h-3.5 animate-spin text-emerald-600" />
                              <span>Searching categories across catalog hierarchy...</span>
                            </div>
                          ) : pickerSearchResults.length === 0 ? (
                            <div className="p-4 text-center text-slate-500 text-xs">
                              <p className="font-semibold">No categories match "{pickerSearch}"</p>
                              <p className="text-[11px] text-slate-400 mt-0.5">
                                Try another keyword or browse the cascading columns below.
                              </p>
                            </div>
                          ) : (
                            <div className="divide-y divide-slate-100">
                              {pickerSearchResults.map((cat) => (
                                <div
                                  key={cat.id}
                                  onClick={() => cat.is_leaf && handleSearchResultClick(cat)}
                                  className={`p-3 flex items-center justify-between text-xs transition-colors ${
                                    cat.is_leaf
                                      ? 'hover:bg-emerald-50/80 cursor-pointer'
                                      : 'opacity-60 bg-slate-50/50 cursor-not-allowed'
                                  }`}
                                >
                                  <div className="min-w-0 flex-1 pr-3">
                                    <div className="flex items-center gap-2">
                                      <span className="font-bold text-slate-900">{cat.name}</span>
                                      {cat.is_leaf ? (
                                        <span className="text-[10px] font-bold text-emerald-700 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
                                          Leaf Category
                                        </span>
                                      ) : (
                                        <span className="text-[10px] text-slate-500 bg-slate-100 px-2 py-0.5 rounded-full">
                                          Subcategory
                                        </span>
                                      )}
                                    </div>
                                    <p className="text-[11px] text-slate-500 font-mono mt-0.5 truncate">
                                      {cat.path_string || cat.name}
                                    </p>
                                  </div>
                                  {cat.is_leaf ? (
                                    <button
                                      type="button"
                                      className="px-2.5 py-1 text-[11px] font-bold text-emerald-700 bg-emerald-100/80 hover:bg-emerald-200 rounded-lg shrink-0 transition-colors"
                                    >
                                      Select Leaf
                                    </button>
                                  ) : (
                                    <span className="text-[11px] text-slate-400 shrink-0">Has Subcategories</span>
                                  )}
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      )}
                    </div>

                    <button
                      type="button"
                      onClick={handleRefreshPicker}
                      disabled={pickerColumnLoading[0]}
                      className="inline-flex items-center gap-1.5 px-3 py-2.5 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-xl text-xs font-semibold shrink-0 transition-colors shadow-2xs disabled:opacity-50"
                      title="Refresh all catalog categories from server"
                    >
                      <RefreshCw className={`w-3.5 h-3.5 ${pickerColumnLoading[0] ? 'animate-spin text-emerald-600' : 'text-slate-500'}`} />
                      <span>Refresh</span>
                    </button>
                  </div>

                  {/* Cascading Independent Scroll Columns */}
                  <div className="bg-slate-50 rounded-2xl border border-slate-200 p-3">
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                      {/* Column 1: Root Departments */}
                      <div className="bg-white rounded-xl border border-slate-200 flex flex-col h-72 shadow-2xs overflow-hidden">
                        <div className="px-3.5 py-2 bg-slate-100/80 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider text-slate-600 flex items-center justify-between">
                          <span>1. Department</span>
                          {pickerColumnLoading[0] && <RefreshCw className="w-3 h-3 animate-spin text-emerald-600" />}
                        </div>
                        <div className="p-1.5 flex-1 overflow-y-auto divide-y divide-slate-50 text-xs">
                          {pickerColumnLoading[0] ? (
                            <div className="h-full flex flex-col items-center justify-center text-slate-400 text-center p-4 gap-2">
                              <RefreshCw className="w-5 h-5 animate-spin text-emerald-600" />
                              <p className="text-[11px]">Loading categories...</p>
                            </div>
                          ) : pickerErrors[0] ? (
                            <div className="h-full flex flex-col items-center justify-center text-rose-600 text-center p-4 gap-2">
                              <AlertCircle className="w-5 h-5 text-rose-500" />
                              <p className="text-[11px] font-medium">{pickerErrors[0]}</p>
                              <button
                                type="button"
                                onClick={handleRefreshPicker}
                                className="inline-flex items-center gap-1 px-2.5 py-1 bg-rose-50 hover:bg-rose-100 text-rose-700 rounded-lg text-[11px] font-semibold border border-rose-200"
                              >
                                <RefreshCw className="w-3 h-3" />
                                <span>Refresh categories</span>
                              </button>
                            </div>
                          ) : !pickerColumns[0] || pickerColumns[0].length === 0 ? (
                            <div className="h-full flex flex-col items-center justify-center text-slate-400 text-center p-4 gap-2">
                              <Layers className="w-6 h-6 text-slate-300" />
                              <p className="text-[11px]">No active categories found.</p>
                              <button
                                type="button"
                                onClick={handleRefreshPicker}
                                className="inline-flex items-center gap-1 px-2.5 py-1 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-lg text-[11px] font-semibold border border-slate-200"
                              >
                                <RefreshCw className="w-3 h-3" />
                                <span>Refresh categories</span>
                              </button>
                            </div>
                          ) : (
                            pickerColumns[0].map((cat) => {
                              const isSelected = pickerSelectedPath[0]?.id === cat.id;
                              return (
                                <button
                                  key={cat.id}
                                  type="button"
                                  onClick={() => handleColumnItemClick(cat, 0)}
                                  className={`w-full text-left px-3 py-2 rounded-lg flex items-center justify-between transition-all ${
                                    isSelected
                                      ? 'bg-emerald-50 text-emerald-950 font-bold border-l-4 border-emerald-600 shadow-2xs'
                                      : 'text-slate-700 hover:bg-slate-100/80 font-medium'
                                  }`}
                                >
                                  <span className="truncate pr-2">{cat.name}</span>
                                  {cat.has_children ? (
                                    <ChevronRight className={`w-3.5 h-3.5 shrink-0 ${isSelected ? 'text-emerald-700' : 'text-slate-400'}`} />
                                  ) : (
                                    <span className="w-2 h-2 rounded-full bg-emerald-500 shrink-0" title="Leaf category" />
                                  )}
                                </button>
                              );
                            })
                          )}
                        </div>
                      </div>

                      {/* Column 2: Subcategories */}
                      <div className="bg-white rounded-xl border border-slate-200 flex flex-col h-72 shadow-2xs overflow-hidden">
                        <div className="px-3.5 py-2 bg-slate-100/80 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider text-slate-600 flex items-center justify-between">
                          <span>2. Subcategory</span>
                          {pickerColumnLoading[1] && <RefreshCw className="w-3 h-3 animate-spin text-emerald-600" />}
                        </div>
                        <div className="p-1.5 flex-1 overflow-y-auto divide-y divide-slate-50 text-xs">
                          {pickerColumnLoading[1] ? (
                            <div className="h-full flex flex-col items-center justify-center text-slate-400 text-center p-4 gap-2">
                              <RefreshCw className="w-5 h-5 animate-spin text-emerald-600" />
                              <p className="text-[11px]">Loading subcategories...</p>
                            </div>
                          ) : pickerErrors[1] ? (
                            <div className="h-full flex flex-col items-center justify-center text-rose-600 text-center p-4 gap-2">
                              <AlertCircle className="w-5 h-5 text-rose-500" />
                              <p className="text-[11px] font-medium">{pickerErrors[1]}</p>
                              {pickerSelectedPath[0] && (
                                <button
                                  type="button"
                                  onClick={() => loadPickerColumn(pickerSelectedPath[0].id, 1, true)}
                                  className="inline-flex items-center gap-1 px-2.5 py-1 bg-rose-50 hover:bg-rose-100 text-rose-700 rounded-lg text-[11px] font-semibold border border-rose-200"
                                >
                                  <RefreshCw className="w-3 h-3" />
                                  <span>Refresh categories</span>
                                </button>
                              )}
                            </div>
                          ) : !pickerSelectedPath[0] ? (
                            <div className="h-full flex flex-col items-center justify-center text-slate-400 text-center p-4">
                              <p className="text-[11px]">Select a department on the left to view subcategories.</p>
                            </div>
                          ) : !pickerColumns[1] || pickerColumns[1].length === 0 ? (
                            <div className="h-full flex flex-col items-center justify-center text-slate-400 text-center p-4 gap-2">
                              <Layers className="w-6 h-6 text-slate-300" />
                              <p className="text-[11px]">No sub-categories</p>
                              <button
                                type="button"
                                onClick={() => loadPickerColumn(pickerSelectedPath[0].id, 1, true)}
                                className="inline-flex items-center gap-1 px-2.5 py-1 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-lg text-[11px] font-semibold border border-slate-200"
                              >
                                <RefreshCw className="w-3 h-3" />
                                <span>Refresh categories</span>
                              </button>
                            </div>
                          ) : (
                            pickerColumns[1].map((cat) => {
                              const isSelected = pickerSelectedPath[1]?.id === cat.id;
                              return (
                                <button
                                  key={cat.id}
                                  type="button"
                                  onClick={() => handleColumnItemClick(cat, 1)}
                                  className={`w-full text-left px-3 py-2 rounded-lg flex items-center justify-between transition-all ${
                                    isSelected
                                      ? 'bg-emerald-50 text-emerald-950 font-bold border-l-4 border-emerald-600 shadow-2xs'
                                      : 'text-slate-700 hover:bg-slate-100/80 font-medium'
                                  }`}
                                >
                                  <span className="truncate pr-2">{cat.name}</span>
                                  {cat.has_children ? (
                                    <ChevronRight className={`w-3.5 h-3.5 shrink-0 ${isSelected ? 'text-emerald-700' : 'text-slate-400'}`} />
                                  ) : (
                                    <span className="w-2 h-2 rounded-full bg-emerald-500 shrink-0" title="Leaf category" />
                                  )}
                                </button>
                              );
                            })
                          )}
                        </div>
                      </div>

                      {/* Column 3: Product Types / Specific Leaves */}
                      <div className="bg-white rounded-xl border border-slate-200 flex flex-col h-72 shadow-2xs overflow-hidden">
                        <div className="px-3.5 py-2 bg-slate-100/80 border-b border-slate-200 text-[11px] font-bold uppercase tracking-wider text-slate-600 flex items-center justify-between">
                          <span>3. Product Type (Leaf)</span>
                          {pickerColumnLoading[2] && <RefreshCw className="w-3 h-3 animate-spin text-emerald-600" />}
                        </div>
                        <div className="p-1.5 flex-1 overflow-y-auto divide-y divide-slate-50 text-xs">
                          {pickerColumnLoading[2] ? (
                            <div className="h-full flex flex-col items-center justify-center text-slate-400 text-center p-4 gap-2">
                              <RefreshCw className="w-5 h-5 animate-spin text-emerald-600" />
                              <p className="text-[11px]">Loading product types...</p>
                            </div>
                          ) : pickerErrors[2] ? (
                            <div className="h-full flex flex-col items-center justify-center text-rose-600 text-center p-4 gap-2">
                              <AlertCircle className="w-5 h-5 text-rose-500" />
                              <p className="text-[11px] font-medium">{pickerErrors[2]}</p>
                              {pickerSelectedPath[1] && (
                                <button
                                  type="button"
                                  onClick={() => loadPickerColumn(pickerSelectedPath[1].id, 2, true)}
                                  className="inline-flex items-center gap-1 px-2.5 py-1 bg-rose-50 hover:bg-rose-100 text-rose-700 rounded-lg text-[11px] font-semibold border border-rose-200"
                                >
                                  <RefreshCw className="w-3 h-3" />
                                  <span>Refresh categories</span>
                                </button>
                              )}
                            </div>
                          ) : !pickerSelectedPath[1] ? (
                            <div className="h-full flex flex-col items-center justify-center text-slate-400 text-center p-4">
                              <p className="text-[11px]">
                                {pickerSelectedLeaf
                                  ? 'Leaf category confirmed in previous column.'
                                  : 'Select a subcategory on the left to view product types.'}
                              </p>
                            </div>
                          ) : !pickerColumns[2] || pickerColumns[2].length === 0 ? (
                            <div className="h-full flex flex-col items-center justify-center text-slate-400 text-center p-4 gap-2">
                              <Layers className="w-6 h-6 text-slate-300" />
                              <p className="text-[11px]">No sub-categories</p>
                              <button
                                type="button"
                                onClick={() => loadPickerColumn(pickerSelectedPath[1].id, 2, true)}
                                className="inline-flex items-center gap-1 px-2.5 py-1 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-lg text-[11px] font-semibold border border-slate-200"
                              >
                                <RefreshCw className="w-3 h-3" />
                                <span>Refresh categories</span>
                              </button>
                            </div>
                          ) : (
                            pickerColumns[2].map((cat) => {
                              const isSelected = pickerSelectedPath[2]?.id === cat.id;
                              return (
                                <button
                                  key={cat.id}
                                  type="button"
                                  onClick={() => handleColumnItemClick(cat, 2)}
                                  className={`w-full text-left px-3 py-2 rounded-lg flex items-center justify-between transition-all ${
                                    isSelected
                                      ? 'bg-emerald-50 text-emerald-950 font-bold border-l-4 border-emerald-600 shadow-2xs'
                                      : 'text-slate-700 hover:bg-slate-100/80 font-medium'
                                  }`}
                                >
                                  <span className="truncate pr-2">{cat.name}</span>
                                  {cat.has_children ? (
                                    <ChevronRight className={`w-3.5 h-3.5 shrink-0 ${isSelected ? 'text-emerald-700' : 'text-slate-400'}`} />
                                  ) : (
                                    <span className="w-2 h-2 rounded-full bg-emerald-500 shrink-0" title="Leaf category" />
                                  )}
                                </button>
                              );
                            })
                          )}
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Selected Breadcrumb Preview Panel */}
                  <div
                    className={`p-4 rounded-xl border transition-all ${
                      pickerSelectedLeaf
                        ? 'bg-emerald-50/80 border-emerald-200 text-emerald-950 shadow-2xs'
                        : 'bg-slate-50 border-slate-200 text-slate-600'
                    }`}
                  >
                    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                      <div>
                        <div className="flex items-center gap-2">
                          <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400">
                            Current Classification
                          </span>
                          {pickerSelectedLeaf ? (
                            <span className="text-[10px] font-bold text-emerald-800 bg-emerald-100 px-2 py-0.5 rounded-full border border-emerald-300">
                              ✓ Final Leaf Category Selected
                            </span>
                          ) : (
                            <span className="text-[10px] font-medium text-amber-700 bg-amber-50 px-2 py-0.5 rounded-full border border-amber-200">
                              Choose a final (leaf) category
                            </span>
                          )}
                        </div>
                        <p className="font-bold text-sm text-slate-900 mt-1">
                          {pickerSelectedLeaf
                            ? pickerSelectedLeaf.path_string || pickerSelectedLeaf.name
                            : pickerSelectedPath.length > 0
                            ? pickerSelectedPath.map((p) => p.name).join(' › ')
                            : 'No category chosen yet'}
                        </p>
                        {pickerSelectedLeaf && (
                          <p className="text-[11px] text-emerald-800 mt-1">
                            You are cataloging under <strong>{pickerSelectedLeaf.name}</strong>. Clear packaging photos and accurate grocery specs ensure faster admin approval.
                          </p>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Helper Footnotes (Vendor Gating Notice) */}
                  <div className="flex flex-col sm:flex-row sm:items-center justify-between text-[11px] text-slate-500 pt-1">
                    <p>Can't find the category? Use Search Category above.</p>
                    <p className="text-slate-400">
                      Still can't find it? Ask your administrator to add it. (Vendors cannot create categories)
                    </p>
                  </div>

                  {/* Step 1 Actions */}
                  <div className="pt-3 border-t border-slate-200 flex items-center justify-between">
                    <button
                      type="button"
                      onClick={() => handleCloseProductModal()}
                      className="px-4 py-2 text-xs font-semibold text-slate-600 hover:text-slate-900"
                    >
                      Discard & Close
                    </button>

                    <button
                      type="button"
                      disabled={!pickerSelectedLeaf}
                      onClick={() => {
                        if (pickerSelectedLeaf) {
                          setProductForm((prev) => ({ ...prev, category: pickerSelectedLeaf.id }));
                          setProductModalStep(2);
                        }
                      }}
                      className={`px-6 py-2.5 text-xs font-bold rounded-xl shadow-xs transition-all flex items-center gap-1.5 ${
                        pickerSelectedLeaf
                          ? 'bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer'
                          : 'bg-slate-200 text-slate-400 cursor-not-allowed'
                      }`}
                    >
                      <span>Continue to Product Details</span>
                      <ArrowRight className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              ) : (
                /* ───────────────────────────────────────────────────────────── */
                /* STEP 2: PRODUCT DETAILS FORM                                  */
                /* ───────────────────────────────────────────────────────────── */
                <div>
                  <div className="p-6 space-y-4 max-h-[75vh] overflow-y-auto">
                    {/* Selected Category Header Strip with "Change category" link */}
                    <div className="p-3.5 bg-emerald-50/80 border border-emerald-200 rounded-xl flex items-center justify-between shadow-2xs">
                      <div className="min-w-0 flex-1 pr-3">
                        <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-700">
                          Selected Category
                        </span>
                        <p className="text-xs font-bold text-slate-900 truncate mt-0.5">
                          {pickerSelectedLeaf?.path_string ||
                            editingProduct?.category_path ||
                            `Category #${productForm.category}`}
                        </p>
                      </div>
                      <button
                        type="button"
                        onClick={() => {
                          setProductModalStep(1);
                          loadPickerColumn(null, 0);
                        }}
                        className="px-3 py-1.5 text-xs font-bold text-emerald-800 bg-white hover:bg-emerald-100 border border-emerald-300 rounded-lg shadow-2xs transition-colors flex items-center gap-1 shrink-0"
                      >
                        <FileEdit className="w-3.5 h-3.5" />
                        <span>Change category</span>
                      </button>
                    </div>

                    {categoryWarning && (
                      <div className="p-3 bg-amber-50 border border-amber-200 text-amber-900 rounded-xl text-xs font-medium flex items-center gap-2">
                        <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0" />
                        <span>{categoryWarning}</span>
                      </div>
                    )}

                    {/* Basic Details */}
                    <div className="space-y-3">
                      <h4 className="text-[11px] font-bold uppercase tracking-wider text-slate-400 border-b pb-1">
                        1. General Information
                      </h4>

                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                        <div className="sm:col-span-2">
                          <label className="block text-xs font-bold text-slate-700 mb-1">
                            Product Title <span className="text-rose-500">*</span>
                          </label>
                          <input
                            type="text"
                            placeholder="e.g. Fortune Sunlite Refined Sunflower Oil 1L"
                            value={productForm.title}
                            onChange={(e) => setProductForm({ ...productForm, title: e.target.value })}
                            className={`w-full px-3.5 py-2 bg-slate-50 border rounded-xl text-xs text-slate-800 ${
                              formErrors.title ? 'border-rose-500 ring-1 ring-rose-500/20' : 'border-slate-200'
                            }`}
                          />
                          {formErrors.title && <p className="text-[10px] text-rose-600 mt-0.5">{formErrors.title}</p>}
                        </div>

                        <div>
                          <label className="block text-xs font-bold text-slate-700 mb-1">
                            SKU (Store Unique) <span className="text-rose-500">*</span>
                          </label>
                          <input
                            type="text"
                            placeholder="e.g. FORT-SUN-1L"
                            value={productForm.sku}
                            onChange={(e) => setProductForm({ ...productForm, sku: e.target.value })}
                            className={`w-full px-3.5 py-2 bg-slate-50 border rounded-xl text-xs text-slate-800 font-mono ${
                              formErrors.sku ? 'border-rose-500 ring-1 ring-rose-500/20' : 'border-slate-200'
                            }`}
                          />
                          {formErrors.sku && <p className="text-[10px] text-rose-600 mt-0.5">{formErrors.sku}</p>}
                        </div>

                        <div>
                          <label className="block text-xs font-bold text-slate-700 mb-1">Brand Name</label>
                          <input
                            type="text"
                            placeholder="e.g. Fortune, Tata, Aashirvaad"
                            value={productForm.brand}
                            onChange={(e) => setProductForm({ ...productForm, brand: e.target.value })}
                            className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800"
                          />
                        </div>

                        <div className="sm:col-span-2 space-y-1.5">
                          <div className="flex items-center justify-between">
                            <label className="block text-xs font-bold text-slate-700">
                              Barcode / EAN (Optional)
                            </label>
                            <button
                              type="button"
                              onClick={() => setShowBarcodeScanner(true)}
                              className="inline-flex items-center gap-1 text-xs font-bold text-emerald-700 hover:text-emerald-800 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 px-2.5 py-1 rounded-lg transition-colors shadow-2xs cursor-pointer"
                              title="Scan barcode with camera or simulated input"
                            >
                              <Scan className="w-3.5 h-3.5 text-emerald-600" />
                              <span>Scan with Camera</span>
                            </button>
                          </div>
                          <div className="relative">
                            <input
                              type="text"
                              placeholder="e.g. 8901234567890 (or click Scan with Camera)"
                              value={productForm.barcode}
                              onChange={(e) => setProductForm({ ...productForm, barcode: e.target.value })}
                              className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 font-mono pr-16"
                            />
                            {productForm.barcode && (
                              <button
                                type="button"
                                onClick={() => setProductForm({ ...productForm, barcode: '' })}
                                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 p-1"
                              >
                                <X className="w-3.5 h-3.5" />
                              </button>
                            )}
                          </div>

                          {/* Live Scannable Barcode Visual Preview */}
                          {productForm.barcode && (
                            <div className="p-3 bg-slate-50 rounded-xl border border-slate-200 flex flex-col sm:flex-row items-center justify-between gap-3 mt-1.5 animate-in fade-in duration-150">
                              <div className="flex items-center gap-2">
                                <span className="p-1.5 bg-emerald-100 text-emerald-800 rounded-lg">
                                  <BarcodeIcon className="w-4 h-4 text-emerald-700 shrink-0" />
                                </span>
                                <div>
                                  <span className="text-[11px] font-bold text-slate-800">Scannable Visual Barcode</span>
                                  <p className="text-[10px] text-slate-400">Verifies scannability for retail packaging and Phase O shipping labels</p>
                                </div>
                              </div>
                              <BarcodeRenderer
                                value={productForm.barcode}
                                height={36}
                                width={1.4}
                                fontSize={10}
                                showCopyButton={false}
                              />
                            </div>
                          )}
                        </div>
                      </div>

                      {/* ── Fulfillment Method Selection ── */}
                      <div className="space-y-2 pt-1 pb-1">
                        <label className="block text-xs font-bold text-slate-700">
                          Fulfillment Method <span className="text-rose-500">*</span>
                        </label>
                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                          {/* Option 1: Self-Ship */}
                          <div
                            onClick={() => setProductForm({ ...productForm, fulfillment_method: 'SELF_SHIP' })}
                            className={`p-3.5 rounded-xl border-2 cursor-pointer transition-all flex items-start gap-3 ${
                              productForm.fulfillment_method === 'SELF_SHIP'
                                ? 'border-indigo-600 bg-indigo-50/40 shadow-xs'
                                : 'border-slate-200 bg-white hover:border-slate-300'
                            }`}
                          >
                            <div className={`p-2 rounded-lg shrink-0 ${
                              productForm.fulfillment_method === 'SELF_SHIP'
                                ? 'bg-indigo-600 text-white'
                                : 'bg-slate-100 text-slate-500'
                            }`}>
                              <Truck className="w-4 h-4" />
                            </div>
                            <div className="min-w-0 flex-1">
                              <div className="flex items-center justify-between">
                                <span className="font-bold text-xs text-slate-900">Self-Ship</span>
                                <span className="text-[10px] font-semibold text-slate-500">Merchant Direct</span>
                              </div>
                              <p className="text-[11px] text-slate-500 mt-0.5 leading-snug">
                                You store inventory and dispatch orders directly from your store or facility.
                              </p>
                            </div>
                          </div>

                          {/* Option 2: Fulfilled by Sevo (FBS) */}
                          <div
                            onClick={() => setProductForm({ ...productForm, fulfillment_method: 'FULFILLED_BY_SEVO' })}
                            className={`p-3.5 rounded-xl border-2 cursor-pointer transition-all flex items-start gap-3 ${
                              productForm.fulfillment_method === 'FULFILLED_BY_SEVO'
                                ? 'border-indigo-600 bg-indigo-50/40 shadow-xs'
                                : 'border-slate-200 bg-white hover:border-slate-300'
                            }`}
                          >
                            <div className={`p-2 rounded-lg shrink-0 ${
                              productForm.fulfillment_method === 'FULFILLED_BY_SEVO'
                                ? 'bg-indigo-600 text-white'
                                : 'bg-slate-100 text-slate-500'
                            }`}>
                              <WarehouseIcon className="w-4 h-4" />
                            </div>
                            <div className="min-w-0 flex-1">
                              <div className="flex items-center justify-between">
                                <span className="font-bold text-xs text-slate-900">Fulfilled by Sevo</span>
                                <span className="text-[10px] font-bold px-1.5 py-0.2 rounded bg-indigo-100 text-indigo-700">FBS</span>
                              </div>
                              <p className="text-[11px] text-slate-500 mt-0.5 leading-snug">
                                Sevo central warehouse physically holds, barcode verifies, and fulfills your stock.
                              </p>
                            </div>
                          </div>
                        </div>

                        {productForm.fulfillment_method === 'FULFILLED_BY_SEVO' && (
                          <div className="p-2.5 bg-indigo-50 border border-indigo-200 rounded-xl text-[11px] text-indigo-900 flex items-start gap-2">
                            <Info className="w-4 h-4 text-indigo-600 shrink-0 mt-0.5" />
                            <div>
                              <span className="font-bold">Fulfilled by Sevo (FBS) Catalog Registration:</span>
                              <p className="text-indigo-700 mt-0.5">
                                Marking as FBS saves your warehouse fulfillment preference. Inbound stock request and barcode intake scanning workflows will be activated in upcoming operational updates.
                              </p>
                            </div>
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Pricing & Taxes */}
                    <div className="space-y-3 pt-2">
                      <h4 className="text-[11px] font-bold uppercase tracking-wider text-slate-400 border-b pb-1">
                        2. Pricing, Margin & Taxes
                      </h4>

                      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                        <div>
                          <label className="block text-xs font-bold text-slate-700 mb-1">
                            MRP (₹) <span className="text-rose-500">*</span>
                          </label>
                          <input
                            type="number"
                            step="0.01"
                            placeholder="180.00"
                            value={productForm.mrp}
                            onChange={(e) => setProductForm({ ...productForm, mrp: e.target.value })}
                            className={`w-full px-3.5 py-2 bg-slate-50 border rounded-xl text-xs text-slate-800 font-mono ${
                              formErrors.mrp ? 'border-rose-500' : 'border-slate-200'
                            }`}
                          />
                          {formErrors.mrp && <p className="text-[10px] text-rose-600 mt-0.5">{formErrors.mrp}</p>}
                        </div>

                        <div>
                          <label className="block text-xs font-bold text-slate-700 mb-1">
                            Selling Price (₹) <span className="text-rose-500">*</span>
                          </label>
                          <input
                            type="number"
                            step="0.01"
                            placeholder="165.00"
                            value={productForm.selling_price}
                            onChange={(e) => setProductForm({ ...productForm, selling_price: e.target.value })}
                            className={`w-full px-3.5 py-2 bg-slate-50 border rounded-xl text-xs text-slate-800 font-mono ${
                              formErrors.selling_price ? 'border-rose-500' : 'border-slate-200'
                            }`}
                          />
                          {formErrors.selling_price && (
                            <p className="text-[10px] text-rose-600 mt-0.5">{formErrors.selling_price}</p>
                          )}
                        </div>

                        <div>
                          <label className="block text-xs font-bold text-slate-700 mb-1">GST Tax Rate (%)</label>
                          <input
                            type="number"
                            step="0.01"
                            placeholder="5.00"
                            value={productForm.tax_rate}
                            onChange={(e) => setProductForm({ ...productForm, tax_rate: e.target.value })}
                            className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 font-mono"
                          />
                        </div>

                        <div>
                          <label className="block text-xs font-bold text-slate-700 mb-1">HSN Code</label>
                          <input
                            type="text"
                            placeholder="1512"
                            value={productForm.hsn_code}
                            onChange={(e) => setProductForm({ ...productForm, hsn_code: e.target.value })}
                            className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 font-mono"
                          />
                        </div>
                      </div>
                    </div>

                    {/* Packaging & Storage */}
                    <div className="space-y-3 pt-2">
                      <h4 className="text-[11px] font-bold uppercase tracking-wider text-slate-400 border-b pb-1">
                        3. Packaging & Grocery Specs
                      </h4>

                      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
                        <div>
                          <label className="block text-xs font-bold text-slate-700 mb-1">Unit</label>
                          <select
                            value={productForm.unit}
                            onChange={(e) => setProductForm({ ...productForm, unit: e.target.value })}
                            className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800"
                          >
                            <option value="piece">piece</option>
                            <option value="pack">pack</option>
                            <option value="g">g (Grams)</option>
                            <option value="kg">kg (Kilograms)</option>
                            <option value="ml">ml (Millilitres)</option>
                            <option value="litre">litre (Litres)</option>
                            <option value="box">box</option>
                            <option value="bottle">bottle</option>
                            <option value="can">can</option>
                            <option value="bunch">bunch</option>
                          </select>
                        </div>

                        <div>
                          <label className="block text-xs font-bold text-slate-700 mb-1">Pack Size / Value</label>
                          <input
                            type="text"
                            placeholder="e.g. 1L, 500g, Pack of 3"
                            value={productForm.pack_size}
                            onChange={(e) => setProductForm({ ...productForm, pack_size: e.target.value })}
                            className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800"
                          />
                        </div>

                        <div className="sm:col-span-2">
                          <label className="block text-xs font-bold text-slate-700 mb-1">Storage Instructions</label>
                          <input
                            type="text"
                            placeholder="e.g. Store in a cool and dry place away from heat"
                            value={productForm.storage_info}
                            onChange={(e) => setProductForm({ ...productForm, storage_info: e.target.value })}
                            className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800"
                          />
                        </div>

                        <div className="sm:col-span-4">
                          <label className="block text-xs font-bold text-slate-700 mb-1">Expiry / Shelf Life Info</label>
                          <input
                            type="text"
                            placeholder="e.g. Best before 9 months from date of packaging"
                            value={productForm.expiry_info}
                            onChange={(e) => setProductForm({ ...productForm, expiry_info: e.target.value })}
                            className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800"
                          />
                        </div>
                      </div>
                    </div>

                    {/* Product Media */}
                    <div className="space-y-3 pt-2">
                      <h4 className="text-[11px] font-bold uppercase tracking-wider text-slate-400 border-b pb-1">
                        4. Product Image Media
                      </h4>

                      <div className="space-y-2">
                        <div className="flex items-center gap-3">
                          <label className="cursor-pointer px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-xl text-xs font-bold border border-slate-200 transition-colors inline-flex items-center gap-1.5">
                            <ImageIcon className="w-4 h-4 text-slate-500" />
                            <span>Upload Photo File</span>
                            <input
                              type="file"
                              accept="image/*"
                              onChange={handleImageFileUpload}
                              className="hidden"
                            />
                          </label>
                          <span className="text-[11px] text-slate-400">or paste a direct web image URL below</span>
                        </div>

                        {/* Image URL input */}
                        <div className="flex items-center gap-2">
                          <input
                            type="text"
                            placeholder="https://example.com/product-image.jpg"
                            value={productForm.images[0] || ''}
                            onChange={(e) => {
                              const val = e.target.value.trim();
                              setProductForm({ ...productForm, images: val ? [val] : [] });
                            }}
                            className="flex-1 px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800"
                          />
                        </div>
                        {formErrors.images && <p className="text-[10px] text-rose-600">{formErrors.images}</p>}

                        {/* Thumbnail preview */}
                        {productForm.images.length > 0 && (
                          <div className="flex items-center gap-2 pt-1">
                            {productForm.images.map((img, idx) => (
                              <div
                                key={idx}
                                className="relative w-16 h-16 rounded-xl border border-slate-200 overflow-hidden bg-slate-50"
                              >
                                <img src={img} alt="Product" className="w-full h-full object-cover" />
                                <button
                                  type="button"
                                  onClick={() => setProductForm({ ...productForm, images: [] })}
                                  className="absolute top-1 right-1 bg-slate-900/80 text-white rounded-full p-0.5"
                                >
                                  <X className="w-3 h-3" />
                                </button>
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    </div>

                    {/* Description */}
                    <div className="space-y-1.5 pt-2">
                      <label className="block text-xs font-bold text-slate-700">Detailed Product Description</label>
                      <textarea
                        rows={3}
                        placeholder="Enter detailed description, ingredients, benefits..."
                        value={productForm.description}
                        onChange={(e) => setProductForm({ ...productForm, description: e.target.value })}
                        className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800"
                      />
                    </div>
                  </div>

                  {/* Modal Footer */}
                  <div className="px-6 py-4 border-t border-slate-200 bg-slate-50/50 flex items-center justify-between">
                    {!editingProduct ? (
                      <button
                        type="button"
                        onClick={() => {
                          setProductModalStep(1);
                          loadPickerColumn(null, 0);
                        }}
                        className="px-4 py-2 text-xs font-semibold text-slate-600 hover:text-slate-900 flex items-center gap-1"
                      >
                        <ChevronRight className="w-3.5 h-3.5 rotate-180" />
                        <span>Back to Categories</span>
                      </button>
                    ) : (
                      <button
                        type="button"
                        onClick={() => handleCloseProductModal()}
                        className="px-4 py-2 text-xs font-semibold text-slate-600 hover:text-slate-900"
                      >
                        Cancel
                      </button>
                    )}

                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => handleSaveProduct(false)}
                        disabled={actionLoading}
                        className="px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-800 font-bold text-xs rounded-xl transition-colors"
                      >
                        Save as Draft
                      </button>
                      <button
                        type="button"
                        onClick={() => handleSaveProduct(true)}
                        disabled={actionLoading}
                        className="px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white font-bold text-xs rounded-xl shadow-xs transition-colors flex items-center gap-1.5"
                      >
                        <Send className="w-3.5 h-3.5" />
                        <span>Submit for Review</span>
                      </button>
                    </div>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}

        {/* ════════════════════════════════════════════════════════════════════ */}
        {/* MODAL 2: ADMIN REVIEW DECISION MODAL                               */}
        {/* ════════════════════════════════════════════════════════════════════ */}
        {showReviewModal && selectedProductForReview && (
          <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4">
            <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl max-w-md w-full overflow-hidden animate-in fade-in zoom-in-95 duration-150">
              <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-purple-50/50">
                <div className="flex items-center gap-2">
                  <ShieldCheck className="w-5 h-5 text-purple-600" />
                  <h3 className="font-bold text-slate-900 text-sm">Platform Catalog Review</h3>
                </div>
                <button onClick={() => setShowReviewModal(false)} className="text-slate-400 hover:text-slate-600">
                  <X className="w-5 h-5" />
                </button>
              </div>

              <div className="p-6 space-y-4">
                <div className="p-3 bg-slate-50 border border-slate-200 rounded-xl text-xs space-y-1">
                  <p className="font-bold text-slate-900">{selectedProductForReview.title}</p>
                  <p className="text-slate-500 font-mono">
                    SKU: {selectedProductForReview.sku} • {selectedProductForReview.company_name}
                  </p>
                </div>

                <div className="space-y-2">
                  <label className="block text-xs font-bold text-slate-700">Select Review Decision</label>
                  <div className="grid grid-cols-2 gap-2">
                    {[
                      { id: 'approve', label: 'Approve & Publish', color: 'emerald' },
                      { id: 'request_changes', label: 'Request Changes', color: 'orange' },
                      { id: 'reject', label: 'Reject Item', color: 'rose' },
                      { id: 'pause', label: 'Pause Product', color: 'zinc' },
                    ].map((act) => (
                      <button
                        key={act.id}
                        type="button"
                        onClick={() => setReviewAction(act.id)}
                        className={`p-2.5 rounded-xl text-xs font-bold border transition-all text-left ${
                          reviewAction === act.id
                            ? 'bg-purple-600 text-white border-purple-600 shadow-xs'
                            : 'bg-white text-slate-700 border-slate-200 hover:bg-slate-50'
                        }`}
                      >
                        {act.label}
                      </button>
                    ))}
                  </div>
                </div>

                {['reject', 'request_changes', 'pause'].includes(reviewAction) && (
                  <div className="space-y-1.5">
                    <label className="block text-xs font-bold text-slate-700">
                      Mandatory Feedback Reason <span className="text-rose-500">*</span>
                    </label>
                    <textarea
                      rows={3}
                      placeholder="Explain clearly what changes are needed or why this item was rejected..."
                      value={reviewNote}
                      onChange={(e) => setReviewNote(e.target.value)}
                      className="w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800"
                    />
                  </div>
                )}
              </div>

              <div className="px-6 py-4 border-t border-slate-200 bg-slate-50/50 flex items-center justify-between">
                <button
                  onClick={() => setShowReviewModal(false)}
                  className="px-4 py-2 text-xs font-semibold text-slate-600"
                >
                  Cancel
                </button>
                <button
                  onClick={handleExecuteReviewDecision}
                  disabled={actionLoading}
                  className="px-5 py-2 bg-purple-600 hover:bg-purple-700 text-white font-bold text-xs rounded-xl shadow-xs transition-colors"
                >
                  {actionLoading ? 'Recording Decision...' : 'Confirm Decision'}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* ════════════════════════════════════════════════════════════════════ */}
        {/* MODAL 3: AUDIT TIMELINE & PRODUCT DETAILS                          */}
        {/* ════════════════════════════════════════════════════════════════════ */}
        {showDetailModal && detailedProduct && (
          <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto">
            <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl max-w-2xl w-full my-8 overflow-hidden animate-in fade-in zoom-in-95 duration-150">
              <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50/50">
                <div className="flex items-center gap-2">
                  <History className="w-5 h-5 text-indigo-600" />
                  <h3 className="font-bold text-slate-900 text-sm">Product Detail & Audit History</h3>
                </div>
                <button onClick={() => setShowDetailModal(false)} className="text-slate-400 hover:text-slate-600">
                  <X className="w-5 h-5" />
                </button>
              </div>

              <div className="p-6 space-y-5 max-h-[75vh] overflow-y-auto">
                {/* Product Snapshot */}
                <div className="flex items-start gap-4 p-4 bg-slate-50 rounded-2xl border border-slate-200">
                  <div className="w-16 h-16 rounded-xl bg-white border border-slate-200 shrink-0 overflow-hidden">
                    {detailedProduct.images?.[0] ? (
                      <img
                        src={detailedProduct.images[0].image_url}
                        alt=""
                        className="w-full h-full object-cover"
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-slate-300">
                        <ImageIcon className="w-6 h-6" />
                      </div>
                    )}
                  </div>
                  <div className="min-w-0 flex-1 space-y-1">
                    <span className="text-sm font-bold text-slate-900 block truncate">{detailedProduct.title}</span>
                    <p className="text-xs text-slate-500 font-mono">
                      SKU: <span className="font-bold text-slate-700">{detailedProduct.sku}</span> • Selling Price:{' '}
                      <span className="font-bold text-emerald-700">₹{detailedProduct.selling_price}</span> (MRP: ₹{detailedProduct.mrp})
                    </p>
                    <p className="text-[11px] text-slate-600">
                      Category: <span className="font-semibold">{detailedProduct.category_path}</span>
                    </p>
                    <div className="flex items-center gap-2 pt-0.5">
                      <span className="text-[11px] text-slate-500">Fulfillment Method:</span>
                      {detailedProduct.fulfillment_method === 'FULFILLED_BY_SEVO' ? (
                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-bold bg-indigo-50 text-indigo-700 border border-indigo-200">
                          <WarehouseIcon className="w-3 h-3 text-indigo-500" />
                          <span>Fulfilled by Sevo (FBS)</span>
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-semibold bg-slate-100 text-slate-700 border border-slate-200">
                          <Truck className="w-3 h-3 text-slate-400" />
                          <span>Self-Ship (Merchant Direct)</span>
                        </span>
                      )}
                    </div>
                    {detailedProduct.barcode && (
                      <div className="pt-2 flex items-center justify-between bg-white p-2.5 rounded-xl border border-slate-200">
                        <div className="flex items-center gap-2">
                          <BarcodeIcon className="w-4 h-4 text-emerald-600" />
                          <span className="text-xs font-bold text-slate-800">Scannable Barcode:</span>
                        </div>
                        <BarcodeRenderer
                          value={detailedProduct.barcode}
                          height={36}
                          width={1.3}
                          fontSize={10}
                          showCopyButton={true}
                        />
                      </div>
                    )}
                  </div>
                </div>

                {/* Audit Timeline */}
                <div className="space-y-3">
                  <h4 className="text-xs font-bold uppercase tracking-wider text-slate-400">
                    Decision & Lifecycle Timeline
                  </h4>

                  {detailedProduct.audit_logs?.length === 0 ? (
                    <p className="text-xs text-slate-400 italic">No audit events recorded.</p>
                  ) : (
                    <div className="space-y-2.5 border-l-2 border-indigo-200 pl-4 ml-2">
                      {detailedProduct.audit_logs.map((log) => (
                        <div key={log.id} className="relative space-y-0.5 text-xs">
                          <div className="w-2.5 h-2.5 bg-indigo-600 rounded-full absolute -left-[21px] top-1 ring-4 ring-white" />
                          <div className="flex items-center gap-2">
                            <span className="font-bold text-slate-900">{log.action}</span>
                            <span className="text-[10px] text-slate-400 font-mono">
                              {new Date(log.created_at).toLocaleString()}
                            </span>
                          </div>
                          <p className="text-[11px] text-slate-600">{log.notes}</p>
                          <p className="text-[10px] text-slate-400">By: {log.actor_name}</p>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              <div className="px-6 py-4 border-t border-slate-200 bg-slate-50/50 text-right">
                <button
                  onClick={() => setShowDetailModal(false)}
                  className="px-4 py-2 bg-slate-900 text-white font-bold text-xs rounded-xl shadow-xs"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        )}

        {/* ════════════════════════════════════════════════════════════════════ */}
        {/* MODAL 4: REQUEST WAREHOUSE STORAGE (PHASE X)                         */}
        {/* ════════════════════════════════════════════════════════════════════ */}
        {showInboundModal && inboundModalProduct && (
          <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto">
            <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl max-w-xl w-full my-8 overflow-hidden animate-in fade-in zoom-in-95 duration-150">
              {/* Header */}
              <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50/50">
                <div className="flex items-center gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-indigo-100 text-indigo-700 flex items-center justify-center font-bold">
                    <WarehouseIcon className="w-4 h-4" />
                  </div>
                  <div>
                    <h3 className="font-bold text-slate-900 text-sm">Request Warehouse Storage (FBS)</h3>
                    <p className="text-[11px] text-slate-500">
                      Submit a stock replenishment intake request to your designated warehouse
                    </p>
                  </div>
                </div>
                <button
                  onClick={() => setShowInboundModal(false)}
                  className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-100"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Body */}
              <div className="p-6 space-y-4">
                {inboundError && (
                  <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-800 flex items-center gap-2">
                    <AlertCircle className="w-4 h-4 shrink-0 text-rose-600" />
                    <span>{inboundError}</span>
                  </div>
                )}

                {/* Product Summary */}
                <div className="p-3.5 bg-slate-50 border border-slate-200 rounded-xl flex items-start gap-3">
                  <div className="w-10 h-10 rounded-lg bg-white border border-slate-200 flex items-center justify-center shrink-0">
                    <Package className="w-5 h-5 text-slate-500" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="font-bold text-slate-900 text-xs truncate">{inboundModalProduct.title}</div>
                    <div className="text-[11px] text-slate-500 font-mono mt-0.5">
                      SKU: <span className="font-bold text-slate-700">{inboundModalProduct.sku}</span> • Selling Price:{' '}
                      <span className="text-emerald-700 font-bold">₹{inboundModalProduct.selling_price}</span>
                    </div>
                  </div>
                </div>

                {/* Phase AA: Warehouse Picker */}
                {inboundLoading ? (
                  <div className="p-4 bg-slate-50 border border-slate-200 rounded-xl text-center">
                    <RefreshCw className="w-4 h-4 text-indigo-600 animate-spin mx-auto mb-1" />
                    <span className="text-xs text-slate-500">Loading available warehouses...</span>
                  </div>
                ) : eligibleWarehouses.length === 0 ? (
                  <div className="p-4 bg-amber-50 border border-amber-300 rounded-xl text-xs text-amber-900 space-y-1">
                    <div className="font-bold flex items-center gap-1.5 text-amber-800">
                      <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0" />
                      <span>No Active Warehouses Available</span>
                    </div>
                    <p className="text-[11px] text-amber-700">
                      There are currently no active warehouse facilities. Please contact Platform Administration.
                    </p>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <label className="block text-xs font-bold text-slate-700">
                      Target Warehouse <span className="text-rose-500">*</span>
                    </label>
                    <div className="relative">
                      <WarehouseIcon className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-indigo-500 pointer-events-none" />
                      <select
                        value={selectedWarehouseId}
                        onChange={(e) => setSelectedWarehouseId(e.target.value)}
                        className="w-full pl-9 pr-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-medium focus:outline-none focus:border-indigo-600 focus:bg-white appearance-none"
                      >
                        <option value=""> -  Select a warehouse  - </option>
                        {eligibleWarehouses.map((wh) => (
                          <option key={wh.id} value={String(wh.id)}>
                            {wh.name}{wh.city ? ` - ${wh.city}` : ''} {wh.id === assignedWarehouseInfo?.warehouse?.id ? '(Your Assigned)' : ''}
                          </option>
                        ))}
                      </select>
                      <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-400 pointer-events-none" />
                    </div>

                    {/* Phase AA: Current balance at selected warehouse */}
                    {selectedWarehouseId && (
                      <div className="flex items-center gap-2 px-3 py-2 bg-indigo-50 border border-indigo-100 rounded-lg min-h-[30px]">
                        {balanceLoading ? (
                          <RefreshCw className="w-3 h-3 text-indigo-500 animate-spin shrink-0" />
                        ) : (
                          <Boxes className="w-3.5 h-3.5 text-indigo-500 shrink-0" />
                        )}
                        {balanceLoading ? (
                          <span className="text-[11px] text-indigo-600">Fetching current stock...</span>
                        ) : inventoryBalance ? (
                          <span className="text-[11px] text-indigo-800 font-medium">
                            Currently at{' '}
                            <span className="font-bold">{inventoryBalance.warehouse_name}</span>:{' '}
                            <span className="font-bold text-emerald-700">{inventoryBalance.on_hand_qty} {inventoryBalance.unit}</span>
                            {inventoryBalance.on_hand_qty === 0 && (
                              <span className="text-slate-500">  -  no stock yet at this warehouse</span>
                            )}
                          </span>
                        ) : (
                          <span className="text-[11px] text-slate-500">No stock data available</span>
                        )}
                      </div>
                    )}
                  </div>
                )}

                {/* Form */}
                <form onSubmit={handleSubmitInboundRequest} className="space-y-3">
                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">
                      Requested Intake Quantity (Units) <span className="text-rose-500">*</span>
                    </label>
                    <input
                      type="number"
                      min="1"
                      required
                      placeholder="e.g. 50"
                      value={inboundForm.requested_quantity}
                      onChange={(e) => setInboundForm({ ...inboundForm, requested_quantity: e.target.value })}
                      disabled={!selectedWarehouseId}
                      className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs font-mono text-slate-900 focus:outline-none focus:border-indigo-600 focus:bg-white disabled:opacity-50 disabled:cursor-not-allowed"
                    />
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">
                      Seller Notes / Special Handling Instructions (Optional)
                    </label>
                    <textarea
                      rows={2}
                      placeholder="e.g., Temperature sensitive spice, scheduled delivery next Tuesday..."
                      value={inboundForm.seller_note}
                      onChange={(e) => setInboundForm({ ...inboundForm, seller_note: e.target.value })}
                      disabled={!selectedWarehouseId}
                      className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-indigo-600 focus:bg-white disabled:opacity-50 disabled:cursor-not-allowed"
                    />
                  </div>

                  <div className="flex items-center justify-end gap-2 pt-2">
                    <button
                      type="button"
                      onClick={() => setShowInboundModal(false)}
                      className="px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-xl text-xs font-bold transition"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      disabled={inboundSubmitting || !selectedWarehouseId}
                      className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-1.5 shadow-sm disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      {inboundSubmitting ? (
                        <>
                          <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                          <span>Submitting Request...</span>
                        </>
                      ) : (
                        <>
                          <Send className="w-3.5 h-3.5" />
                          <span>Submit Storage Request</span>
                        </>
                      )}
                    </button>
                  </div>
                </form>

                {/* Past Requests History for this product */}
                {inboundProductRequests.length > 0 && (
                  <div className="pt-3 border-t border-slate-200 space-y-2">
                    <span className="text-[11px] font-bold text-slate-600 uppercase tracking-wider block">
                      Past Storage Requests for this Item ({inboundProductRequests.length})
                    </span>
                    <div className="max-h-48 overflow-y-auto space-y-2">
                      {inboundProductRequests.map((req) => (
                        <div key={req.id} className="p-2.5 bg-slate-50 rounded-xl border border-slate-200 text-xs space-y-1">
                          <div className="flex items-center justify-between">
                            <span className="font-bold text-slate-800">Req #{req.id} • {req.requested_quantity} units</span>
                            <span
                              className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${
                                req.status === 'PENDING'
                                  ? 'bg-amber-50 text-amber-700 border-amber-200'
                                  : req.status === 'ACCEPTED'
                                  ? 'bg-emerald-50 text-emerald-700 border-emerald-200'
                                  : 'bg-rose-50 text-rose-700 border-rose-200'
                              }`}
                            >
                              {req.status === 'PENDING' ? 'Pending Review' : req.status === 'ACCEPTED' ? 'Accepted' : 'Rejected'}
                            </span>
                          </div>
                          <div className="text-[10px] text-slate-400">
                            {new Date(req.created_at).toLocaleDateString()} {new Date(req.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </div>
                          {req.reviewer_note && (
                            <div className={`text-[11px] p-1.5 rounded border mt-1 ${
                              req.status === 'ACCEPTED'
                                ? 'bg-emerald-50 text-emerald-800 border-emerald-200'
                                : 'bg-rose-50 text-rose-800 border-rose-200'
                            }`}>
                              <span className="font-bold block text-[10px]">
                                {req.status === 'ACCEPTED' ? 'Warehouse Staff Note:' : 'Rejection Reason:'}
                              </span>
                              "{req.reviewer_note}"
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        )}

        {/* Phase Z: Shortfall Reconciliation Decision Modal */}
        {showShortfallDecisionModal && shortfallDecisionRequest && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/60 backdrop-blur-sm animate-fade-in">
            <div className="bg-white rounded-2xl shadow-2xl border border-slate-100 max-w-lg w-full overflow-hidden flex flex-col max-h-[90vh]">
              {/* Modal Header */}
              <div className="p-5 border-b border-slate-100 flex items-center justify-between bg-amber-500/10">
                <div className="flex items-center gap-3">
                  <div className="p-2.5 rounded-xl bg-amber-500 text-white shadow-md shadow-amber-500/20">
                    <AlertTriangle className="w-5 h-5" />
                  </div>
                  <div>
                    <h3 className="text-base font-bold text-slate-900">Inbound Shortfall Notice</h3>
                    <p className="text-xs text-slate-500">Warehouse reported partial physical delivery</p>
                  </div>
                </div>
                <button
                  onClick={() => setShowShortfallDecisionModal(false)}
                  className="p-1.5 text-slate-400 hover:text-slate-600 rounded-lg hover:bg-white/60 transition"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Modal Body */}
              <div className="p-5 space-y-4 overflow-y-auto">
                {shortfallDecisionError && (
                  <div className="p-3 bg-rose-50 border border-rose-200 text-rose-700 text-xs rounded-xl flex items-start gap-2">
                    <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
                    <span>{shortfallDecisionError}</span>
                  </div>
                )}

                {/* Inbound Request & Product Summary */}
                <div className="p-3.5 bg-slate-50 border border-slate-200 rounded-xl space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-slate-800">
                      Req #{shortfallDecisionRequest.id} • {shortfallDecisionRequest.product_title}
                    </span>
                    <span className="px-2 py-0.5 rounded-full text-[10px] font-black uppercase bg-amber-100 text-amber-800 border border-amber-300">
                      Short-Received
                    </span>
                  </div>
                  <div className="text-[11px] text-slate-500 flex items-center gap-3">
                    <span>SKU: <strong className="text-slate-700">{shortfallDecisionRequest.product_sku || 'N/A'}</strong></span>
                    <span>•</span>
                    <span>Facility: <strong className="text-slate-700">{shortfallDecisionRequest.warehouse_name}</strong></span>
                  </div>
                </div>

                {/* Scanned vs Expected Breakdown */}
                <div className="grid grid-cols-3 gap-2 text-center">
                  <div className="p-3 bg-slate-50 rounded-xl border border-slate-200">
                    <span className="text-[10px] font-bold text-slate-400 uppercase tracking-wider block">Requested</span>
                    <span className="text-lg font-black text-slate-800">{shortfallDecisionRequest.requested_quantity}</span>
                    <span className="text-[10px] text-slate-400 block">units</span>
                  </div>
                  <div className="p-3 bg-emerald-50 rounded-xl border border-emerald-200">
                    <span className="text-[10px] font-bold text-emerald-600 uppercase tracking-wider block">Confirmed Scan</span>
                    <span className="text-lg font-black text-emerald-700">{shortfallDecisionRequest.confirmed_quantity || shortfallDecisionRequest.received_units_count || 0}</span>
                    <span className="text-[10px] text-emerald-600 block">verified</span>
                  </div>
                  <div className="p-3 bg-rose-50 rounded-xl border border-rose-200">
                    <span className="text-[10px] font-bold text-rose-600 uppercase tracking-wider block">Missing</span>
                    <span className="text-lg font-black text-rose-700">
                      {Math.max(0, (shortfallDecisionRequest.requested_quantity || 0) - (shortfallDecisionRequest.confirmed_quantity || shortfallDecisionRequest.received_units_count || 0))}
                    </span>
                    <span className="text-[10px] text-rose-600 block">units short</span>
                  </div>
                </div>

                {/* Warehouse Staff Note */}
                <div className="p-3.5 bg-amber-50 border border-amber-200 rounded-xl space-y-1">
                  <div className="flex items-center gap-1.5 text-xs font-bold text-amber-900">
                    <Building2 className="w-3.5 h-3.5" />
                    <span>Warehouse Shortfall Report Note</span>
                  </div>
                  <p className="text-xs text-amber-800 italic bg-white/70 p-2.5 rounded-lg border border-amber-200">
                    "{shortfallDecisionRequest.shortfall_note || 'No additional note provided by warehouse staff.'}"
                  </p>
                </div>

                <form onSubmit={handleConfirmShortfallDecision} className="space-y-4 pt-1">
                  {/* Decision Selection Cards */}
                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-2">
                      Choose Resolution Action:
                    </label>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                      <button
                        type="button"
                        onClick={() => setShortfallDecisionAction('ACCEPT')}
                        className={`p-3 rounded-xl border text-left transition relative ${
                          shortfallDecisionAction === 'ACCEPT'
                            ? 'bg-emerald-50 border-emerald-500 ring-2 ring-emerald-500/20 shadow-sm'
                            : 'bg-white border-slate-200 hover:border-slate-300'
                        }`}
                      >
                        <div className="flex items-center gap-2 mb-1">
                          <CheckCircle2 className={`w-4 h-4 ${shortfallDecisionAction === 'ACCEPT' ? 'text-emerald-600' : 'text-slate-400'}`} />
                          <span className={`text-xs font-bold ${shortfallDecisionAction === 'ACCEPT' ? 'text-emerald-900' : 'text-slate-700'}`}>
                            Accept Partial Count
                          </span>
                        </div>
                        <p className="text-[11px] text-slate-500">
                          Credited <strong>{shortfallDecisionRequest.confirmed_quantity || shortfallDecisionRequest.received_units_count} units</strong> to live inventory. Unscanned units marked not-received.
                        </p>
                      </button>

                      <button
                        type="button"
                        onClick={() => setShortfallDecisionAction('REJECT')}
                        className={`p-3 rounded-xl border text-left transition relative ${
                          shortfallDecisionAction === 'REJECT'
                            ? 'bg-rose-50 border-rose-500 ring-2 ring-rose-500/20 shadow-sm'
                            : 'bg-white border-slate-200 hover:border-slate-300'
                        }`}
                      >
                        <div className="flex items-center gap-2 mb-1">
                          <XCircle className={`w-4 h-4 ${shortfallDecisionAction === 'REJECT' ? 'text-rose-600' : 'text-slate-400'}`} />
                          <span className={`text-xs font-bold ${shortfallDecisionAction === 'REJECT' ? 'text-rose-900' : 'text-slate-700'}`}>
                            Reject & Return Batch
                          </span>
                        </div>
                        <p className="text-[11px] text-slate-500">
                          Nothing goes live. Stages a return order to ship all physically scanned units back to your store address.
                        </p>
                      </button>
                    </div>
                  </div>

                  {/* Seller Note / Instructions */}
                  <div>
                    <label className="block text-xs font-bold text-slate-700 mb-1">
                      Your Response Note (Optional)
                    </label>
                    <textarea
                      rows={2}
                      placeholder={shortfallDecisionAction === 'ACCEPT' ? "e.g., Confirmed 3 units received, supplier short-shipped." : "e.g., Batch incomplete, please return all units to merchant address."}
                      value={sellerShortfallNote}
                      onChange={(e) => setSellerShortfallNote(e.target.value)}
                      className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-indigo-600 focus:bg-white"
                    />
                  </div>

                  {/* Modal Action Buttons */}
                  <div className="flex items-center justify-end gap-2 pt-2 border-t border-slate-100">
                    <button
                      type="button"
                      onClick={() => setShowShortfallDecisionModal(false)}
                      className="px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-xl text-xs font-bold transition"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      disabled={shortfallDecisionSubmitting}
                      className={`px-5 py-2 text-white rounded-xl text-xs font-bold transition flex items-center gap-1.5 shadow-sm disabled:opacity-50 disabled:cursor-not-allowed ${
                        shortfallDecisionAction === 'ACCEPT'
                          ? 'bg-emerald-600 hover:bg-emerald-700'
                          : 'bg-rose-600 hover:bg-rose-700'
                      }`}
                    >
                      {shortfallDecisionSubmitting ? (
                        <>
                          <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                          <span>Submitting Decision...</span>
                        </>
                      ) : shortfallDecisionAction === 'ACCEPT' ? (
                        <>
                          <CheckCircle2 className="w-3.5 h-3.5" />
                          <span>Confirm & Go Live ({shortfallDecisionRequest.confirmed_quantity || shortfallDecisionRequest.received_units_count} Units)</span>
                        </>
                      ) : (
                        <>
                          <XCircle className="w-3.5 h-3.5" />
                          <span>Confirm & Request Return</span>
                        </>
                      )}
                    </button>
                  </div>
                </form>
              </div>
            </div>
          </div>
        )}

        {/* MODAL 5: PRINT INBOUND UNIT LABELS (MULTI-FORMAT) */}
        {showLabelsModal && labelsModalRequest && (
          <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto">
            <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl w-full max-w-lg overflow-hidden animate-in fade-in zoom-in-95 duration-150">
              {/* Header */}
              <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50/50">
                <div className="flex items-center gap-2.5">
                  <div className="w-8 h-8 rounded-lg bg-indigo-100 text-indigo-700 flex items-center justify-center font-bold">
                    <Printer className="w-4 h-4" />
                  </div>
                  <div>
                    <h3 className="font-bold text-slate-900 text-sm">Print Unit Barcode Labels</h3>
                    <p className="text-[11px] text-slate-500">
                      Request #{labelsModalRequest.id} &bull; {labelsModalRequest.requested_quantity} Unit Labels
                    </p>
                  </div>
                </div>
                <button
                  type="button"
                  onClick={() => setShowLabelsModal(false)}
                  className="text-slate-400 hover:text-slate-600 p-1 rounded-lg hover:bg-slate-100 transition"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              {/* Body */}
              <div className="p-6 space-y-4">
                {/* Product & Warehouse Info */}
                <div className="p-3.5 bg-slate-50 border border-slate-200 rounded-xl space-y-2">
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <div className="font-bold text-slate-900 text-xs">{labelsModalRequest.product_title}</div>
                      <div className="text-[11px] font-mono text-slate-500 mt-0.5">
                        SKU: <span className="font-bold text-slate-700">{labelsModalRequest.product_sku}</span>
                      </div>
                    </div>
                    <span className="px-2.5 py-1 rounded-md bg-indigo-100 text-indigo-800 font-bold text-xs font-mono shrink-0">
                      {labelsModalRequest.requested_quantity} Units
                    </span>
                  </div>
                  <div className="text-[11px] text-slate-600 border-t border-slate-200/80 pt-2 flex items-center gap-1.5">
                    <WarehouseIcon className="w-3.5 h-3.5 text-indigo-600 shrink-0" />
                    <span>Target Warehouse: <b className="text-slate-800">{labelsModalRequest.warehouse_name}</b></span>
                  </div>
                </div>

                {/* Paper Size / Format Selector */}
                <div className="space-y-2.5">
                  <label className="block text-xs font-bold text-slate-700">
                    Select Printer Type & Paper Format
                  </label>
                  <div className="grid grid-cols-1 gap-2">
                    {[
                      {
                        id: 'a4',
                        name: 'A4 Sheet (Multi-Label Grid)',
                        desc: '2-column grid layout with multiple unit labels per page. For laser/inkjet printers.',
                        badge: 'Standard A4',
                      },
                      {
                        id: 'thermal_4x6',
                        name: 'Thermal 4×6 in (Roll Label)',
                        desc: '1 unit label per page (101.6 × 152.4 mm). Standard shipping & warehouse label roll.',
                        badge: 'Thermal 4x6"',
                      },
                      {
                        id: 'thermal_2x1',
                        name: 'Thermal 2×1 in (Barcode Sticker)',
                        desc: '1 compact barcode label per page (50.8 × 25.4 mm). For retail & item barcode stickers.',
                        badge: 'Thermal 2x1"',
                      },
                    ].map((opt) => (
                      <label
                        key={opt.id}
                        className={`flex items-start gap-3 p-3 rounded-xl border cursor-pointer transition ${
                          labelsPaperSize === opt.id
                            ? 'bg-indigo-50/70 border-indigo-600 ring-1 ring-indigo-600'
                            : 'bg-white border-slate-200 hover:border-slate-300 hover:bg-slate-50/50'
                        }`}
                      >
                        <input
                          type="radio"
                          name="labelPaperFormat"
                          value={opt.id}
                          checked={labelsPaperSize === opt.id}
                          onChange={(e) => setLabelsPaperSize(e.target.value)}
                          className="mt-0.5 text-indigo-600 focus:ring-indigo-500"
                        />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between">
                            <span className="text-xs font-bold text-slate-900">{opt.name}</span>
                            <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-slate-100 text-slate-600 font-semibold">
                              {opt.badge}
                            </span>
                          </div>
                          <p className="text-[11px] text-slate-500 mt-0.5">{opt.desc}</p>
                        </div>
                      </label>
                    ))}
                  </div>
                </div>

                {/* Footer Buttons */}
                <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
                  <button
                    type="button"
                    onClick={() => setShowLabelsModal(false)}
                    className="px-4 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-xl text-xs font-bold transition"
                  >
                    Close
                  </button>
                  <button
                    type="button"
                    onClick={() => handlePrintLabelsPdf(labelsPaperSize)}
                    className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-1.5 shadow-sm"
                  >
                    <Printer className="w-3.5 h-3.5" />
                    <span>Generate & Print PDF</span>
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Barcode Camera / Test Scanner Modal */}
        <BarcodeScannerModal
          isOpen={showBarcodeScanner}
          onClose={() => setShowBarcodeScanner(false)}
          onScan={(scannedBarcode) => {
            setProductForm((prev) => ({ ...prev, barcode: scannedBarcode }));
            setSuccessMessage(`Scanned barcode: ${scannedBarcode}`);
            setTimeout(() => setSuccessMessage(null), 3500);
          }}
          title="Scan Product Barcode"
          description="Point your camera at the packaging barcode to auto-fill into product details"
        />
      </main>
    </div>
  );
}

export default SellerCatalogUploadsPage;
