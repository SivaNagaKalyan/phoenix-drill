from ledger.config import Settings


def test_database_url_takes_precedence(monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "postgresql://u:p@h:1/d")
    monkeypatch.setenv("PGHOST", "ignored")
    assert Settings.from_env().database_url == "postgresql://u:p@h:1/d"


def test_url_built_from_pg_env(monkeypatch):
    monkeypatch.delenv("DATABASE_URL", raising=False)
    for k, v in {"PGHOST": "db", "PGPORT": "5433", "PGUSER": "u", "PGPASSWORD": "p", "PGDATABASE": "d"}.items():
        monkeypatch.setenv(k, v)
    assert Settings.from_env().database_url == "postgresql://u:p@db:5433/d"
