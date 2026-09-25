import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('workforce_api', '0032_workforcedispatchstate'),
        ('workforce_api', '0032_remove_inventoryitem_unique_inventory_company_service_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('service_requests', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='workforcequote',
            name='estimated_duration_days',
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.AddField(
            model_name='workforcepaintingquote',
            name='estimated_duration_days',
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.AddField(
            model_name='workforceservicepricingpolicy',
            name='max_service_radius_km',
            field=models.DecimalField(decimal_places=2, default=50.00, help_text='Beyond this radius from the base/hub, service is rejected as non-serviceable.', max_digits=6),
        ),
        migrations.CreateModel(
            name='WorkforceVendorBaseLocation',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('address', models.TextField(blank=True, default='')),
                ('area', models.CharField(blank=True, default='', max_length=150)),
                ('city', models.CharField(default='Hosur', max_length=100)),
                ('pincode', models.CharField(blank=True, default='', max_length=20)),
                ('base_latitude', models.FloatField(default=12.7409)),
                ('base_longitude', models.FloatField(default=77.8253)),
                ('max_service_radius_km', models.DecimalField(decimal_places=2, default=50.00, max_digits=6)),
                ('is_active', models.BooleanField(db_index=True, default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('company', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='base_locations', to='companies.company')),
                ('employee', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='base_locations', to='employees.employee')),
            ],
            options={
                'db_table': 'workforce_vendor_base_location',
                'ordering': ['-created_at'],
            },
        ),
        migrations.CreateModel(
            name='WorkforceJobHold',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('reason', models.CharField(default='WEATHER_DELAY', max_length=100)),
                ('notes', models.TextField(blank=True, default='')),
                ('hold_start', models.DateTimeField(auto_now_add=True)),
                ('hold_end', models.DateTimeField(blank=True, null=True)),
                ('status', models.CharField(choices=[('ACTIVE', 'Active Hold'), ('RESUMED', 'Resumed'), ('CANCELLED', 'Cancelled')], db_index=True, default='ACTIVE', max_length=20)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('employee', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='job_holds', to='employees.employee')),
                ('held_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='created_job_holds', to=settings.AUTH_USER_MODEL)),
                ('job', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='job_holds', to='service_requests.servicerequest')),
            ],
            options={
                'db_table': 'workforce_job_hold',
                'ordering': ['-created_at'],
            },
        ),
        migrations.CreateModel(
            name='WorkforceScopeReduction',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('original_amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('reduction_amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('revised_amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('reason', models.TextField()),
                ('crm_status', models.CharField(choices=[('REQUESTED', 'Requested'), ('APPROVED', 'Approved'), ('REJECTED', 'Rejected')], db_index=True, default='REQUESTED', max_length=20)),
                ('approved_at', models.DateTimeField(blank=True, null=True)),
                ('rejection_reason', models.TextField(blank=True, default='')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('approved_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='approved_scope_reductions', to=settings.AUTH_USER_MODEL)),
                ('job', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='scope_reductions', to='service_requests.servicerequest')),
                ('quote', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='scope_reductions', to='workforce_api.workforcequote')),
                ('requested_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='requested_scope_reductions', to=settings.AUTH_USER_MODEL)),
            ],
            options={
                'db_table': 'workforce_scope_reduction',
                'ordering': ['-created_at'],
            },
        ),
    ]
