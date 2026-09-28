# Generated for Phase W: SellerProduct fulfillment_method
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('workforce_api', '0046_merge_20260925_1022'),
    ]

    operations = [
        migrations.AddField(
            model_name='sellerproduct',
            name='fulfillment_method',
            field=models.CharField(
                choices=[('SELF_SHIP', 'Self-Ship'), ('FULFILLED_BY_SEVO', 'Fulfilled by Sevo')],
                db_index=True,
                default='SELF_SHIP',
                help_text='Fulfillment mode: SELF_SHIP (seller dispatches directly) or FULFILLED_BY_SEVO (FBS - stock held at Sevo warehouse)',
                max_length=30,
            ),
        ),
    ]
