"""
Database connection helper for the Banking Management System.

Reads connection settings from config.py and provides a small API:
    fetch_all(sql, params)       — list of dict rows
    fetch_one(sql, params)       — one dict row or None
    execute(sql, params)         — runs INSERT/UPDATE/DELETE
    callproc(name, params, out)  — wraps cursor.callproc() with auto-commit

All methods open and close a fresh connection per call. For a small back-office
app this is simple and safe; a future enhancement (mentioned in the report's
Future Work section) is to introduce a connection pool.
"""

import mysql.connector
from mysql.connector import Error
from contextlib import contextmanager

from config import DB_CONFIG


def _connect():
    return mysql.connector.connect(**DB_CONFIG)


@contextmanager
def _cursor(commit: bool = False, dictionary: bool = False):
    cnx = _connect()
    cur = cnx.cursor(dictionary=dictionary)
    try:
        yield cur
        if commit:
            cnx.commit()
    except Exception:
        cnx.rollback()
        raise
    finally:
        cur.close()
        cnx.close()


def fetch_all(sql: str, params: tuple = ()) -> list[dict]:
    with _cursor(dictionary=True) as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def fetch_one(sql: str, params: tuple = ()) -> dict | None:
    with _cursor(dictionary=True) as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def execute(sql: str, params: tuple = ()) -> int:
    """Run INSERT/UPDATE/DELETE.  Returns lastrowid (for INSERTs) or 0."""
    with _cursor(commit=True) as cur:
        cur.execute(sql, params)
        return cur.lastrowid or 0


def callproc(proc_name: str, args: list, out_indices: list[int] | None = None):
    """Call a stored procedure with auto-commit.

    Args:
        proc_name:   procedure name, e.g. 'sp_Deposit'
        args:        list of all IN and OUT arguments in declared order.
                     For OUT params, pass any placeholder (e.g. 0) — the
                     value is returned via out_indices.
        out_indices: indices in `args` that are OUT params; their post-call
                     values are returned as a tuple, in order.

    Returns:
        Tuple of OUT values if out_indices given, else None.

    Raises:
        mysql.connector.Error  on SQL-side failure (caught and shown by UI).
    """
    cnx = _connect()
    cur = cnx.cursor()
    try:
        result = cur.callproc(proc_name, args)
        cnx.commit()
        if out_indices:
            return tuple(result[i] for i in out_indices)
        return None
    finally:
        cur.close()
        cnx.close()


def test_connection() -> tuple[bool, str]:
    """Return (ok, message). Used by the app on startup."""
    try:
        with _cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        return True, "Connection OK"
    except Error as e:
        return False, f"MySQL error: {e}"
    except Exception as e:
        return False, f"Error: {e}"
