"""
workforce_api/views_seller_basket.py

Seller Hub Basket Offers (Multi-Product Combo Bundles) Management APIs:
- SellerProductBasketListView (GET list, POST create)
- SellerProductBasketDetailView (GET, PUT/PATCH, DELETE)
- SellerProductBasketActivateView (POST activate)
- SellerProductBasketPauseView (POST pause)
- SellerProductBasketCalculatePreviewView (POST preview calculate live totals)
"""
import logging
from decimal import Decimal, InvalidOperation
from django.db import transaction, models
from rest_framework import status, permissions
from rest_framework.views import APIView
from rest_framework.response import Response

from companies.models import Company
from workforce_api.models import (
    SellerProduct,
    SellerProductBasket,
    SellerProductBasketItem,
    SellerInventory,
)
from workforce_api.serializers import (
    SellerProductBasketSerializer,
    SellerProductBasketItemSerializer,
)

logger = logging.getLogger(__name__)


def _get_seller_company(user):
    """Resolve caller's authenticated seller company."""
    if not user or not user.is_authenticated:
        return None
    # 1. Direct company on user
    if getattr(user, "company", None):
        return user.company
    # 2. Company from employee profile
    emp = getattr(user, "employee_profile", None)
    if emp and getattr(emp, "company", None):
        return emp.company
    # 3. Superuser override if company_id query param passed
    return None


class SellerProductBasketCalculatePreviewView(APIView):
    """
    POST /api/workforce/seller-hub/baskets/calculate/
    Lightweight, server-side authoritative pricing & margin calculator preview.
    Does NOT write to database.
    Accepts:
      - items: [{"product_id": int, "quantity": int}]
      - pricing_mode: "MARGIN" | "FIXED_PRICE"
      - margin_percent: float/decimal (optional)
      - selling_price: float/decimal (optional)
    Returns:
      - total_mrp
      - total_procurement_price
      - selling_price
      - margin_percent
      - profit_amount (selling_price - total_procurement_price)
      - savings_vs_mrp (total_mrp - selling_price)
      - missing_procurement_products: list[str]
      - items_detail: list of item stats
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        company = _get_seller_company(request.user)
        is_admin = request.user.is_superuser or getattr(request.user, "is_staff", False)

        target_company_id = request.data.get("company_id")
        if is_admin and target_company_id:
            company = Company.objects.filter(id=target_company_id).first()

        items_payload = request.data.get("items", [])
        if not isinstance(items_payload, list) or len(items_payload) == 0:
            return Response(
                {
                    "item_count": 0,
                    "total_mrp": "0.00",
                    "total_procurement_price": "0.00",
                    "selling_price": "0.00",
                    "margin_percent": "0.00",
                    "profit_amount": "0.00",
                    "savings_vs_mrp": "0.00",
                    "missing_procurement_products": [],
                    "items_detail": [],
                },
                status=status.HTTP_200_OK,
            )

        product_ids = []
        qty_map = {}
        for it in items_payload:
            if isinstance(it, dict) and it.get("product_id"):
                try:
                    pid = int(it["product_id"])
                    qty = max(1, int(it.get("quantity", 1)))
                    product_ids.append(pid)
                    qty_map[pid] = qty
                except (ValueError, TypeError):
                    continue

        # Fetch products from company (or all if admin)
        qs = SellerProduct.objects.filter(id__in=product_ids).select_related("inventory", "company").prefetch_related("images")
        if company:
            qs = qs.filter(company=company)

        products = {p.id: p for p in qs}

        total_mrp = Decimal("0.00")
        total_procurement_price = Decimal("0.00")
        missing_procurement = []
        items_detail = []

        for pid in product_ids:
            p = products.get(pid)
            if not p:
                continue
            qty = Decimal(str(qty_map.get(pid, 1)))
            mrp = p.mrp or Decimal("0.00")
            total_mrp += mrp * qty

            if p.procurement_price is None:
                missing_procurement.append(p.title)
            else:
                total_procurement_price += p.procurement_price * qty

            inv = getattr(p, "inventory", None)
            avail_qty = max(Decimal("0.000"), (inv.on_hand_qty - inv.reserved_qty)) if inv else Decimal("0.000")
            primary_img = p.images.filter(is_primary=True).first() or p.images.first()

            items_detail.append({
                "product_id": p.id,
                "title": p.title,
                "sku": p.sku,
                "unit": p.unit,
                "mrp": str(p.mrp),
                "selling_price": str(p.selling_price),
                "procurement_price": str(p.procurement_price) if p.procurement_price is not None else None,
                "quantity": qty_map.get(pid, 1),
                "available_qty": int(avail_qty) if (avail_qty % 1) == 0 else float(avail_qty),
                "image_url": primary_img.image_url if primary_img else "",
                "status": p.status,
            })

        pricing_mode = str(request.data.get("pricing_mode", "MARGIN")).upper()
        margin_percent_val = request.data.get("margin_percent")
        selling_price_val = request.data.get("selling_price")

        computed_selling_price = Decimal("0.00")
        computed_margin_percent = Decimal("0.00")

        if pricing_mode == "MARGIN":
            try:
                margin_dec = Decimal(str(margin_percent_val)) if margin_percent_val is not None else Decimal("10.00")
            except (InvalidOperation, TypeError, ValueError):
                margin_dec = Decimal("0.00")
            computed_margin_percent = margin_dec
            mult = Decimal("1.00") + (margin_dec / Decimal("100.00"))
            computed_selling_price = (total_procurement_price * mult).quantize(Decimal("0.01"))
        else:  # FIXED_PRICE
            try:
                sp_dec = Decimal(str(selling_price_val)) if selling_price_val is not None else Decimal("0.00")
            except (InvalidOperation, TypeError, ValueError):
                sp_dec = Decimal("0.00")
            computed_selling_price = sp_dec.quantize(Decimal("0.01"))
            if total_procurement_price > Decimal("0.00"):
                computed_margin_percent = (((sp_dec - total_procurement_price) / total_procurement_price) * Decimal("100.00")).quantize(Decimal("0.01"))
            else:
                computed_margin_percent = Decimal("0.00")

        profit_amount = (computed_selling_price - total_procurement_price).quantize(Decimal("0.01"))
        savings_vs_mrp = max(Decimal("0.00"), total_mrp - computed_selling_price).quantize(Decimal("0.01"))

        return Response({
            "item_count": len(items_detail),
            "total_mrp": str(total_mrp),
            "total_procurement_price": str(total_procurement_price),
            "selling_price": str(computed_selling_price),
            "margin_percent": str(computed_margin_percent),
            "profit_amount": str(profit_amount),
            "savings_vs_mrp": str(savings_vs_mrp),
            "missing_procurement_products": missing_procurement,
            "items_detail": items_detail,
        }, status=status.HTTP_200_OK)


class SellerProductBasketListView(APIView):
    """
    GET /api/workforce/seller-hub/baskets/ - List baskets for caller seller.
    POST /api/workforce/seller-hub/baskets/ - Create a new basket offer with items.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        company = _get_seller_company(request.user)
        is_admin = request.user.is_superuser or getattr(request.user, "is_staff", False)

        if not company and not is_admin:
            return Response({"error": "No associated seller company found."}, status=status.HTTP_403_FORBIDDEN)

        target_company_id = request.query_params.get("company_id")
        if is_admin and target_company_id:
            company = Company.objects.filter(id=target_company_id).first()

        queryset = SellerProductBasket.objects.all().prefetch_related(
            "items__product__images",
            "items__product__inventory",
            "items__product__company",
        )
        if company:
            queryset = queryset.filter(company=company)

        status_filter = request.query_params.get("status")
        if status_filter:
            queryset = queryset.filter(status=status_filter.upper())

        search = request.query_params.get("search") or request.query_params.get("q")
        if search:
            queryset = queryset.filter(
                models.Q(title__icontains=search) | models.Q(description__icontains=search)
            )

        baskets = list(queryset)

        # Dynamic stock synchronization: If active basket has stock deficits, update/return out of stock
        for b in baskets:
            if b.status == SellerProductBasket.Status.ACTIVE:
                is_avail, _, _ = b.check_availability()
                if not is_avail:
                    b.status = SellerProductBasket.Status.OUT_OF_STOCK
                    b.save(update_fields=["status", "updated_at"])
            elif b.status == SellerProductBasket.Status.OUT_OF_STOCK:
                is_avail, _, _ = b.check_availability()
                if is_avail:
                    b.status = SellerProductBasket.Status.ACTIVE
                    b.save(update_fields=["status", "updated_at"])

        serializer = SellerProductBasketSerializer(baskets, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def post(self, request):
        company = _get_seller_company(request.user)
        is_admin = request.user.is_superuser or getattr(request.user, "is_staff", False)

        target_company_id = request.data.get("company_id")
        if is_admin and target_company_id:
            company = Company.objects.filter(id=target_company_id).first()

        if not company:
            return Response({"error": "Seller company is required."}, status=status.HTTP_400_BAD_REQUEST)

        title = str(request.data.get("title", "")).strip()
        if not title:
            return Response({"error": "Basket title is required."}, status=status.HTTP_400_BAD_REQUEST)

        items_payload = request.data.get("items", [])
        if not isinstance(items_payload, list) or len(items_payload) < 3:
            return Response(
                {"error": "A basket offer must contain at least 3 distinct products.", "code": "MIN_ITEMS_REQUIRED"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Parse and validate distinct products
        product_qtys = {}
        for it in items_payload:
            if not isinstance(it, dict) or "product_id" not in it:
                continue
            try:
                pid = int(it["product_id"])
                qty = max(1, int(it.get("quantity", 1)))
                product_qtys[pid] = qty
            except (ValueError, TypeError):
                continue

        if len(product_qtys) < 3:
            return Response(
                {"error": "A basket offer must contain at least 3 distinct products.", "code": "MIN_ITEMS_REQUIRED"},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Fetch products and verify company scoping and approval
        prods = list(SellerProduct.objects.filter(id__in=product_qtys.keys()).select_related("inventory"))
        if len(prods) < len(product_qtys):
            return Response(
                {"error": "One or more selected products were not found in the catalog.", "code": "PRODUCT_NOT_FOUND"},
                status=status.HTTP_400_BAD_REQUEST
            )

        for p in prods:
            if p.company_id != company.id:
                return Response(
                    {"error": f"Product '{p.title}' does not belong to your store.", "code": "CROSS_COMPANY_PRODUCT"},
                    status=status.HTTP_400_BAD_REQUEST
                )
            if p.status != SellerProduct.Status.APPROVED:
                return Response(
                    {"error": f"Product '{p.title}' is not approved (Current status: {p.status}). Only approved products can be bundled in baskets.", "code": "PRODUCT_NOT_APPROVED"},
                    status=status.HTTP_400_BAD_REQUEST
                )

        pricing_mode = str(request.data.get("pricing_mode", "MARGIN")).upper()
        if pricing_mode not in (SellerProductBasket.PricingMode.MARGIN, SellerProductBasket.PricingMode.FIXED_PRICE):
            pricing_mode = SellerProductBasket.PricingMode.MARGIN

        margin_percent_val = request.data.get("margin_percent")
        selling_price_val = request.data.get("selling_price")

        target_status = str(request.data.get("target_status") or request.data.get("status") or "DRAFT").upper()
        if target_status not in (SellerProductBasket.Status.DRAFT, SellerProductBasket.Status.ACTIVE, SellerProductBasket.Status.PAUSED):
            target_status = SellerProductBasket.Status.DRAFT

        # If activating immediately, enforce procurement prices on all products
        if target_status == SellerProductBasket.Status.ACTIVE:
            missing_proc = [p.title for p in prods if p.procurement_price is None]
            if missing_proc:
                return Response(
                    {
                        "error": f"Cannot activate basket: the following products are missing procurement prices: {', '.join(missing_proc)}. Please update their cost prices first.",
                        "code": "MISSING_PROCUREMENT_PRICE",
                        "missing_products": missing_proc,
                    },
                    status=status.HTTP_400_BAD_REQUEST
                )

        with transaction.atomic():
            basket = SellerProductBasket.objects.create(
                company=company,
                created_by=request.user,
                title=title,
                description=str(request.data.get("description", "")).strip(),
                image_url=str(request.data.get("image_url", "")).strip(),
                pricing_mode=pricing_mode,
                margin_percent=Decimal(str(margin_percent_val)) if margin_percent_val is not None else None,
                selling_price=Decimal(str(selling_price_val)) if selling_price_val is not None else Decimal("0.00"),
                status=SellerProductBasket.Status.DRAFT,
            )

            for pid, qty in product_qtys.items():
                SellerProductBasketItem.objects.create(
                    basket=basket,
                    product_id=pid,
                    quantity=qty,
                )

            # Authoritative server-side recalculation
            basket.recalculate_totals(save=True)

            if target_status == SellerProductBasket.Status.ACTIVE:
                is_avail, _, reasons = basket.check_availability()
                if not is_avail:
                    basket.status = SellerProductBasket.Status.OUT_OF_STOCK
                else:
                    basket.status = SellerProductBasket.Status.ACTIVE
                basket.save(update_fields=["status", "updated_at"])

        refreshed = SellerProductBasket.objects.prefetch_related("items__product__images", "items__product__inventory").get(id=basket.id)
        serializer = SellerProductBasketSerializer(refreshed)
        return Response(serializer.data, status=status.HTTP_201_CREATED)


class SellerProductBasketDetailView(APIView):
    """
    GET /api/workforce/seller-hub/baskets/<id>/ - Retrieve basket details.
    PUT / PATCH /api/workforce/seller-hub/baskets/<id>/ - Update basket & items.
    DELETE /api/workforce/seller-hub/baskets/<id>/ - Delete basket.
    """
    permission_classes = [permissions.IsAuthenticated]

    def _get_basket(self, request, pk):
        company = _get_seller_company(request.user)
        is_admin = request.user.is_superuser or getattr(request.user, "is_staff", False)
        qs = SellerProductBasket.objects.prefetch_related(
            "items__product__images",
            "items__product__inventory",
            "items__product__company",
        )
        if not is_admin:
            if not company:
                return None
            qs = qs.filter(company=company)
        return qs.filter(pk=pk).first()

    def get(self, request, pk):
        basket = self._get_basket(request, pk)
        if not basket:
            return Response({"error": "Basket offer not found."}, status=status.HTTP_404_NOT_FOUND)
        serializer = SellerProductBasketSerializer(basket)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def patch(self, request, pk):
        basket = self._get_basket(request, pk)
        if not basket:
            return Response({"error": "Basket offer not found."}, status=status.HTTP_404_NOT_FOUND)

        data = request.data
        if "title" in data:
            val = str(data["title"]).strip()
            if not val:
                return Response({"error": "Basket title cannot be empty."}, status=status.HTTP_400_BAD_REQUEST)
            basket.title = val

        if "description" in data:
            basket.description = str(data["description"]).strip()

        if "image_url" in data:
            basket.image_url = str(data["image_url"]).strip()

        if "pricing_mode" in data:
            pm = str(data["pricing_mode"]).upper()
            if pm in (SellerProductBasket.PricingMode.MARGIN, SellerProductBasket.PricingMode.FIXED_PRICE):
                basket.pricing_mode = pm

        if "margin_percent" in data:
            try:
                basket.margin_percent = Decimal(str(data["margin_percent"])) if data["margin_percent"] is not None else None
            except Exception:
                pass

        if "selling_price" in data:
            try:
                basket.selling_price = Decimal(str(data["selling_price"])) if data["selling_price"] is not None else Decimal("0.00")
            except Exception:
                pass

        with transaction.atomic():
            if "items" in data and isinstance(data["items"], list):
                items_payload = data["items"]
                if len(items_payload) < 3:
                    return Response(
                        {"error": "A basket offer must contain at least 3 distinct products.", "code": "MIN_ITEMS_REQUIRED"},
                        status=status.HTTP_400_BAD_REQUEST
                    )

                product_qtys = {}
                for it in items_payload:
                    if isinstance(it, dict) and "product_id" in it:
                        try:
                            pid = int(it["product_id"])
                            qty = max(1, int(it.get("quantity", 1)))
                            product_qtys[pid] = qty
                        except (ValueError, TypeError):
                            continue

                if len(product_qtys) < 3:
                    return Response(
                        {"error": "A basket offer must contain at least 3 distinct products.", "code": "MIN_ITEMS_REQUIRED"},
                        status=status.HTTP_400_BAD_REQUEST
                    )

                prods = list(SellerProduct.objects.filter(id__in=product_qtys.keys()))
                for p in prods:
                    if p.company_id != basket.company_id:
                        return Response(
                            {"error": f"Product '{p.title}' does not belong to your store.", "code": "CROSS_COMPANY_PRODUCT"},
                            status=status.HTTP_400_BAD_REQUEST
                        )
                    if p.status != SellerProduct.Status.APPROVED:
                        return Response(
                            {"error": f"Product '{p.title}' is not approved (Status: {p.status}).", "code": "PRODUCT_NOT_APPROVED"},
                            status=status.HTTP_400_BAD_REQUEST
                        )

                basket.items.all().delete()
                for pid, qty in product_qtys.items():
                    SellerProductBasketItem.objects.create(
                        basket=basket,
                        product_id=pid,
                        quantity=qty,
                    )

            basket.recalculate_totals(save=True)

            if "status" in data:
                st = str(data["status"]).upper()
                if st == SellerProductBasket.Status.ACTIVE:
                    is_avail, _, reasons = basket.check_availability()
                    if not is_avail:
                        return Response(
                            {"error": f"Cannot activate basket: {'; '.join(reasons)}", "reasons": reasons},
                            status=status.HTTP_400_BAD_REQUEST
                        )
                    basket.status = SellerProductBasket.Status.ACTIVE
                elif st in (SellerProductBasket.Status.DRAFT, SellerProductBasket.Status.PAUSED):
                    basket.status = st
                basket.save(update_fields=["status", "updated_at"])

        refreshed = SellerProductBasket.objects.prefetch_related("items__product__images", "items__product__inventory").get(id=basket.id)
        serializer = SellerProductBasketSerializer(refreshed)
        return Response(serializer.data, status=status.HTTP_200_OK)

    def put(self, request, pk):
        return self.patch(request, pk)

    def delete(self, request, pk):
        basket = self._get_basket(request, pk)
        if not basket:
            return Response({"error": "Basket offer not found."}, status=status.HTTP_404_NOT_FOUND)
        basket_id = basket.id
        basket.delete()
        return Response({"message": f"Basket offer #{basket_id} deleted successfully."}, status=status.HTTP_200_OK)


class SellerProductBasketActivateView(APIView):
    """
    POST /api/workforce/seller-hub/baskets/<id>/activate/
    Validates readiness and sets status to ACTIVE.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        company = _get_seller_company(request.user)
        is_admin = request.user.is_superuser or getattr(request.user, "is_staff", False)
        qs = SellerProductBasket.objects.filter(pk=pk)
        if not is_admin and company:
            qs = qs.filter(company=company)
        basket = qs.first()
        if not basket:
            return Response({"error": "Basket offer not found."}, status=status.HTTP_404_NOT_FOUND)

        is_avail, _, reasons = basket.check_availability()
        if not is_avail:
            return Response(
                {
                    "error": f"Cannot activate basket: {'; '.join(reasons)}",
                    "code": "ACTIVATION_FAILED",
                    "reasons": reasons,
                },
                status=status.HTTP_400_BAD_REQUEST
            )

        basket.status = SellerProductBasket.Status.ACTIVE
        basket.recalculate_totals(save=True)
        basket.save(update_fields=["status", "updated_at"])

        refreshed = SellerProductBasket.objects.prefetch_related("items__product__images", "items__product__inventory").get(id=basket.id)
        serializer = SellerProductBasketSerializer(refreshed)
        return Response({"message": "Basket activated successfully.", "basket": serializer.data}, status=status.HTTP_200_OK)


class SellerProductBasketPauseView(APIView):
    """
    POST /api/workforce/seller-hub/baskets/<id>/pause/
    Pauses an active basket offer.
    """
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        company = _get_seller_company(request.user)
        is_admin = request.user.is_superuser or getattr(request.user, "is_staff", False)
        qs = SellerProductBasket.objects.filter(pk=pk)
        if not is_admin and company:
            qs = qs.filter(company=company)
        basket = qs.first()
        if not basket:
            return Response({"error": "Basket offer not found."}, status=status.HTTP_404_NOT_FOUND)

        basket.status = SellerProductBasket.Status.PAUSED
        basket.save(update_fields=["status", "updated_at"])
        return Response({"message": "Basket paused successfully.", "status": basket.status}, status=status.HTTP_200_OK)
