import React, { useState, useEffect, useRef, useCallback } from 'react';

import { useParams, useNavigate, Link } from 'react-router-dom';

import { Sidebar } from '../../components/common/Sidebar.jsx';

import { useAuth } from '../../context/AuthProvider.jsx';

import {

  ArrowLeft,

  ArrowRight,

  Check,

  CheckCircle2,

  Package,

  Layers,

  Tag,

  FileEdit,

  UploadCloud,

  RefreshCw,

  AlertCircle,

  AlertTriangle,

  Scan,

  Barcode as BarcodeIcon,

  Warehouse as WarehouseIcon,

  Truck,

  Image as ImageIcon,

  X,

  Info,

  ChevronLeft,

  ChevronRight,

  Plus,

  Search,

  DollarSign,

  HelpCircle,

  Sparkles,

  Save,

  Send,

  Trash2,

  Copy,

  PlusCircle,

  ExternalLink,

  Pencil,

  Star,

  Link as LinkIcon,

} from 'lucide-react';

import { BarcodeScannerModal } from '../../components/common/BarcodeScannerModal.jsx';

import { BarcodeRenderer } from '../../components/common/BarcodeRenderer.jsx';

import { apiSellerGetVariantGroups, apiSellerCreateVariantGroup } from '../../api/workforceService.js';



/**

 * Reusable Multi-Image Manager

 * Supports multi-file drag-and-drop / file picker upload & direct image URLs,

 * with primary/cover selection, manual reordering (left/right), and deletion.

 */

function MultiImageManager({

  images = [],

  onChange,

  token,

  accentColor = 'emerald',

  title = 'Product Images & Media',

  subtitle = 'Upload multiple high-resolution photos or paste direct image links',

  errorMessage = null,

  disabled = false,

}) {

  const [urlInput, setUrlInput] = useState('');

  const [uploading, setUploading] = useState(false);

  const [uploadError, setUploadError] = useState(null);

  const [dragOver, setDragOver] = useState(false);

  const fileInputRef = useRef(null);



  const isPurple = accentColor === 'purple';

  const isIndigo = accentColor === 'indigo';

  const primaryBg = isPurple

    ? 'bg-purple-600 hover:bg-purple-700'

    : isIndigo

    ? 'bg-indigo-600 hover:bg-indigo-700'

    : 'bg-emerald-600 hover:bg-emerald-700';

  const primaryBorder = isPurple

    ? 'border-purple-500'

    : isIndigo

    ? 'border-indigo-500'

    : 'border-emerald-500';

  const primaryText = isPurple

    ? 'text-purple-700'

    : isIndigo

    ? 'text-indigo-700'

    : 'text-emerald-700';

  const focusBorder = isPurple

    ? 'focus:border-purple-600'

    : isIndigo

    ? 'focus:border-indigo-600'

    : 'focus:border-emerald-600';

  const dropzoneBg = dragOver

    ? isPurple

      ? 'bg-purple-50 border-purple-400'

      : isIndigo

      ? 'bg-indigo-50 border-indigo-400'

      : 'bg-emerald-50 border-emerald-400'

    : 'bg-slate-50 hover:bg-slate-100/80 border-slate-200';



  const handleFiles = async (fileList) => {

    if (!fileList || fileList.length === 0) return;

    const files = Array.from(fileList);

    setUploadError(null);



    for (const f of files) {

      if (f.size > 5 * 1024 * 1024) {

        setUploadError(`File '${f.name}' exceeds 5MB limit`);

        return;

      }

    }



    const formData = new FormData();

    files.forEach((f) => formData.append('images', f));



    try {

      setUploading(true);

      const res = await fetch('/api/workforce/seller-hub/products/upload-image/', {

        method: 'POST',

        headers: { Authorization: `Bearer ${token}` },

        body: formData,

      });

      const data = await res.json();

      if (!res.ok) throw new Error(data.error || 'Failed to upload image(s)');



      const newUrls = Array.isArray(data.image_urls)

        ? data.image_urls

        : data.image_url

        ? [data.image_url]

        : [];

      if (newUrls.length > 0) {

        onChange([...images, ...newUrls]);

      }

    } catch (err) {

      setUploadError(err.message || 'Image upload failed');

    } finally {

      setUploading(false);

      if (fileInputRef.current) fileInputRef.current.value = '';

    }

  };



  const handleAddUrl = (e) => {

    if (e) e.preventDefault();

    const cleanUrl = urlInput.trim();

    if (!cleanUrl) return;

    onChange([...images, cleanUrl]);

    setUrlInput('');

    setUploadError(null);

  };



  const handleRemove = (indexToRemove) => {

    onChange(images.filter((_, idx) => idx !== indexToRemove));

  };



  const handleSetPrimary = (index) => {

    if (index === 0 || index >= images.length) return;

    const selected = images[index];

    const rest = images.filter((_, idx) => idx !== index);

    onChange([selected, ...rest]);

  };



  const handleMove = (fromIndex, toIndex) => {

    if (toIndex < 0 || toIndex >= images.length) return;

    const copy = [...images];

    const [moved] = copy.splice(fromIndex, 1);

    copy.splice(toIndex, 0, moved);

    onChange(copy);

  };



  return (

    <div className="space-y-4">

      {/* Upload Zone & Link Input */}

      <div className="space-y-3">

        <div

          onDragOver={(e) => {

            e.preventDefault();

            setDragOver(true);

          }}

          onDragLeave={() => setDragOver(false)}

          onDrop={(e) => {

            e.preventDefault();

            setDragOver(false);

            handleFiles(e.dataTransfer.files);

          }}

          className={`border-2 border-dashed rounded-2xl p-4 sm:p-5 text-center transition-all ${dropzoneBg}`}

        >

          <input

            ref={fileInputRef}

            type="file"

            multiple

            accept="image/*"

            disabled={disabled || uploading}

            onChange={(e) => handleFiles(e.target.files)}

            className="hidden"

          />

          <div className="flex flex-col items-center justify-center gap-2">

            <div

              className={`p-2.5 rounded-full ${

                isPurple

                  ? 'bg-purple-100 text-purple-700'

                  : isIndigo

                  ? 'bg-indigo-100 text-indigo-700'

                  : 'bg-emerald-100 text-emerald-700'

              }`}

            >

              {uploading ? (

                <RefreshCw className="w-5 h-5 animate-spin" />

              ) : (

                <UploadCloud className="w-5 h-5" />

              )}

            </div>

            <div>

              <button

                type="button"

                onClick={() => fileInputRef.current?.click()}

                disabled={disabled || uploading}

                className={`cursor-pointer font-bold text-xs ${primaryText} hover:underline inline-flex items-center gap-1.5`}

              >

                <span>Upload image files from device</span>

                <span className="text-slate-500 font-normal">(multi-file supported)</span>

              </button>

              <p className="text-[11px] text-slate-400 mt-0.5">

                Select 1 or more files, or drag & drop (JPG, PNG, WEBP, up to 5MB each)

              </p>

            </div>

          </div>

        </div>



        {/* Or Paste Direct URL */}

        <div className="flex items-center gap-2">

          <div className="relative flex-1">

            <input

              type="text"

              placeholder="Or paste direct image URL (e.g. https://.../photo.jpg)"

              value={urlInput}

              disabled={disabled || uploading}

              onChange={(e) => setUrlInput(e.target.value)}

              onKeyDown={(e) => {

                if (e.key === 'Enter') {

                  e.preventDefault();

                  handleAddUrl();

                }

              }}

              className={`w-full px-3.5 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-mono focus:outline-none ${focusBorder} focus:bg-white transition-all`}

            />

          </div>

          <button

            type="button"

            onClick={handleAddUrl}

            disabled={disabled || !urlInput.trim() || uploading}

            className={`px-4 py-2 ${primaryBg} text-white rounded-xl text-xs font-bold transition-all shadow-xs disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-1.5 shrink-0`}

          >

            <Plus className="w-3.5 h-3.5" />

            <span>Add Link</span>

          </button>

        </div>



        {uploadError && (

          <div className="p-2.5 bg-rose-50 border border-rose-200 rounded-xl text-xs text-rose-700 flex items-center gap-2">

            <AlertCircle className="w-4 h-4 shrink-0 text-rose-600" />

            <span>{uploadError}</span>

          </div>

        )}



        {errorMessage && (

          <p className="text-xs text-rose-600 font-medium">{errorMessage}</p>

        )}

      </div>



      {/* Thumbnails Gallery Grid */}

      {images.length > 0 && (

        <div className="space-y-2 pt-1">

          <div className="flex items-center justify-between">

            <span className="text-xs font-bold text-slate-700 flex items-center gap-1.5">

              <span>Added Images</span>

              <span className="px-2 py-0.5 rounded-full bg-slate-200/80 text-slate-700 text-[10px] font-mono font-bold">

                {images.length}

              </span>

            </span>

            <span className="text-[11px] text-slate-400">

              ★ First image is the primary cover photo

            </span>

          </div>



          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">

            {images.map((img, idx) => {

              const isPrimary = idx === 0;

              return (

                <div

                  key={`${img}-${idx}`}

                  className={`relative group rounded-2xl overflow-hidden border-2 transition-all bg-slate-100 aspect-square flex flex-col justify-between ${

                    isPrimary

                      ? `${primaryBorder} shadow-sm ring-2 ring-emerald-500/20`

                      : 'border-slate-200 hover:border-slate-300'

                  }`}

                >

                  {/* Image Display */}

                  <img

                    src={img}

                    alt={`Product ${idx + 1}`}

                    className="w-full h-full object-cover"

                    onError={(e) => {

                      e.target.src = 'https://placehold.co/200x200?text=Invalid+Image';

                    }}

                  />



                  {/* Primary Badge or Secondary Index Badge */}

                  <div className="absolute top-1.5 left-1.5 flex items-center gap-1 pointer-events-none">

                    {isPrimary ? (

                      <span className="bg-emerald-600 text-white text-[10px] font-bold px-2 py-0.5 rounded-md shadow-md flex items-center gap-1">

                        <Star className="w-3 h-3 fill-current" />

                        <span>Cover</span>

                      </span>

                    ) : (

                      <span className="bg-slate-900/70 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-md backdrop-blur-xs">

                        #{idx + 1}

                      </span>

                    )}

                  </div>



                  {/* Remove Button */}

                  <button

                    type="button"

                    onClick={() => handleRemove(idx)}

                    disabled={disabled}

                    className="absolute top-1.5 right-1.5 p-1 bg-slate-900/80 hover:bg-rose-600 text-white rounded-full transition-colors opacity-90 group-hover:opacity-100 shadow-md z-10"

                    title="Remove image"

                  >

                    <X className="w-3.5 h-3.5" />

                  </button>



                  {/* Bottom Action Bar: Set as Primary + Move Left / Right */}

                  <div className="absolute bottom-0 inset-x-0 bg-slate-900/85 backdrop-blur-xs p-1.5 flex items-center justify-between text-white opacity-0 group-hover:opacity-100 transition-opacity z-10">

                    {!isPrimary ? (

                      <button

                        type="button"

                        onClick={() => handleSetPrimary(idx)}

                        className="text-[10px] font-bold text-emerald-300 hover:text-emerald-200 flex items-center gap-0.5"

                        title="Set as main cover image"

                      >

                        <Star className="w-2.5 h-2.5 fill-current" />

                        <span>Make Cover</span>

                      </button>

                    ) : (

                      <span className="text-[10px] font-bold text-emerald-300">

                        Primary Cover

                      </span>

                    )}



                    <div className="flex items-center gap-1 ml-auto">

                      <button

                        type="button"

                        disabled={idx === 0}

                        onClick={() => handleMove(idx, idx - 1)}

                        className="p-1 hover:bg-white/20 rounded disabled:opacity-30 transition"

                        title="Move left"

                      >

                        <ChevronLeft className="w-3 h-3" />

                      </button>

                      <button

                        type="button"

                        disabled={idx === images.length - 1}

                        onClick={() => handleMove(idx, idx + 1)}

                        className="p-1 hover:bg-white/20 rounded disabled:opacity-30 transition"

                        title="Move right"

                      >

                        <ChevronRight className="w-3 h-3" />

                      </button>

                    </div>

                  </div>

                </div>

              );

            })}

          </div>

        </div>

      )}

    </div>

  );

}





export function SellerProductEditorPage() {

  const { id } = useParams();

  const isEditMode = Boolean(id);

  const { user, token } = useAuth();

  const navigate = useNavigate();



  // Wizard Step: 1 = Category Selection, 2 = Product Details

  const [currentStep, setCurrentStep] = useState(isEditMode ? 2 : 1);

  const [pageLoading, setPageLoading] = useState(isEditMode);

  const [actionLoading, setActionLoading] = useState(false);

  const [errorMessage, setErrorMessage] = useState(null);

  const [successMessage, setSuccessMessage] = useState(null);



  // Variant Groups from backend

  const [variantGroups, setVariantGroups] = useState([]);



  // Category Picker State (Step 1)

  const [pickerSearch, setPickerSearch] = useState('');

  const [pickerSearchResults, setPickerSearchResults] = useState([]);

  const [pickerSearchLoading, setPickerSearchLoading] = useState(false);

  const [pickerColumns, setPickerColumns] = useState([]); // Array of arrays: [[roots], [subs], [leafs]]

  const [pickerSelectedPath, setPickerSelectedPath] = useState([]); // Array of Category objects

  const [pickerSelectedLeaf, setPickerSelectedLeaf] = useState(null); // Selected leaf Category

  const pickerCacheRef = useRef({});

  const [pickerColumnLoading, setPickerColumnLoading] = useState({});

  const [pickerErrors, setPickerErrors] = useState({});

  const pickerSearchTimerRef = useRef(null);

  const pickerSelectedPathRef = useRef(pickerSelectedPath);

  pickerSelectedPathRef.current = pickerSelectedPath;



  // Barcode Scanner & USB Keyboard-Wedge Scanner Support

  const barcodeInputRef = useRef(null);

  const [showBarcodeScanner, setShowBarcodeScanner] = useState(false);

  const [activeBarcodeScannerRowIndex, setActiveBarcodeScannerRowIndex] = useState(null); // null = productForm.barcode, or number for variantRows[index]



  // Product Form State (Shared Fields across variants or standalone product)

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

    procurement_price: '',

    tax_rate: '0.00',

    hsn_code: '',

    storage_info: '',

    expiry_info: '',

    fssai_license_number: '',

    description: '',

    images: [],

    status: 'DRAFT',

    // Variant fields

    has_variants: false,

    variant_group_mode: 'new', // 'new' | 'existing'

    variant_group: '',

    new_variant_group_title: '',

    new_variant_attribute_name: 'Size',

    variant_label: '',

  });



  const [formErrors, setFormErrors] = useState({});



  // ── Batch Variant Creation State (Amazon-Style Flow) ─────────────────────────

  const [variantTags, setVariantTags] = useState([]); // Array of string tags e.g. ['50g', '100g', '200g']

  const [variantTagInput, setVariantTagInput] = useState('');

  const [variantRows, setVariantRows] = useState([]);

  // Each row: { id, variant_label, sku, mrp, selling_price, procurement_price, pack_size, barcode, has_own_image, images, image_url, has_custom_description, custom_description, has_custom_storage, custom_storage_info, custom_expiry_info, specs, errors }



  // ── Per-Variant Details Popup / Modal State ─────────────────────────────────

  const [activeVariantModalIndex, setActiveVariantModalIndex] = useState(null);

  const [variantModalForm, setVariantModalForm] = useState({

    has_custom_description: false,

    custom_description: '',

    has_custom_storage: false,

    custom_storage_info: '',

    custom_expiry_info: '',

    specs: [],

    has_own_image: false,

    images: [],

    image_url: '',

  });



  // ── Edit Mode Variant Family & Sibling State ─────────────────────────────────

  const [variantSiblings, setVariantSiblings] = useState([]);

  const [variantGroupTitle, setVariantGroupTitle] = useState('');

  const [showAddSiblingModal, setShowAddSiblingModal] = useState(false);

  const [newSiblingForm, setNewSiblingForm] = useState({

    variant_label: '',

    sku: '',

    mrp: '',

    selling_price: '',

    procurement_price: '',

    pack_size: '',

    barcode: '',

    has_own_image: false,

    images: [],

    image_url: '',

  });

  const [newSiblingErrors, setNewSiblingErrors] = useState({});

  const [newSiblingLoading, setNewSiblingLoading] = useState(false);



  // Helper: Is this product editor currently in Batch Variant Creation mode?

  const isBatchVariantMode =

    !isEditMode &&

    productForm.has_variants &&

    productForm.variant_group_mode === 'new';



  // ── Physical USB Barcode Scanner Focus & Global Keydown Listeners ──────────

  // Maintain focus on the physical barcode input when Step 2 is active in single SKU mode

  useEffect(() => {

    if (currentStep === 2 && !showBarcodeScanner && !isBatchVariantMode) {

      const timer = setTimeout(() => {

        barcodeInputRef.current?.focus();

      }, 50);

      return () => clearTimeout(timer);

    }

  }, [currentStep, showBarcodeScanner, isBatchVariantMode]);



  // Global keydown fallback listener: if Step 2 is active and user scans with physical USB scanner,

  // ensure keystrokes are routed to the barcode input without losing characters.

  useEffect(() => {

    if (currentStep !== 2 || showBarcodeScanner || isBatchVariantMode) return;



    const handleGlobalKeyDown = (e) => {

      // If user is currently focused on an input, textarea, or select, let normal handling proceed

      if (['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName)) {

        return;

      }

      // If it's a hotkey or navigation key (Escape, Ctrl+C, etc.), let normal handling proceed

      if (e.ctrlKey || e.altKey || e.metaKey || e.key === 'Escape' || e.key === 'Tab') {

        return;

      }

      // If printable character, focus the barcode input so scanner doesn't drop keystrokes

      if (e.key.length === 1) {

        barcodeInputRef.current?.focus();

      }

    };



    window.addEventListener('keydown', handleGlobalKeyDown);

    return () => window.removeEventListener('keydown', handleGlobalKeyDown);

  }, [currentStep, showBarcodeScanner, isBatchVariantMode]);



  // Fetch initial variant groups

  const loadVariantGroups = useCallback(async () => {

    try {

      const data = await apiSellerGetVariantGroups();

      setVariantGroups(Array.isArray(data) ? data : data?.results || []);

    } catch (e) {

      console.error('Error fetching variant groups:', e);

    }

  }, []);



  useEffect(() => {

    loadVariantGroups();

  }, [loadVariantGroups]);



  // Load a column of categories for parentId (or 'root' if null)

  const loadPickerColumn = useCallback(

    async (parentId = null, colIndex = 0, forceRefresh = false) => {

      const cacheKey = parentId ? String(parentId) : 'root';

      if (!forceRefresh && pickerCacheRef.current[cacheKey]) {

        const cachedItems = pickerCacheRef.current[cacheKey];

        setPickerColumns((prev) => {

          const next = prev.slice(0, colIndex);

          next[colIndex] = cachedItems;

          return next;

        });

        return cachedItems;

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

          const items = Array.isArray(raw) ? raw : raw?.results || [];

          pickerCacheRef.current[cacheKey] = items;

          setPickerColumns((prev) => {

            const next = prev.slice(0, colIndex);

            next[colIndex] = items;

            return next;

          });

          return items;

        } else {

          setPickerErrors((prev) => ({

            ...prev,

            [colIndex]: `Failed to load categories (HTTP ${res.status})`,

          }));

        }

      } catch (e) {

        console.error('Error fetching category column', e);

        setPickerErrors((prev) => ({

          ...prev,

          [colIndex]: e.message || 'Network connection failed',

        }));

      } finally {

        setPickerColumnLoading((prev) => ({ ...prev, [colIndex]: false }));

      }

      return [];

    },

    [token]

  );



  // Initialize root categories on mount (if new product)

  useEffect(() => {

    if (!isEditMode) {

      loadPickerColumn(null, 0, true);

    }

  }, [isEditMode, loadPickerColumn]);



  // Load existing product if in Edit Mode

  useEffect(() => {

    if (!isEditMode) return;



    const fetchProductDetails = async () => {

      setPageLoading(true);

      try {

        const res = await fetch(`/api/workforce/seller-hub/products/${id}/`, {

          headers: { Authorization: `Bearer ${token}` },

        });

        const data = await res.json();

        if (!res.ok) throw new Error(data.error || 'Failed to load product details');



        setProductForm({

          title: data.title || '',

          brand: data.brand || '',

          sku: data.sku || '',

          barcode: data.barcode || '',

          fulfillment_method: data.fulfillment_method || 'SELF_SHIP',

          category: data.category || '',

          unit: data.unit || 'piece',

          pack_size: data.pack_size || '1',

          mrp: data.mrp || '',

          selling_price: data.selling_price || '',

          procurement_price: data.procurement_price ?? '',

          tax_rate: data.tax_rate || '0.00',

          hsn_code: data.hsn_code || '',

          storage_info: data.storage_info || '',

          expiry_info: data.expiry_info || '',

          fssai_license_number: data.fssai_license_number || '',

          description: data.description || '',

          images: data.images?.map((img) => img.image_url) || (data.primary_image ? [data.primary_image] : []),

          status: data.status || 'DRAFT',

          has_variants: Boolean(data.variant_group),

          variant_group_mode: 'existing',

          variant_group: data.variant_group || '',

          new_variant_group_title: data.variant_group_title || '',

          new_variant_attribute_name: data.variant_attribute_name || 'Size',

          variant_label: data.variant_label || '',

        });



        setVariantGroupTitle(data.variant_group_title || '');

        setVariantSiblings(Array.isArray(data.variant_siblings) ? data.variant_siblings : []);



        // Setup category leaf representation

        setPickerSelectedLeaf({

          id: data.category,

          name: data.category_name || `Category #${data.category}`,

          path_string: data.category_path || data.path_string || `Category #${data.category}`,

          is_leaf: true,

        });



        setCurrentStep(2);

      } catch (err) {

        setErrorMessage(err.message || 'Error loading product');

      } finally {

        setPageLoading(false);

      }

    };



    fetchProductDetails();

  }, [id, isEditMode, token]);



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

            setPickerSearchResults(Array.isArray(data) ? data : []);

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



  // Handle Image file upload (Shared product primary image)

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



  // ── Helper: SKU generation per tag ──────────────────────────────────────────

  const generateSkuForTag = (tag) => {

    const base = (productForm.brand || productForm.title || 'PROD')

      .toUpperCase()

      .replace(/[^A-Z0-9]+/g, '-')

      .replace(/^-|-$/g, '')

      .slice(0, 12);

    const tagClean = tag.toUpperCase().replace(/[^A-Z0-9]+/g, '-').replace(/^-|-$/g, '');

    return `${base || 'SKU'}-${tagClean || 'VAR'}`;

  };



  // ── Batch Variant Tags & Rows Helpers ────────────────────────────────────────

  const addVariantTag = (rawValue) => {

    if (!rawValue) return;

    // Split by comma in case user pasted comma-separated values (e.g. "50g, 100g, 200g")

    const rawTokens = rawValue.split(',').map((t) => t.trim()).filter(Boolean);

    if (rawTokens.length === 0) return;



    let updatedTags = [...variantTags];

    let updatedRows = [...variantRows];



    rawTokens.forEach((tokenVal) => {

      // Check case-insensitive duplicate in tags

      const exists = updatedTags.some(

        (t) => t.toLowerCase() === tokenVal.toLowerCase()

      );

      if (!exists) {

        updatedTags.push(tokenVal);

        const newRow = {

          id: `vrow_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,

          variant_label: tokenVal,

          sku: generateSkuForTag(tokenVal),

          pack_size: tokenVal, // prefill pack size from variant tag

          mrp: productForm.mrp || '',

          selling_price: productForm.selling_price || '',

          procurement_price: productForm.procurement_price || '',

          barcode: '',

          has_own_image: false,

          images: [],

          image_url: '',

          has_custom_description: false,

          custom_description: '',

          has_custom_storage: false,

          custom_storage_info: '',

          custom_expiry_info: '',

          specs: [],

          errors: {},

        };

        updatedRows.push(newRow);

      }

    });



    setVariantTags(updatedTags);

    setVariantRows(updatedRows);

    setVariantTagInput('');

  };



  const removeVariantTag = (indexToRemove) => {

    setVariantTags((prev) => prev.filter((_, idx) => idx !== indexToRemove));

    setVariantRows((prev) => prev.filter((_, idx) => idx !== indexToRemove));

  };



  const updateVariantRow = (rowIndex, field, value) => {

    setVariantRows((prev) => {

      const next = [...prev];

      const row = { ...next[rowIndex], [field]: value };

      if (row.errors && row.errors[field]) {

        const nextErrors = { ...row.errors };

        delete nextErrors[field];

        row.errors = nextErrors;

      }

      next[rowIndex] = row;

      return next;

    });

  };



  // ── Per-Variant Details Modal Handlers ─────────────────────────────────────

  const handleOpenVariantDetailsModal = (rowIndex) => {

    const row = variantRows[rowIndex];

    if (!row) return;

    setActiveVariantModalIndex(rowIndex);

    const rowImgs = Array.isArray(row.images) && row.images.length > 0

      ? row.images

      : (row.image_url ? [row.image_url] : []);

    setVariantModalForm({

      has_custom_description: Boolean(row.has_custom_description),

      custom_description:

        row.custom_description !== undefined && row.custom_description !== null

          ? row.custom_description

          : productForm.description,

      has_custom_storage: Boolean(row.has_custom_storage),

      custom_storage_info:

        row.custom_storage_info !== undefined && row.custom_storage_info !== null

          ? row.custom_storage_info

          : productForm.storage_info,

      custom_expiry_info:

        row.custom_expiry_info !== undefined && row.custom_expiry_info !== null

          ? row.custom_expiry_info

          : productForm.expiry_info,

      specs: Array.isArray(row.specs)

        ? row.specs.map((s) => ({ label: s.label || '', value: s.value || '' }))

        : [],

      has_own_image: Boolean(row.has_own_image || rowImgs.length > 0),

      images: rowImgs,

      image_url: rowImgs[0] || '',

    });

  };



  const handleSaveVariantDetailsModal = () => {
    if (activeVariantModalIndex === null) return;
    setVariantRows((prev) => {
      const next = [...prev];
      const row = next[activeVariantModalIndex];
      if (!row) return prev;
      const modalImgs = Array.isArray(variantModalForm.images) ? variantModalForm.images : [];
      next[activeVariantModalIndex] = {
        ...row,
        has_custom_description: variantModalForm.has_custom_description,
        custom_description: variantModalForm.custom_description,
        has_custom_storage: variantModalForm.has_custom_storage,
        custom_storage_info: variantModalForm.custom_storage_info,
        custom_expiry_info: variantModalForm.custom_expiry_info,
        specs: row.specs || [],
        has_own_image: Boolean(
          variantModalForm.has_own_image && modalImgs.length > 0
        ),
        images: modalImgs,
        image_url: modalImgs[0] || '',
      };
      return next;
    });
    setActiveVariantModalIndex(null);
  };



  const hasRowOverrides = (row) => {

    if (!row) return false;

    const hasDesc =

      row.has_custom_description && Boolean(row.custom_description?.trim());

    const hasStorage =

      row.has_custom_storage &&

      Boolean(row.custom_storage_info?.trim() || row.custom_expiry_info?.trim());

    const hasSpecs = Array.isArray(row.specs) && row.specs.length > 0;

    const hasPhoto = Boolean(

      row.has_own_image && ((row.images && row.images.length > 0) || row.image_url)

    );

    return Boolean(hasDesc || hasStorage || hasSpecs || hasPhoto);

  };



  const copyFirstRowPricingToAll = () => {

    if (variantRows.length < 2) return;

    const first = variantRows[0];

    setVariantRows((prev) =>

      prev.map((row, idx) => {

        if (idx === 0) return row;

        return {

          ...row,

          mrp: first.mrp || row.mrp,

          selling_price: first.selling_price || row.selling_price,

          procurement_price: first.procurement_price || row.procurement_price,

        };

      })

    );

  };



  // Handle uploading custom photo(s) for a specific variant row in the matrix

  const handleVariantRowMultiImageUpload = async (rowIndex, files) => {

    if (!files || files.length === 0) return;

    const fileArray = Array.from(files);

    for (const f of fileArray) {

      if (f.size > 5 * 1024 * 1024) {

        alert(`Image file '${f.name}' exceeds 5MB limit`);

        return;

      }

    }



    const formData = new FormData();

    fileArray.forEach((f) => formData.append('images', f));



    try {

      setActionLoading(true);

      const res = await fetch('/api/workforce/seller-hub/products/upload-image/', {

        method: 'POST',

        headers: { Authorization: `Bearer ${token}` },

        body: formData,

      });

      const data = await res.json();

      if (!res.ok) throw new Error(data.error || 'Failed to upload image(s)');



      const newUrls = Array.isArray(data.image_urls)

        ? data.image_urls

        : data.image_url

        ? [data.image_url]

        : [];



      setVariantRows((prev) => {

        const next = [...prev];

        const row = next[rowIndex];

        if (!row) return prev;

        const currentImgs = Array.isArray(row.images)

          ? row.images

          : row.image_url

          ? [row.image_url]

          : [];

        const updatedImgs = [...currentImgs, ...newUrls];

        next[rowIndex] = {

          ...row,

          has_own_image: true,

          images: updatedImgs,

          image_url: updatedImgs[0] || '',

        };

        return next;

      });

    } catch (err) {

      alert(err.message || 'Variant image upload failed');

    } finally {

      setActionLoading(false);

    }

  };



  // ── Form Submission (Draft or Submit for Review) ─────────────────────────────

  const handleSaveProduct = async (submitNow = false) => {

    setFormErrors({});

    setErrorMessage(null);

    const errors = {};



    if (!productForm.title.trim()) errors.title = 'Product title is required';

    if (!productForm.category) errors.category = 'Category is required';



    // ──────────────────────────────────────────────────────────────────────────

    // BRANCH 1: AMAZON-STYLE BATCH VARIANT CREATION MODE (NEW FAMILY)

    // ──────────────────────────────────────────────────────────────────────────

    if (isBatchVariantMode) {

      if (!productForm.new_variant_group_title.trim()) {

        errors.new_variant_group_title = 'Variant family title (e.g. Colgate Total) is required';

      }



      if (variantRows.length < 2) {

        errors.variant_tags = 'Please enter at least 2 size/qty options (e.g. 50g, 100g) for a new variant family';

      }



      // Check shared images requirement if submitting for review

      if (submitNow && productForm.images.length === 0) {

        const allHaveCustomImages = variantRows.every(

          (r) => r.has_own_image && ((r.images && r.images.length > 0) || r.image_url)

        );

        if (!allHaveCustomImages) {

          errors.images = 'Shared product photo (or individual photos on all variants) required to submit for review';

        }

      }



      // Validate each row in variantRows

      const updatedRows = [...variantRows];

      let hasRowErrors = false;

      const seenSkus = new Set();



      updatedRows.forEach((row, idx) => {

        const rErr = {};

        if (!row.sku || !row.sku.trim()) {

          rErr.sku = 'SKU is required';

        } else {

          const skuLower = row.sku.trim().toLowerCase();

          if (seenSkus.has(skuLower)) {

            rErr.sku = 'SKU must be unique across rows';

          } else {

            seenSkus.add(skuLower);

          }

        }



        if (!row.mrp || Number(row.mrp) <= 0) {

          rErr.mrp = 'Valid MRP is required';

        }



        if (!row.selling_price || Number(row.selling_price) <= 0) {

          rErr.selling_price = 'Valid selling price required';

        } else if (Number(row.selling_price) > Number(row.mrp)) {

          rErr.selling_price = 'Selling price cannot exceed MRP';

        }



        if (!row.pack_size || !row.pack_size.trim()) {

          rErr.pack_size = 'Pack size is required';

        }



        const hasRowImg = (row.images && row.images.length > 0) || Boolean(row.image_url);

        if (row.has_own_image && !hasRowImg) {

          rErr.image_url = 'Image required when custom photo is enabled';

        }



        row.errors = rErr;

        if (Object.keys(rErr).length > 0) {

          hasRowErrors = true;

        }

      });



      if (Object.keys(errors).length > 0 || hasRowErrors) {

        setFormErrors(errors);

        setVariantRows(updatedRows);

        setErrorMessage('Please resolve the highlighted validation errors in the product and variant rows.');

        window.scrollTo({ top: 100, behavior: 'smooth' });

        return;

      }



      // ── Execute Batch Creation ──

      setActionLoading(true);

      try {

        // Step A: Create the SellerProductVariantGroup first

        const vgData = await apiSellerCreateVariantGroup({

          group_title: productForm.new_variant_group_title.trim(),

          variant_attribute_name: productForm.new_variant_attribute_name.trim() || 'Size',

        });

        const createdGroupId = vgData.id;



        // Step B: Create each SellerProduct row sequentially

        const createdProducts = [];

        const failedRows = [];



        for (let i = 0; i < variantRows.length; i++) {

          const row = variantRows[i];

          const rowImages =

            row.has_own_image && ((row.images && row.images.length > 0) || row.image_url)

              ? (row.images && row.images.length > 0 ? row.images : [row.image_url])

              : productForm.images;





          const rowDescription =

            row.has_custom_description && row.custom_description?.trim()

              ? row.custom_description.trim()

              : productForm.description;



          const rowStorageInfo =

            row.has_custom_storage && row.custom_storage_info !== undefined

              ? row.custom_storage_info

              : productForm.storage_info;



          const rowExpiryInfo =

            row.has_custom_storage && row.custom_expiry_info !== undefined

              ? row.custom_expiry_info

              : productForm.expiry_info;



          const rowSpecs = (row.specs || [])

            .filter((s) => (s.label && s.label.trim()) || (s.value && s.value.trim()))

            .map((s, idx) => ({

              label: s.label.trim(),

              value: s.value.trim(),

              sort_order: idx,

            }));



          const payload = {

            title: productForm.title.trim(),

            brand: productForm.brand.trim(),

            sku: row.sku.trim(),

            barcode: row.barcode ? row.barcode.trim() : '',

            fulfillment_method: productForm.fulfillment_method,

            category: productForm.category,

            unit: productForm.unit,

            pack_size: row.pack_size.trim() || row.variant_label.trim(),

            mrp: row.mrp,

            selling_price: row.selling_price,

            procurement_price:

              row.procurement_price !== '' && row.procurement_price !== null

                ? row.procurement_price

                : null,

            tax_rate: productForm.tax_rate,

            hsn_code: productForm.hsn_code,

            storage_info: rowStorageInfo,

            expiry_info: rowExpiryInfo,

            fssai_license_number: productForm.fssai_license_number ? productForm.fssai_license_number.trim() : '',

            description: rowDescription,
            images: rowImages,
            ...(rowSpecs.length > 0 ? { specs: rowSpecs } : {}),
            variant_group: createdGroupId,

            variant_label: row.variant_label.trim(),

            status: submitNow ? 'SUBMITTED' : 'DRAFT',

          };



          const res = await fetch('/api/workforce/seller-hub/products/', {

            method: 'POST',

            headers: {

              'Content-Type': 'application/json',

              Authorization: `Bearer ${token}`,

            },

            body: JSON.stringify(payload),

          });



          const data = await res.json();

          if (res.ok) {

            createdProducts.push(data);

          } else {

            failedRows.push({

              index: i,

              row,

              error: data.error || 'Failed to create variant SKU',

              details: data.details || {},

            });

          }

        }



        if (failedRows.length === 0) {

          setSuccessMessage(

            `Successfully created variant family "${productForm.new_variant_group_title}" with ${createdProducts.length} SKU(s)!`

          );

          setTimeout(() => {

            navigate('/workforce/seller-hub/catalog-uploads');

          }, 1400);

        } else {

          // If some succeeded and some failed, keep only the failed rows in the table with inline error messages

          const nextRows = [];

          variantRows.forEach((r, idx) => {

            const fail = failedRows.find((f) => f.index === idx);

            if (fail) {

              const rErr = { ...fail.details };

              if (fail.error && !rErr.sku) {

                rErr.sku = fail.error;

              }

              nextRows.push({ ...r, errors: rErr });

            }

          });

          setVariantRows(nextRows);

          setErrorMessage(

            `Created ${createdProducts.length} of ${variantRows.length} variant SKUs. Please resolve errors on the remaining row(s) below.`

          );

          window.scrollTo({ top: 100, behavior: 'smooth' });

        }

      } catch (err) {

        setErrorMessage(err.message || 'Failed to create variant group');

        window.scrollTo({ top: 0, behavior: 'smooth' });

      } finally {

        setActionLoading(false);

      }

      return;

    }



    // ──────────────────────────────────────────────────────────────────────────

    // BRANCH 2: STANDALONE PRODUCT OR ATTACH TO EXISTING FAMILY (SINGLE SKU)

    // ──────────────────────────────────────────────────────────────────────────

    if (!productForm.sku.trim()) errors.sku = 'SKU is required';

    if (!productForm.mrp || Number(productForm.mrp) <= 0) errors.mrp = 'Valid MRP is required';

    if (!productForm.selling_price || Number(productForm.selling_price) <= 0) {

      errors.selling_price = 'Valid selling price is required';

    }

    if (Number(productForm.selling_price) > Number(productForm.mrp)) {

      errors.selling_price = 'Selling price cannot exceed MRP';

    }

    if (submitNow && productForm.images.length === 0) {

      errors.images = 'At least one product image is required to submit for review';

    }



    if (productForm.has_variants) {

      if (productForm.variant_group_mode === 'existing' && !productForm.variant_group) {

        errors.variant_group = 'Please select an existing variant family';

      }

      if (!productForm.variant_label.trim()) {

        errors.variant_label = 'Option label (e.g. 50g, 100g) is required for this variant SKU';

      }

    }



    if (Object.keys(errors).length > 0) {

      setFormErrors(errors);

      window.scrollTo({ top: 100, behavior: 'smooth' });

      return;

    }



    setActionLoading(true);

    try {

      const payload = {

        ...productForm,

        variant_group: productForm.has_variants ? (productForm.variant_group ? Number(productForm.variant_group) : null) : null,

        variant_label: productForm.has_variants ? productForm.variant_label.trim() : '',

        procurement_price:

          productForm.procurement_price !== '' && productForm.procurement_price !== null

            ? productForm.procurement_price

            : null,

        status: submitNow ? 'SUBMITTED' : (isEditMode ? productForm.status : 'DRAFT'),

      };



      const url = isEditMode

        ? `/api/workforce/seller-hub/products/${id}/`

        : '/api/workforce/seller-hub/products/';

      const method = isEditMode ? 'PATCH' : 'POST';



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



      setSuccessMessage(

        data.message || (isEditMode ? 'Product updated successfully!' : 'Product created successfully!')

      );

      setTimeout(() => {

        navigate('/workforce/seller-hub/catalog-uploads');

      }, 1200);

    } catch (err) {

      setErrorMessage(err.message || 'Failed to save product');

      window.scrollTo({ top: 0, behavior: 'smooth' });

    } finally {

      setActionLoading(false);

    }

  };



  // ── Quick Add Another Size to Existing Family (In Edit Mode) ─────────────────

  const handleAddSiblingSubmit = async (e) => {

    e.preventDefault();

    setNewSiblingErrors({});

    const errs = {};



    if (!newSiblingForm.variant_label.trim()) errs.variant_label = 'Option label (e.g. 250g) is required';

    if (!newSiblingForm.sku.trim()) errs.sku = 'SKU is required';

    if (!newSiblingForm.mrp || Number(newSiblingForm.mrp) <= 0) errs.mrp = 'Valid MRP is required';

    if (!newSiblingForm.selling_price || Number(newSiblingForm.selling_price) <= 0) {

      errs.selling_price = 'Valid selling price required';

    } else if (Number(newSiblingForm.selling_price) > Number(newSiblingForm.mrp)) {

      errs.selling_price = 'Selling price cannot exceed MRP';

    }



    if (Object.keys(errs).length > 0) {

      setNewSiblingErrors(errs);

      return;

    }



    setNewSiblingLoading(true);

    try {

      const siblingImages =

        newSiblingForm.has_own_image && ((newSiblingForm.images && newSiblingForm.images.length > 0) || newSiblingForm.image_url)

          ? (newSiblingForm.images && newSiblingForm.images.length > 0 ? newSiblingForm.images : [newSiblingForm.image_url])

          : productForm.images;



      const payload = {

        title: productForm.title,

        brand: productForm.brand,

        sku: newSiblingForm.sku.trim(),

        barcode: newSiblingForm.barcode ? newSiblingForm.barcode.trim() : '',

        fulfillment_method: productForm.fulfillment_method,

        category: productForm.category,

        unit: productForm.unit,

        pack_size: newSiblingForm.pack_size.trim() || newSiblingForm.variant_label.trim(),

        mrp: newSiblingForm.mrp,

        selling_price: newSiblingForm.selling_price,

        procurement_price:

          newSiblingForm.procurement_price !== '' && newSiblingForm.procurement_price !== null

            ? newSiblingForm.procurement_price

            : null,

        tax_rate: productForm.tax_rate,

        hsn_code: productForm.hsn_code,

        storage_info: productForm.storage_info,

        expiry_info: productForm.expiry_info,

        description: productForm.description,

        images: siblingImages,

        variant_group: productForm.variant_group,

        variant_label: newSiblingForm.variant_label.trim(),

        status: 'DRAFT',

      };



      const res = await fetch('/api/workforce/seller-hub/products/', {

        method: 'POST',

        headers: {

          'Content-Type': 'application/json',

          Authorization: `Bearer ${token}`,

        },

        body: JSON.stringify(payload),

      });



      const data = await res.json();

      if (!res.ok) {

        if (data.details) setNewSiblingErrors(data.details);

        throw new Error(data.error || 'Failed to add variant to family');

      }



      // Add to sibling list

      setVariantSiblings((prev) => [

        ...prev,

        {

          id: data.id,

          title: data.title,

          sku: data.sku,

          variant_label: data.variant_label,

          status: data.status,

          selling_price: data.selling_price,

          mrp: data.mrp,

          in_stock: false,

        },

      ]);



      setShowAddSiblingModal(false);

      setNewSiblingForm({

        variant_label: '',

        sku: '',

        mrp: '',

        selling_price: '',

        procurement_price: '',

        pack_size: '',

        barcode: '',

        has_own_image: false,

        images: [],

        image_url: '',

      });



      setSuccessMessage(`Added "${data.variant_label}" to variant family successfully!`);

      setTimeout(() => setSuccessMessage(null), 4000);

    } catch (err) {

      alert(err.message || 'Failed to add variant');

    } finally {

      setNewSiblingLoading(false);

    }

  };



  // Find selected variant group object for preview

  const selectedVariantGroupObj = variantGroups.find(

    (g) => String(g.id) === String(productForm.variant_group)

  );



  return (

    <div className="flex h-screen bg-slate-50 overflow-hidden font-sans text-slate-800">

      <Sidebar />



      <main className="flex-1 flex flex-col min-w-0 overflow-y-auto relative">

        {/* Sticky Page Header */}

        <header className="sticky top-0 z-20 bg-white border-b border-slate-200 px-6 py-4 shadow-2xs">

          <div className="w-full flex flex-col md:flex-row md:items-center md:justify-between gap-4">

            <div className="flex items-center gap-3">

              <Link

                to="/workforce/seller-hub/catalog-uploads"

                className="p-2 rounded-xl text-slate-500 hover:text-slate-800 hover:bg-slate-100 transition-colors"

                title="Back to Catalog"

              >

                <ArrowLeft className="w-5 h-5" />

              </Link>

              <div>

                <div className="flex items-center gap-2">

                  <h1 className="text-lg font-bold text-slate-900">

                    {isEditMode ? `Edit Product #${id}` : 'Add New Product to Catalog'}

                  </h1>

                  {isEditMode && (

                    <span className="px-2 py-0.5 rounded-md text-[10px] font-bold font-mono bg-indigo-50 text-indigo-700 border border-indigo-200">

                      {productForm.status}

                    </span>

                  )}

                  {isBatchVariantMode && (

                    <span className="px-2 py-0.5 rounded-md text-[10px] font-bold bg-purple-100 text-purple-800 border border-purple-200 flex items-center gap-1">

                      <Sparkles className="w-3 h-3" />

                      Multi-Size Product

                    </span>

                  )}

                </div>

                <p className="text-xs text-slate-500 mt-0.5">

                  {currentStep === 1

                    ? 'Step 1 of 2: Select the leaf category where this product belongs'

                    : isBatchVariantMode

                    ? 'Step 2 of 2: Enter shared specs once, define all size options, and review size and price options'

                    : 'Step 2 of 2: Configure product pricing, packaging, variants, and imagery'}

                </p>

              </div>

            </div>



            {/* 2-Step Progress Indicator Bar */}

            <div className="flex items-center gap-3 bg-slate-50 border border-slate-200/80 px-3.5 py-1.5 rounded-xl self-start md:self-auto">

              {/* Step 1 Pill */}

              <button

                type="button"

                onClick={() => setCurrentStep(1)}

                className={`flex items-center gap-2 text-xs font-bold transition-colors ${

                  currentStep === 1

                    ? 'text-emerald-700'

                    : pickerSelectedLeaf

                    ? 'text-slate-700 hover:text-emerald-600 cursor-pointer'

                    : 'text-slate-400'

                }`}

              >

                <span

                  className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${

                    currentStep === 1

                      ? 'bg-emerald-600 text-white shadow-xs'

                      : pickerSelectedLeaf

                      ? 'bg-emerald-100 text-emerald-800'

                      : 'bg-slate-200 text-slate-600'

                  }`}

                >

                  {pickerSelectedLeaf && currentStep !== 1 ? <Check className="w-3.5 h-3.5" /> : '1'}

                </span>

                <span>1. Category</span>

              </button>



              <ChevronRight className="w-4 h-4 text-slate-300" />



              {/* Step 2 Pill */}

              <button

                type="button"

                disabled={!pickerSelectedLeaf}

                onClick={() => {

                  if (pickerSelectedLeaf) {

                    setProductForm((prev) => ({ ...prev, category: pickerSelectedLeaf.id }));

                    setCurrentStep(2);

                  }

                }}

                className={`flex items-center gap-2 text-xs font-bold transition-colors ${

                  currentStep === 2

                    ? 'text-emerald-700'

                    : pickerSelectedLeaf

                    ? 'text-slate-700 hover:text-emerald-600 cursor-pointer'

                    : 'text-slate-300 cursor-not-allowed'

                }`}

              >

                <span

                  className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold ${

                    currentStep === 2

                      ? 'bg-emerald-600 text-white shadow-xs'

                      : 'bg-slate-200 text-slate-600'

                  }`}

                >

                  2

                </span>

                <span>2. Product Details</span>

              </button>

            </div>

          </div>

        </header>



        {/* Global Notifications */}

        <div className="w-full px-6 pt-4">

          {errorMessage && (

            <div className="mb-4 p-4 rounded-xl bg-rose-50 border border-rose-200 text-rose-800 text-xs flex items-center justify-between shadow-xs animate-in fade-in">

              <div className="flex items-center gap-2">

                <AlertCircle className="w-4 h-4 text-rose-600 shrink-0" />

                <span className="font-medium">{errorMessage}</span>

              </div>

              <button onClick={() => setErrorMessage(null)} className="text-rose-500 hover:text-rose-700 p-1">

                <X className="w-4 h-4" />

              </button>

            </div>

          )}



          {successMessage && (

            <div className="mb-4 p-4 rounded-xl bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs flex items-center gap-2 shadow-xs animate-in fade-in">

              <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0" />

              <span className="font-bold">{successMessage}</span>

            </div>

          )}

        </div>



        {/* Page Content Body */}

        {pageLoading ? (

          <div className="flex-1 flex flex-col items-center justify-center py-20 text-slate-400">

            <RefreshCw className="w-8 h-8 animate-spin text-emerald-600 mb-3" />

            <p className="text-sm font-semibold">Loading product specifications...</p>

          </div>

        ) : (

          <div className="flex-1 w-full px-6 pb-24 pt-2">

            {/* ══════════════════════════════════════════════════════════════════ */}

            {/* STEP 1: CATEGORY SELECTION (FULL PAGE FLOW)                        */}

            {/* ══════════════════════════════════════════════════════════════════ */}

            {currentStep === 1 && (

              <div className="space-y-6 animate-in fade-in duration-200">

                {/* Search Bar Card */}

                <div className="p-5 bg-white rounded-2xl border border-slate-200 shadow-2xs space-y-3">

                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">

                    <div>

                      <h2 className="text-sm font-bold text-slate-900">Find or Browse Category</h2>

                      <p className="text-xs text-slate-500 mt-0.5">

                        Type keywords to find leaf categories quickly, or drill down through the columns below

                      </p>

                    </div>

                    <button

                      type="button"

                      onClick={() => {

                        pickerCacheRef.current = {};

                        setPickerSelectedPath([]);

                        setPickerSelectedLeaf(null);

                        loadPickerColumn(null, 0, true);

                      }}

                      className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold text-slate-600 bg-slate-100 hover:bg-slate-200 rounded-lg transition-colors self-start sm:self-auto"

                    >

                      <RefreshCw className="w-3.5 h-3.5" />

                      <span>Refresh Categories</span>

                    </button>

                  </div>



                  {/* Search Input */}

                  <div className="relative">

                    <Search className="w-4 h-4 text-slate-400 absolute left-3.5 top-1/2 -translate-y-1/2" />

                    <input

                      type="text"

                      placeholder="Search category (e.g. Sunflower Oil, Basmati Rice, Toothpaste, Milk)..."

                      value={pickerSearch}

                      onChange={(e) => handlePickerSearchChange(e.target.value)}

                      className="w-full pl-10 pr-10 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-800 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all shadow-inner"

                    />

                    {pickerSearch && (

                      <button

                        type="button"

                        onClick={() => {

                          setPickerSearch('');

                          setPickerSearchResults([]);

                        }}

                        className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 p-1"

                      >

                        <X className="w-3.5 h-3.5" />

                      </button>

                    )}

                  </div>



                  {/* Search Results Dropdown/List */}

                  {pickerSearchLoading && (

                    <div className="p-3 text-xs text-slate-500 flex items-center gap-2">

                      <RefreshCw className="w-3.5 h-3.5 animate-spin text-emerald-600" />

                      <span>Searching active category taxonomy...</span>

                    </div>

                  )}



                  {!pickerSearchLoading && pickerSearch.trim().length >= 2 && (

                    <div className="max-h-60 overflow-y-auto rounded-xl border border-emerald-200 bg-emerald-50/40 p-2 space-y-1">

                      {pickerSearchResults.length === 0 ? (

                        <p className="p-3 text-xs text-slate-500 italic text-center">

                          No matching leaf categories found for "{pickerSearch}". Try a different keyword or browse columns below.

                        </p>

                      ) : (

                        pickerSearchResults.map((cat) => (

                          <div

                            key={cat.id}

                            onClick={() => handleSearchResultClick(cat)}

                            className={`p-2.5 rounded-lg text-xs cursor-pointer flex items-center justify-between transition-colors ${

                              cat.is_leaf

                                ? 'hover:bg-white text-slate-900 font-semibold'

                                : 'text-slate-400 cursor-not-allowed'

                            } ${pickerSelectedLeaf?.id === cat.id ? 'bg-emerald-600 text-white hover:bg-emerald-700' : ''}`}

                          >

                            <div className="flex items-center gap-2 min-w-0 flex-1">

                              <Tag className={`w-3.5 h-3.5 shrink-0 ${pickerSelectedLeaf?.id === cat.id ? 'text-white' : 'text-emerald-600'}`} />

                              <span className="truncate">{cat.path_string || cat.name}</span>

                            </div>

                            <span className={`text-[10px] font-mono px-2 py-0.5 rounded shrink-0 ml-2 ${

                              pickerSelectedLeaf?.id === cat.id ? 'bg-white/20 text-white font-bold' : 'bg-emerald-100 text-emerald-800 font-semibold'

                            }`}>

                              Leaf Category

                            </span>

                          </div>

                        ))

                      )}

                    </div>

                  )}

                </div>



                {/* Multi-Column Cascading Drilldown Grid */}

                <div className="bg-white rounded-2xl border border-slate-200 shadow-2xs p-5 space-y-3">

                  <div className="flex items-center justify-between">

                    <h3 className="text-xs font-bold uppercase tracking-wider text-slate-500">

                      Category Taxonomy Hierarchy

                    </h3>

                    <span className="text-[11px] text-slate-400">

                      Select Department &rarr; Category &rarr; Subcategory until a leaf is selected

                    </span>

                  </div>



                  <div className="grid grid-cols-1 md:grid-cols-3 gap-3 min-h-[360px]">

                    {[0, 1, 2].map((colIndex) => {

                      const items = pickerColumns[colIndex] || [];

                      const isLoading = pickerColumnLoading[colIndex];

                      const error = pickerErrors[colIndex];

                      const selectedInCol = pickerSelectedPath[colIndex];



                      const colTitle =

                        colIndex === 0

                          ? '1. Primary Department'

                          : colIndex === 1

                          ? '2. Category Group'

                          : '3. Subcategory (Leaf)';



                      return (

                        <div

                          key={colIndex}

                          className="flex flex-col rounded-xl border border-slate-200 bg-slate-50/50 overflow-hidden"

                        >

                          <div className="px-3.5 py-2.5 bg-slate-100/80 border-b border-slate-200 text-xs font-bold text-slate-700 flex items-center justify-between">

                            <span>{colTitle}</span>

                            {items.length > 0 && (

                              <span className="text-[10px] font-mono font-semibold px-1.5 py-0.2 rounded bg-white text-slate-600 border border-slate-200">

                                {items.length}

                              </span>

                            )}

                          </div>



                          <div className="flex-1 p-2 space-y-1 overflow-y-auto max-h-[380px]">

                            {isLoading ? (

                              <div className="py-12 text-center text-xs text-slate-400 flex flex-col items-center gap-2">

                                <RefreshCw className="w-5 h-5 animate-spin text-emerald-600" />

                                <span>Loading categories...</span>

                              </div>

                            ) : error ? (

                              <div className="p-3 text-xs text-rose-600 bg-rose-50 rounded-lg border border-rose-200">

                                {error}

                              </div>

                            ) : items.length === 0 ? (

                              <div className="py-12 text-center text-xs text-slate-400 italic">

                                {colIndex === 0

                                  ? 'No root categories found.'

                                  : 'Select a category from the previous column to view subcategories.'}

                              </div>

                            ) : (

                              items.map((cat) => {

                                const isSelected = selectedInCol?.id === cat.id;

                                const isLeaf = !cat.has_children;



                                return (

                                  <button

                                    key={cat.id}

                                    type="button"

                                    onClick={() => handleColumnItemClick(cat, colIndex)}

                                    className={`w-full text-left p-2.5 rounded-lg text-xs font-medium transition-all flex items-center justify-between group ${

                                      isSelected

                                        ? 'bg-emerald-600 text-white shadow-2xs font-bold'

                                        : 'bg-white text-slate-800 hover:bg-slate-100 border border-slate-200/70'

                                    }`}

                                  >

                                    <div className="flex items-center gap-2 min-w-0 flex-1">

                                      {isLeaf ? (

                                        <Tag

                                          className={`w-3.5 h-3.5 shrink-0 ${

                                            isSelected ? 'text-white' : 'text-emerald-600'

                                          }`}

                                        />

                                      ) : (

                                        <Package

                                          className={`w-3.5 h-3.5 shrink-0 ${

                                            isSelected ? 'text-white' : 'text-slate-400'

                                          }`}

                                        />

                                      )}

                                      <span className="truncate">{cat.name}</span>

                                    </div>



                                    {isLeaf ? (

                                      <span

                                        className={`text-[9px] font-bold px-1.5 py-0.5 rounded font-mono shrink-0 ml-1.5 ${

                                          isSelected

                                            ? 'bg-white/20 text-white'

                                            : 'bg-emerald-50 text-emerald-700 border border-emerald-200'

                                        }`}

                                      >

                                        LEAF

                                      </span>

                                    ) : (

                                      <ChevronRight

                                        className={`w-4 h-4 shrink-0 transition-transform ${

                                          isSelected

                                            ? 'text-white translate-x-0.5'

                                            : 'text-slate-400 group-hover:translate-x-0.5'

                                        }`}

                                      />

                                    )}

                                  </button>

                                );

                              })

                            )}

                          </div>

                        </div>

                      );

                    })}

                  </div>

                </div>



                {/* Selected Leaf Category Confirmation Box */}

                <div className="p-4 bg-emerald-50/80 border border-emerald-200 rounded-2xl flex flex-col sm:flex-row sm:items-center justify-between gap-4 shadow-2xs">

                  <div className="flex items-start gap-3 min-w-0 flex-1">

                    <div className="p-2.5 bg-emerald-600 text-white rounded-xl shadow-xs shrink-0">

                      <CheckCircle2 className="w-5 h-5" />

                    </div>

                    <div>

                      <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-700">

                        Selected Catalog Destination

                      </span>

                      <p className="font-bold text-sm text-slate-900 mt-0.5 truncate">

                        {pickerSelectedLeaf

                          ? pickerSelectedLeaf.path_string || pickerSelectedLeaf.name

                          : pickerSelectedPath.length > 0

                          ? pickerSelectedPath.map((p) => p.name).join(' › ')

                          : 'No leaf category selected yet — choose a leaf category above to proceed'}

                      </p>

                      {pickerSelectedLeaf && (

                        <p className="text-[11px] text-emerald-800 mt-0.5">

                          You are cataloging under <strong>{pickerSelectedLeaf.name}</strong>. Clear packaging photos and accurate grocery specs ensure faster admin approval.

                        </p>

                      )}

                    </div>

                  </div>



                  <button

                    type="button"

                    disabled={!pickerSelectedLeaf}

                    onClick={() => {

                      if (pickerSelectedLeaf) {

                        setProductForm((prev) => ({ ...prev, category: pickerSelectedLeaf.id }));

                        setCurrentStep(2);

                        window.scrollTo({ top: 0, behavior: 'smooth' });

                      }

                    }}

                    className={`px-6 py-3 text-xs font-bold rounded-xl shadow-xs transition-all flex items-center justify-center gap-2 shrink-0 ${

                      pickerSelectedLeaf

                        ? 'bg-emerald-600 hover:bg-emerald-700 text-white cursor-pointer shadow-emerald-600/20'

                        : 'bg-slate-200 text-slate-400 cursor-not-allowed'

                    }`}

                  >

                    <span>Continue to Product Details</span>

                    <ArrowRight className="w-4 h-4" />

                  </button>

                </div>



                {/* Helper Footnotes */}

                <div className="flex flex-col sm:flex-row sm:items-center justify-between text-xs text-slate-500 px-1">

                  <p>Can't find the category? Use the Search Bar at the top.</p>

                  <p className="text-slate-400">

                    Vendors cannot create root categories. Contact platform administrator if an entire new category tree is needed.

                  </p>

                </div>

              </div>

            )}



            {/* ══════════════════════════════════════════════════════════════════ */}

            {/* STEP 2: PRODUCT DETAILS FORM (SPACIOUS SECTIONS & CARDS)           */}

            {/* ══════════════════════════════════════════════════════════════════ */}

            {currentStep === 2 && (

              <form

                onSubmit={(e) => {

                  e.preventDefault();

                  handleSaveProduct(false);

                }}

                className="space-y-6 animate-in fade-in duration-200"

              >

                {/* 1. Category Breadcrumbs Strip */}

                <div className="p-4 bg-emerald-50/80 border border-emerald-200 rounded-2xl flex items-center justify-between shadow-2xs">

                  <div className="min-w-0 flex-1 pr-3">

                    <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-700">

                      Assigned Category

                    </span>

                    <p className="text-sm font-bold text-slate-900 truncate mt-0.5">

                      {pickerSelectedLeaf?.path_string ||

                        `Category #${productForm.category}`}

                    </p>

                  </div>

                  <button

                    type="button"

                    onClick={() => {

                      setCurrentStep(1);

                      window.scrollTo({ top: 0, behavior: 'smooth' });

                    }}

                    className="px-3.5 py-1.5 text-xs font-bold text-emerald-800 bg-white hover:bg-emerald-100 border border-emerald-300 rounded-xl shadow-2xs transition-colors flex items-center gap-1.5 shrink-0"

                  >

                    <FileEdit className="w-3.5 h-3.5" />

                    <span>Change Category</span>

                  </button>

                </div>



                {/* 2. Basic & General Information Card */}

                <div className="bg-white rounded-2xl border border-slate-200 shadow-2xs p-6 space-y-5">

                  <div className="border-b border-slate-100 pb-3">

                    <h3 className="text-sm font-bold text-slate-900 flex items-center gap-2">

                      <Package className="w-4 h-4 text-emerald-600" />

                      <span>General Product Information</span>

                    </h3>

                    <p className="text-xs text-slate-500 mt-0.5">

                      {isBatchVariantMode

                        ? 'Product title, brand, and fulfillment method (applied to all variants in this family)'

                        : 'Product title, brand, store-unique SKU identifier, and fulfillment method'}

                    </p>

                  </div>



                  <div className="grid grid-cols-1 md:grid-cols-2 gap-5">

                    {/* Title (Full Width) */}

                    <div className="md:col-span-2">

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">

                        Product Title <span className="text-rose-500">*</span>

                      </label>

                      <input

                        type="text"

                        placeholder="e.g. Fortune Sunlite Refined Sunflower Oil"

                        value={productForm.title}

                        onChange={(e) => setProductForm({ ...productForm, title: e.target.value })}

                        className={`w-full px-4 py-2.5 bg-slate-50 border rounded-xl text-xs text-slate-900 focus:outline-none focus:bg-white transition-all ${

                          formErrors.title ? 'border-rose-500 ring-2 ring-rose-500/20' : 'border-slate-200 focus:border-emerald-600'

                        }`}

                      />

                      {formErrors.title && <p className="text-xs text-rose-600 mt-1">{formErrors.title}</p>}

                    </div>



                    {/* Brand */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">Brand Name</label>

                      <input

                        type="text"

                        placeholder="e.g. Fortune, Tata, Aashirvaad, Colgate"

                        value={productForm.brand}

                        onChange={(e) => setProductForm({ ...productForm, brand: e.target.value })}

                        className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                      />

                    </div>



                    {/* SKU (Conditional Display / Information) */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">

                        SKU (Store Unique Identifier){' '}

                        {!isBatchVariantMode && <span className="text-rose-500">*</span>}

                      </label>

                      {isBatchVariantMode ? (

                        <div className="px-4 py-2.5 bg-purple-50/70 border border-purple-200 rounded-xl text-xs text-purple-900 flex items-center gap-2">

                          <Sparkles className="w-4 h-4 text-purple-600 shrink-0" />

                          <span>Configured individually per size in Section 5 (Variant Matrix)</span>

                        </div>

                      ) : (

                        <>

                          <input

                            type="text"

                            placeholder="e.g. FORT-SUN-1L-POUCH"

                            value={productForm.sku}

                            onChange={(e) => setProductForm({ ...productForm, sku: e.target.value })}

                            className={`w-full px-4 py-2.5 bg-slate-50 border rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:bg-white transition-all ${

                              formErrors.sku ? 'border-rose-500 ring-2 ring-rose-500/20' : 'border-slate-200 focus:border-emerald-600'

                            }`}

                          />

                          {formErrors.sku && <p className="text-xs text-rose-600 mt-1">{formErrors.sku}</p>}

                        </>

                      )}

                    </div>



                    {/* FSSAI License Override (Optional) */}
                    <div className="md:col-span-2">
                      <label className="block text-xs font-bold text-slate-700 mb-1.5">
                        FSSAI Number (Override) <span className="text-slate-400 font-normal">(Optional)</span>
                      </label>
                      <input
                        type="text"
                        maxLength={14}
                        placeholder="Leave blank to use your store's default FSSAI number"
                        value={productForm.fssai_license_number}
                        onChange={(e) =>
                          setProductForm({
                            ...productForm,
                            fssai_license_number: e.target.value.replace(/\D/g, ''),
                          })
                        }
                        className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"
                      />
                      <p className="text-[11px] text-slate-400 mt-1">
                        Leave blank to use your store's FSSAI number. Only specify if this product has a separate FSSAI registration.
                      </p>
                    </div>

                    {/* Barcode / EAN (Only for single SKU mode) */}

                    {!isBatchVariantMode && (

                      <div className="md:col-span-2 space-y-2">

                        <div className="flex items-center justify-between">

                          <label className="block text-xs font-bold text-slate-700">

                            Scannable Barcode / EAN (Optional)

                          </label>

                          <button

                            type="button"

                            onClick={() => {

                              setActiveBarcodeScannerRowIndex(null);

                              setShowBarcodeScanner(true);

                            }}

                            className="inline-flex items-center gap-1.5 text-xs font-bold text-emerald-700 hover:text-emerald-800 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 px-3 py-1.5 rounded-xl transition-colors shadow-2xs"

                          >

                            <Scan className="w-3.5 h-3.5 text-emerald-600" />

                            <span>Scan with Camera</span>

                          </button>

                        </div>



                        <div className="relative">

                          <input

                            ref={barcodeInputRef}

                            type="text"

                            placeholder="e.g. 8901234567890 (or scan with USB scanner / camera)"

                            value={productForm.barcode}

                            readOnly={actionLoading}

                            autoComplete="off"

                            autoCorrect="off"

                            spellCheck={false}

                            onChange={(e) => {

                              const clean = e.target.value.replace(/[\r\n\t]/g, '');

                              setProductForm({ ...productForm, barcode: clean });

                            }}

                            onKeyDown={(e) => {

                              if (e.key === 'Enter' || e.key === 'Tab') {

                                e.preventDefault();

                                const clean = String(e.target.value).replace(/[\r\n\t]/g, '').trim();

                                setProductForm((prev) => ({ ...prev, barcode: clean }));

                                setTimeout(() => {

                                  barcodeInputRef.current?.focus();

                                }, 20);

                              }

                            }}

                            className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-mono pr-10 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                          />

                          {productForm.barcode && (

                            <button

                              type="button"

                              onClick={() => {

                                setProductForm({ ...productForm, barcode: '' });

                                setTimeout(() => {

                                  barcodeInputRef.current?.focus();

                                }, 20);

                              }}

                              className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 p-1"

                            >

                              <X className="w-3.5 h-3.5" />

                            </button>

                          )}

                        </div>





                        {/* Live Scannable Barcode Preview */}

                        {productForm.barcode && (

                          <div className="p-4 bg-slate-50 rounded-xl border border-slate-200 flex flex-col sm:flex-row items-center justify-between gap-4 mt-2">

                            <div className="flex items-center gap-3">

                              <span className="p-2 bg-emerald-100 text-emerald-800 rounded-xl">

                                <BarcodeIcon className="w-5 h-5 text-emerald-700 shrink-0" />

                              </span>

                              <div>

                                <span className="text-xs font-bold text-slate-800">Scannable Visual Barcode</span>

                                <p className="text-[11px] text-slate-400">

                                  Verifies barcode scanner readability for warehouse intake and retail verification

                                </p>

                              </div>

                            </div>

                            <BarcodeRenderer

                              value={productForm.barcode}

                              height={40}

                              width={1.4}

                              fontSize={10}

                              showCopyButton={false}

                            />

                          </div>

                        )}

                      </div>

                    )}



                    {/* Fulfillment Method Selection Cards */}

                    <div className="md:col-span-2 space-y-2 pt-2">

                      <label className="block text-xs font-bold text-slate-700">

                        Fulfillment Method <span className="text-rose-500">*</span>

                      </label>

                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">

                        {/* Option 1: Self-Ship */}

                        <div

                          onClick={() => setProductForm({ ...productForm, fulfillment_method: 'SELF_SHIP' })}

                          className={`p-4 rounded-xl border-2 cursor-pointer transition-all flex items-start gap-3.5 ${

                            productForm.fulfillment_method === 'SELF_SHIP'

                              ? 'border-indigo-600 bg-indigo-50/40 shadow-xs ring-2 ring-indigo-600/10'

                              : 'border-slate-200 bg-white hover:border-slate-300'

                          }`}

                        >

                          <div

                            className={`p-2.5 rounded-xl shrink-0 ${

                              productForm.fulfillment_method === 'SELF_SHIP'

                                ? 'bg-indigo-600 text-white shadow-xs'

                                : 'bg-slate-100 text-slate-500'

                            }`}

                          >

                            <Truck className="w-5 h-5" />

                          </div>

                          <div className="min-w-0 flex-1">

                            <div className="flex items-center justify-between">

                              <span className="font-bold text-xs text-slate-900">Self-Ship</span>

                              <span className="text-[10px] font-semibold text-slate-500">Merchant Direct</span>

                            </div>

                            <p className="text-xs text-slate-500 mt-1 leading-snug">

                              You store physical inventory and dispatch orders directly from your store or facility.

                            </p>

                          </div>

                        </div>



                        {/* Option 2: Fulfilled by Sevo (FBS) */}

                        <div

                          onClick={() => setProductForm({ ...productForm, fulfillment_method: 'FULFILLED_BY_SEVO' })}

                          className={`p-4 rounded-xl border-2 cursor-pointer transition-all flex items-start gap-3.5 ${

                            productForm.fulfillment_method === 'FULFILLED_BY_SEVO'

                              ? 'border-indigo-600 bg-indigo-50/40 shadow-xs ring-2 ring-indigo-600/10'

                              : 'border-slate-200 bg-white hover:border-slate-300'

                          }`}

                        >

                          <div

                            className={`p-2.5 rounded-xl shrink-0 ${

                              productForm.fulfillment_method === 'FULFILLED_BY_SEVO'

                                ? 'bg-indigo-600 text-white shadow-xs'

                                : 'bg-slate-100 text-slate-500'

                            }`}

                          >

                            <WarehouseIcon className="w-5 h-5" />

                          </div>

                          <div className="min-w-0 flex-1">

                            <div className="flex items-center justify-between">

                              <span className="font-bold text-xs text-slate-900">Fulfilled by Sevo</span>

                              <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-indigo-100 text-indigo-700">

                                FBS

                              </span>

                            </div>

                            <p className="text-xs text-slate-500 mt-1 leading-snug">

                              Sevo central warehouse holds, barcode-verifies, and fulfills orders on your behalf.

                            </p>

                          </div>

                        </div>

                      </div>

                    </div>

                  </div>

                </div>



                {/* 3. Pricing, Margin & Taxes Card */}

                <div className="bg-white rounded-2xl border border-slate-200 shadow-2xs p-6 space-y-5">

                  <div className="border-b border-slate-100 pb-3">

                    <h3 className="text-sm font-bold text-slate-900 flex items-center gap-2">

                      <DollarSign className="w-4 h-4 text-emerald-600" />

                      <span>Pricing, Margin & Tax Rates</span>

                    </h3>

                    <p className="text-xs text-slate-500 mt-0.5">

                      {isBatchVariantMode

                        ? 'GST and HSN apply to all variants; individual MRP and selling prices are set per size below'

                        : 'Enter Maximum Retail Price (MRP), actual selling price, cost price, and applicable GST rate'}

                    </p>

                  </div>



                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">

                    {/* MRP (Hidden/Disabled in Batch Mode) */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">

                        MRP (₹) {!isBatchVariantMode && <span className="text-rose-500">*</span>}

                      </label>

                      {isBatchVariantMode ? (

                        <input

                          type="number"

                          step="0.01"

                          placeholder="Family default (optional)"

                          value={productForm.mrp}

                          onChange={(e) => setProductForm({ ...productForm, mrp: e.target.value })}

                          className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                        />

                      ) : (

                        <>

                          <input

                            type="number"

                            step="0.01"

                            placeholder="180.00"

                            value={productForm.mrp}

                            onChange={(e) => setProductForm({ ...productForm, mrp: e.target.value })}

                            className={`w-full px-4 py-2.5 bg-slate-50 border rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:bg-white transition-all ${

                              formErrors.mrp ? 'border-rose-500 ring-2 ring-rose-500/20' : 'border-slate-200 focus:border-emerald-600'

                            }`}

                          />

                          {formErrors.mrp && <p className="text-xs text-rose-600 mt-1">{formErrors.mrp}</p>}

                        </>

                      )}

                    </div>



                    {/* Selling Price */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">

                        Selling Price (₹) {!isBatchVariantMode && <span className="text-rose-500">*</span>}

                      </label>

                      {isBatchVariantMode ? (

                        <input

                          type="number"

                          step="0.01"

                          placeholder="Family default (optional)"

                          value={productForm.selling_price}

                          onChange={(e) => setProductForm({ ...productForm, selling_price: e.target.value })}

                          className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                        />

                      ) : (

                        <>

                          <input

                            type="number"

                            step="0.01"

                            placeholder="165.00"

                            value={productForm.selling_price}

                            onChange={(e) => setProductForm({ ...productForm, selling_price: e.target.value })}

                            className={`w-full px-4 py-2.5 bg-slate-50 border rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:bg-white transition-all ${

                              formErrors.selling_price ? 'border-rose-500 ring-2 ring-rose-500/20' : 'border-slate-200 focus:border-emerald-600'

                            }`}

                          />

                          {formErrors.selling_price && <p className="text-xs text-rose-600 mt-1">{formErrors.selling_price}</p>}

                        </>

                      )}

                    </div>



                    {/* Procurement Price */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">

                        Cost Price (₹) <span className="text-[10px] text-slate-400 font-normal">(Optional)</span>

                      </label>

                      <input

                        type="number"

                        step="0.01"

                        placeholder="140.00"

                        value={productForm.procurement_price}

                        onChange={(e) => setProductForm({ ...productForm, procurement_price: e.target.value })}

                        className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                      />

                      <p className="text-[10px] text-slate-400 mt-1">Merchant confidential (not customer-facing)</p>

                    </div>



                    {/* GST Tax Rate */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">GST Rate (%)</label>

                      <input

                        type="number"

                        step="0.01"

                        placeholder="5.00"

                        value={productForm.tax_rate}

                        onChange={(e) => setProductForm({ ...productForm, tax_rate: e.target.value })}

                        className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                      />

                    </div>



                    {/* HSN Code */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">HSN Code</label>

                      <input

                        type="text"

                        placeholder="e.g. 1512"

                        value={productForm.hsn_code}

                        onChange={(e) => setProductForm({ ...productForm, hsn_code: e.target.value })}

                        className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 font-mono focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                      />

                    </div>

                  </div>

                </div>



                {/* 4. Packaging & Grocery Specs Card */}

                <div className="bg-white rounded-2xl border border-slate-200 shadow-2xs p-6 space-y-5">

                  <div className="border-b border-slate-100 pb-3">

                    <h3 className="text-sm font-bold text-slate-900 flex items-center gap-2">

                      <Tag className="w-4 h-4 text-emerald-600" />

                      <span>Packaging & Grocery Specifications</span>

                    </h3>

                    <p className="text-xs text-slate-500 mt-0.5">

                      Specify measurement unit, storage conditions, and expiry shelf life

                    </p>

                  </div>



                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">

                    {/* Unit */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">Measurement Unit</label>

                      <select

                        value={productForm.unit}

                        onChange={(e) => setProductForm({ ...productForm, unit: e.target.value })}

                        className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

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



                    {/* Pack Size (Only for single SKU mode) */}

                    <div>

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">

                        Pack Size / Value

                      </label>

                      {isBatchVariantMode ? (

                        <div className="px-4 py-2.5 bg-slate-100 border border-slate-200 rounded-xl text-xs text-slate-600">

                          Set per variant in Section 5

                        </div>

                      ) : (

                        <input

                          type="text"

                          placeholder="e.g. 1L, 500g, Pack of 6"

                          value={productForm.pack_size}

                          onChange={(e) => setProductForm({ ...productForm, pack_size: e.target.value })}

                          className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                        />

                      )}

                    </div>



                    {/* Storage Info */}

                    <div className="sm:col-span-2">

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">Storage Instructions</label>

                      <input

                        type="text"

                        placeholder="e.g. Store in a cool, dry place away from direct sunlight"

                        value={productForm.storage_info}

                        onChange={(e) => setProductForm({ ...productForm, storage_info: e.target.value })}

                        className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                      />

                    </div>



                    {/* Expiry Info */}

                    <div className="sm:col-span-2 lg:col-span-4">

                      <label className="block text-xs font-bold text-slate-700 mb-1.5">Expiry / Shelf Life Info</label>

                      <input

                        type="text"

                        placeholder="e.g. Best before 9 months from date of manufacture/packaging"

                        value={productForm.expiry_info}

                        onChange={(e) => setProductForm({ ...productForm, expiry_info: e.target.value })}

                        className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                      />

                    </div>

                  </div>

                </div>



                {/* 5. Product Variants (Size / Quantity Options) Card */}

                <div className="bg-white rounded-2xl border border-slate-200 shadow-2xs p-6 space-y-5">

                  {/* Card Header with Prominent Toggle */}

                  <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-100 pb-4">

                    <div className="flex items-start gap-3">

                      <div className="p-2.5 bg-indigo-50 text-indigo-700 rounded-xl shrink-0 mt-0.5">

                        <Layers className="w-5 h-5" />

                      </div>

                      <div>

                        <h3 className="text-sm font-bold text-slate-900">

                          Product Variants (Size / Quantity Options)

                        </h3>

                        <p className="text-xs text-slate-500 mt-0.5">

                          Product families with selectable option chips (e.g. 50g, 100g, 1L)

                        </p>

                      </div>

                    </div>



                    {/* Large Switch Toggle (Disabled in Edit Mode if already part of a family) */}

                    {!isEditMode && (

                      <label className="inline-flex items-center gap-3 cursor-pointer select-none self-start sm:self-auto bg-slate-50 hover:bg-slate-100 border border-slate-200 px-3.5 py-2 rounded-xl transition-all">

                        <input

                          type="checkbox"

                          checked={productForm.has_variants}

                          onChange={(e) =>

                            setProductForm({

                              ...productForm,

                              has_variants: e.target.checked,

                              variant_group_mode: productForm.variant_group_mode || 'new',

                            })

                          }

                          className="sr-only peer"

                        />

                        <div className="w-9 h-5 bg-slate-300 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-slate-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-emerald-600 relative"></div>

                        <span className="text-xs font-bold text-slate-800">

                          {productForm.has_variants ? 'Variants Enabled' : 'Enable Size/Qty Variants'}

                        </span>

                      </label>

                    )}

                  </div>



                  {/* ── CASE A: EDIT MODE (VIEW SIBLINGS & ADD ANOTHER SIZE QUICKLY) ── */}

                  {isEditMode ? (

                    productForm.has_variants && productForm.variant_group ? (

                      <div className="space-y-4 pt-1">

                        <div className="p-4 bg-indigo-50/70 border border-indigo-200 rounded-2xl flex flex-col md:flex-row md:items-center justify-between gap-4">

                          <div>

                            <div className="flex items-center gap-2">

                              <span className="text-xs font-bold text-indigo-950">

                                Variant Family: {variantGroupTitle || 'Product Family'}

                              </span>

                              <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-indigo-200/80 text-indigo-900">

                                Selector: {productForm.new_variant_attribute_name || 'Size'}

                              </span>

                            </div>

                            <p className="text-xs text-indigo-800 mt-1">

                              This SKU represents option <strong>"{productForm.variant_label || 'Current'}"</strong>. Other sizes in this family are shown below.

                            </p>

                          </div>



                          <button

                            type="button"

                            onClick={() => {

                              setNewSiblingForm({

                                variant_label: '',

                                sku: `${(productForm.brand || productForm.title || 'PROD').toUpperCase().slice(0, 8)}-`,

                                mrp: productForm.mrp,

                                selling_price: productForm.selling_price,

                                procurement_price: productForm.procurement_price,

                                pack_size: '',

                                barcode: '',

                                has_own_image: false,

                                image_url: '',

                              });

                              setNewSiblingErrors({});

                              setShowAddSiblingModal(true);

                            }}

                            className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-xs font-bold transition flex items-center gap-1.5 shadow-xs shrink-0 self-start md:self-auto"

                          >

                            <Plus className="w-4 h-4" />

                            <span>Add Another Size to Family</span>

                          </button>

                        </div>



                        {/* Sibling List Grid */}

                        <div className="space-y-2">

                          <span className="text-xs font-bold text-slate-700 block">

                            All Sizes & SKUs in this Family ({variantSiblings.length + 1} total)

                          </span>

                          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">

                            {/* Current Product Card */}

                            <div className="p-3 bg-emerald-50 border-2 border-emerald-500/60 rounded-xl shadow-2xs">

                              <div className="flex items-center justify-between">

                                <span className="px-2 py-0.5 rounded text-xs font-bold bg-emerald-600 text-white">

                                  {productForm.variant_label || 'Current'}

                                </span>

                                <span className="text-[10px] font-bold text-emerald-800">THIS PRODUCT</span>

                              </div>

                              <div className="mt-2 text-xs font-mono font-bold text-slate-800 truncate">

                                {productForm.sku}

                              </div>

                              <div className="text-xs text-slate-500 mt-0.5">

                                ₹{productForm.selling_price} (MRP ₹{productForm.mrp})

                              </div>

                            </div>



                            {/* Other Sibling Cards */}

                            {variantSiblings.map((sib) => (

                              <div key={sib.id} className="p-3 bg-white border border-slate-200 rounded-xl shadow-2xs flex flex-col justify-between">

                                <div>

                                  <div className="flex items-center justify-between">

                                    <span className="px-2 py-0.5 rounded text-xs font-bold bg-slate-100 text-slate-800 border border-slate-200">

                                      {sib.variant_label}

                                    </span>

                                    <span className={`text-[10px] font-bold font-mono px-1.5 py-0.2 rounded ${

                                      sib.status === 'APPROVED' ? 'bg-emerald-100 text-emerald-800' : 'bg-slate-100 text-slate-600'

                                    }`}>

                                      {sib.status}

                                    </span>

                                  </div>

                                  <div className="mt-2 text-xs font-mono font-semibold text-slate-700 truncate">

                                    {sib.sku}

                                  </div>

                                  <div className="text-xs text-slate-500 mt-0.5">

                                    ₹{sib.selling_price} (MRP ₹{sib.mrp})

                                  </div>

                                </div>

                                <div className="mt-3 pt-2 border-t border-slate-100 flex items-center justify-end">

                                  <Link

                                    to={`/workforce/seller-hub/products/${sib.id}/edit`}

                                    className="text-[11px] font-bold text-indigo-600 hover:text-indigo-800 flex items-center gap-1"

                                  >

                                    <span>Edit Sibling</span>

                                    <ExternalLink className="w-3 h-3" />

                                  </Link>

                                </div>

                              </div>

                            ))}

                          </div>

                        </div>

                      </div>

                    ) : (

                      <p className="text-xs text-slate-500 italic">

                        This product is currently configured as a standalone catalog listing without size/quantity option chips.

                      </p>

                    )

                  ) : productForm.has_variants ? (

                    /* ── CASE B: CREATE PRODUCT (AMAZON-STYLE BATCH VARIANT FLOW) ── */

                    <div className="space-y-6 pt-1 animate-in fade-in duration-150">

                      {/* Mode Tabs: Create New Family vs Attach to Existing */}

                      <div className="space-y-2">

                        <label className="block text-xs font-bold text-slate-700">

                          Variant Family Configuration Mode

                        </label>

                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">

                          {/* Tab 1: Create New Family (Batch Creation Matrix) */}

                          <div

                            onClick={() => setProductForm({ ...productForm, variant_group_mode: 'new' })}

                            className={`p-3.5 rounded-xl border-2 cursor-pointer transition-all flex items-start gap-3 ${

                              productForm.variant_group_mode === 'new'

                                ? 'border-emerald-600 bg-emerald-50/40 shadow-xs ring-2 ring-emerald-600/10'

                                : 'border-slate-200 bg-white hover:border-slate-300'

                            }`}

                          >

                            <div

                              className={`p-2 rounded-lg shrink-0 ${

                                productForm.variant_group_mode === 'new'

                                  ? 'bg-emerald-600 text-white'

                                  : 'bg-slate-100 text-slate-500'

                              }`}

                            >

                              <Sparkles className="w-4 h-4" />

                            </div>

                            <div>

                              <span className="font-bold text-xs text-slate-900 block">

                                + Create New Size/Variant Family

                              </span>

                              <p className="text-[11px] text-slate-500 mt-0.5">

                                Enter all sizes at once (e.g. 50g, 100g, 200g) and generate all SKUs in one sitting

                              </p>

                            </div>

                          </div>



                          {/* Tab 2: Attach to Existing */}

                          <div

                            onClick={() => setProductForm({ ...productForm, variant_group_mode: 'existing' })}

                            className={`p-3.5 rounded-xl border-2 cursor-pointer transition-all flex items-start gap-3 ${

                              productForm.variant_group_mode === 'existing'

                                ? 'border-emerald-600 bg-emerald-50/40 shadow-xs ring-2 ring-emerald-600/10'

                                : 'border-slate-200 bg-white hover:border-slate-300'

                            }`}

                          >

                            <div

                              className={`p-2 rounded-lg shrink-0 ${

                                productForm.variant_group_mode === 'existing'

                                  ? 'bg-emerald-600 text-white'

                                  : 'bg-slate-100 text-slate-500'

                              }`}

                            >

                              <Layers className="w-4 h-4" />

                            </div>

                            <div>

                              <span className="font-bold text-xs text-slate-900 block">

                                Attach Single SKU to Existing Family

                              </span>

                              <p className="text-[11px] text-slate-500 mt-0.5">

                                Add just one new size option to a family you previously created

                              </p>

                            </div>

                          </div>

                        </div>

                      </div>



                      {/* ── SUB-BRANCH: CREATE NEW FAMILY (AMAZON-STYLE MULTI-TAG INPUT) ── */}

                      {productForm.variant_group_mode === 'new' ? (

                        <div className="space-y-5">

                          {/* Family Group Title & Selector Attribute */}

                          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">

                            <div>

                              <label className="block text-xs font-bold text-slate-700 mb-1.5">

                                Family Group Title <span className="text-rose-500">*</span>

                              </label>

                              <input

                                type="text"

                                placeholder="e.g. Colgate Total Toothpaste"

                                value={productForm.new_variant_group_title}

                                onChange={(e) =>

                                  setProductForm({ ...productForm, new_variant_group_title: e.target.value })

                                }

                                className={`w-full px-4 py-2.5 bg-slate-50 border rounded-xl text-xs text-slate-900 focus:outline-none focus:bg-white transition-all ${

                                  formErrors.new_variant_group_title

                                    ? 'border-rose-500 ring-2 ring-rose-500/20'

                                    : 'border-slate-200 focus:border-emerald-600'

                                }`}

                              />

                              {formErrors.new_variant_group_title && (

                                <p className="text-xs text-rose-600 mt-1">{formErrors.new_variant_group_title}</p>

                              )}

                            </div>



                            <div>

                              <label className="block text-xs font-bold text-slate-700 mb-1.5">

                                Selector Attribute Label

                              </label>

                              <input

                                type="text"

                                placeholder="e.g. Size, Weight, Quantity, Pack, Volume"

                                value={productForm.new_variant_attribute_name}

                                onChange={(e) =>

                                  setProductForm({ ...productForm, new_variant_attribute_name: e.target.value })

                                }

                                className="w-full px-4 py-2.5 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all"

                              />

                            </div>

                          </div>



                          {/* Multi-Value Chip / Tag Input */}

                          <div className="p-4 bg-slate-50 rounded-2xl border border-slate-200 space-y-3">

                            <div className="flex items-center justify-between">

                              <div>

                                <label className="block text-xs font-bold text-slate-800">

                                  Enter Size / Quantity Option Values <span className="text-rose-500">*</span>

                                </label>

                                <p className="text-[11px] text-slate-500 mt-0.5">

                                  Type an option value and press <kbd className="px-1.5 py-0.5 rounded bg-white border border-slate-300 font-mono text-[10px] text-slate-700">Enter</kbd> or <kbd className="px-1.5 py-0.5 rounded bg-white border border-slate-300 font-mono text-[10px] text-slate-700">,</kbd> to add (e.g. 50g, 100g, 200g, 1L, Pack of 3)

                                </p>

                              </div>

                              {variantTags.length > 0 && (

                                <span className="text-[11px] font-bold font-mono px-2 py-0.5 rounded bg-emerald-100 text-emerald-800">

                                  {variantTags.length} option{variantTags.length === 1 ? '' : 's'} added

                                </span>

                              )}

                            </div>



                            {/* Tag Input Container with Chips */}

                            <div className="flex flex-wrap items-center gap-2 p-2.5 bg-white border border-slate-200 rounded-xl shadow-inner min-h-[46px]">

                              {variantTags.map((tagVal, idx) => (

                                <span

                                  key={idx}

                                  className="inline-flex items-center gap-1.5 px-3 py-1 bg-emerald-50 text-emerald-800 border border-emerald-200 rounded-lg text-xs font-bold shadow-2xs animate-in zoom-in-95"

                                >

                                  <span>{tagVal}</span>

                                  <button

                                    type="button"

                                    onClick={() => removeVariantTag(idx)}

                                    className="p-0.5 hover:bg-emerald-200 rounded-full transition-colors text-emerald-700"

                                    title={`Remove ${tagVal}`}

                                  >

                                    <X className="w-3 h-3" />

                                  </button>

                                </span>

                              ))}



                              <input

                                type="text"

                                placeholder={

                                  variantTags.length === 0

                                    ? "Type value (e.g. 50g) and press Enter or comma..."

                                    : "Add another size (e.g. 100g)..."

                                }

                                value={variantTagInput}

                                onChange={(e) => setVariantTagInput(e.target.value)}

                                onKeyDown={(e) => {

                                  if (e.key === 'Enter' || e.key === ',') {

                                    e.preventDefault();

                                    addVariantTag(variantTagInput);

                                  }

                                }}

                                onPaste={(e) => {

                                  const text = e.clipboardData.getData('text');

                                  if (text.includes(',')) {

                                    e.preventDefault();

                                    addVariantTag(text);

                                  }

                                }}

                                className="flex-1 min-w-[180px] bg-transparent border-none text-xs text-slate-800 focus:outline-none placeholder:text-slate-400 py-1"

                              />



                              {variantTagInput.trim() && (

                                <button

                                  type="button"

                                  onClick={() => addVariantTag(variantTagInput)}

                                  className="px-3 py-1 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg text-xs font-bold shadow-2xs transition shrink-0"

                                >

                                  + Add Option

                                </button>

                              )}

                            </div>

                            {formErrors.variant_tags && (

                              <p className="text-xs text-rose-600 font-medium">{formErrors.variant_tags}</p>

                            )}

                          </div>



                          {/* ── BATCH VARIANT MATRIX TABLE ── */}

                          {variantRows.length > 0 ? (

                            <div className="space-y-3 pt-2">

                              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-slate-100 pb-2">

                                <div>

                                  <h4 className="text-xs font-bold uppercase tracking-wider text-slate-700 flex items-center gap-2">

                                    <span>Size & Price Options Table</span>

                                    <span className="text-emerald-700 font-mono">({variantRows.length} SKUs)</span>

                                  </h4>

                                  <p className="text-[11px] text-slate-500 mt-0.5">

                                    Each row generates an independent SellerProduct SKU sharing common title & specifications

                                  </p>

                                </div>



                                {variantRows.length >= 2 && (

                                  <button

                                    type="button"

                                    onClick={copyFirstRowPricingToAll}

                                    className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-bold text-slate-700 bg-slate-100 hover:bg-slate-200 border border-slate-200 rounded-lg transition-colors self-start sm:self-auto"

                                    title="Copy MRP, Selling Price, and Cost Price from Row 1 to all rows"

                                  >

                                    <Copy className="w-3.5 h-3.5 text-slate-500" />

                                    <span>Copy 1st Row Pricing to All</span>

                                  </button>

                                )}

                              </div>



                              <div className="overflow-x-auto rounded-xl border border-slate-200 shadow-2xs">

                                <table className="w-full text-left border-collapse text-xs">

                                  <thead>

                                    <tr className="bg-slate-100/80 border-b border-slate-200 text-slate-700 font-bold text-[11px]">

                                      <th className="p-3 w-28">Option Chip</th>

                                      <th className="p-3 min-w-[160px]">

                                        SKU <span className="text-rose-500">*</span>

                                      </th>

                                      <th className="p-3 w-32">

                                        Pack Size <span className="text-rose-500">*</span>

                                      </th>

                                      <th className="p-3 w-28">

                                        MRP (₹) <span className="text-rose-500">*</span>

                                      </th>

                                      <th className="p-3 w-28">

                                        Selling (₹) <span className="text-rose-500">*</span>

                                      </th>

                                      <th className="p-3 w-28">Cost (₹)</th>

                                      <th className="p-3 min-w-[140px]">Barcode / EAN</th>

                                      <th className="p-3 w-36">Image Photo</th>

                                      <th className="p-3 w-20 text-center">Action</th>

                                    </tr>

                                  </thead>

                                  <tbody className="divide-y divide-slate-100 bg-white">

                                    {variantRows.map((row, rIdx) => {

                                      const rowErr = row.errors || {};

                                      const hasCustom = hasRowOverrides(row);



                                      return (

                                        <tr

                                          key={row.id || rIdx}

                                          className={`hover:bg-slate-50/80 transition-colors ${

                                            Object.keys(rowErr).length > 0 ? 'bg-rose-50/30' : ''

                                          }`}

                                        >

                                          {/* 1. Option Label Chip */}

                                          <td className="p-3 align-top">

                                            <span className="inline-block px-2.5 py-1 bg-indigo-50 text-indigo-700 border border-indigo-200 font-bold rounded-lg text-xs font-mono shadow-2xs">

                                              {row.variant_label}

                                            </span>

                                          </td>



                                          {/* 2. SKU */}

                                          <td className="p-3 align-top">

                                            <input

                                              type="text"

                                              value={row.sku}

                                              onChange={(e) => updateVariantRow(rIdx, 'sku', e.target.value)}

                                              placeholder="SKU-CODE"

                                              className={`w-full px-2.5 py-1.5 bg-slate-50 border rounded-lg text-xs font-mono text-slate-900 focus:outline-none focus:bg-white ${

                                                rowErr.sku

                                                  ? 'border-rose-500 ring-1 ring-rose-500'

                                                  : 'border-slate-200 focus:border-emerald-600'

                                              }`}

                                            />

                                            {rowErr.sku && (

                                              <p className="text-[10px] text-rose-600 mt-1">{rowErr.sku}</p>

                                            )}

                                          </td>



                                          {/* 3. Pack Size */}

                                          <td className="p-3 align-top">

                                            <input

                                              type="text"

                                              value={row.pack_size}

                                              onChange={(e) => updateVariantRow(rIdx, 'pack_size', e.target.value)}

                                              placeholder="e.g. 50g"

                                              className={`w-full px-2.5 py-1.5 bg-slate-50 border rounded-lg text-xs text-slate-900 focus:outline-none focus:bg-white ${

                                                rowErr.pack_size

                                                  ? 'border-rose-500 ring-1 ring-rose-500'

                                                  : 'border-slate-200 focus:border-emerald-600'

                                              }`}

                                            />

                                            {rowErr.pack_size && (

                                              <p className="text-[10px] text-rose-600 mt-1">{rowErr.pack_size}</p>

                                            )}

                                          </td>



                                          {/* 4. MRP */}

                                          <td className="p-3 align-top">

                                            <input

                                              type="number"

                                              step="0.01"

                                              value={row.mrp}

                                              onChange={(e) => updateVariantRow(rIdx, 'mrp', e.target.value)}

                                              placeholder="100.00"

                                              className={`w-full px-2.5 py-1.5 bg-slate-50 border rounded-lg text-xs font-mono text-slate-900 focus:outline-none focus:bg-white ${

                                                rowErr.mrp

                                                  ? 'border-rose-500 ring-1 ring-rose-500'

                                                  : 'border-slate-200 focus:border-emerald-600'

                                              }`}

                                            />

                                            {rowErr.mrp && (

                                              <p className="text-[10px] text-rose-600 mt-1">{rowErr.mrp}</p>

                                            )}

                                          </td>



                                          {/* 5. Selling Price */}

                                          <td className="p-3 align-top">

                                            <input

                                              type="number"

                                              step="0.01"

                                              value={row.selling_price}

                                              onChange={(e) => updateVariantRow(rIdx, 'selling_price', e.target.value)}

                                              placeholder="90.00"

                                              className={`w-full px-2.5 py-1.5 bg-slate-50 border rounded-lg text-xs font-mono text-slate-900 focus:outline-none focus:bg-white ${

                                                rowErr.selling_price

                                                  ? 'border-rose-500 ring-1 ring-rose-500'

                                                  : 'border-slate-200 focus:border-emerald-600'

                                              }`}

                                            />

                                            {rowErr.selling_price && (

                                              <p className="text-[10px] text-rose-600 mt-1">{rowErr.selling_price}</p>

                                            )}

                                          </td>



                                          {/* 6. Procurement / Cost Price */}

                                          <td className="p-3 align-top">

                                            <input

                                              type="number"

                                              step="0.01"

                                              value={row.procurement_price}

                                              onChange={(e) => updateVariantRow(rIdx, 'procurement_price', e.target.value)}

                                              placeholder="75.00"

                                              className="w-full px-2.5 py-1.5 bg-slate-50 border border-slate-200 rounded-lg text-xs font-mono text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white"

                                            />

                                          </td>



                                           {/* 7. Barcode / EAN */}

                                           <td className="p-3 align-top">

                                             <div className="flex items-center gap-1">

                                               <input

                                                 type="text"

                                                 value={row.barcode}

                                                 readOnly={actionLoading}

                                                 autoComplete="off"

                                                 autoCorrect="off"

                                                 spellCheck={false}

                                                 onChange={(e) => {

                                                   const clean = e.target.value.replace(/[\r\n\t]/g, '');

                                                   updateVariantRow(rIdx, 'barcode', clean);

                                                 }}

                                                 onKeyDown={(e) => {

                                                   if (e.key === 'Enter' || e.key === 'Tab') {

                                                     e.preventDefault();

                                                     const clean = String(e.target.value).replace(/[\r\n\t]/g, '').trim();

                                                     updateVariantRow(rIdx, 'barcode', clean);

                                                   }

                                                 }}

                                                 placeholder="890..."

                                                 className="w-full px-2.5 py-1.5 bg-slate-50 border border-slate-200 rounded-lg text-xs font-mono text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white"

                                               />

                                               <button

                                                 type="button"

                                                 onClick={() => {

                                                   setActiveBarcodeScannerRowIndex(rIdx);

                                                   setShowBarcodeScanner(true);

                                                 }}

                                                 className="p-1.5 bg-slate-100 hover:bg-slate-200 rounded-lg text-slate-600 transition"

                                                 title="Scan with Camera"

                                               >

                                                 <Scan className="w-3.5 h-3.5" />

                                               </button>

                                             </div>

                                           </td>



                                           {/* 8. Own Image Toggle & Multi-Upload */}

                                           <td className="p-3 align-top">

                                             <div className="space-y-1.5">

                                               <label className="flex items-center gap-1.5 cursor-pointer text-[11px] font-semibold text-slate-700">

                                                 <input

                                                   type="checkbox"

                                                   checked={row.has_own_image}

                                                   onChange={(e) => {

                                                     const checked = e.target.checked;

                                                     updateVariantRow(rIdx, 'has_own_image', checked);

                                                   }}

                                                   className="rounded text-purple-600 focus:ring-purple-500"

                                                 />

                                                 <span>Custom Photos</span>

                                               </label>



                                               {row.has_own_image ? (

                                                 <div className="space-y-1.5">

                                                   {((row.images && row.images.length > 0) || row.image_url) ? (

                                                     <div>

                                                       <div className="flex items-center gap-1 mb-1">

                                                         <div className="flex items-center -space-x-1.5 overflow-hidden py-0.5">

                                                           {(row.images && row.images.length > 0 ? row.images : [row.image_url]).slice(0, 3).map((img, i) => (

                                                             <img

                                                               key={i}

                                                               src={img}

                                                               alt=""

                                                               className="w-7 h-7 rounded-lg object-cover border-2 border-white shadow-2xs"

                                                             />

                                                           ))}

                                                           {(row.images?.length || 1) > 3 && (

                                                             <span className="w-7 h-7 rounded-lg bg-purple-100 text-purple-800 text-[10px] font-bold border-2 border-white flex items-center justify-center shadow-2xs">

                                                               +{(row.images?.length || 1) - 3}

                                                             </span>

                                                           )}

                                                         </div>

                                                         <span className="text-[10px] font-bold text-slate-600">

                                                           {row.images?.length || 1} photo{(row.images?.length || 1) > 1 ? 's' : ''}

                                                         </span>

                                                       </div>



                                                       <div className="flex items-center gap-1">

                                                         <label className="cursor-pointer px-2 py-0.5 bg-slate-100 hover:bg-purple-100 text-slate-700 hover:text-purple-800 rounded text-[10px] font-bold transition flex items-center gap-1">

                                                           <UploadCloud className="w-3 h-3 text-purple-600" />

                                                           <span>+ Add</span>

                                                           <input

                                                             type="file"

                                                             multiple

                                                             accept="image/*"

                                                             onChange={(e) => handleVariantRowMultiImageUpload(rIdx, e.target.files)}

                                                             className="hidden"

                                                           />

                                                         </label>

                                                         <button

                                                           type="button"

                                                           onClick={() => handleOpenVariantDetailsModal(rIdx)}

                                                           className="px-2 py-0.5 bg-purple-50 hover:bg-purple-100 text-purple-700 rounded text-[10px] font-bold transition"

                                                           title="Manage variant photos"

                                                         >

                                                           Edit

                                                         </button>

                                                         <button

                                                           type="button"

                                                           onClick={() => {

                                                             updateVariantRow(rIdx, 'images', []);

                                                             updateVariantRow(rIdx, 'image_url', '');

                                                             updateVariantRow(rIdx, 'has_own_image', false);

                                                           }}

                                                           className="p-1 text-slate-400 hover:text-rose-600 rounded transition"

                                                           title="Clear variant photos"

                                                         >

                                                           <X className="w-3 h-3" />

                                                         </button>

                                                       </div>

                                                     </div>

                                                   ) : (

                                                     <div className="space-y-1">

                                                       <label className="cursor-pointer block text-center px-2 py-1 bg-purple-50 hover:bg-purple-100 border border-purple-200 text-purple-700 rounded text-[10px] font-bold transition">

                                                         <span>+ Upload Photos</span>

                                                         <input

                                                           type="file"

                                                           multiple

                                                           accept="image/*"

                                                           onChange={(e) => handleVariantRowMultiImageUpload(rIdx, e.target.files)}

                                                           className="hidden"

                                                         />

                                                       </label>

                                                       <button

                                                         type="button"

                                                         onClick={() => handleOpenVariantDetailsModal(rIdx)}

                                                         className="block w-full text-center text-[10px] text-purple-600 hover:underline"

                                                       >

                                                         or paste link

                                                       </button>

                                                     </div>

                                                   )}

                                                   {rowErr.image_url && (

                                                     <p className="text-[10px] text-rose-600">{rowErr.image_url}</p>

                                                   )}

                                                 </div>

                                               ) : (

                                                 <div className="text-[10px] text-slate-400 flex items-center gap-1 italic">

                                                   {productForm.images[0] && (

                                                     <img

                                                       src={productForm.images[0]}

                                                       alt=""

                                                       className="w-5 h-5 rounded object-cover opacity-60"

                                                     />

                                                   )}

                                                   <span>Uses family photo</span>

                                                 </div>

                                               )}

                                             </div>

                                           </td>



                                          {/* 9. Action (Edit per-variant details & Remove Row) */}

                                          <td className="p-3 align-top text-center">

                                            <div className="flex items-center justify-center gap-1">

                                              <button

                                                type="button"

                                                onClick={() => handleOpenVariantDetailsModal(rIdx)}

                                                className={`p-1.5 rounded-lg transition relative ${

                                                  hasCustom

                                                    ? 'text-purple-700 bg-purple-100 hover:bg-purple-200 border border-purple-300'

                                                    : 'text-slate-400 hover:text-purple-600 hover:bg-purple-50'

                                                }`}

                                                title={

                                                  hasCustom

                                                    ? 'Custom per-variant details configured (Click to edit)'

                                                    : 'Edit variant details (description, storage, photo)'

                                                }

                                              >

                                                <Pencil className="w-3.5 h-3.5" />

                                                {hasCustom && (

                                                  <span className="absolute -top-1 -right-1 w-2.5 h-2.5 bg-purple-600 rounded-full ring-2 ring-white" />

                                                )}

                                              </button>

                                              <button

                                                type="button"

                                                onClick={() => removeVariantTag(rIdx)}

                                                className="p-1.5 text-slate-400 hover:text-rose-600 hover:bg-rose-50 rounded-lg transition"

                                                title="Remove variant"

                                              >

                                                <Trash2 className="w-3.5 h-3.5" />

                                              </button>

                                            </div>

                                          </td>

                                        </tr>

                                      );

                                    })}

                                  </tbody>

                                </table>

                              </div>

                            </div>

                          ) : (

                            <div className="py-8 text-center text-xs text-slate-400 border-2 border-dashed border-slate-200 rounded-xl bg-slate-50/50">

                              <Layers className="w-6 h-6 mx-auto text-slate-300 mb-1" />

                              <span>Add size/qty option values above to configure your size and price options.</span>

                            </div>

                          )}

                        </div>

                      ) : (

                        /* ── SUB-BRANCH: ATTACH TO EXISTING VARIANT FAMILY ── */

                        <div className="space-y-4">

                          <div>

                            <label className="block text-xs font-bold text-slate-700 mb-1.5">

                              Select Existing Variant Family <span className="text-rose-500">*</span>

                            </label>

                            {variantGroups.length > 0 ? (

                              <select

                                value={productForm.variant_group}

                                onChange={(e) => setProductForm({ ...productForm, variant_group: e.target.value })}

                                className={`w-full px-4 py-2.5 bg-slate-50 border rounded-xl text-xs text-slate-900 focus:outline-none focus:bg-white transition-all ${

                                  formErrors.variant_group

                                    ? 'border-rose-500 ring-2 ring-rose-500/20'

                                    : 'border-slate-200 focus:border-emerald-600'

                                }`}

                              >

                                <option value="">-- Choose existing variant family --</option>

                                {variantGroups.map((g) => (

                                  <option key={g.id} value={g.id}>

                                    {g.group_title} ({g.variants_count} sibling{g.variants_count === 1 ? '' : 's'} • Selector: {g.variant_attribute_name})

                                  </option>

                                ))}

                              </select>

                            ) : (

                              <div className="p-4 bg-slate-50 rounded-xl border border-slate-200 text-xs text-slate-600 flex items-center justify-between">

                                <span>No existing variant families found in your account.</span>

                                <button

                                  type="button"

                                  onClick={() => setProductForm({ ...productForm, variant_group_mode: 'new' })}

                                  className="px-3 py-1.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-lg text-xs font-bold transition"

                                >

                                  Create New Family Now

                                </button>

                              </div>

                            )}

                            {formErrors.variant_group && (

                              <p className="text-xs text-rose-600 mt-1">{formErrors.variant_group}</p>

                            )}

                          </div>



                          {/* Option Label for Single SKU attach */}

                          <div>

                            <label className="block text-xs font-bold text-slate-700 mb-1.5">

                              Option Label for THIS Specific Product SKU <span className="text-rose-500">*</span>

                            </label>

                            <input

                              type="text"

                              placeholder="e.g. 50g, 100g, 1L, Pack of 3"

                              value={productForm.variant_label}

                              onChange={(e) => setProductForm({ ...productForm, variant_label: e.target.value })}

                              className={`w-full px-4 py-2.5 bg-slate-50 border rounded-xl text-xs text-slate-900 focus:outline-none focus:bg-white transition-all ${

                                formErrors.variant_label

                                  ? 'border-rose-500 ring-2 ring-rose-500/20'

                                  : 'border-slate-200 focus:border-emerald-600'

                              }`}

                            />

                            <p className="text-xs text-slate-500 mt-1">

                              This label will be printed on the customer selector chip (e.g. "50g").

                            </p>

                            {formErrors.variant_label && (

                              <p className="text-xs text-rose-600 mt-1">{formErrors.variant_label}</p>

                            )}

                          </div>

                        </div>

                      )}

                    </div>

                  ) : (

                    <p className="text-xs text-slate-500 italic">

                      This product is currently configured as a standalone catalog listing without size/quantity option chips. Enable the toggle switch above to group it with other sizes.

                    </p>

                  )}

                </div>



                {/* 6. Product Images & Media Card */}

                <div className="bg-white rounded-2xl border border-slate-200 shadow-2xs p-6 space-y-5">

                  <div className="border-b border-slate-100 pb-3">

                    <h3 className="text-sm font-bold text-slate-900 flex items-center gap-2">

                      <ImageIcon className="w-4 h-4 text-emerald-600" />

                      <span>Product Images & Media</span>

                    </h3>

                    <p className="text-xs text-slate-500 mt-0.5">

                      {isBatchVariantMode

                        ? 'Upload primary shared family photos (used across all sizes, unless a variant has custom photos)'

                        : 'Upload high-resolution packaging photos or provide direct image URLs (required for catalog review)'}

                    </p>

                  </div>



                  <MultiImageManager

                    images={productForm.images}

                    onChange={(newImages) => setProductForm({ ...productForm, images: newImages })}

                    token={token}

                    accentColor="emerald"

                    errorMessage={formErrors.images}

                    disabled={actionLoading}

                  />

                </div>



                {/* 7. Detailed Product Description Card */}

                <div className="bg-white rounded-2xl border border-slate-200 shadow-2xs p-6 space-y-4">

                  <div className="border-b border-slate-100 pb-3">

                    <h3 className="text-sm font-bold text-slate-900">Detailed Product Description</h3>

                    <p className="text-xs text-slate-500 mt-0.5">

                      Highlight key benefits, ingredients, usage directions, and customer FAQs

                    </p>

                  </div>



                  <textarea

                    rows={4}

                    placeholder="Enter full product description, features, dietary information, and customer usage instructions..."

                    value={productForm.description}

                    onChange={(e) => setProductForm({ ...productForm, description: e.target.value })}

                    className="w-full px-4 py-3 bg-slate-50 border border-slate-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-emerald-600 focus:bg-white transition-all leading-relaxed"

                  />

                </div>



                {/* ══════════════════════════════════════════════════════════════ */}

                {/* STICKY BOTTOM ACTION FOOTER                                    */}

                {/* ══════════════════════════════════════════════════════════════ */}

                <div className="sticky bottom-0 z-30 bg-white/95 backdrop-blur-md border-t border-slate-200 -mx-6 px-6 py-4 shadow-lg flex flex-col sm:flex-row sm:items-center justify-between gap-3">

                  <div className="flex items-center gap-2">

                    <button

                      type="button"

                      onClick={() => {

                        setCurrentStep(1);

                        window.scrollTo({ top: 0, behavior: 'smooth' });

                      }}

                      className="px-4 py-2.5 text-xs font-bold text-slate-700 bg-slate-100 hover:bg-slate-200 rounded-xl transition-colors"

                    >

                      &larr; Back to Category Selection

                    </button>

                    <Link

                      to="/workforce/seller-hub/catalog-uploads"

                      className="px-4 py-2.5 text-xs font-semibold text-slate-500 hover:text-slate-800 transition-colors"

                    >

                      Cancel

                    </Link>

                  </div>



                  <div className="flex items-center gap-3">

                    {/* Save as Draft */}

                    <button

                      type="button"

                      disabled={actionLoading}

                      onClick={() => handleSaveProduct(false)}

                      className="px-5 py-2.5 bg-slate-100 hover:bg-slate-200 text-slate-800 text-xs font-bold rounded-xl transition-all flex items-center gap-2 shadow-2xs disabled:opacity-50"

                    >

                      <Save className="w-4 h-4 text-slate-500" />

                      <span>

                        {isBatchVariantMode

                          ? `Save All Drafts (${variantRows.length || 0})`

                          : 'Save as Draft'}

                      </span>

                    </button>



                    {/* Submit for Review */}

                    <button

                      type="button"

                      disabled={actionLoading}

                      onClick={() => handleSaveProduct(true)}

                      className="px-6 py-2.5 bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-bold rounded-xl transition-all flex items-center gap-2 shadow-md shadow-emerald-600/20 disabled:opacity-50 cursor-pointer"

                    >

                      {actionLoading ? (

                        <>

                          <RefreshCw className="w-4 h-4 animate-spin" />

                          <span>Processing Batch...</span>

                        </>

                      ) : (

                        <>

                          <Send className="w-4 h-4" />

                          <span>

                            {isBatchVariantMode

                              ? `Submit Batch (${variantRows.length || 0} SKUs) for Review`

                              : 'Submit for Review'}

                          </span>

                        </>

                      )}

                    </button>

                  </div>

                </div>

              </form>

            )}

          </div>

        )}



        {/* ── MODAL: QUICK ADD SIBLING TO EXISTING FAMILY (EDIT MODE) ── */}

        {showAddSiblingModal && (

          <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto animate-in fade-in">

            <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl max-w-xl w-full p-6 space-y-5 animate-in zoom-in-95">

              <div className="flex items-center justify-between border-b border-slate-100 pb-3">

                <div className="flex items-center gap-2.5">

                  <div className="p-2 bg-indigo-50 text-indigo-700 rounded-xl">

                    <PlusCircle className="w-5 h-5" />

                  </div>

                  <div>

                    <h3 className="text-sm font-bold text-slate-900">

                      Add Another Size to Family

                    </h3>

                    <p className="text-[11px] text-slate-500">

                      Family: <strong>{variantGroupTitle || productForm.title}</strong>

                    </p>

                  </div>

                </div>

                <button

                  type="button"

                  onClick={() => setShowAddSiblingModal(false)}

                  className="text-slate-400 hover:text-slate-600 p-1"

                >

                  <X className="w-4 h-4" />

                </button>

              </div>



              <form onSubmit={handleAddSiblingSubmit} className="space-y-4 text-xs">

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">

                  {/* Option Label */}

                  <div>

                    <label className="block font-bold text-slate-700 mb-1">

                      Option Label (e.g. 250g) <span className="text-rose-500">*</span>

                    </label>

                    <input

                      type="text"

                      placeholder="e.g. 250g, 2L, Pack of 4"

                      value={newSiblingForm.variant_label}

                      onChange={(e) => {

                        const val = e.target.value;

                        setNewSiblingForm((prev) => ({

                          ...prev,

                          variant_label: val,

                          pack_size: prev.pack_size || val,

                          sku: prev.sku.endsWith('-')

                            ? `${prev.sku}${val.toUpperCase().replace(/[^A-Z0-9]+/g, '-')}`

                            : prev.sku,

                        }));

                      }}

                      className={`w-full px-3 py-2 bg-slate-50 border rounded-xl text-xs focus:outline-none focus:bg-white ${

                        newSiblingErrors.variant_label ? 'border-rose-500' : 'border-slate-200'

                      }`}

                    />

                    {newSiblingErrors.variant_label && (

                      <p className="text-[10px] text-rose-600 mt-0.5">{newSiblingErrors.variant_label}</p>

                    )}

                  </div>



                  {/* SKU */}

                  <div>

                    <label className="block font-bold text-slate-700 mb-1">

                      SKU (Store Unique) <span className="text-rose-500">*</span>

                    </label>

                    <input

                      type="text"

                      placeholder="e.g. COLG-TOT-250G"

                      value={newSiblingForm.sku}

                      onChange={(e) => setNewSiblingForm({ ...newSiblingForm, sku: e.target.value })}

                      className={`w-full px-3 py-2 bg-slate-50 border rounded-xl text-xs font-mono focus:outline-none focus:bg-white ${

                        newSiblingErrors.sku ? 'border-rose-500' : 'border-slate-200'

                      }`}

                    />

                    {newSiblingErrors.sku && (

                      <p className="text-[10px] text-rose-600 mt-0.5">{newSiblingErrors.sku}</p>

                    )}

                  </div>



                  {/* Pack Size */}

                  <div>

                    <label className="block font-bold text-slate-700 mb-1">Pack Size / Specs</label>

                    <input

                      type="text"

                      placeholder="e.g. 250g"

                      value={newSiblingForm.pack_size}

                      onChange={(e) => setNewSiblingForm({ ...newSiblingForm, pack_size: e.target.value })}

                      className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs focus:outline-none focus:bg-white"

                    />

                  </div>



                  {/* Barcode */}

                  <div>

                    <label className="block font-bold text-slate-700 mb-1">Barcode (Optional)</label>

                    <input

                      type="text"

                      placeholder="e.g. 890..."

                      value={newSiblingForm.barcode}

                      onChange={(e) => setNewSiblingForm({ ...newSiblingForm, barcode: e.target.value })}

                      className="w-full px-3 py-2 bg-slate-50 border border-slate-200 rounded-xl text-xs font-mono focus:outline-none focus:bg-white"

                    />

                  </div>



                  {/* MRP */}

                  <div>

                    <label className="block font-bold text-slate-700 mb-1">

                      MRP (₹) <span className="text-rose-500">*</span>

                    </label>

                    <input

                      type="number"

                      step="0.01"

                      placeholder="200.00"

                      value={newSiblingForm.mrp}

                      onChange={(e) => setNewSiblingForm({ ...newSiblingForm, mrp: e.target.value })}

                      className={`w-full px-3 py-2 bg-slate-50 border rounded-xl text-xs font-mono focus:outline-none focus:bg-white ${

                        newSiblingErrors.mrp ? 'border-rose-500' : 'border-slate-200'

                      }`}

                    />

                    {newSiblingErrors.mrp && (

                      <p className="text-[10px] text-rose-600 mt-0.5">{newSiblingErrors.mrp}</p>

                    )}

                  </div>



                  {/* Selling Price */}

                  <div>

                    <label className="block font-bold text-slate-700 mb-1">

                      Selling Price (₹) <span className="text-rose-500">*</span>

                    </label>

                    <input

                      type="number"

                      step="0.01"

                      placeholder="180.00"

                      value={newSiblingForm.selling_price}

                      onChange={(e) => setNewSiblingForm({ ...newSiblingForm, selling_price: e.target.value })}

                      className={`w-full px-3 py-2 bg-slate-50 border rounded-xl text-xs font-mono focus:outline-none focus:bg-white ${

                        newSiblingErrors.selling_price ? 'border-rose-500' : 'border-slate-200'

                      }`}

                    />

                    {newSiblingErrors.selling_price && (

                      <p className="text-[10px] text-rose-600 mt-0.5">{newSiblingErrors.selling_price}</p>

                    )}

                  </div>

                </div>



                <div className="p-4 bg-slate-50 rounded-2xl border border-slate-200 space-y-3">

                  <label className="flex items-center gap-2 cursor-pointer font-semibold text-slate-700">

                    <input

                      type="checkbox"

                      checked={newSiblingForm.has_own_image}

                      onChange={(e) => {

                        const checked = e.target.checked;

                        setNewSiblingForm((prev) => ({

                          ...prev,

                          has_own_image: checked,

                          images: checked ? prev.images : [],

                          image_url: checked ? prev.image_url : '',

                        }));

                      }}

                      className="rounded text-indigo-600 focus:ring-indigo-500"

                    />

                    <span>Upload specific photo(s) for this size (otherwise reuses family photo)</span>

                  </label>



                  {newSiblingForm.has_own_image && (

                    <div className="pt-2">

                      <MultiImageManager

                        images={newSiblingForm.images || (newSiblingForm.image_url ? [newSiblingForm.image_url] : [])}

                        onChange={(newImages) =>

                          setNewSiblingForm((prev) => ({

                            ...prev,

                            has_own_image: newImages.length > 0,

                            images: newImages,

                            image_url: newImages[0] || '',

                          }))

                        }

                        token={token}

                        accentColor="indigo"

                        disabled={newSiblingLoading}

                      />

                    </div>

                  )}

                </div>



                <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-100">

                  <button

                    type="button"

                    onClick={() => setShowAddSiblingModal(false)}

                    className="px-4 py-2 bg-slate-100 hover:bg-slate-200 rounded-xl text-slate-700 font-bold transition"

                  >

                    Cancel

                  </button>

                  <button

                    type="submit"

                    disabled={newSiblingLoading}

                    className="px-5 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl font-bold transition shadow-xs flex items-center gap-2"

                  >

                    {newSiblingLoading ? (

                      <>

                        <RefreshCw className="w-4 h-4 animate-spin" />

                        <span>Adding Size...</span>

                      </>

                    ) : (

                      <>

                        <Plus className="w-4 h-4" />

                        <span>Add Variant SKU</span>

                      </>

                    )}

                  </button>

                </div>

              </form>

            </div>

          </div>

        )}



        {/* Barcode Scanner Camera Modal */}

        <BarcodeScannerModal

          isOpen={showBarcodeScanner}

          onClose={() => {

            setShowBarcodeScanner(false);

            setActiveBarcodeScannerRowIndex(null);

            setTimeout(() => {

              barcodeInputRef.current?.focus();

            }, 50);

          }}

          onScan={(scannedBarcode) => {

            const clean = String(scannedBarcode).replace(/[\r\n\t]/g, '').trim();

            if (activeBarcodeScannerRowIndex !== null && variantRows[activeBarcodeScannerRowIndex]) {

              updateVariantRow(activeBarcodeScannerRowIndex, 'barcode', clean);

            } else {

              setProductForm((prev) => ({ ...prev, barcode: clean }));

              setTimeout(() => {

                barcodeInputRef.current?.focus();

              }, 50);

            }

            setSuccessMessage(`Scanned barcode: ${clean}`);

            setTimeout(() => setSuccessMessage(null), 3500);

          }}

          title="Scan Product Barcode"

          description="Point your device camera at the retail packaging barcode"

        />



        {/* ════════════════════════════════════════════════════════════════════ */}

        {/* PER-VARIANT SPECIFICATIONS & OVERRIDES MODAL                         */}

        {/* ════════════════════════════════════════════════════════════════════ */}

        {activeVariantModalIndex !== null && variantRows[activeVariantModalIndex] && (

          <div className="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center p-4 overflow-y-auto">

            <div className="bg-white rounded-2xl border border-slate-200 shadow-2xl max-w-2xl w-full my-8 overflow-hidden animate-in fade-in zoom-in-95 duration-150">

              {/* Modal Header */}

              <div className="px-6 py-4 border-b border-slate-200 flex items-center justify-between bg-slate-50/70">

                <div className="flex items-center gap-3">

                  <div className="p-2 bg-purple-100 text-purple-700 rounded-xl">

                    <Pencil className="w-4 h-4" />

                  </div>

                  <div>

                    <h3 className="font-bold text-slate-900 text-sm flex items-center gap-2">

                      <span>Per-Variant Specifications & Overrides</span>

                      <span className="px-2 py-0.5 rounded-md bg-purple-100 text-purple-800 font-mono text-xs font-bold">

                        {variantRows[activeVariantModalIndex].variant_label}

                      </span>

                    </h3>

                    <p className="text-[11px] text-slate-500 font-mono mt-0.5">

                      SKU: {variantRows[activeVariantModalIndex].sku || 'Unassigned'} • Pack Size: {variantRows[activeVariantModalIndex].pack_size || '—'}

                    </p>

                  </div>

                </div>

                <button

                  type="button"

                  onClick={() => setActiveVariantModalIndex(null)}

                  className="text-slate-400 hover:text-slate-600 p-1.5 rounded-lg hover:bg-slate-200 transition"

                >

                  <X className="w-5 h-5" />

                </button>

              </div>



              <div className="p-6 space-y-5 max-h-[75vh] overflow-y-auto">

                {/* SECTION 1: DESCRIPTION OVERRIDE */}

                <div className="space-y-3 p-4 bg-slate-50 rounded-2xl border border-slate-200">

                  <div className="flex items-center justify-between">

                    <div className="flex items-center gap-2">

                      <FileEdit className="w-4 h-4 text-slate-700" />

                      <span className="text-xs font-bold text-slate-800">Variant Description</span>

                    </div>

                    <label className="flex items-center gap-2 cursor-pointer select-none">

                      <input

                        type="checkbox"

                        checked={variantModalForm.has_custom_description}

                        onChange={(e) => {

                          const checked = e.target.checked;

                          setVariantModalForm((prev) => ({

                            ...prev,

                            has_custom_description: checked,

                            custom_description:

                              checked && !prev.custom_description

                                ? productForm.description

                                : prev.custom_description,

                          }));

                        }}

                        className="rounded text-purple-600 focus:ring-purple-500"

                      />

                      <span className="text-xs font-semibold text-slate-700">

                        Use a different description for this variant

                      </span>

                    </label>

                  </div>



                  {variantModalForm.has_custom_description ? (

                    <div className="space-y-1.5 pt-1">

                      <textarea

                        rows={3}

                        placeholder="Enter variant-specific description, pack contents, or usage details..."

                        value={variantModalForm.custom_description}

                        onChange={(e) =>

                          setVariantModalForm({ ...variantModalForm, custom_description: e.target.value })

                        }

                        className="w-full px-3.5 py-2.5 bg-white border border-purple-200 focus:border-purple-600 focus:ring-2 focus:ring-purple-600/10 rounded-xl text-xs text-slate-900 focus:outline-none transition"

                      />

                      <p className="text-[11px] text-purple-700">

                        Overrides family description specifically for SKU {variantRows[activeVariantModalIndex].sku}.

                      </p>

                    </div>

                  ) : (

                    <div className="p-3 bg-white/70 rounded-xl border border-slate-200 text-xs text-slate-500 space-y-1">

                      <div className="flex items-center gap-1.5 text-[11px] font-semibold text-slate-600">

                        <Info className="w-3.5 h-3.5 text-slate-400" />

                        <span>Uses shared family description:</span>

                      </div>

                      <p className="italic line-clamp-2 text-slate-600">

                        {productForm.description || '(No family description specified above yet)'}

                      </p>

                    </div>

                  )}

                </div>



                {/* SECTION 2: STORAGE & EXPIRY OVERRIDE */}

                <div className="space-y-3 p-4 bg-slate-50 rounded-2xl border border-slate-200">

                  <div className="flex items-center justify-between">

                    <div className="flex items-center gap-2">

                      <Tag className="w-4 h-4 text-slate-700" />

                      <span className="text-xs font-bold text-slate-800">Storage & Expiry Instructions</span>

                    </div>

                    <label className="flex items-center gap-2 cursor-pointer select-none">

                      <input

                        type="checkbox"

                        checked={variantModalForm.has_custom_storage}

                        onChange={(e) => {

                          const checked = e.target.checked;

                          setVariantModalForm((prev) => ({

                            ...prev,

                            has_custom_storage: checked,

                            custom_storage_info:

                              checked && !prev.custom_storage_info

                                ? productForm.storage_info

                                : prev.custom_storage_info,

                            custom_expiry_info:

                              checked && !prev.custom_expiry_info

                                ? productForm.expiry_info

                                : prev.custom_expiry_info,

                          }));

                        }}

                        className="rounded text-purple-600 focus:ring-purple-500"

                      />

                      <span className="text-xs font-semibold text-slate-700">

                        Use different storage/expiry for this variant

                      </span>

                    </label>

                  </div>



                  {variantModalForm.has_custom_storage ? (

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 pt-1">

                      <div>

                        <label className="block text-[11px] font-bold text-slate-700 mb-1">

                          Storage Instructions (This Variant)

                        </label>

                        <input

                          type="text"

                          placeholder="e.g. Keep refrigerated below 4°C"

                          value={variantModalForm.custom_storage_info}

                          onChange={(e) =>

                            setVariantModalForm({ ...variantModalForm, custom_storage_info: e.target.value })

                          }

                          className="w-full px-3 py-2 bg-white border border-purple-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-purple-600 transition"

                        />

                      </div>

                      <div>

                        <label className="block text-[11px] font-bold text-slate-700 mb-1">

                          Expiry / Shelf Life (This Variant)

                        </label>

                        <input

                          type="text"

                          placeholder="e.g. Best before 30 days from packing"

                          value={variantModalForm.custom_expiry_info}

                          onChange={(e) =>

                            setVariantModalForm({ ...variantModalForm, custom_expiry_info: e.target.value })

                          }

                          className="w-full px-3 py-2 bg-white border border-purple-200 rounded-xl text-xs text-slate-900 focus:outline-none focus:border-purple-600 transition"

                        />

                      </div>

                    </div>

                  ) : (

                    <div className="p-3 bg-white/70 rounded-xl border border-slate-200 text-xs text-slate-500 space-y-1">

                      <div className="flex items-center gap-1.5 text-[11px] font-semibold text-slate-600">

                        <Info className="w-3.5 h-3.5 text-slate-400" />

                        <span>Uses shared family storage info:</span>

                      </div>

                      <p className="text-slate-600">

                        <strong>Storage:</strong> {productForm.storage_info || '(Default)'} •{' '}

                        <strong>Expiry:</strong> {productForm.expiry_info || '(Default)'}

                      </p>

                    </div>

                  )}

                </div>



                {/* SECTION 3: VARIANT IMAGES & MEDIA */}

                <div className="space-y-3 p-4 bg-slate-50 rounded-2xl border border-slate-200">

                  <div className="flex items-center justify-between border-b border-slate-200 pb-2.5">

                    <div className="flex items-center gap-2">

                      <ImageIcon className="w-4 h-4 text-purple-700" />

                      <span className="text-xs font-bold text-slate-800">Variant-Specific Packaging Photos</span>

                    </div>

                    {variantModalForm.images?.length > 0 || variantModalForm.image_url ? (

                      <span className="text-[10px] font-bold px-2 py-0.5 rounded bg-purple-100 text-purple-800">

                        {variantModalForm.images?.length || 1} Custom photo(s) active

                      </span>

                    ) : (

                      <span className="text-[10px] text-slate-400 italic">

                        Uses shared family photos by default

                      </span>

                    )}

                  </div>



                  <MultiImageManager

                    images={variantModalForm.images || (variantModalForm.image_url ? [variantModalForm.image_url] : [])}

                    onChange={(newImages) =>

                      setVariantModalForm((prev) => ({

                        ...prev,

                        has_own_image: newImages.length > 0,

                        images: newImages,

                        image_url: newImages[0] || '',

                      }))

                    }

                    token={token}

                    accentColor="purple"

                    title="Variant Photos"

                    disabled={actionLoading}

                  />

                </div>

              </div>



              {/* Modal Footer */}

              <div className="px-6 py-4 border-t border-slate-200 bg-slate-50/70 flex items-center justify-between">

                <button

                  type="button"

                  onClick={() => setActiveVariantModalIndex(null)}

                  className="px-4 py-2 bg-white border border-slate-200 hover:bg-slate-100 rounded-xl text-slate-700 text-xs font-bold transition shadow-2xs"

                >

                  Cancel

                </button>

                <button

                  type="button"

                  onClick={handleSaveVariantDetailsModal}

                  className="px-5 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-xl text-xs font-bold transition shadow-xs flex items-center gap-1.5"

                >

                  <Check className="w-4 h-4" />

                  <span>Apply Details</span>

                </button>

              </div>

            </div>

          </div>

        )}

      </main>

    </div>

  );

}



export default SellerProductEditorPage;

