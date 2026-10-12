import os

import psycopg
from fastapi import APIRouter

router = APIRouter()


@router.get("/db-check")
def db_check():
    with psycopg.connect(
        host=os.environ["DB_HOST"],
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
        sslmode="require",
    ) as conn:
        row = conn.execute("select 1").fetchone()
    return {"db": "ok", "result": row[0]}