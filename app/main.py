import os

from fastapi import FastAPI
from db import router as db_router

app = FastAPI(title="FHIR POC API")
app.include_router(db_router)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/version")
def version():
    return {"version": os.getenv("APP_VERSION", "dev")}