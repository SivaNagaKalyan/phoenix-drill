"""Database access. Plain SQL, no ORM, so the backup and restore surface is obvious."""

from __future__ import annotations

from psycopg_pool import ConnectionPool

from . import records

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS records (
    id         BIGSERIAL PRIMARY KEY,
    key        TEXT        NOT NULL UNIQUE,
    value      TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""

# Advisory lock id so that several replicas starting together do not race on DDL.
MIGRATION_LOCK_ID = 7_202_609

CHECKSUM_SQL = """
SELECT count(*),
       encode(sha256(convert_to(
           coalesce(string_agg(id::text || ':' || key || ':' || value, ',' ORDER BY id), ''),
           'UTF8')), 'hex')
FROM records;
"""


class Store:
    def __init__(self, pool: ConnectionPool) -> None:
        self.pool = pool

    def migrate(self) -> None:
        with self.pool.connection() as conn:
            conn.execute("SELECT pg_advisory_lock(%s)", (MIGRATION_LOCK_ID,))
            try:
                conn.execute(SCHEMA_SQL)
                conn.commit()
            finally:
                conn.execute("SELECT pg_advisory_unlock(%s)", (MIGRATION_LOCK_ID,))
                conn.commit()

    def ping(self) -> bool:
        with self.pool.connection() as conn:
            return conn.execute("SELECT 1").fetchone() == (1,)

    def insert(self, key: str, value: str) -> int:
        with self.pool.connection() as conn:
            row = conn.execute("INSERT INTO records (key, value) VALUES (%s, %s) RETURNING id", (key, value)).fetchone()
            return int(row[0])

    def insert_generated(self, seed: str, start: int, count: int) -> int:
        """Insert deterministic records, skipping keys that already exist. Returns rows added."""
        with self.pool.connection() as conn:
            with conn.cursor() as cur:
                before = cur.execute("SELECT count(*) FROM records").fetchone()[0]
                cur.executemany(
                    "INSERT INTO records (key, value) VALUES (%s, %s) ON CONFLICT (key) DO NOTHING",
                    list(records.generate(seed, start, count)),
                )
                after = cur.execute("SELECT count(*) FROM records").fetchone()[0]
            return int(after - before)

    def summary(self) -> tuple[int, str]:
        with self.pool.connection() as conn:
            count, digest = conn.execute(CHECKSUM_SQL).fetchone()
            return int(count), str(digest)
