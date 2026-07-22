import os
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SILVER_PATH = PROJECT_ROOT / "data" / "parquet" / "silver"
# Mismo criterio que ingest_silver.py: localhost fuera de Docker, hostname del servicio dentro.
POSTGRES_URL = os.environ.get(
    "POSTGRES_URL", "postgresql+psycopg2://bootcamp:bootcamp@localhost:5432/gold"
)

DOMAINS = ["university", "billing", "crm"]

# Todas las tablas Silver se cargan a staging tal cual (staging = espejo de Silver, sin volver a
# Bronze). Las transformaciones de negocio y el modelo dimensional se resuelven en SQL (sql/gold/).


def cargar_tabla_silver(engine, dominio, tabla):
    ruta = SILVER_PATH / dominio / f"{tabla}.parquet"
    if not ruta.exists():
        raise FileNotFoundError(f"No existe {ruta}. Ejecuta ingest_silver.py primero.")

    df = pd.read_parquet(ruta)
    df.to_sql(tabla, engine, schema="staging", if_exists="replace", index=False)
    print(f"OK: staging.{tabla} <- silver/{dominio} -> {len(df)} filas")
    return len(df)


def cargar_staging():
    engine = create_engine(POSTGRES_URL)

    with engine.begin() as conn:
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS staging"))
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS gold"))

    total_filas = 0
    tablas_procesadas = 0

    for dominio in DOMAINS:
        for parquet in sorted((SILVER_PATH / dominio).glob("*.parquet")):
            tabla = parquet.stem
            total_filas += cargar_tabla_silver(engine, dominio, tabla)
            tablas_procesadas += 1

    print(f"\nCarga staging completada: {tablas_procesadas} tablas, {total_filas} filas.")
    return engine


if __name__ == "__main__":
    cargar_staging()
