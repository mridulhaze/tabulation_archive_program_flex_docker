from flask import Flask, render_template, request, session, redirect, url_for
import oracledb
import base64
import time
import threading
import db
import cache

app = Flask(__name__)
app.secret_key = "NU_SECRET_KEY_CHANGE_ME"

# ── Init Oracle connection pool ───────────────────────────────────────
db.init_pool()

# ── Background cache janitor (purges expired keys every 10 min) ───────
def _cache_janitor():
    while True:
        time.sleep(600)
        removed = cache.purge_expired()
        if removed:
            print(f"[CACHE] Purged {removed} expired entries")

threading.Thread(target=_cache_janitor, daemon=True).start()


# ─────────────────────────────────────────────────────────────────────
# AUTH
# ─────────────────────────────────────────────────────────────────────
@app.route("/", methods=["GET", "POST"])
@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "").strip()
        try:
            conn = db.get_connection()
            cur  = conn.cursor()
            cur.execute(
                "SELECT USERNAME FROM T_USER WHERE USERNAME=:1 AND PASSWORD=:2",
                [username, password]
            )
            row = cur.fetchone()
            cur.close()
            conn.close()
            if row:
                session["user"] = username
                return redirect(url_for("index"))
            else:
                error = "Invalid credentials."
        except Exception as e:
            error = f"Database error: {e}"
    return render_template("login.html", error=error)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


# ─────────────────────────────────────────────────────────────────────
# MAIN INDEX
# ─────────────────────────────────────────────────────────────────────
@app.route("/index", methods=["GET", "POST"])
def index():
    if "user" not in session:
        return redirect(url_for("login"))

    results  = []
    student  = None
    image    = None

    if request.method == "POST":
        reg_no           = request.form.get("reg_no", "").strip()
        roll             = request.form.get("roll",   "").strip()
        target_master_id = request.form.get("target_master_id", "").strip()

        if reg_no or roll:
            results = _get_results(reg_no, roll)

        if target_master_id:
            student = _get_student(target_master_id)
            image   = _get_image(target_master_id)

    return render_template(
        "index.html",
        user=session["user"],
        results=results,
        student=student,
        image=image
    )


# ─────────────────────────────────────────────────────────────────────
# CACHED DB HELPERS
# ─────────────────────────────────────────────────────────────────────

def _get_results(reg_no: str, roll: str) -> list:
    """Search NU_DATA — cached 30 min per reg_no+roll pair."""
    cached = cache.get("results", reg_no=reg_no, roll=roll)
    if cached is not None:
        print(f"[CACHE HIT] results reg={reg_no} roll={roll}")
        return cached

    rows = []
    try:
        conn = db.get_connection()
        cur  = conn.cursor()
        conditions, params = [], []
        if reg_no:
            conditions.append("REG_NO = :reg")
            params.append(reg_no)
        if roll:
            conditions.append("EXM_ROLL = :roll")
            params.append(roll)

        sql = f"""
            SELECT MASTER_ID, EXM_NAME, REG_NO, EXM_ROLL, EXM_YR
            FROM   NU_DATA
            WHERE  {' AND '.join(conditions)}
            ORDER  BY EXM_YR DESC
        """
        cur.execute(sql, params)
        cols = [d[0] for d in cur.description]
        rows = [dict(zip(cols, row)) for row in cur.fetchall()]
        cur.close()
        conn.close()
        print(f"[DB] results fetched: {len(rows)} rows")
    except Exception as e:
        print(f"[DB ERROR] _get_results: {e}")

    cache.set("results", rows, ttl=1800, reg_no=reg_no, roll=roll)
    return rows


def _get_student(master_id: str) -> dict | None:
    """Fetch student detail — cached 2 hours per master_id."""
    cached = cache.get("student", master_id=master_id)
    if cached is not None:
        print(f"[CACHE HIT] student master_id={master_id}")
        return cached

    student = None
    try:
        conn = db.get_connection()
        cur  = conn.cursor()
        cur.execute(
            "SELECT * FROM NU_DATA WHERE MASTER_ID = :1",
            [master_id]
        )
        cols = [d[0] for d in cur.description]
        row  = cur.fetchone()
        cur.close()
        conn.close()
        if row:
            student = dict(zip(cols, row))
            print(f"[DB] student fetched: {master_id}")
    except Exception as e:
        print(f"[DB ERROR] _get_student: {e}")

    if student:
        cache.set("student", student, ttl=7200, master_id=master_id)
    return student


def _get_image(master_id: str) -> str | None:
    """
    Fetch base64 image from T_IMAGES — cached 2 hours.
    This is the heaviest call; cache makes repeat loads instant.
    """
    cached = cache.get("image", master_id=master_id)
    if cached is not None:
        print(f"[CACHE HIT] image master_id={master_id}")
        return cached

    image_b64 = None
    try:
        conn = db.get_connection()
        cur  = conn.cursor()
        cur.execute(
            "SELECT IMAGE FROM T_IMAGES WHERE MASTER_ID = :1",
            [master_id]
        )
        row = cur.fetchone()
        cur.close()
        conn.close()

        if row and row[0]:
            raw = row[0]
            if isinstance(raw, oracledb.LOB):
                raw = raw.read()
            if isinstance(raw, (bytes, bytearray)):
                image_b64 = base64.b64encode(raw).decode("utf-8")
            elif isinstance(raw, str):
                if "base64," in raw:
                    image_b64 = raw.split("base64,", 1)[1].strip()
                else:
                    image_b64 = raw.strip()
            print(f"[DB] image fetched: {master_id}")
    except Exception as e:
        print(f"[DB ERROR] _get_image: {e}")

    if image_b64:
        cache.set("image", image_b64, ttl=7200, master_id=master_id)
    return image_b64


# ─────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app.run(debug=False, threaded=True)
