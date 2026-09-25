# Generated for Phase T: Warehouse and Seller Warehouse Assignment
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('companies', '__first__'),
        ('workforce_api', '0042_remove_inventoryitem_unique_inventory_company_service_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='Warehouse',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('name', models.CharField(help_text='Warehouse facility name (e.g. Central Bangalore Hub)', max_length=200)),
                ('code', models.CharField(blank=True, help_text='Unique facility code (e.g. WH-BLR-01)', max_length=50, null=True, unique=True)),
                ('address', models.TextField(help_text='Physical street address for navigation')),
                ('latitude', models.DecimalField(decimal_places=7, help_text='GPS latitude coordinate for rider pickup routing', max_digits=10)),
                ('longitude', models.DecimalField(decimal_places=7, help_text='GPS longitude coordinate for rider pickup routing', max_digits=10)),
                ('city', models.CharField(blank=True, default='', help_text='City or urban district', max_length=100)),
                ('region', models.CharField(blank=True, default='', help_text='State, province or operating zone', max_length=100)),
                ('contact_phone', models.CharField(blank=True, default='', help_text='Facility phone number', max_length=50)),
                ('is_active', models.BooleanField(db_index=True, default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
            ],
            options={
                'db_table': 'workforce_warehouse',
                'ordering': ['name'],
            },
        ),
        migrations.CreateModel(
            name='SellerWarehouseAssignment',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('assigned_at', models.DateTimeField(auto_now=True)),
                ('notes', models.CharField(blank=True, default='', max_length=255)),
                ('assigned_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='seller_warehouse_assignments', to=settings.AUTH_USER_MODEL)),
                ('company', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='warehouse_assignment', to='companies.company')),
                ('warehouse', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='seller_assignments', to='workforce_api.warehouse')),
            ],
            options={
                'db_table': 'workforce_seller_warehouse_assignment',
            },
        ),
        migrations.AddIndex(
            model_name='warehouse',
            index=models.Index(fields=['is_active', 'city'], name='wf_wh_active_city_idx'),
        ),
        migrations.AddIndex(
            model_name='sellerwarehouseassignment',
            index=models.Index(fields=['company', 'warehouse'], name='wf_slr_wh_comp_wh_idx'),
        ),
    ]

