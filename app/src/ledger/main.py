"""HTTP API for the ledger service."""

from __future__ import annotations

import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from psycopg import errors
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field

from . import __version__
from .config import Settings
from .db import Store

logging.basicConfig(level=logging.INFO, format='{"level":"%(levelname)s","msg":"%(message)s"}')
log = logging.getLogger("ledger")

REQUESTS = Counter("ledger_http_requests_total", "HTTP requests", ["method", "route", "status"])
LATENCY = Histogram("ledger_http_request_seconds", "HTTP request latency", ["method", "route"])


class RecordIn(BaseModel):
    key: str = Field(min_length=1, max_length=128)
    value: str = Field(min_length=1, max_length=1024)


class GenerateIn(BaseModel):
    seed: str = Field(min_length=1, max_length=32, pattern=r"^[a-z0-9-]+$")
    start: int = Field(ge=0)
    count: int = Field(ge=1)


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        pool = ConnectionPool(
            settings.database_url,
            min_size=settings.pool_min,
            max_size=settings.pool_max,
            open=False,
        )
        pool.open(wait=True, timeout=30)
        store = Store(pool)
        store.migrate()
        app.state.store = store
        log.info("ledger %s started", __version__)
        try:
            yield
        finally:
            pool.close()

    app = FastAPI(title="ledger", version=__version__, lifespan=lifespan)

    @app.middleware("http")
    async def metrics(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        # The matched route template keeps label cardinality bounded.
        route = request.scope.get("route")
        path = route.path if route is not None else "unmatched"
        LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
        REQUESTS.labels(request.method, path, str(response.status_code)).inc()
        return response

    @app.get("/healthz")
    def healthz() -> dict:
        # Liveness: the process is serving. Deliberately does not touch the database,
        # so a database outage does not cause a restart storm.
        return {"status": "ok"}

    @app.get("/readyz")
    def readyz(request: Request) -> dict:
        try:
            request.app.state.store.ping()
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=503, detail="database unavailable") from exc
        return {"status": "ready"}

    @app.post("/records", status_code=201)
    def create_record(body: RecordIn, request: Request) -> dict:
        try:
            rid = request.app.state.store.insert(body.key, body.value)
        except errors.UniqueViolation as exc:
            raise HTTPException(status_code=409, detail="key already exists") from exc
        return {"id": rid}

    @app.post("/records/generate")
    def generate_records(body: GenerateIn, request: Request) -> dict:
        if body.count > settings.max_bulk:
            raise HTTPException(status_code=422, detail=f"count exceeds {settings.max_bulk}")
        added = request.app.state.store.insert_generated(body.seed, body.start, body.count)
        return {"added": added}

    @app.get("/records/summary")
    def summary(request: Request) -> dict:
        count, digest = request.app.state.store.summary()
        return {"count": count, "checksum": digest}

    @app.get("/metrics")
    def prometheus() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    return app
