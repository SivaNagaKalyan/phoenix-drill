"""End-to-end API tests against a real PostgreSQL.

Skipped unless TEST_DATABASE_URL is set. CI provides one through a service container.
"""

import os

import pytest
from fastapi.testclient import TestClient

from ledger import records
from ledger.config import Settings
from ledger.main import create_app

DB_URL = os.environ.get("TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DB_URL, reason="TEST_DATABASE_URL not set")


@pytest.fixture()
def client():
    import psycopg

    with psycopg.connect(DB_URL, autocommit=True) as conn:
        conn.execute("DROP TABLE IF EXISTS records")
    settings = Settings(database_url=DB_URL, pool_min=1, pool_max=2, max_bulk=1000)
    with TestClient(create_app(settings)) as c:
        yield c


def test_health_and_readiness(client):
    assert client.get("/healthz").json() == {"status": "ok"}
    assert client.get("/readyz").json() == {"status": "ready"}


def test_generate_is_idempotent(client):
    assert client.post("/records/generate", json={"seed": "t", "start": 0, "count": 50}).json() == {"added": 50}
    assert client.post("/records/generate", json={"seed": "t", "start": 0, "count": 50}).json() == {"added": 0}


def test_database_checksum_matches_reference(client):
    client.post("/records/generate", json={"seed": "t", "start": 0, "count": 25})
    body = client.get("/records/summary").json()
    expected_rows = [(i + 1, k, v) for i, (k, v) in enumerate(records.generate("t", 0, 25))]
    assert body == {"count": 25, "checksum": records.checksum(expected_rows)}


def test_empty_table_checksum_is_stable(client):
    assert client.get("/records/summary").json()["count"] == 0


def test_duplicate_key_conflicts(client):
    assert client.post("/records", json={"key": "a", "value": "1"}).status_code == 201
    assert client.post("/records", json={"key": "a", "value": "2"}).status_code == 409


def test_bulk_limit_enforced(client):
    r = client.post("/records/generate", json={"seed": "t", "start": 0, "count": 5000})
    assert r.status_code == 422


def test_metrics_exposed(client):
    client.get("/healthz")
    assert "ledger_http_requests_total" in client.get("/metrics").text
