-- Vistas de KPIs iniciales (docs/decisiones.md). Se recalculan solas al consultarse:
-- no requieren paso de carga porque leen directo de las tablas gold ya construidas.

-- Billing: MRR, churn, ARPU y tasa de cobranza, por mes.
CREATE OR REPLACE VIEW gold.kpi_billing_mensual AS
WITH activos AS (
    SELECT f.subscription_id, f.cliente_sk, f.mrr_amount, d.fecha AS mes
    FROM gold.fact_subscription_monthly f
    JOIN gold.dim_fecha d ON d.date_sk = f.mes_date_sk
),
mrr AS (
    SELECT mes, SUM(mrr_amount) AS mrr, COUNT(DISTINCT cliente_sk) AS clientes_activos
    FROM activos
    GROUP BY mes
),
churn AS (
    SELECT
        (a.mes + INTERVAL '1 month')::date AS mes,
        COUNT(*) AS activos_mes_anterior,
        COUNT(*) FILTER (WHERE b.subscription_id IS NULL) AS bajas
    FROM activos a
    LEFT JOIN activos b
        ON b.subscription_id = a.subscription_id
       AND b.mes = (a.mes + INTERVAL '1 month')::date
    GROUP BY 1
),
cobranza AS (
    SELECT
        DATE_TRUNC('month', d.fecha)::date AS mes,
        SUM(fi.total) FILTER (WHERE fi.status = 'paid') AS cobrado,
        SUM(fi.total) AS facturado
    FROM gold.fact_invoices fi
    JOIN gold.dim_fecha d ON d.date_sk = fi.issued_date_sk
    GROUP BY 1
)
SELECT
    COALESCE(mrr.mes, churn.mes, cobranza.mes) AS mes,
    mrr.mrr,
    ROUND(mrr.mrr / NULLIF(mrr.clientes_activos, 0), 2) AS arpu,
    ROUND(churn.bajas::numeric / NULLIF(churn.activos_mes_anterior, 0), 4) AS churn_rate,
    ROUND(cobranza.cobrado / NULLIF(cobranza.facturado, 0), 4) AS tasa_cobranza
FROM mrr
FULL OUTER JOIN churn ON churn.mes = mrr.mes
FULL OUTER JOIN cobranza ON cobranza.mes = COALESCE(mrr.mes, churn.mes)
ORDER BY 1;


-- University: tasa de aprobacion, GPA y desercion, por semestre.
CREATE OR REPLACE VIEW gold.kpi_university_semestre AS
SELECT
    se.code,
    se.year,
    se.half,
    COUNT(*)                                                       AS total_inscripciones,
    COUNT(*) FILTER (WHERE fe.status = 'completed')                AS aprobados,
    ROUND(
        COUNT(*) FILTER (WHERE fe.status = 'completed')::numeric
        / NULLIF(COUNT(*) FILTER (WHERE fe.status IN ('completed', 'failed')), 0), 4
    )                                                               AS tasa_aprobacion,
    ROUND(AVG(fe.nota_final), 2)                                   AS gpa_promedio,
    ROUND(COUNT(*) FILTER (WHERE fe.status = 'dropped')::numeric / NULLIF(COUNT(*), 0), 4) AS tasa_desercion
FROM gold.fact_enrollment fe
JOIN gold.dim_semestre se ON se.semestre_sk = fe.semestre_sk
GROUP BY se.code, se.year, se.half
ORDER BY se.year, se.half;


-- CRM: conversion de leads por fuente.
CREATE OR REPLACE VIEW gold.kpi_crm_leads AS
SELECT
    source,
    COUNT(*)                                            AS total_leads,
    COUNT(*) FILTER (WHERE status = 'converted')        AS convertidos,
    ROUND(COUNT(*) FILTER (WHERE status = 'converted')::numeric / NULLIF(COUNT(*), 0), 4) AS tasa_conversion
FROM gold.fact_leads
GROUP BY source
ORDER BY source;


-- CRM: pipeline y ciclo de venta por stage.
CREATE OR REPLACE VIEW gold.kpi_crm_pipeline AS
SELECT
    stage,
    COUNT(*)                          AS cantidad,
    SUM(amount)                       AS valor_total,
    ROUND(AVG(ciclo_venta_dias), 1)   AS ciclo_venta_promedio_dias
FROM gold.fact_opportunities
GROUP BY stage
ORDER BY stage;


-- CRM: volumen de actividades por hora del dia (usa dim_hora).
CREATE OR REPLACE VIEW gold.kpi_crm_actividades_por_hora AS
SELECT
    h.hora,
    h.periodo_dia,
    h.es_hora_laboral,
    COUNT(*) AS total_actividades,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER (), 4) AS pct_del_total
FROM gold.fact_activities fa
JOIN gold.dim_hora h ON h.hour_sk = fa.occurred_hour_sk
GROUP BY h.hora, h.periodo_dia, h.es_hora_laboral
ORDER BY h.hora;


-- CRM: leads entrantes por hora del dia y fuente (usa dim_hora).
CREATE OR REPLACE VIEW gold.kpi_crm_leads_por_hora AS
SELECT
    h.hora,
    h.periodo_dia,
    fl.source,
    COUNT(*) AS total_leads
FROM gold.fact_leads fl
JOIN gold.dim_hora h ON h.hour_sk = fl.created_hour_sk
GROUP BY h.hora, h.periodo_dia, fl.source
ORDER BY fl.source, h.hora;
