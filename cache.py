import time
import hashlib
import threading

# ── In-process memory cache ──────────────────────────────────────────
# { key: (value, expire_at) }
_store: dict = {}
_lock = threading.Lock()


def _key(prefix: str, **kwargs) -> str:
    raw = prefix + "|" + "|".join(f"{k}={v}" for k, v in sorted(kwargs.items()))
    return hashlib.md5(raw.encode()).hexdigest()


def get(prefix: str, **kwargs):
    """Return cached value or None if missing/expired."""
    k = _key(prefix, **kwargs)
    with _lock:
        entry = _store.get(k)
        if entry is None:
            return None
        value, expire_at = entry
        if time.time() > expire_at:
            del _store[k]   # expired → evict
            return None
        return value


def set(prefix: str, value, ttl: int = 1800, **kwargs):
    """Store value with TTL in seconds."""
    k = _key(prefix, **kwargs)
    with _lock:
        _store[k] = (value, time.time() + ttl)


def invalidate(prefix: str, **kwargs):
    k = _key(prefix, **kwargs)
    with _lock:
        _store.pop(k, None)


def flush_all():
    with _lock:
        _store.clear()


def purge_expired():
    """Optional: call periodically to free memory from stale entries."""
    now = time.time()
    with _lock:
        expired_keys = [k for k, (_, exp) in _store.items() if now > exp]
        for k in expired_keys:
            del _store[k]
    return len(expired_keys)
