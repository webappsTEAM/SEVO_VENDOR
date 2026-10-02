"""Short-lived, single-use tickets for the driver live-update stream (SSE).

Browsers cannot send an Authorization header on an EventSource, so the stream used to take the full
access JWT in the URL query string (valid for hours, and recorded by proxies/access logs). A ticket is
the safe thing to put in a URL: it only authorises opening ONE stream, expires in seconds, and is
useless for any other API call."""
import uuid

from django.core import signing
from django.core.cache import cache

SALT = "workforce.realtime.stream.ticket"
TTL_SECONDS = 60


def issue_stream_ticket(user_id):
    return signing.dumps({"u": int(user_id), "n": uuid.uuid4().hex}, salt=SALT)


def redeem_stream_ticket(ticket, ttl=TTL_SECONDS):
    """Return the user id the ticket was issued to, or None if it is invalid, expired or already used."""
    try:
        data = signing.loads(str(ticket), salt=SALT, max_age=ttl)
        user_id, nonce = int(data["u"]), str(data["n"])
    except (signing.BadSignature, KeyError, TypeError, ValueError):
        return None
    # single use: the first redeemer wins
    if not cache.add(f"sse_ticket_used:{nonce}", 1, timeout=ttl * 2):
        return None
    return user_id
