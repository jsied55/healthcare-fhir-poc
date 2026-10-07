import os

from fastapi import FastAPI

app = FastAPI(title="FHIR POC API")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/version")
def version():
    return {"version": os.getenv("APP_VERSION", "dev")}