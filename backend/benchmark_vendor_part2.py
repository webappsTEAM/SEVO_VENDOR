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
    AdminCatalogCategoryListView,
)
from workforce_api.views import (
    WorkforceJobListView,
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

tech_emp = Employee.objects.filter(is_active=True).first()
tech_user = tech_emp.user if tech_emp else admin_user

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
    print("RUNNING STEP 1 BENCHMARKS: SEVO-VENDOR (PART 2)", flush=True)
    print("=" * 80, flush=True)
    
    results = []

    # 5. Technician Jobs list (with technician user)
    jobs_view = WorkforceJobListView.as_view()
    results.append(profile_view("5a. Technician Jobs list (technician role)", jobs_view, "/api/workforce/jobs/", user=tech_user, query_params={"page_size": 20}))

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

if __name__ == "__main__":
    run_benchmarks()
