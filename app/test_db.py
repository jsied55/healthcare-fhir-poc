from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_db_check_ok(monkeypatch):
    monkeypatch.setenv("DB_HOST", "db.example")
    monkeypatch.setenv("DB_NAME", "fhir")
    monkeypatch.setenv("DB_USER", "user")
    monkeypatch.setenv("DB_PASSWORD", "password")

    conn = MagicMock()
    conn.__enter__.return_value = conn
    conn.__exit__.return_value = False
    conn.execute.return_value.fetchone.return_value = (1,)

    with patch("db.psycopg.connect", return_value=conn):
        response = client.get("/db-check")

    assert response.json() == {"db": "ok", "result": 1}