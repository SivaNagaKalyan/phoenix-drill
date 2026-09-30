"""Runtime configuration, read once from the environment."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    database_url: str
    pool_min: int
    pool_max: int
    max_bulk: int

    @classmethod
    def from_env(cls) -> Settings:
        url = os.environ.get("DATABASE_URL")
        if not url:
            host = os.environ.get("PGHOST", "localhost")
            port = os.environ.get("PGPORT", "5432")
            user = os.environ.get("PGUSER", "ledger")
            password = os.environ.get("PGPASSWORD", "")
            name = os.environ.get("PGDATABASE", "ledger")
            url = f"postgresql://{user}:{password}@{host}:{port}/{name}"
        return cls(
            database_url=url,
            pool_min=int(os.environ.get("DB_POOL_MIN", "1")),
            pool_max=int(os.environ.get("DB_POOL_MAX", "5")),
            max_bulk=int(os.environ.get("MAX_BULK_RECORDS", "50000")),
        )
