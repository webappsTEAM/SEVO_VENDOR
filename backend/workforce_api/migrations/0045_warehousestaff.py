# Generated for Phase V: Warehouse Staff Login & Portal
import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('workforce_api', '0044_remove_inventoryitem_unique_inventory_company_service_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='WarehouseStaff',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('role', models.CharField(default='operator', help_text='Role at the warehouse: operator, manager, supervisor', max_length=50)),
                ('is_primary', models.BooleanField(default=True, help_text='Primary contact/account for this warehouse facility')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='warehouse_profile', to=settings.AUTH_USER_MODEL)),
                ('warehouse', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='staff_members', to='workforce_api.warehouse')),
            ],
            options={
                'db_table': 'workforce_warehouse_staff',
            },
        ),
        migrations.AddIndex(
            model_name='warehousestaff',
            index=models.Index(fields=['user', 'warehouse'], name='wf_wh_staff_user_wh_idx'),
        ),
        migrations.AddIndex(
            model_name='warehousestaff',
            index=models.Index(fields=['warehouse', 'is_primary'], name='wf_wh_staff_wh_prim_idx'),
        ),
    ]
