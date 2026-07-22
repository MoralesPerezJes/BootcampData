set -e

DELAY="${PIPELINE_STARTUP_DELAY_SECONDS:-20}"

echo "Esperando ${DELAY}s tras el arranque de los contenedores..."
sleep "$DELAY"

echo "Esperando a que Airflow cargue el DAG medallion_pipeline..."
for i in $(seq 1 60); do
  if airflow dags list 2>/dev/null | grep -q "medallion_pipeline"; then
    break
  fi
  echo "  reintento ${i}/60..."
  sleep 2
done

if ! airflow dags list 2>/dev/null | grep -q "medallion_pipeline"; then
  echo "ERROR: no se encontro el DAG medallion_pipeline"
  exit 1
fi

airflow dags unpause medallion_pipeline
airflow dags trigger medallion_pipeline --run-id "docker_compose_up_$(date +%Y%m%dT%H%M%S)"

echo "OK: medallion_pipeline disparado."
