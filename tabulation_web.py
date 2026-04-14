from flask import Flask, render_template, request, redirect, url_for, session, flash, jsonify
import oracledb
import base64
import io
import os
import time
import hashlib
import threading
from datetime import datetime
from PIL import Image

app = Flask(__name__)
app.secret_key = "nu_archive_secure_key_2026"

# ── Oracle Config ─────────────────────────────────────────────────────
DB_USER     = "NU"
DB_PASSWORD = "12345"
DB_HOST     = "103.113.200.20"
DB_PORT     = 1521
DB_SID      = "nuorcl"

# ── Disk cache folder ─────────────────────────────────────────────────
TEMP_DIR = os.path.join(os.path.dirname(__file__), "temp_cache")
os.makedirs(TEMP_DIR, exist_ok=True)

# ── Connection Pool ───────────────────────────────────────────────────
_pool      = None
_pool_lock = threading.Lock()

def get_pool():
    global _pool
    with _pool_lock:
        if _pool is None:
            try:
                _pool = oracledb.create_pool(
                    user=DB_USER, password=DB_PASSWORD,
                    host=DB_HOST, port=DB_PORT, sid=DB_SID,
                    min=2, max=10, increment=1
                )
                print("[DB] Oracle pool initialized.")
            except oracledb.DatabaseError as e:
                error, = e.args
                if hasattr(error, 'code') and error.code == 28001:
                    print("[DB] Password expired at pool init — renewing with same password...")
                    _pool = oracledb.create_pool(
                        user=DB_USER,
                        password=DB_PASSWORD,
                        newpassword=DB_PASSWORD,
                        host=DB_HOST, port=DB_PORT, sid=DB_SID,
                        min=2, max=10, increment=1
                    )
                    print("[DB] Password renewed. Pool initialized.")
                else:
                    raise
    return _pool

def get_db():
    """
    Acquire a connection from the pool.
    Handles ORA-28001 (expired password) by rebuilding pool with renewal.
    """
    try:
        return get_pool().acquire()
    except oracledb.DatabaseError as e:
        error, = e.args
        if hasattr(error, 'code') and error.code == 28001:
            global _pool
            print("[DB] Password expired on acquire — rebuilding pool with renewal...")
            with _pool_lock:
                _pool = None
            new_pool = oracledb.create_pool(
                user=DB_USER,
                password=DB_PASSWORD,
                newpassword=DB_PASSWORD,
                host=DB_HOST, port=DB_PORT, sid=DB_SID,
                min=2, max=10, increment=1
            )
            with _pool_lock:
                _pool = new_pool
            return _pool.acquire()
        raise

# ── In-Memory Cache ───────────────────────────────────────────────────
_cache      = {}
_cache_lock = threading.Lock()

def _ckey(*args):
    return hashlib.md5("|".join(str(a) for a in args).encode()).hexdigest()

def cache_get(key):
    with _cache_lock:
        e = _cache.get(key)
        if not e:
            return None
        val, exp = e
        if time.time() > exp:
            del _cache[key]
            return None
        return val

def cache_set(key, val, ttl=1800):
    with _cache_lock:
        _cache[key] = (val, time.time() + ttl)

def _janitor():
    while True:
        time.sleep(600)
        now = time.time()
        with _cache_lock:
            dead = [k for k, (_, exp) in _cache.items() if now > exp]
            for k in dead:
                del _cache[k]

threading.Thread(target=_janitor, daemon=True).start()

# ── Disk cache helpers ────────────────────────────────────────────────
def _disk_path(master_id):
    return os.path.join(TEMP_DIR, f"{master_id}.jpg")

def disk_cache_get(master_id):
    p = _disk_path(master_id)
    if os.path.exists(p):
        with open(p, "rb") as f:
            return base64.b64encode(f.read()).decode("utf-8")
    return None

def disk_cache_save(master_id, jpeg_bytes):
    try:
        with open(_disk_path(master_id), "wb") as f:
            f.write(jpeg_bytes)
    except Exception as e:
        print(f"[CACHE] Disk write error: {e}")

# ── Utilities ─────────────────────────────────────────────────────────
def check_expiration():
    return datetime.now().date() > datetime(2026, 12, 31).date()

def log_login(username):
    """
    CRITICAL: Capture ip/device BEFORE spawning thread.
    Flask request context does NOT exist inside background threads.
    """
    try:
        ip     = request.remote_addr
        device = (request.user_agent.string or "unknown")[:255]
    except Exception:
        ip, device = "unknown", "unknown"

    def _log():
        conn = None
        try:
            conn = get_db()
            cur  = conn.cursor()
            cur.execute(
                """INSERT INTO T_LOGIN_LOG
                       (USERNAME, IP_ADDRESS, DEVICE_INFO, LOGIN_TIME)
                   VALUES (:1, :2, :3, SYSTIMESTAMP)""",
                (username, ip, device)
            )
            conn.commit()
            cur.close()
            print(f"[LOG] Login recorded  user={username}  ip={ip}")
        except Exception as e:
            print(f"[LOG] Login log FAILED for '{username}': {e}")
        finally:
            if conn:
                try:
                    conn.close()
                except Exception:
                    pass

    threading.Thread(target=_log, daemon=True).start()

# ── Image helpers ─────────────────────────────────────────────────────
def _fetch_and_process_image(master_id):
    """Fetch BLOB from Oracle, resize, convert to JPEG. Returns (bytes, b64) or (None, None)."""
    try:
        conn = get_db()
        cur  = conn.cursor()
        cur.execute("SELECT IMAGE FROM T_IMAGES WHERE MASTER_ID = :1", [master_id])
        row = cur.fetchone()
        cur.close()
        conn.close()

        if row and row[0]:
            blob_data = row[0].read() if hasattr(row[0], "read") else row[0]
            if not isinstance(blob_data, (bytes, bytearray)):
                blob_data = base64.b64decode(str(blob_data).split(",")[-1])

            img = Image.open(io.BytesIO(blob_data))
            if img.mode in ("RGBA", "P"):
                img = img.convert("RGB")
            if img.width > 1800:
                h = int(img.height * 1800 / img.width)
                img = img.resize((1800, h), Image.LANCZOS)

            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=75, optimize=True)
            jpeg_bytes = buf.getvalue()
            b64 = base64.b64encode(jpeg_bytes).decode("utf-8")
            return jpeg_bytes, b64
    except Exception as e:
        print(f"[IMG] Fetch error master_id={master_id}: {e}")
    return None, None

def get_image_from_db(master_id):
    """Priority: memory cache -> disk cache -> Oracle."""
    key = _ckey("img", master_id)

    hit = cache_get(key)
    if hit:
        return hit

    b64 = disk_cache_get(master_id)
    if b64:
        cache_set(key, b64, ttl=7200)
        return b64

    jpeg_bytes, b64 = _fetch_and_process_image(master_id)
    if b64:
        disk_cache_save(master_id, jpeg_bytes)
        cache_set(key, b64, ttl=7200)
        return b64
    return None

def _prefetch_all_images(results):
    """Background thread: pre-cache images for every result row."""
    def _worker():
        for row in results:
            mid = str(row.get("MASTER_ID", ""))
            if not mid or os.path.exists(_disk_path(mid)):
                continue
            jpeg_bytes, b64 = _fetch_and_process_image(mid)
            if jpeg_bytes:
                disk_cache_save(mid, jpeg_bytes)
                cache_set(_ckey("img", mid), b64, ttl=7200)
    threading.Thread(target=_worker, daemon=True).start()


# ══════════════════════════════════════════════════════════════════════
# ROUTES
# ══════════════════════════════════════════════════════════════════════

@app.route('/login', methods=['GET', 'POST'])
def login():
    if check_expiration():
        return "Program Expired. Please contact ICT Department for Support."

    if request.method == 'POST':
        u = (request.form.get('username') or '').strip()
        p = (request.form.get('password') or '').strip()

        # Hardcoded accounts — NEVER touch Oracle
        if u == "superadmin" and p == "superadmin":
            session['user'], session['role'] = u, 'superadmin'
            log_login(u)
            return redirect(url_for('index'))

        if u == "admin" and p == "adminnu":
            session['user'], session['role'] = u, 'admin'
            log_login(u)
            return redirect(url_for('admin_panel'))

        # Oracle T_USER check
        try:
            conn = get_db()
            cur  = conn.cursor()
            cur.execute(
                "SELECT COUNT(*) FROM T_USER WHERE USERNAME=:1 AND PASSWORD=:2",
                (u, p)
            )
            exists = cur.fetchone()[0]
            cur.close()
            conn.close()
            if exists:
                session['user'], session['role'] = u, 'user'
                log_login(u)
                return redirect(url_for('index'))
            else:
                flash("Invalid username or password.", "danger")
        except Exception as e:
            flash(f"Database Connection Error: {str(e)}", "danger")

    return render_template('login.html')


@app.route('/', methods=['GET', 'POST'])
def index():
    if 'user' not in session:
        return redirect(url_for('login'))

    results          = []
    img_b64          = None
    selected_student = None

    if request.method == 'POST':
        reg        = request.form.get('reg_no', '').strip()
        roll       = request.form.get('roll',   '').strip()
        target_mid = request.form.get('target_master_id', '').strip()

        try:
            skey    = _ckey("search", reg, roll)
            results = cache_get(skey)

            if results is None:
                conn   = get_db()
                cur    = conn.cursor()
                query  = """
                    SELECT MASTER_ID, EXM_NAME, REG_NO, EXM_ROLL, EXM_YR,
                           TOTAL_MARK, RESULT1, COLLEGE, DISTRICT
                    FROM   NU_DATA
                    WHERE  1=1
                """
                params = []
                if reg:
                    query += " AND REG_NO = :1"
                    params.append(reg)
                if roll:
                    idx = len(params) + 1
                    query += f" AND EXM_ROLL = :{idx}"
                    params.append(roll)
                query += " ORDER BY EXM_YR DESC"

                if params:
                    cur.execute(query, params)
                    rows    = cur.fetchall()
                    cols    = [d[0] for d in cur.description]
                    results = [dict(zip(cols, r)) for r in rows]
                else:
                    results = []
                cur.close()
                conn.close()
                cache_set(skey, results, ttl=1800)
                if results:
                    _prefetch_all_images(results)

            if target_mid:
                img_b64          = get_image_from_db(target_mid)
                selected_student = next(
                    (s for s in results if str(s['MASTER_ID']) == target_mid), None
                )
            elif results:
                img_b64          = get_image_from_db(str(results[0]['MASTER_ID']))
                selected_student = results[0]

        except Exception as e:
            print(f"[SEARCH] Error: {e}")
            flash(f"Search error: {e}", "danger")

    return render_template(
        'index.html',
        results=results,
        image=img_b64,
        student=selected_student,
        user=session['user']
    )


@app.route('/fetch_image/<master_id>')
def fetch_image(master_id):
    if 'user' not in session:
        return jsonify({"error": "unauthorized"}), 401
    b64 = get_image_from_db(master_id)
    if b64:
        return jsonify({"image": b64})
    return jsonify({"error": "not found"}), 404


@app.route('/admin', methods=['GET', 'POST'])
def admin_panel():
    if session.get('role') not in ['admin', 'superadmin']:
        return "Access Denied", 403
    try:
        conn = get_db()
        cur  = conn.cursor()

        # ── POST actions ──────────────────────────────────────────
        if request.method == 'POST':
            action = request.form.get('action')

            if action == 'add_user':
                nu = request.form.get('new_user', '').strip()
                np = request.form.get('new_pass', '').strip()
                nr = request.form.get('new_role', 'user').strip()
                if nu and np:
                    cur.execute(
                        "INSERT INTO T_USER (USERNAME, PASSWORD, ROLE) "
                        "VALUES (:1, :2, :3)", (nu, np, nr)
                    )
                    conn.commit()
                    flash(f"User '{nu}' created.", "success")
                else:
                    flash("Username and password cannot be empty.", "danger")

            elif action == 'delete_user':
                uid = request.form.get('user_id')
                if uid:
                    cur.execute("DELETE FROM T_USER WHERE ID = :1", [uid])
                    conn.commit()
                    flash("User deleted.", "success")

        # ── Pagination ────────────────────────────────────────────
        ROWS_PER_PAGE = 20
        page = max(1, request.args.get('page', 1, type=int))

        cur.execute("SELECT COUNT(*) FROM T_LOGIN_LOG")
        total_logs  = cur.fetchone()[0]
        print(f"[ADMIN] T_LOGIN_LOG total rows: {total_logs}")

        total_pages = max(1, (total_logs + ROWS_PER_PAGE - 1) // ROWS_PER_PAGE)
        page        = min(page, total_pages)
        offset      = (page - 1) * ROWS_PER_PAGE

        # KEY FIXES:
        # 1. Alias is FORMATTED_TIME (not LOGIN_TIME) — avoids Oracle
        #    resolving ORDER BY to the string alias instead of the column
        # 2. ORDER BY ID DESC — always sequential, never ambiguous
        # 3. Positional bind vars [:1, :2]
        cur.execute("""
            SELECT
                ID,
                USERNAME,
                TO_CHAR(LOGIN_TIME, 'DD-Mon-YYYY HH24:MI:SS') AS FORMATTED_TIME,
                IP_ADDRESS,
                DEVICE_INFO
            FROM   T_LOGIN_LOG
            ORDER  BY ID DESC
            OFFSET :1 ROWS FETCH NEXT :2 ROWS ONLY
        """, [offset, ROWS_PER_PAGE])
        logs = cur.fetchall()
        print(f"[ADMIN] Fetched {len(logs)} rows  page={page}/{total_pages}")

        # ── Users ─────────────────────────────────────────────────
        cur.execute("SELECT ID, USERNAME, PASSWORD, ROLE FROM T_USER ORDER BY ID")
        users = cur.fetchall()

        cur.close()
        conn.close()

        return render_template(
            'admin.html',
            logs=logs,
            users=users,
            page=page,
            total_pages=total_pages
        )

    except Exception as e:
        import traceback
        traceback.print_exc()
        return f"Admin Panel Error: {str(e)}"


# ── DIAGNOSTIC ────────────────────────────────────────────────────────
@app.route('/admin/check_logs')
def check_logs():
    """
    Diagnostic endpoint — shows raw T_LOGIN_LOG data directly.
    Visit: http://localhost:5000/admin/check_logs
    Remove this route before deploying to production.
    """
    if session.get('role') not in ['admin', 'superadmin']:
        return "Access Denied", 403
    try:
        conn = get_db()
        cur  = conn.cursor()

        cur.execute("SELECT COUNT(*) FROM T_LOGIN_LOG")
        total = cur.fetchone()[0]

        cur.execute("""
            SELECT ID, USERNAME, LOGIN_TIME, IP_ADDRESS, DEVICE_INFO
            FROM   T_LOGIN_LOG
            ORDER  BY ID DESC
            FETCH  FIRST 10 ROWS ONLY
        """)
        rows = cur.fetchall()

        cur.execute("""
            SELECT COLUMN_NAME, DATA_TYPE, NULLABLE, DATA_DEFAULT
            FROM   USER_TAB_COLUMNS
            WHERE  TABLE_NAME = 'T_LOGIN_LOG'
            ORDER  BY COLUMN_ID
        """)
        cols = cur.fetchall()

        cur.close()
        conn.close()

        out  = "<pre style='font-family:monospace;padding:20px;font-size:14px'>"
        out += f"<b>T_LOGIN_LOG — total rows: {total}</b>\n\n"
        out += "<b>Table structure:</b>\n"
        for c in cols:
            out += f"  {str(c[0]):<25} {str(c[1]):<20} nullable={c[2]}  default={c[3]}\n"
        out += "\n<b>Latest 10 rows (raw timestamps):</b>\n"
        for r in rows:
            out += f"  ID={str(r[0]):<6} user={str(r[1]):<20} time={r[2]}  ip={r[3]}\n"
        out += "</pre>"
        return out

    except Exception as e:
        return f"<pre>Diagnostic Error: {e}</pre>"


@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))


if __name__ == '__main__':
    try:
        get_pool()
    except Exception as e:
        print(f"[WARN] Oracle pool init failed at startup: {e}")
        print("[WARN] App will still run — admin/superadmin login works without Oracle.")
    app.run(debug=False, threaded=True)
