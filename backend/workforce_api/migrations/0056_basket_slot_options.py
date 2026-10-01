from django.db import migrations, models
import django.db.models.deletion


def populate_basket_slot_options(apps, schema_editor):
    SellerProductBasketItem = apps.get_model('workforce_api', 'SellerProductBasketItem')
    SellerProductBasketItemOption = apps.get_model('workforce_api', 'SellerProductBasketItemOption')
    for item in SellerProductBasketItem.objects.all():
        if item.product_id:
            if not SellerProductBasketItemOption.objects.filter(basket_item=item, product_id=item.product_id).exists():
                SellerProductBasketItemOption.objects.create(
                    basket_item=item,
                    product_id=item.product_id,
                    is_default=True,
                    display_order=0
                )


class Migration(migrations.Migration):

    dependencies = [
        ('workforce_api', '0055_sellerproductspec'),
    ]

    operations = [
        migrations.RemoveConstraint(
            model_name='sellerproductbasketitem',
            name='unique_seller_product_basket_item',
        ),
        migrations.AlterModelOptions(
            name='sellerproductbasketitem',
            options={'ordering': ['display_order', 'id']},
        ),
        migrations.AddField(
            model_name='sellerproductbasketitem',
            name='display_order',
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='sellerproductbasketitem',
            name='slot_title',
            field=models.CharField(blank=True, default='', max_length=255),
        ),
        migrations.AlterField(
            model_name='sellerproductbasketitem',
            name='product',
            field=models.ForeignKey(blank=True, help_text='Default / legacy product reference for single-option slots.', null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='basket_items', to='workforce_api.sellerproduct'),
        ),
        migrations.CreateModel(
            name='SellerProductBasketItemOption',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('is_default', models.BooleanField(default=False)),
                ('display_order', models.PositiveIntegerField(default=0)),
                ('basket_item', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='options', to='workforce_api.sellerproductbasketitem')),
                ('product', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='basket_slot_options', to='workforce_api.sellerproduct')),
            ],
            options={
                'db_table': 'workforce_seller_product_basket_item_option',
                'ordering': ['display_order', 'id'],
            },
        ),
        migrations.AddConstraint(
            model_name='sellerproductbasketitemoption',
            constraint=models.UniqueConstraint(fields=('basket_item', 'product'), name='unique_basket_item_product_option'),
        ),
        migrations.RunPython(
            code=populate_basket_slot_options,
            reverse_code=migrations.RunPython.noop,
        ),
    ]
