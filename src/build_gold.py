from pathlib import Path

from sqlalchemy import text

from load_staging import cargar_staging

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SQL_GOLD_PATH = PROJECT_ROOT / "sql" / "gold"


def ejecutar_scripts_sql(engine):
    for script in sorted(SQL_GOLD_PATH.glob("*.sql")):
        sql = script.read_text(encoding="utf-8")
        with engine.begin() as conn:
            conn.execute(text(sql))
        print(f"OK: ejecutado {script.relative_to(PROJECT_ROOT)}")


def build_gold():
    engine = cargar_staging()
    ejecutar_scripts_sql(engine)
    print("\nConstruccion de Gold completada.")


if __name__ == "__main__":
    build_gold()
