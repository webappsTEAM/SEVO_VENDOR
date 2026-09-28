"""
Commercial policy resolution.

Everything here answers a question that used to be answered by a literal in the
code: what does the consultation cost, does this quote need admin eyes before
the customer sees it, how much is payable up front. The answers now come from
WorkforceServicePricingPolicy, which a SEVO admin edits in the app.

Categories are matched case-insensitively, and an unknown category falls back
to a permissive default rather than raising -- a service nobody has configured
yet must still be bookable.
"""
import logging
from decimal import Decimal

from workforce_api.models import WorkforceServicePricingPolicy

logger = logging.getLogger(__name__)

ZERO = Decimal("0.00")
CENT = Decimal("0.01")

# Used when no policy row exists for a category. Deliberately matches the
# behaviour of the code before policies existed: no consultation fee, no
# pre-send threshold, full payment up front, admin approval on.
DEFAULT_POLICY = {
    "consultation_fee_mode": WorkforceServicePricingPolicy.ConsultationFeeMode.FREE,
    "consultation_fee_amount": ZERO,
    "high_value_review_threshold": None,
    "requires_admin_approval": True,
    "advance_percent": Decimal("100.00"),
    "allow_customer_supplied_materials": False,
}


CATEGORY_ALIASES = {
    "paintings": ["paintings", "painting", "interior painting", "exterior painting", "waterproofing", "wood & metal", "texture decor"],
    "painting": ["painting", "paintings", "interior painting", "exterior painting", "waterproofing", "wood & metal", "texture decor"],
    "interior painting": ["interior painting", "painting", "paintings"],
    "exterior painting": ["exterior painting", "painting", "paintings", "waterproofing"],
    "waterproofing": ["waterproofing", "painting", "paintings", "exterior painting"],
    "mason": ["mason", "masonry", "tile fixing", "bathroom tile fixing", "plastering", "civil work"],
    "masonry": ["masonry", "mason", "tile fixing", "bathroom tile fixing", "plastering", "civil work"],
    "tile fixing": ["tile fixing", "masonry", "mason", "bathroom tile fixing"],
    "bathroom tile fixing": ["bathroom tile fixing", "tile fixing", "masonry", "mason"],
}


def _normalise(category):
    return str(category or "").strip().lower()


def policy_for(category):
    """The policy row for a service category, or None."""
    key = _normalise(category)
    if not key:
        return None
    # 1. Exact case-insensitive match
    direct = (
        WorkforceServicePricingPolicy.objects
        .filter(service_category__iexact=key, is_active=True)
        .first()
    )
    if direct:
        return direct
    # 2. Canonical alias lookup (e.g. paintings <-> painting, mason <-> masonry)
    candidates = CATEGORY_ALIASES.get(key, [])
    if candidates:
        for cand in candidates:
            alias_pol = (
                WorkforceServicePricingPolicy.objects
                .filter(service_category__iexact=cand, is_active=True)
                .first()
            )
            if alias_pol:
                return alias_pol
    # 3. Substring match fallback (e.g. "painting" in "Interior Painting")
    for pol in WorkforceServicePricingPolicy.objects.filter(is_active=True):
        p_key = _normalise(pol.service_category)
        if p_key and (p_key in key or key in p_key):
            return pol
    return None


DEFAULT_TECHNICIAN_FREE_CANCEL_MINUTES = 5


def technician_cancel_window_minutes(category):
    """Minutes after acceptance during which the assigned technician may
    cancel without penalty. Falls back to 5 (the previously hardcoded value)
    when no active policy exists or the lookup fails, so a DB hiccup can
    never widen or close the window unexpectedly."""
    try:
        policy = policy_for(category)
    except Exception:  # pragma: no cover - defensive
        logger.exception("technician_cancel_window_minutes: policy lookup failed")
        policy = None
    value = getattr(policy, "technician_free_cancel_minutes", None) if policy else None
    if value is None:
        return DEFAULT_TECHNICIAN_FREE_CANCEL_MINUTES
    return max(0, int(value))


def policy_value(category, field):
    policy = policy_for(category)
    if policy is None:
        return DEFAULT_POLICY[field]
    return getattr(policy, field)


# --------------------------------------------------------------------------- #
# consultation fee
# --------------------------------------------------------------------------- #
def consultation_fee_for(category, latitude=None, longitude=None, vendor=None):
    """
    What the customer pays for the site visit based on dynamic dual-radius rules.

    Returns (amount, explanation) -- the explanation is stored on the fee record
    so a customer questioning the charge can be given a straight answer months
    later, rather than someone re-deriving it from the code.
    """
    fee, explanation, _is_serviceable, _dist = evaluate_serviceability(
        category, latitude=latitude, longitude=longitude, vendor=vendor
    )
    return fee, explanation


def evaluate_serviceability(category, latitude=None, longitude=None, vendor=None):
    """
    Authoritative dual-radius serviceability & consultation pricing evaluator.
    Anchored against the Vendor's registered base location (or central policy hub).

    Returns:
        (fee: Decimal, explanation: str, is_serviceable: bool, distance_km: Optional[float])
    """
    policy = policy_for(category)
    if policy is None:
        return ZERO, "No pricing policy configured for this category; consultation free.", True, None

    mode = policy.consultation_fee_mode
    Mode = WorkforceServicePricingPolicy.ConsultationFeeMode

    if mode == Mode.FREE:
        return ZERO, "Consultation is free for this category.", True, None

    if mode == Mode.FLAT:
        return (
            Decimal(policy.consultation_fee_amount).quantize(CENT),
            f"Flat consultation fee for {policy.service_category}.",
            True,
            None,
        )

    # DISTANCE_BAND
    if latitude is None or longitude is None:
        # No coordinates is not a licence to charge: default to the free side,
        # and say so, rather than silently billing the customer for a distance
        # nobody measured.
        return ZERO, "Site coordinates unavailable; distance-based fee waived.", True, None

    # Resolve anchor coordinates (Vendor Base Location or Policy Hub)
    anchor_lat = policy.hub_latitude
    anchor_lon = policy.hub_longitude
    max_radius = float(getattr(policy, "max_service_radius_km", 50.00) or 50.00)
    free_radius = float(getattr(policy, "free_radius_km", 15.00) or 15.00)
    beyond_amount = Decimal(str(policy.beyond_radius_amount or 300.00)).quantize(CENT)

    if vendor is not None:
        from workforce_api.models import WorkforceVendorBaseLocation
        v_base = None
        if hasattr(vendor, "base_locations"):
            v_base = vendor.base_locations.filter(is_active=True).first()
        elif hasattr(vendor, "company") and getattr(vendor, "company", None):
            v_base = WorkforceVendorBaseLocation.objects.filter(company=vendor.company, is_active=True).first()
        elif hasattr(vendor, "employee") and getattr(vendor, "employee", None):
            v_base = WorkforceVendorBaseLocation.objects.filter(employee=vendor.employee, is_active=True).first()

        if v_base:
            anchor_lat = v_base.base_latitude
            anchor_lon = v_base.base_longitude
            if v_base.max_service_radius_km:
                max_radius = float(v_base.max_service_radius_km)

    distance_km = _haversine_km(
        anchor_lat, anchor_lon, float(latitude), float(longitude)
    )

    # 1. Check max operating radius
    if distance_km > max_radius:
        return (
            beyond_amount,
            f"Site is {distance_km:.1f} km from base/hub, which exceeds the maximum serviceable radius of {max_radius:.1f} km.",
            False,
            distance_km,
        )

    # 2. Free zone (0 to free_radius_km, default 15 km)
    if distance_km <= free_radius:
        return (
            ZERO,
            f"Site is {distance_km:.1f} km from base/hub, within the {free_radius:.1f} km free consultation zone.",
            True,
            distance_km,
        )

    # 3. Beyond free zone (15 to 50 km, default ₹300)
    return (
        beyond_amount,
        f"Site is {distance_km:.1f} km from base/hub (between {free_radius:.1f} km and {max_radius:.1f} km).",
        True,
        distance_km,
    )


def _haversine_km(lat1, lon1, lat2, lon2):
    from math import asin, cos, radians, sin, sqrt

    r = 6371.0
    dlat = radians(lat2 - lat1)
    dlon = radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return 2 * r * asin(sqrt(a))


# --------------------------------------------------------------------------- #
# gates and schedule
# --------------------------------------------------------------------------- #
def needs_pre_send_review(category, amount):
    """Whether a quote of this size must be seen by an admin before it is sent."""
    threshold = policy_value(category, "high_value_review_threshold")
    if threshold is None:
        return False, None
    return Decimal(str(amount or 0)) > Decimal(threshold), Decimal(threshold)


def requires_admin_approval(category):
    return bool(policy_value(category, "requires_admin_approval"))


def advance_percent(category):
    return Decimal(str(policy_value(category, "advance_percent")))


def allows_customer_supplied_materials(category):
    return bool(policy_value(category, "allow_customer_supplied_materials"))


def split_advance_and_balance(total, category, percent=None):
    """(advance, balance) for a total. `percent` overrides the category default."""
    total = Decimal(str(total or 0)).quantize(CENT)
    pct = Decimal(str(percent)) if percent is not None else advance_percent(category)
    if pct >= Decimal("100"):
        return total, ZERO
    advance = (total * pct / Decimal("100")).quantize(CENT)
    return advance, (total - advance).quantize(CENT)
