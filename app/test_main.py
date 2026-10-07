from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_version_defaults_to_dev(monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    response = client.get("/version")
    assert response.json() == {"version": "dev"}


def test_version_reads_environment(monkeypatch):
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    response = client.get("/version")
    assert response.json() == {"version": "1.2.3"}