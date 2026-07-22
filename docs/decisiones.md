# Decisiones del proyecto

---

## Arquitectura de capas

- Solamente bronze y silver se transformaran a parquet.
- Se cargar silver a postgres como staging debido a la necesitad de tener silver y utilizar JOINs para contruir gold.
- gold debera pasarse a postgres con un modelo estrella

---

## Transformaciones y limpieza

### Registro de incidencias

Los datos transformados y sitauciones encontradas se guardaran en una tabla postgresql de incidencias con las siguientes columnas:

`(id, capa, tabla, columna, regla, descripcion)`

La descripcion debera estar formateada por:

`(filas_afectadas, filas_totales, pct_afectado, pipeline_run_id, ejecutado_at)`

### Reglas aplicadas

- conservar las filas sin modificacion ni columnas adicionales. Son contactos distintos de cuentas distintas; el email repetido puede ser dato real (email compartido) o error de origen.
- Intercambiar start_date y end_date directamente en las filas con rango invertido. Sin columnas adicionales: Silver entrega fechas ya coherentes.
- Reemplazar line_total por quantity  unit_price calculado con Decimal y redondeo a 2 decimales. Es ruido de punto flotante del CSV.
- Excluir del output Silver las facturas sin items. La tasa estable (5%) confirma que es caracteristica del origen, no una falla reciente; la limpieza consiste en omitir esas filas para entregar una tabla consistente.
- Ajustar los montos en payments para que la suma por factura no supere el total. La relacion con multiples pagos (>=2) explica el sobrepago: cada pago adicional no se ajustaba al saldo restante
- Corregir status en las 14 481 facturas afectadas. La tasa estable (29%) confirma que es caracteristica del origen.
- Renormalizar los weight por enrollment para que sumen 1. La baja tasa de completitud en todos los semestres (incluidos los cerrados) descarta la hipotesis de curso en progreso.

---

## Modelado Gold

### Enfoque general

- Construir Gold en Postgres desde tablas staging (espejo de Silver) transformadas con scripts SQL en sql/gold/, no directo desde pandas. El stack exige SQL para modelado de negocio y esa carpeta ya esta reservada para eso.
- Modelo en constelacion, no 3 estrellas aisladas ni fusion total: hechos separados por dominio (academico, facturacion/suscripciones, CRM) compartiendo dim_fecha; dim_cliente incluye student_id opcional. El unico vinculo real entre dominios es customers.external_ref = students.student_id (exacto en 5000/10000 customers); CRM no comparte ninguna llave con billing ni university, asi que fusionar forzaria entidades distintas.
- Surrogate keys enteros autoincrementales en todas las dimensiones Gold, conservando la natural key (STU-0000001, etc.) como atributo. Mejor rendimiento de joins y compatibilidad con herramientas BI.
- SCD Tipo 1 (sobrescribir) en todas las dimensiones Gold. El dataset es una carga unica sin historico real de fechas de ingesta distintas; un Tipo 2 no aporta valor aqui.
- Sin fila "Unknown"/-1 en las dimensiones: se descarta esa decision anterior. En este dataset no hay FKs huerfanas reales (verificado en Silver), asi que las columnas _sk simplemente quedan NULL cuando no aplican (ej. fact_activities.contacto_sk cuando la actividad no tiene contacto). Mas simple y evita una tabla incidencias con capa='gold' registrando algo que no es un problema de calidad, sino un nulo normal del origen.

### Tablas de hechos por dominio

**Facturación**

- Facturacion en 3 grados de detalle: fact_invoice_items (linea, analisis por producto), fact_payments (pago, metodo/fecha de cobro) y fact_invoices (resumen: status y aging) para no reagregar en cada consulta de cobranza.
- Suscripciones como snapshot mensual (fact_subscription_monthly) derivado de start_date/end_date. Un hecho de solo eventos (alta/baja) no permite calcular MRR ni churn mes a mes directamente.

**Universidad**

- Modelo academico en dos grados: fact_enrollment (nota final ponderada por inscripcion) y fact_grades (detalle por evaluacion), para tener resumen y drill-down sin duplicar logica.
- fact_enrollment usa el weight ya renormalizado por Silver tal cual, sin recalcular desde Bronze ni agregar flag de evaluacion completa (se descarta la decision anterior de marcar evaluacion_completa). Silver ya tomo la decision de normalizar weight para que sume 1; Gold no la reabre, solo construye el modelo dimensional sobre el dato de Silver.

**CRM**

- CRM en fact_opportunities (grano oportunidad: pipeline, conversion, ciclo de venta) y fact_activities (grano actividad: volumen de interacciones).

### Dimensiones y KPIs

- dim_hora como dimension conformada de 24 filas (0-23), con hour_sk = hora y atributos simples (periodo_dia, es_hora_laboral). En staging varias tablas traen timestamp completo en created_at/occurred_at, pero Gold conserva la hora solo en hechos donde el analisis por franja horaria aporta valor: fact_activities (occurred_hour_sk) e fact_leads (created_hour_sk). El resto (altas en dimensiones, oportunidades, facturacion) sigue a nivel dia via dim_fecha.
- KPIs iniciales por dominio: Billing = MRR, churn, ARPU, tasa de cobranza; University = tasa de aprobacion, GPA por curso/profesor/semestre, desercion; CRM = conversion lead-oportunidad-cierre, ciclo de venta, pipeline por stage.
- KPI kpi_crm_actividades_por_hora: cuenta actividades CRM por hora del dia y calcula el porcentaje sobre el total. Sirve para ver en que franjas horarias se concentra el trabajo comercial.
- KPI kpi_crm_leads_por_hora: cuenta leads entrantes por hora del dia y fuente. Complementa kpi_crm_leads (conversion por fuente) con el patron horario de captacion.
- Los KPIs se documentan e interpretan en notebooks/07_calculo_kpis.ipynb; la logica SQL vive en sql/gold/30_kpis.sql como vistas, no como tablas materializadas.

### Estrategia de carga

- Carga de Gold con full refresh en cada corrida del DAG (DROP + CREATE de cada tabla gold, no solo TRUNCATE), igual de espiritu a como Silver maneja incidencias. Se preferio DROP+CREATE sobre TRUNCATE porque un cambio de esquema (columna agregada o quitada) con CREATE TABLE IF NOT EXISTS + TRUNCATE deja la tabla vieja intacta y desincroniza el modelo; DROP+CREATE se autocorrige en cada corrida.

---

## Automatizacion con Airflow

### DAG y tareas

- Un solo DAG (dags/medallion_pipeline.py) con 5 tareas encadenadas: check_raw_files -> ingest_bronze -> ingest_silver -> build_gold -> validar_pipeline. No se separo en varios DAGs porque las capas son secuenciales y dependen 100% una de la anterior; un solo DAG deja la dependencia explicita sin necesitar sensors ni TriggerDagRunOperator.
- Las tareas llaman directo a las funciones que ya existen en src/ (ingest_all(), build_gold()) en vez de reescribir la logica como operators nuevos. Evita mantener el mismo pipeline en dos lugares distintos.
- El pipeline es idempotente por como ya escriben los scripts de src/ (parquet sobrescrito con to_parquet, staging con if_exists="replace", gold con DROP+CREATE), asi que no hizo falta logica extra en el DAG para evitar duplicados al reintentar.

### Manejo de errores y configuracion

- Manejo de errores basico, sin nada especial: retries=2 + retry_delay de 3 minutos a nivel de DAG (por si la conexion a Postgres tarda en levantar), una tarea check_raw_files al inicio que falla rapido y con mensaje claro si falta algun CSV de origen, y una tarea validar_pipeline al final que revisa que las tablas gold principales no hayan quedado vacias. No se agrego alerting (email/Slack) porque esta fuera del alcance del proyecto.
- POSTGRES_URL ahora se lee de variable de entorno (default localhost, igual que antes) en vez de estar hardcodeada en ingest_silver.py y load_staging.py. Corriendo dentro de los contenedores de Airflow, "localhost" apunta al propio contenedor y no al de Postgres; se agrego POSTGRES_URL=postgresql+psycopg2://bootcamp:bootcamp@postgres:5432/gold en docker-compose.yml para los servicios de Airflow, sin romper la ejecucion manual de los scripts desde fuera de Docker.
- Auto-ejecucion al levantar Docker: servicio one-shot airflow-trigger en docker-compose.yml que espera PIPELINE_STARTUP_DELAY_SECONDS (10 por defecto) tras arrancar scheduler/webserver, hace unpause del DAG y lo dispara con airflow dags trigger. No se uso schedule corto en el DAG porque el arranque del stack no coincide con un cron fijo y los DAGs nacen pausados (DAGS_ARE_PAUSED_AT_CREATION=true); un script de arranque es mas explicito y reproducible para el bootcamp.
