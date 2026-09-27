#!/usr/bin/env bash
#
# Container entrypoint for Odoo on DigitalOcean App Platform.
#
# 1. Builds /etc/odoo/odoo.conf from environment variables.
# 2. Waits for PostgreSQL.
# 3. Initialises the database on first start (`-i base`).
# 4. Installs the modules of ODOO_ENSURE_MODULES that are missing.
# 5. Runs deploy/init_db_storage.py so attachments live in PostgreSQL.
# 6. Starts the Odoo server (or whatever command was given).
#
# Environment variables (all optional unless stated otherwise):
#
#   DATABASE_URL            postgresql://user:pass@host:port/db?sslmode=require
#   DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME, DB_SSLMODE
#                           Discrete connection settings; they take precedence
#                           over DATABASE_URL. DB_HOST and DB_NAME are required
#                           when DATABASE_URL is not set.
#   DB_CA_CERT              PEM CA certificate of the server (for verify-ca /
#                           verify-full).
#   DB_WAIT_TIMEOUT         Seconds to wait for PostgreSQL (default 300).
#
#   ODOO_ADMIN_PASSWD       Master password (database manager). A random one
#                           is generated when unset; the manager is disabled
#                           anyway (list_db = False).
#   ODOO_ADMIN_USER_PASSWORD
#                           Password given to the "admin" user when the
#                           database is created (default: admin).
#   ODOO_INIT_MODULES       Modules installed at database creation (base).
#   ODOO_WITH_DEMO          true/false: install demo data at creation (false).
#   ODOO_INIT_LANGUAGE      Languages to load at creation, e.g. el_GR.
#   ODOO_ENSURE_MODULES     Modules that must be installed, comma separated;
#                           the missing ones are installed before the server
#                           starts, so a module added to the image shows up
#                           on the next deploy (default: web_home_menu; set
#                           it empty to disable).
#   ODOO_EXTRA_ADDONS_PATH  Extra addons directories, comma separated.
#
# Note: Odoo itself also reads ODOO_<OPTION> variables (e.g. ODOO_WORKERS,
# ODOO_LOG_LEVEL) and they take precedence over odoo.conf; the names used here
# match that convention on purpose, so both mechanisms agree.
#   ODOO_WORKERS            0 = threaded mode (single port, websocket OK).
#   ODOO_MAX_CRON_THREADS   Default 1.
#   ODOO_DB_MAXCONN         Default 16 (small managed clusters allow ~22).
#   ODOO_LOG_LEVEL          Default info.
#   ODOO_LIMIT_TIME_CPU / ODOO_LIMIT_TIME_REAL / ODOO_LIMIT_MEMORY_SOFT /
#   ODOO_LIMIT_MEMORY_HARD  Worker limits (only enforced when workers > 0).
#   ODOO_UNACCENT           true/false (default true).
#   ODOO_EXTRA_CONF         Extra lines appended verbatim to [options]
#                           (e.g. SMTP settings), newline separated.
#   ODOO_SKIP_DB_INIT       1 = never run the initial `-i base`.
#   ODOO_SKIP_BOOTSTRAP     1 = never run deploy/init_db_storage.py.
#   PORT                    HTTP port (App Platform sets it; default 8069).
#
set -Eeuo pipefail

ODOO_ROOT="${ODOO_ROOT:-/opt/odoo}"
ODOO_RC="${ODOO_RC:-/etc/odoo/odoo.conf}"
ODOO_DATA_DIR="${ODOO_DATA_DIR:-/var/lib/odoo}"
ODOO_BIN=(python3 "${ODOO_ROOT}/odoo-bin")

log() {
    printf '%s entrypoint: %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

is_true() {
    case "${1:-}" in
        1|true|TRUE|True|yes|YES|Yes|on|ON|On) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 1. Database connection settings
# ---------------------------------------------------------------------------
if [ -n "${DATABASE_URL:-}" ]; then
    # Fill the DB_* variables that are not already set from DATABASE_URL.
    eval "$(python3 - "${DATABASE_URL}" <<'PY'
import shlex
import sys
from urllib.parse import parse_qs, unquote, urlsplit

url = urlsplit(sys.argv[1])
query = parse_qs(url.query)
values = {
    "URL_DB_HOST": url.hostname or "",
    "URL_DB_PORT": str(url.port or ""),
    "URL_DB_USER": unquote(url.username or ""),
    "URL_DB_PASSWORD": unquote(url.password or ""),
    "URL_DB_NAME": url.path.lstrip("/"),
    "URL_DB_SSLMODE": query.get("sslmode", [""])[0],
}
for key, value in values.items():
    print(f"{key}={shlex.quote(value)}")
PY
)"
    DB_HOST="${DB_HOST:-${URL_DB_HOST}}"
    DB_PORT="${DB_PORT:-${URL_DB_PORT}}"
    DB_USER="${DB_USER:-${URL_DB_USER}}"
    DB_PASSWORD="${DB_PASSWORD:-${URL_DB_PASSWORD}}"
    DB_NAME="${DB_NAME:-${URL_DB_NAME}}"
    DB_SSLMODE="${DB_SSLMODE:-${URL_DB_SSLMODE}}"
fi

DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-odoo}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-}"
DB_SSLMODE="${DB_SSLMODE:-prefer}"

[ -n "${DB_HOST}" ] || die "DB_HOST (or DATABASE_URL) is required"
[ -n "${DB_NAME}" ] || die "DB_NAME (or a database in DATABASE_URL) is required"
case "${DB_SSLMODE}" in
    disable|allow|prefer|require|verify-ca|verify-full) ;;
    *) die "DB_SSLMODE must be one of disable, allow, prefer, require, verify-ca, verify-full" ;;
esac

mkdir -p "${ODOO_DATA_DIR}"

if [ -n "${DB_CA_CERT:-}" ]; then
    (umask 077 && printf '%s\n' "${DB_CA_CERT}" > "${ODOO_DATA_DIR}/db-ca.crt")
    export PGSSLROOTCERT="${ODOO_DATA_DIR}/db-ca.crt"
fi

# Convenience for psql / pg_dump from the console; identical to odoo.conf.
export PGHOST="${DB_HOST}" PGPORT="${DB_PORT}" PGUSER="${DB_USER}" \
       PGPASSWORD="${DB_PASSWORD}" PGDATABASE="${DB_NAME}" PGSSLMODE="${DB_SSLMODE}"

# ---------------------------------------------------------------------------
# 2. odoo.conf
# ---------------------------------------------------------------------------
if [ -z "${ODOO_ADMIN_PASSWD:-}" ]; then
    ODOO_ADMIN_PASSWD="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
    log "ODOO_ADMIN_PASSWD not set: generated a random master password (database manager is disabled anyway)"
fi

ADDONS_PATH="${ODOO_ROOT}/odoo/addons,${ODOO_ROOT}/addons"
if [ -n "${ODOO_EXTRA_ADDONS_PATH:-}" ]; then
    ADDONS_PATH="${ADDONS_PATH},${ODOO_EXTRA_ADDONS_PATH}"
fi

if is_true "${ODOO_UNACCENT:-true}"; then UNACCENT=True; else UNACCENT=False; fi
if is_true "${ODOO_PROXY_MODE:-true}"; then PROXY_MODE=True; else PROXY_MODE=False; fi

mkdir -p "$(dirname "${ODOO_RC}")"
(
    umask 077
    cat > "${ODOO_RC}" <<CONF
[options]
; generated by deploy/entrypoint.sh at container start - do not edit by hand
addons_path = ${ADDONS_PATH}
data_dir = ${ODOO_DATA_DIR}

; --- database ---
db_host = ${DB_HOST}
db_port = ${DB_PORT}
db_user = ${DB_USER}
db_password = ${DB_PASSWORD}
db_name = ${DB_NAME}
db_sslmode = ${DB_SSLMODE}
; managed clusters expose a single database: use it for bus/cron too
db_system = ${DB_NAME}
db_maxconn = ${ODOO_DB_MAXCONN:-16}
dbfilter = ^${DB_NAME}\$
list_db = False
unaccent = ${UNACCENT}

; --- http ---
http_interface = 0.0.0.0
http_port = ${PORT:-8069}
gevent_port = ${ODOO_GEVENT_PORT:-8072}
proxy_mode = ${PROXY_MODE}
x_sendfile = False

; --- processes ---
workers = ${ODOO_WORKERS:-0}
max_cron_threads = ${ODOO_MAX_CRON_THREADS:-1}
limit_time_cpu = ${ODOO_LIMIT_TIME_CPU:-600}
limit_time_real = ${ODOO_LIMIT_TIME_REAL:-1200}
limit_memory_soft = ${ODOO_LIMIT_MEMORY_SOFT:-1073741824}
limit_memory_hard = ${ODOO_LIMIT_MEMORY_HARD:-1610612736}
limit_request = ${ODOO_LIMIT_REQUEST:-65536}

; --- misc ---
admin_passwd = ${ODOO_ADMIN_PASSWD}
log_level = ${ODOO_LOG_LEVEL:-info}
${ODOO_EXTRA_CONF:-}
CONF
)
log "wrote ${ODOO_RC} (db ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}, sslmode=${DB_SSLMODE})"

# ---------------------------------------------------------------------------
# 3. Wait for PostgreSQL
# ---------------------------------------------------------------------------
wait_for_db() {
    python3 - "${DB_WAIT_TIMEOUT:-300}" <<'PY'
import sys
import time

import psycopg2

timeout = float(sys.argv[1])
deadline = time.monotonic() + timeout
attempt = 0
while True:
    attempt += 1
    try:
        psycopg2.connect(connect_timeout=10).close()  # uses PG* env vars
        break
    except psycopg2.Error as exc:
        if time.monotonic() >= deadline:
            print(f"entrypoint: PostgreSQL still unreachable after {timeout:.0f}s: {exc}", file=sys.stderr)
            sys.exit(1)
        if attempt == 1 or attempt % 10 == 0:
            print(f"entrypoint: waiting for PostgreSQL ({exc.__class__.__name__}: {str(exc).strip()})", file=sys.stderr)
        time.sleep(3)
PY
}

# Prints "empty" (no Odoo tables), "partial" (base not installed) or "ready".
db_state() {
    python3 - <<'PY'
import psycopg2

with psycopg2.connect(connect_timeout=10) as conn, conn.cursor() as cr:
    cr.execute("SELECT to_regclass('ir_module_module')")
    if cr.fetchone()[0] is None:
        print("empty")
    else:
        cr.execute("SELECT state FROM ir_module_module WHERE name = 'base'")
        row = cr.fetchone()
        print("ready" if row and row[0] == "installed" else "partial")
PY
}

# Prints the modules of $1 (comma separated) that are not installed. A module
# unknown to the database (added to the image after the database was created)
# counts as missing: `odoo-bin -i` refreshes the module list before installing.
missing_modules() {
    python3 - "$1" <<'PY'
import sys

import psycopg2

wanted = [name.strip() for name in sys.argv[1].split(",") if name.strip()]
with psycopg2.connect(connect_timeout=10) as conn, conn.cursor() as cr:
    cr.execute(
        "SELECT name FROM ir_module_module WHERE state = 'installed' AND name = ANY(%s)",
        (wanted,),
    )
    installed = {row[0] for row in cr.fetchall()}
print(",".join(name for name in wanted if name not in installed))
PY
}

# Best effort: the extensions improve search (accent-insensitive, trigram).
create_extensions() {
    python3 - <<'PY'
import sys

import psycopg2

conn = psycopg2.connect(connect_timeout=10)
conn.autocommit = True
with conn.cursor() as cr:
    for ext in ("pg_trgm", "unaccent"):
        try:
            cr.execute(f"CREATE EXTENSION IF NOT EXISTS {ext}")
        except psycopg2.Error as exc:
            print(f"entrypoint: could not create extension {ext}: {str(exc).strip()}", file=sys.stderr)
conn.close()
PY
}

# ---------------------------------------------------------------------------
# 4./5./6. Initialise and bootstrap the database, then start Odoo
# ---------------------------------------------------------------------------
prepare_database() {
    log "waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}"
    wait_for_db

    local state fresh_init=0
    state="$(db_state)"
    log "database ${DB_NAME} state: ${state}"

    if [ "${state}" != "ready" ]; then
        if [ "${ODOO_SKIP_DB_INIT:-0}" = "1" ]; then
            die "database ${DB_NAME} is not initialised and ODOO_SKIP_DB_INIT=1"
        fi
        create_extensions
        local -a init_args=(-d "${DB_NAME}" -i "${ODOO_INIT_MODULES:-base}" --stop-after-init)
        if is_true "${ODOO_WITH_DEMO:-false}"; then
            init_args+=(--with-demo)   # default: no demo data
        fi
        if [ -n "${ODOO_INIT_LANGUAGE:-}" ]; then
            init_args+=(--load-language "${ODOO_INIT_LANGUAGE}")
        fi
        log "initialising database ${DB_NAME}: odoo-bin ${init_args[*]} (this takes a few minutes)"
        "${ODOO_BIN[@]}" -c "${ODOO_RC}" "${init_args[@]}"
        fresh_init=1
        log "database ${DB_NAME} initialised"
    fi

    local ensure_modules="${ODOO_ENSURE_MODULES-web_home_menu}" missing
    if [ -n "${ensure_modules}" ]; then
        missing="$(missing_modules "${ensure_modules}")"
        if [ -n "${missing}" ]; then
            log "installing missing module(s) ${missing} (this takes a minute)"
            "${ODOO_BIN[@]}" -c "${ODOO_RC}" -d "${DB_NAME}" -i "${missing}" --stop-after-init
            log "module(s) ${missing} installed"
        fi
    fi

    if [ "${ODOO_SKIP_BOOTSTRAP:-0}" != "1" ]; then
        log "running deploy/init_db_storage.py (attachments stored in PostgreSQL)"
        ODOO_FRESH_INIT="${fresh_init}" "${ODOO_BIN[@]}" shell -c "${ODOO_RC}" -d "${DB_NAME}" --no-http \
            < "${ODOO_ROOT}/deploy/init_db_storage.py"
    fi
}

case "${1:-odoo}" in
    odoo|odoo-bin|server)
        shift
        prepare_database
        log "starting Odoo on port ${PORT:-8069}"
        exec "${ODOO_BIN[@]}" -c "${ODOO_RC}" "$@"
        ;;
    -*)
        prepare_database
        exec "${ODOO_BIN[@]}" -c "${ODOO_RC}" "$@"
        ;;
    *)
        exec "$@"
        ;;
esac
