"""Cloudflare R2 storage backends for Workforce media.

Private workforce evidence is exposed only through short-lived signed URLs.
Public seller/catalog images use the public R2 bucket and custom media domain.
"""

import mimetypes
import os
from copy import deepcopy
from pathlib import Path, PurePosixPath
from urllib.parse import quote

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.core.files.base import ContentFile, File
from django.core.files.storage import Storage, default_storage
from django.utils.deconstruct import deconstructible


def _clean_key(name):
    raw = str(name or "").replace("\\", "/").lstrip("/")
    key = str(PurePosixPath(raw))
    if not key or key == "." or key.startswith("../") or "/../" in f"/{key}":
        raise ValueError("Invalid media object key.")
    return key


@deconstructible
class R2Storage(Storage):
    """Small S3-compatible Django storage adapter with lazy boto3 loading."""

    bucket_setting = ""
    access_key_setting = ""
    secret_key_setting = ""
    public = False

    def _legacy_local_path(self, key):
        if self.public or not getattr(settings, "R2_LEGACY_LOCAL_READS", True):
            return None
        root = Path(settings.MEDIA_ROOT).resolve()
        candidate = (root / key).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            return None
        return candidate if candidate.is_file() else None

    def _config(self):
        config = {
            "endpoint": getattr(settings, "R2_ENDPOINT_URL", ""),
            "bucket": getattr(settings, self.bucket_setting, ""),
            "access_key": getattr(settings, self.access_key_setting, ""),
            "secret_key": getattr(settings, self.secret_key_setting, ""),
        }
        if any(not value for value in config.values()):
            raise ImproperlyConfigured(
                "Cloudflare R2 media storage is enabled but required credentials are missing."
            )
        return config

    def _client(self):
        try:
            import boto3
            from botocore.config import Config
        except ImportError as exc:
            raise ImproperlyConfigured(
                "Cloudflare R2 media storage requires the boto3 package."
            ) from exc

        config = self._config()
        return boto3.client(
            "s3",
            endpoint_url=config["endpoint"],
            aws_access_key_id=config["access_key"],
            aws_secret_access_key=config["secret_key"],
            region_name="auto",
            config=Config(signature_version="s3v4"),
        )

    def _save(self, name, content):
        key = _clean_key(name)
        if hasattr(content, "seek"):
            content.seek(0)
        extra = {}
        content_type = getattr(content, "content_type", "") or mimetypes.guess_type(key)[0]
        if content_type:
            extra["ContentType"] = content_type
        kwargs = {}
        if extra:
            kwargs["ExtraArgs"] = extra
        self._client().upload_fileobj(content, self._config()["bucket"], key, **kwargs)
        return key

    def _open(self, name, mode="rb"):
        key = _clean_key(name)
        legacy_path = self._legacy_local_path(key)
        if legacy_path:
            return File(open(legacy_path, mode), name=key)
        response = self._client().get_object(Bucket=self._config()["bucket"], Key=key)
        return ContentFile(response["Body"].read(), name=os.path.basename(key))

    def delete(self, name):
        key = _clean_key(name)
        self._client().delete_object(Bucket=self._config()["bucket"], Key=key)

    def exists(self, name):
        key = _clean_key(name)
        if self._legacy_local_path(key):
            return True
        try:
            self._client().head_object(Bucket=self._config()["bucket"], Key=key)
            return True
        except Exception as exc:
            status = getattr(exc, "response", {}).get("ResponseMetadata", {}).get("HTTPStatusCode")
            if status == 404:
                return False
            raise

    def size(self, name):
        key = _clean_key(name)
        legacy_path = self._legacy_local_path(key)
        if legacy_path:
            return legacy_path.stat().st_size
        response = self._client().head_object(Bucket=self._config()["bucket"], Key=key)
        return int(response.get("ContentLength", 0))

    def url(self, name):
        key = _clean_key(name)
        legacy_path = self._legacy_local_path(key)
        if legacy_path:
            return f"{settings.MEDIA_URL.rstrip('/')}/{quote(key, safe='/')}"
        if self.public:
            base = getattr(settings, "R2_PUBLIC_BASE_URL", "").rstrip("/")
            if not base:
                raise ImproperlyConfigured("R2_PUBLIC_BASE_URL is required for public media.")
            return f"{base}/{quote(key, safe='/')}"
        return self._client().generate_presigned_url(
            "get_object",
            Params={"Bucket": self._config()["bucket"], "Key": key},
            ExpiresIn=int(getattr(settings, "R2_SIGNED_URL_EXPIRES", 900)),
        )


class PrivateR2Storage(R2Storage):
    bucket_setting = "R2_PRIVATE_BUCKET"
    access_key_setting = "R2_PRIVATE_ACCESS_KEY_ID"
    secret_key_setting = "R2_PRIVATE_SECRET_ACCESS_KEY"


class PublicR2Storage(R2Storage):
    bucket_setting = "R2_PUBLIC_BUCKET"
    access_key_setting = "R2_PUBLIC_ACCESS_KEY_ID"
    secret_key_setting = "R2_PUBLIC_SECRET_ACCESS_KEY"
    public = True


def get_public_media_storage():
    if getattr(settings, "MEDIA_STORAGE_PROVIDER", "local") == "r2":
        return PublicR2Storage()
    return default_storage


def private_media_url(value):
    """Resolve a stored private object key while preserving legacy URLs."""
    raw = str(value or "").strip()
    if not raw:
        return ""
    if raw.startswith(("http://", "https://", "/media/", "/static/", "data:")):
        return raw
    return default_storage.url(raw)


def hydrate_private_document_urls(onboarding):
    """Return an API-safe copy with signed document URLs; never mutate DB JSON."""
    result = deepcopy(onboarding or {})
    documents = result.get("documents")
    if not isinstance(documents, dict):
        return result
    for document in documents.values():
        if not isinstance(document, dict):
            continue
        stored = document.get("storage_path") or document.get("file_url") or document.get("url")
        if stored:
            document["file_url"] = private_media_url(stored)
    return result
