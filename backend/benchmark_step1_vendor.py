import os
import sys
import time
import django

# Force unbuffered output
sys.stdout.reconfigure(line_buffering=True)

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'workforce_core.settings')
django.setup()

from django.conf import settings
from rest_framework.test import APIRequestFactory, force_authenticate
from django.db import connection, reset_queries
from django.test.utils import CaptureQueriesContext
from django.contrib.auth import get_user_model

from companies.models import Company
from workforce_api.models import (
    SellerOrder,
    SellerOrderItem,
    SellerInventory,
    SellerProduct,
    SellerHubCategory,
    Warehouse,
    WorkforceSkill,
    SellerProductBasket,
    SellerProductBasketItem,
)
from employees.models import Employee
from service_requests.models import EmployeeJob

from workforce_api.views_seller_hub import (
    SellerOrderListView,
    SellerInventoryListView,
    SellerOrderAvailableRidersView,
    AdminCatalogCategoryListView,
)
from workforce_api.views_warehouse_portal import (
    WarehousePortalOrdersListView,
)
from workforce_api.views import (
    WorkforceJobListView,
    WorkforceDispatchRadarView,
    WorkforceSkillManageView,
    WorkforceCatalogListView,
)
from workforce_api.views_marketplace_integration import (
    MarketplaceProductListView,
    MarketplaceCategoryFeedView,
    MarketplaceBasketListView,
    MarketplaceBasketDetailView,
)

User = get_user_model()
admin_user = User.objects.filter(is_superuser=True).first()
if not admin_user:
    admin_user = User.objects.first()

seller_order = SellerOrder.objects.first()
sample_order_id = seller_order.id if seller_order else 1
sample_basket = SellerProductBasket.objects.first()
sample_basket_id = sample_basket.id if sample_basket else 1

secret = getattr(settings, "WORKFORCE_WEBHOOK_SECRET", "caldim_sevo_secret_2026")

factory = APIRequestFactory()

def profile_view(name, view_func, path, method="GET", user=None, data=None, query_params=None, headers=None, iterations=1):
    durations = []
    query_counts = []
    last_queries = []
    
    full_path = path
    if query_params:
        from urllib.parse import urlencode
        full_path = f"{path}?{urlencode(query_params)}"

    req_headers = {
        "HTTP_X_WORKFORCE_WEBHOOK_SECRET": secret,
        "HTTP_AUTHORIZATION": f"Bearer {secret}",
    }
    if headers:
        req_headers.update(headers)

    response = None
    for i in range(iterations):
        reset_queries()
        if method == "GET":
            req = factory.get(full_path, **req_headers)
        else:
            req = factory.post(full_path, data=data or {}, format="json", **req_headers)
        
        if user:
            force_authenticate(req, user=user)
        
        with CaptureQueriesContext(connection) as ctx:
            start = time.perf_counter()
            response = view_func(req)
            elapsed = (time.perf_counter() - start) * 1000.0  # ms
            
        durations.append(elapsed)
        query_counts.append(len(ctx.captured_queries))
        if i == iterations - 1:
            last_queries = ctx.captured_queries

    avg_ms = sum(durations) / len(durations)
    q_count = query_counts[-1]
    
    # Check status code
    status_code = getattr(response, "status_code", 200)
    data_len = 0
    if hasattr(response, "data"):
        if isinstance(response.data, dict):
            if "results" in response.data:
                data_len = len(response.data["results"])
            elif "count" in response.data:
                data_len = response.data["count"]
            else:
                data_len = len(response.data)
        elif isinstance(response.data, list):
            data_len = len(response.data)

    print(f"[{name}] -> Status: {status_code} | Returned items: {data_len} | Avg Time: {avg_ms:.2f} ms | SQL Queries: {q_count}", flush=True)
    return {
        "name": name,
        "status_code": status_code,
        "items": data_len,
        "avg_ms": avg_ms,
        "query_count": q_count,
        "queries": last_queries,
    }

def run_benchmarks():
    print("=" * 80, flush=True)
    print("RUNNING STEP 1 BENCHMARKS: SEVO-VENDOR BACKEND", flush=True)
    print("=" * 80, flush=True)
    
    results = []

    # 1. Seller Hub Orders list (page_size 20 vs 50 vs 100)
    order_view = SellerOrderListView.as_view()
    results.append(profile_view("1a. Seller Hub Orders (size=20)", order_view, "/api/workforce/seller-hub/orders/", user=admin_user, query_params={"page_size": 20}))
    results.append(profile_view("1b. Seller Hub Orders (size=50)", order_view, "/api/workforce/seller-hub/orders/", user=admin_user, query_params={"page_size": 50}))
    results.append(profile_view("1c. Seller Hub Orders (size=100)", order_view, "/api/workforce/seller-hub/orders/", user=admin_user, query_params={"page_size": 100}))

    # 2. Warehouse Portal Staging Orders list (page_size 20 vs 50 vs 100)
    wh_order_view = WarehousePortalOrdersListView.as_view()
    results.append(profile_view("2a. Warehouse Portal Orders (size=20)", wh_order_view, "/api/workforce/warehouse/orders/", user=admin_user, query_params={"page_size": 20}))
    results.append(profile_view("2b. Warehouse Portal Orders (size=50)", wh_order_view, "/api/workforce/warehouse/orders/", user=admin_user, query_params={"page_size": 50}))

    # 3. Seller Inventory list / stock page (size 20 vs 50)
    inv_view = SellerInventoryListView.as_view()
    results.append(profile_view("3a. Seller Inventory (size=20)", inv_view, "/api/workforce/seller-hub/inventory/", user=admin_user, query_params={"page_size": 20}))

    # 4. Dispatch Radar / Available Riders
    radar_view = WorkforceDispatchRadarView.as_view()
    results.append(profile_view("4a. Dispatch Radar", radar_view, "/api/workforce/admin/dispatch-radar/", user=admin_user))
    
    if sample_order_id:
        rider_view = lambda req: SellerOrderAvailableRidersView.as_view()(req, pk=sample_order_id)
        results.append(profile_view("4b. Order Available Riders", rider_view, f"/api/workforce/seller-hub/orders/{sample_order_id}/available-riders/", user=admin_user))

    # 5. Technician Jobs list (size 20 vs 50)
    jobs_view = WorkforceJobListView.as_view()
    results.append(profile_view("5a. Technician Jobs list (size=20)", jobs_view, "/api/workforce/jobs/", user=admin_user, query_params={"page_size": 20}))
    results.append(profile_view("5b. Technician Jobs list (size=50)", jobs_view, "/api/workforce/jobs/", user=admin_user, query_params={"page_size": 50}))

    # 6. Skills Master / Categories / Catalog
    skills_view = WorkforceSkillManageView.as_view()
    results.append(profile_view("6a. Skills Master List", skills_view, "/api/workforce/skills/", user=admin_user))
    
    cat_view = AdminCatalogCategoryListView.as_view()
    results.append(profile_view("6b. Categories List", cat_view, "/api/workforce/seller-hub/categories/", user=admin_user))
    
    catalog_view = WorkforceCatalogListView.as_view()
    results.append(profile_view("6c. Catalog Services List", catalog_view, "/api/workforce/catalog/", user=admin_user))

    # 7. Marketplace Products (Marketplace integration feed) (size=20 vs size=50)
    mkt_prod_view = MarketplaceProductListView.as_view()
    results.append(profile_view("7a. Marketplace Products Feed (size=20)", mkt_prod_view, "/api/workforce/marketplace/products/", query_params={"page_size": 20}))
    results.append(profile_view("7b. Marketplace Products Feed (size=50)", mkt_prod_view, "/api/workforce/marketplace/products/", query_params={"page_size": 50}))

    # 8. Marketplace Category Feed
    mkt_cat_view = MarketplaceCategoryFeedView.as_view()
    results.append(profile_view("8. Marketplace Category Feed", mkt_cat_view, "/api/workforce/marketplace/categories/"))

    # 11. Baskets / Combo offers list and detail
    basket_list_view = MarketplaceBasketListView.as_view()
    results.append(profile_view("11a. Marketplace Baskets List", basket_list_view, "/api/workforce/marketplace/baskets/"))
    if sample_basket_id:
        basket_detail_view = lambda req: MarketplaceBasketDetailView.as_view()(req, pk=sample_basket_id)
        results.append(profile_view("11b. Marketplace Basket Detail", basket_detail_view, f"/api/workforce/marketplace/baskets/{sample_basket_id}/"))

    print("\n" + "=" * 95, flush=True)
    print("STEP 1 VENDOR BENCHMARK SUMMARY TABLE", flush=True)
    print("=" * 95, flush=True)
    print(f"{'Endpoint':<42} | {'Items':<6} | {'Avg Time':<12} | {'Queries':<9}", flush=True)
    print("-" * 95, flush=True)
    for r in results:
        print(f"{r['name']:<42} | {r['items']:<6} | {r['avg_ms']:>8.2f} ms | {r['query_count']:>9}", flush=True)

if __name__ == "__main__":
    run_benchmarks()
