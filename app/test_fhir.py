import logging
from unittest.mock import MagicMock, patch

import pytest
from botocore.exceptions import ClientError
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)

PATIENT = {"resourceType": "Patient", "id": "p1", "name": [{"family": "SENTINELNAME"}]}


def observation(ref):
    return {
        "resourceType": "Observation",
        "id": "o1",
        "status": "final",
        "code": {"text": "test"},
        "subject": {"reference": ref},
    }


def bundle(*resources):
    return {
        "resourceType": "Bundle",
        "type": "collection",
        "entry": [{"resource": r} for r in resources],
    }


@pytest.fixture(autouse=True)
def bucket(monkeypatch):
    monkeypatch.setenv("FHIR_BUCKET", "test-bucket")


def test_valid_bundle_is_stored(caplog):
    s3 = MagicMock()
    caplog.set_level(logging.INFO)
    with patch("fhir_api.s3_client", return_value=s3):
        r = client.post("/fhir/bundle", json=bundle(PATIENT, observation("Patient/p1")))
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "stored"
    assert body["entries"] == 2
    kwargs = s3.put_object.call_args.kwargs
    assert kwargs["Bucket"] == "test-bucket"
    assert kwargs["Key"].startswith("incoming/")
    assert "SENTINELNAME" not in caplog.text


def test_malformed_bundle_is_rejected():
    s3 = MagicMock()
    bad = {"resourceType": "Bundle", "entry": [{"resource": PATIENT}]}
    with patch("fhir_api.s3_client", return_value=s3):
        r = client.post("/fhir/bundle", json=bad)
    assert r.status_code == 422
    assert r.json()["error"] == "invalid_bundle"
    s3.put_object.assert_not_called()


def test_dangling_reference_is_rejected():
    s3 = MagicMock()
    with patch("fhir_api.s3_client", return_value=s3):
        r = client.post(
            "/fhir/bundle", json=bundle(PATIENT, observation("Patient/missing"))
        )
    assert r.status_code == 422
    assert "Patient/missing" in r.json()["problems"]
    s3.put_object.assert_not_called()


def test_non_json_body_is_rejected():
    r = client.post(
        "/fhir/bundle", content="not json", headers={"content-type": "application/json"}
    )
    assert r.status_code == 422


def test_storage_failure_returns_502():
    s3 = MagicMock()
    s3.put_object.side_effect = ClientError(
        {"Error": {"Code": "AccessDenied"}}, "PutObject"
    )
    with patch("fhir_api.s3_client", return_value=s3):
        r = client.post("/fhir/bundle", json=bundle(PATIENT))
    assert r.status_code == 502
    assert r.json()["error"] == "storage_failed"