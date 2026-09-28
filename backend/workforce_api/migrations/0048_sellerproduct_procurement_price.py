# Generated for Phase: Seller Product Procurement Price & Order Item Snapshot
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('workforce_api', '0047_sellerproduct_fulfillment_method'),
    ]

    operations = [
        migrations.AddField(
            model_name='sellerproduct',
            name='procurement_price',
            field=models.DecimalField(
                blank=True,
                decimal_places=2,
                help_text="Seller's own cost/acquisition price for this product. Private — visible only to the owning seller and platform admins.",
                max_digits=10,
                null=True,
            ),
        ),
        migrations.AddField(
            model_name='sellerorderitem',
            name='procurement_price_snapshot',
            field=models.DecimalField(
                blank=True,
                decimal_places=2,
                help_text="Snapshot of seller's procurement price at time of order creation/fulfillment.",
                max_digits=10,
                null=True,
            ),
        ),
    ]
