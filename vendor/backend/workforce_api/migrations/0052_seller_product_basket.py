from decimal import Decimal
from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("companies", "__first__"),
        ("workforce_api", "0051_add_workforce_job_hold"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="SellerProductBasket",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("title", models.CharField(db_index=True, max_length=255)),
                ("description", models.TextField(blank=True, default="")),
                (
                    "image_url",
                    models.CharField(blank=True, default="", max_length=1000),
                ),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("DRAFT", "Draft"),
                            ("ACTIVE", "Active"),
                            ("PAUSED", "Paused"),
                            ("OUT_OF_STOCK", "Out of Stock"),
                        ],
                        db_index=True,
                        default="DRAFT",
                        max_length=30,
                    ),
                ),
                (
                    "pricing_mode",
                    models.CharField(
                        choices=[
                            ("MARGIN", "Margin Percentage"),
                            ("FIXED_PRICE", "Fixed Basket Price"),
                        ],
                        default="MARGIN",
                        max_length=30,
                    ),
                ),
                (
                    "margin_percent",
                    models.DecimalField(
                        blank=True,
                        decimal_places=2,
                        help_text="Seller margin percentage on total procurement cost",
                        max_digits=8,
                        null=True,
                    ),
                ),
                (
                    "selling_price",
                    models.DecimalField(
                        decimal_places=2,
                        default=Decimal("0.00"),
                        help_text="Final customer-facing selling price for the combo basket",
                        max_digits=10,
                    ),
                ),
                (
                    "total_mrp",
                    models.DecimalField(
                        decimal_places=2,
                        default=Decimal("0.00"),
                        help_text="Sum of component MRPs * quantities at last calculation",
                        max_digits=10,
                    ),
                ),
                (
                    "total_procurement_price",
                    models.DecimalField(
                        decimal_places=2,
                        default=Decimal("0.00"),
                        help_text="Sum of component procurement prices * quantities at last calculation",
                        max_digits=10,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "company",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="seller_product_baskets",
                        to="companies.company",
                    ),
                ),
                (
                    "created_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="created_seller_baskets",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "db_table": "workforce_seller_product_basket",
                "ordering": ["-updated_at", "-created_at"],
            },
        ),
        migrations.CreateModel(
            name="SellerProductBasketItem",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("quantity", models.PositiveIntegerField(default=1)),
                (
                    "basket",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="items",
                        to="workforce_api.sellerproductbasket",
                    ),
                ),
                (
                    "product",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="basket_items",
                        to="workforce_api.sellerproduct",
                    ),
                ),
            ],
            options={
                "db_table": "workforce_seller_product_basket_item",
            },
        ),
        migrations.AddField(
            model_name="sellerorderitem",
            name="basket",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="order_items",
                to="workforce_api.sellerproductbasket",
            ),
        ),
        migrations.AddField(
            model_name="sellerorderitem",
            name="basket_title",
            field=models.CharField(blank=True, default="", max_length=255),
        ),
        migrations.AddIndex(
            model_name="sellerproductbasket",
            index=models.Index(
                fields=["company", "status"], name="wf_basket_comp_stat_idx"
            ),
        ),
        migrations.AddIndex(
            model_name="sellerproductbasket",
            index=models.Index(
                fields=["status", "updated_at"], name="wf_basket_stat_upd_idx"
            ),
        ),
        migrations.AddConstraint(
            model_name="sellerproductbasketitem",
            constraint=models.UniqueConstraint(
                fields=("basket", "product"), name="unique_seller_product_basket_item"
            ),
        ),
    ]
