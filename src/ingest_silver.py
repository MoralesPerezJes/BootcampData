import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text

from silver_transforms import apply_transforms

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BRONZE_PATH = PROJECT_ROOT / "data" / "parquet" / "bronze"
SILVER_PATH = PROJECT_ROOT / "data" / "parquet" / "silver"
# Fuera de Docker (notebooks/scripts locales) postgres se ve en localhost.
# Dentro de los contenedores de Airflow se usa el hostname del servicio (ver docker-compose.yml).
POSTGRES_URL = os.environ.get(
    "POSTGRES_URL", "postgresql+psycopg2://bootcamp:bootcamp@localhost:5432/gold"
)

DOMAINS = ["university", "billing", "crm"]

# Tablas que pasan de bronze a silver sin transformacion
TABLAS_SIN_CAMBIO = [
    ("university", "courses"),
    ("university", "enrollments"),
    ("university", "professors"),
    ("university", "semesters"),
    ("university", "students"),
    ("billing", "customers"),
    ("billing", "products"),
    ("crm", "accounts"),
    ("crm", "activities"),
    ("crm", "leads"),
    ("crm", "opportunities"),
    ("crm", "opportunity_contacts"),
]

# Tablas que se transforman (deben existir en bronze)
TABLAS_A_TRANSFORMAR = [
    ("crm", "contacts"),
    ("billing", "subscriptions"),
    ("billing", "invoice_items"),
    ("billing", "invoices"),
    ("billing", "payments"),
    ("university", "grades"),
]


def leer_bronze(dominio, tabla):
    ruta = BRONZE_PATH / dominio / f"{tabla}.parquet"
    if not ruta.exists():
        raise FileNotFoundError(f"No existe {ruta}. Ejecuta ingest_bronze.py primero.")

    df = pd.read_parquet(ruta)
    cols_bronze = ["_ingested_at", "_source_file", "_source_domain"]
    return df.drop(columns=[c for c in cols_bronze if c in df.columns])


def guardar_silver(df, dominio, tabla):
    carpeta = SILVER_PATH / dominio
    carpeta.mkdir(parents=True, exist_ok=True)
    archivo = carpeta / f"{tabla}.parquet"
    df.to_parquet(archivo, index=False)
    print(f"OK: {dominio}/{tabla} -> {len(df)} filas -> {archivo.relative_to(PROJECT_ROOT)}")
    return len(df)


def guardar_incidencias_postgres(incidencias):
    engine = create_engine(POSTGRES_URL)
    sql_crear = """
        CREATE TABLE IF NOT EXISTS incidencias (
            id SERIAL PRIMARY KEY,
            capa VARCHAR(50) NOT NULL,
            tabla VARCHAR(150) NOT NULL,
            columna VARCHAR(150),
            regla VARCHAR(255) NOT NULL,
            descripcion TEXT NOT NULL
        )
    """
    sql_insertar = text(
        """
        INSERT INTO incidencias (capa, tabla, columna, regla, descripcion)
        VALUES (:capa, :tabla, :columna, :regla, :descripcion)
        """
    )

    with engine.begin() as conn:
        conn.execute(text(sql_crear))
        conn.execute(text("TRUNCATE TABLE incidencias RESTART IDENTITY"))
        for inc in incidencias:
            conn.execute(sql_insertar, inc)


def cargar_tablas_bronze():
    tablas = {}

    for dominio, tabla in TABLAS_A_TRANSFORMAR:
        tablas[(dominio, tabla)] = leer_bronze(dominio, tabla)

    for dominio, tabla in TABLAS_SIN_CAMBIO:
        tablas[(dominio, tabla)] = leer_bronze(dominio, tabla)

    return tablas


def ingest_all():
    run_id = str(uuid.uuid4())
    ejecutado_at = datetime.now(timezone.utc)
    ctx = {
        "incidencias": [],
        "run_id": run_id,
        "ejecutado_at": ejecutado_at,
    }

    tablas = cargar_tablas_bronze()
    tablas = apply_transforms(tablas, ctx)

    total_filas = 0
    for dominio in DOMAINS:
        for parquet in sorted((BRONZE_PATH / dominio).glob("*.parquet")):
            tabla = parquet.stem
            total_filas += guardar_silver(tablas[(dominio, tabla)], dominio, tabla)

    guardar_incidencias_postgres(ctx["incidencias"])
    print(f"\nIncidencias registradas: {len(ctx['incidencias'])} (pipeline_run_id={run_id})")
    print(f"Ingesta Silver completada: 18 tablas, {total_filas} filas.")


if __name__ == "__main__":
    ingest_all()
