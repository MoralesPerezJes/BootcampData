"""
DAG del pipeline Bronze -> Silver -> Gold.

Orquesta los scripts que ya existen en src/:
  1. check_raw_files  -> valida que esten los CSV de origen antes de arrancar
  2. ingest_bronze     -> src/ingest_bronze.py
  3. ingest_silver      -> src/ingest_silver.py (limpieza + incidencias)
  4. build_gold         -> src/build_gold.py (staging + modelo dimensional en sql/gold)
  5. validar_pipeline   -> chequeo simple de que las tablas gold no quedaron vacias

Cada tarea es idempotente porque los scripts de src/ sobrescriben sus salidas
(parquet con to_parquet, staging con if_exists="replace", gold con DROP+CREATE),
asi que re-ejecutar el DAG no duplica datos.

Tras `docker-compose up`, el servicio `airflow-trigger` espera 10 segundos
(PIPELINE_STARTUP_DELAY_SECONDS) y dispara este DAG automaticamente.
El schedule @daily sigue disponible para corridas programadas manuales en la UI.
"""
import logging
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.exceptions import AirflowFailException
from airflow.operators.python import PythonOperator

# Los scripts de src/ se importan como modulos top-level (ingest_silver.py hace
# "from silver_transforms import ..."), por eso hace falta esta carpeta en el path.
SRC_PATH = "/opt/airflow/src"
if SRC_PATH not in sys.path:
    sys.path.insert(0, SRC_PATH)

logger = logging.getLogger(__name__)

DOMINIOS = ["university", "billing", "crm"]

# Tablas gold minimas para el chequeo final (una por dominio + una compartida).
TABLAS_GOLD_A_VALIDAR = [
    "gold.dim_fecha",
    "gold.fact_enrollment",
    "gold.fact_invoices",
    "gold.fact_opportunities",
]

default_args = {
    "owner": "bootcamp",
    "depends_on_past": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=3),
}


def _check_raw_files():
    """Chequeo simple: que existan CSV de origen antes de gastar tiempo en el resto del pipeline."""
    raw_path = Path(os.environ.get("DATA_ROOT", "/opt/airflow/data")) / "raw"
    faltantes = []

    for dominio in DOMINIOS:
        carpeta = raw_path / dominio
        if not carpeta.exists() or not list(carpeta.glob("*.csv")):
            faltantes.append(dominio)

    if faltantes:
        raise AirflowFailException(
            f"No se encontraron CSV en data/raw/ para: {', '.join(faltantes)}. "
            "Revisar que el volumen de datos este montado."
        )

    logger.info("CSV de origen encontrados para los %s dominios.", len(DOMINIOS))


def _run_bronze():
    from ingest_bronze import ingest_all

    try:
        ingest_all()
    except Exception as e:
        logger.error("Fallo la ingesta Bronze: %s", e)
        raise


def _run_silver():
    from ingest_silver import ingest_all

    try:
        ingest_all()
    except Exception as e:
        logger.error("Fallo la ingesta Silver: %s", e)
        raise


def _run_gold():
    from build_gold import build_gold

    try:
        build_gold()
    except Exception as e:
        logger.error("Fallo la construccion de Gold: %s", e)
        raise


def _validar_pipeline():
    """Validacion basica post-pipeline: las tablas gold clave no deben quedar vacias."""
    from load_staging import POSTGRES_URL
    from sqlalchemy import create_engine, text

    engine = create_engine(POSTGRES_URL)
    vacias = []

    with engine.connect() as conn:
        for tabla in TABLAS_GOLD_A_VALIDAR:
            count = conn.execute(text(f"SELECT COUNT(*) FROM {tabla}")).scalar()
            logger.info("%s -> %s filas", tabla, count)
            if not count:
                vacias.append(tabla)

    if vacias:
        raise AirflowFailException(
            f"Las siguientes tablas gold quedaron vacias: {', '.join(vacias)}"
        )

    logger.info("Validacion OK: tablas gold con datos.")


with DAG(
    dag_id="medallion_pipeline",
    description="Pipeline Bronze -> Silver -> Gold (CRM + Billing + University)",
    default_args=default_args,
    schedule_interval="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    tags=["medallion", "bootcamp"],
) as dag:

    check_raw_files = PythonOperator(
        task_id="check_raw_files",
        python_callable=_check_raw_files,
    )

    ingest_bronze = PythonOperator(
        task_id="ingest_bronze",
        python_callable=_run_bronze,
    )

    ingest_silver = PythonOperator(
        task_id="ingest_silver",
        python_callable=_run_silver,
    )

    build_gold = PythonOperator(
        task_id="build_gold",
        python_callable=_run_gold,
    )

    validar_pipeline = PythonOperator(
        task_id="validar_pipeline",
        python_callable=_validar_pipeline,
    )

    check_raw_files >> ingest_bronze >> ingest_silver >> build_gold >> validar_pipeline
