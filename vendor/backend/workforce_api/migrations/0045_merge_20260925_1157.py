"""Merge the independent Workforce API feature branches without data changes."""
from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("workforce_api", "0033_dynamic_painting_mason_and_vendor_location"),
        ("workforce_api", "0034_add_workforce_outbound_webhook"),
        ("workforce_api", "0044_remove_inventoryitem_unique_inventory_company_service_and_more"),
    ]

    operations = []
