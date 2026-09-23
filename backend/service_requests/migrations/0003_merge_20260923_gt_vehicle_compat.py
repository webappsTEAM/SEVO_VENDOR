# Hand-written merge migration (this session, 2026-09-23) -- NOT generated
# by `manage.py makemigrations --merge`, because this session had no
# working shell on the target machine to run it. This app's migration
# graph had two competing, un-merged 0002 migrations
# (0002_deliveryproof_package_tripstop.py and 0002_deliveryproof_tripstop.py,
# both depending on 0001_initial), discovered while investigating why this
# app's ServiceRequest model couldn't be safely extended -- there was no
# single "latest" migration to depend a new one on.
#
# This merge is believed safe because both branches are STATE-ONLY
# CreateModel operations for a managed=False app (no real DDL executes for
# either), and the two branches declare byte-identical field sets for the
# DeliveryProof and TripStop models they share -- only Package differs (it
# exists in 0002_deliveryproof_package_tripstop only). An empty merge with
# no operations, depending on both leaves, is exactly what
# `makemigrations --merge` itself would produce here since there is nothing
# to reconcile between the two field sets.
#
# IMPORTANT: this was NOT verified against a real django_migrations table
# this session (no DB/shell access). Before trusting this: run
# `python manage.py showmigrations service_requests` and
# `python manage.py makemigrations --check --dry-run` against a real
# database copy first. If either historical 0002 migration was already
# applied and recorded under a name/hash this file's dependency list
# doesn't match, Django will still handle it correctly (dependencies are
# matched by (app_label, name), not by content) -- but confirm before
# applying this to a production database.
from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('service_requests', '0002_deliveryproof_package_tripstop'),
        ('service_requests', '0002_deliveryproof_tripstop'),
    ]

    operations = []
