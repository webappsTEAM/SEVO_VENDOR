"""
accounts/platform.py

Shared platform admin identity resolution.
Used identically across accounts login/me responses and workforce API authorization checks.
"""


PLATFORM_COMPANY_ID = 1
PLATFORM_COMPANY_SLUGS = frozenset({
    "calservices",
    "caldim-platform",
    "caldim-engineering-pvt-ltd",
    "caldim-services",
})


def is_platform_company(company_or_id) -> bool:
    """
    Evaluates whether a company (or company ID) represents the platform/system tenant.
    """
    if not company_or_id:
        return False
    if isinstance(company_or_id, int):
        if company_or_id == PLATFORM_COMPANY_ID:
            return True
        try:
            from companies.models import Company
            slug = Company.objects.filter(id=company_or_id).values_list("slug", flat=True).first()
            return bool(slug and slug in PLATFORM_COMPANY_SLUGS)
        except Exception:
            return False
    if isinstance(company_or_id, str):
        if company_or_id.isdigit():
            return is_platform_company(int(company_or_id))
        return company_or_id in PLATFORM_COMPANY_SLUGS

    cid = getattr(company_or_id, "id", None)
    slug = getattr(company_or_id, "slug", "") or ""
    return bool(cid == PLATFORM_COMPANY_ID or slug in PLATFORM_COMPANY_SLUGS)


def is_platform_admin_user(user) -> bool:
    """
    Evaluates whether an authenticated user is a platform administrator.
    A user is considered a platform administrator if:
      - is_superuser is True
      - OR (is_staff is True and user belongs to platform company)
      - OR role in ('superadmin', 'platform_admin')
      - OR (role in ('admin', 'manager') and user belongs to platform company)
    """
    if not user or not getattr(user, "is_authenticated", False):
        return False

    company_id = getattr(user, "company_id", None)
    if company_id is None and hasattr(user, "company") and user.company is not None:
        company_id = getattr(user.company, "id", None)

    role = str(getattr(user, "role", "") or "").strip().lower()
    is_super = bool(getattr(user, "is_superuser", False))
    is_staff = bool(getattr(user, "is_staff", False))

    is_plat_company = is_platform_company(company_id)

    return bool(
        is_super
        or (is_staff and is_plat_company)
        or role in ("superadmin", "platform_admin")
        or (role in ("admin", "manager") and is_plat_company)
    )

