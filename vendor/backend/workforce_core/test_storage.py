from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import Mock, patch

from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase, override_settings

from workforce_core.storage import (
    PrivateR2Storage,
    PublicR2Storage,
    hydrate_private_document_urls,
)


R2_SETTINGS = {
    "MEDIA_STORAGE_PROVIDER": "r2",
    "R2_ENDPOINT_URL": "https://account.r2.cloudflarestorage.com",
    "R2_PRIVATE_ACCESS_KEY_ID": "private-key",
    "R2_PRIVATE_SECRET_ACCESS_KEY": "private-secret",
    "R2_PRIVATE_BUCKET": "private-bucket",
    "R2_PUBLIC_ACCESS_KEY_ID": "public-key",
    "R2_PUBLIC_SECRET_ACCESS_KEY": "public-secret",
    "R2_PUBLIC_BUCKET": "public-bucket",
    "R2_PUBLIC_BASE_URL": "https://media.example.com",
    "R2_SIGNED_URL_EXPIRES": 900,
}


@override_settings(**R2_SETTINGS)
class R2StorageTests(SimpleTestCase):
    def test_private_url_is_signed_for_private_bucket(self):
        client = Mock()
        client.generate_presigned_url.return_value = "https://signed.example/object"
        storage = PrivateR2Storage()
        with patch.object(storage, "_client", return_value=client):
            result = storage.url("workforce_docs/id.pdf")
        self.assertEqual(result, "https://signed.example/object")
        client.generate_presigned_url.assert_called_once_with(
            "get_object",
            Params={"Bucket": "private-bucket", "Key": "workforce_docs/id.pdf"},
            ExpiresIn=900,
        )

    def test_public_url_uses_custom_domain_without_signature(self):
        self.assertEqual(
            PublicR2Storage().url("seller_products/item one.webp"),
            "https://media.example.com/seller_products/item%20one.webp",
        )

    def test_upload_is_scoped_to_configured_private_bucket(self):
        client = Mock()
        upload = BytesIO(b"private evidence")
        upload.content_type = "application/pdf"
        storage = PrivateR2Storage()
        with patch.object(storage, "_client", return_value=client):
            saved = storage._save("workforce_docs/id.pdf", upload)
        self.assertEqual(saved, "workforce_docs/id.pdf")
        client.upload_fileobj.assert_called_once_with(
            upload,
            "private-bucket",
            "workforce_docs/id.pdf",
            ExtraArgs={"ContentType": "application/pdf"},
        )

    def test_document_hydration_signs_copy_and_preserves_stored_key(self):
        source = {"documents": {"aadhaar": {"file_url": "workforce_docs/id.pdf"}}}
        with patch("workforce_core.storage.default_storage.url", return_value="https://signed.example/id"):
            hydrated = hydrate_private_document_urls(source)
        self.assertEqual(hydrated["documents"]["aadhaar"]["file_url"], "https://signed.example/id")
        self.assertEqual(source["documents"]["aadhaar"]["file_url"], "workforce_docs/id.pdf")

    @override_settings(R2_PRIVATE_SECRET_ACCESS_KEY="")
    def test_missing_private_credentials_fail_closed(self):
        with self.assertRaises(ImproperlyConfigured):
            PrivateR2Storage()._config()

    def test_parent_path_is_rejected(self):
        with self.assertRaises(ValueError):
            PrivateR2Storage().url("../secret.txt")

    def test_existing_local_media_keeps_working_during_migration(self):
        with TemporaryDirectory() as media_root:
            legacy = Path(media_root) / "avatars" / "existing.jpg"
            legacy.parent.mkdir(parents=True)
            legacy.write_bytes(b"existing")
            with override_settings(MEDIA_ROOT=media_root, MEDIA_URL="/media/"):
                self.assertEqual(
                    PrivateR2Storage().url("avatars/existing.jpg"),
                    "/media/avatars/existing.jpg",
                )
