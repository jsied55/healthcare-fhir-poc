import json
import logging
import os
import uuid
from collections import Counter
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from fhir.resources.bundle import Bundle
from pydantic import ValidationError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fhir")
router = APIRouter()


def s3_client():
    return boto3.client("s3")


def find_references(node):
    """Yield every 'reference' string found anywhere inside a resource."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "reference" and isinstance(value, str):
                yield value
            else:
                yield from find_references(value)
    elif isinstance(node, list):
        for item in node:
            yield from find_references(item)


def dangling_references(bundle: dict) -> list[str]:
    """References that point at a resource that is not in the bundle."""
    known = set()
    for entry in bundle.get("entry", []):
        if entry.get("fullUrl"):
            known.add(entry["fullUrl"])
        resource = entry.get("resource", {})
        if resource.get("resourceType") and resource.get("id"):
            known.add(f"{resource['resourceType']}/{resource['id']}")
    missing = set()
    for entry in bundle.get("entry", []):
        for ref in find_references(entry.get("resource", {})):
            if ref.startswith(("#", "http://", "https://")):
                continue
            if ref not in known:
                missing.add(ref)
    return sorted(missing)


def reject(request_id: str, message: str, problems: list[str]):
    logger.info("request_id=%s rejected reason=%s", request_id, message)
    return JSONResponse(
        status_code=422,
        content={
            "error": "invalid_bundle",
            "message": message,
            "problems": problems,
            "request_id": request_id,
        },
    )


@router.post("/fhir/bundle")
async def post_bundle(request: Request):
    request_id = str(uuid.uuid4())
    try:
        payload = await request.json()
    except ValueError:
        return reject(request_id, "body is not valid JSON", [])
    if not isinstance(payload, dict) or payload.get("resourceType") != "Bundle":
        return reject(request_id, "body must be a FHIR Bundle", [])
    try:
        Bundle.model_validate(payload)
    except ValidationError as exc:
        problems = [
            f"{'.'.join(str(p) for p in e['loc'])}: {e['msg']}" for e in exc.errors()
        ]
        return reject(request_id, "not a valid FHIR Bundle", problems[:10])
    missing = dangling_references(payload)
    if missing:
        return reject(
            request_id, "bundle references resources that are not in it", missing[:10]
        )

    key = f"incoming/{datetime.now(timezone.utc):%Y-%m-%d}/{uuid.uuid4()}.json"
    try:
        s3_client().put_object(
            Bucket=os.environ["FHIR_BUCKET"],
            Key=key,
            Body=json.dumps(payload).encode(),
            ContentType="application/fhir+json",
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "unknown")
        logger.error("request_id=%s s3_put_failed code=%s", request_id, code)
        return JSONResponse(
            status_code=502,
            content={"error": "storage_failed", "request_id": request_id},
        )

    entries = payload.get("entry", [])
    types = Counter(e["resource"]["resourceType"] for e in entries if "resource" in e)
    logger.info(
        "request_id=%s stored key=%s entries=%d types=%s",
        request_id,
        key,
        len(entries),
        dict(types),
    )
    return {"status": "stored", "request_id": request_id, "key": key, "entries": len(entries)}