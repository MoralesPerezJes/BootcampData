import json
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_PATH = PROJECT_ROOT / "data" / "raw"
BRONZE_PATH = PROJECT_ROOT / "data" / "parquet" / "bronze"
MANIFEST_PATH = PROJECT_ROOT / "manifest.json"

DOMAINS = ["university", "billing", "crm"]


def load_expected_rows():
    if not MANIFEST_PATH.exists():
        return {}

    with open(MANIFEST_PATH, encoding="utf-8") as f:
        manifest = json.load(f)

    expected = {}
    for domain, tables in manifest.get("domains", {}).items():
        for table_name, info in tables.items():
            expected[f"{domain}/{table_name}"] = info["rows"]
    return expected


def ingest_table(domain, table_name, expected_rows=None):
    csv_file = RAW_PATH / domain / f"{table_name}.csv"
    if not csv_file.exists():
        raise FileNotFoundError(f"No se encontró el CSV: {csv_file}")

    df = pd.read_csv(csv_file)

    df["_ingested_at"] = datetime.now(timezone.utc)
    df["_source_file"] = csv_file.name
    df["_source_domain"] = domain

    output_dir = BRONZE_PATH / domain
    output_dir.mkdir(parents=True, exist_ok=True)

    output_file = output_dir / f"{table_name}.parquet"
    df.to_parquet(output_file, index=False)

    row_count = len(df)
    label = f"{domain}/{table_name}"

    if expected_rows is not None and row_count != expected_rows:
        print(
            f"WARN: {label} -> {row_count} filas "
            f"(esperadas en manifest: {expected_rows})"
        )
    else:
        print(f"OK: {label} -> {row_count} filas -> {output_file.relative_to(PROJECT_ROOT)}")

    return row_count


def ingest_all():
    expected_rows = load_expected_rows()
    total_rows = 0
    tables_processed = 0

    for domain in DOMAINS:
        domain_path = RAW_PATH / domain
        if not domain_path.exists():
            raise FileNotFoundError(f"No se encontró el dominio: {domain_path}")

        for csv_file in sorted(domain_path.glob("*.csv")):
            table_name = csv_file.stem
            key = f"{domain}/{table_name}"
            total_rows += ingest_table(
                domain,
                table_name,
                expected_rows.get(key),
            )
            tables_processed += 1

    print(f"\nIngesta Bronze completada: {tables_processed} tablas, {total_rows} filas.")


if __name__ == "__main__":
    ingest_all()
