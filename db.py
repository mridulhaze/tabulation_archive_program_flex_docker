import oracledb

_pool = None

# ── Your Oracle credentials ───────────────────────────────────────────
DB_USER     = "NU"
DB_PASSWORD = "YOUR_PASSWORD"
DB_HOST     = "103.113.200.20"
DB_PORT     = 1521
DB_SID      = "nuorcl"


def init_pool():
    global _pool
    _pool = oracledb.create_pool(
        user=DB_USER,
        password=DB_PASSWORD,
        host=DB_HOST,
        port=DB_PORT,
        sid=DB_SID,
        min=2,
        max=10,
        increment=1
    )
    print("[DB] Oracle connection pool initialized.")


def get_connection():
    """Borrow a connection from the pool."""
    if _pool is None:
        init_pool()
    return _pool.acquire()
