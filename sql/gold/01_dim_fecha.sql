--Rango de fechas utilizado: 2019 - 2028
DROP TABLE IF EXISTS gold.dim_fecha CASCADE;

CREATE TABLE gold.dim_fecha (
    date_sk        INT PRIMARY KEY,
    fecha          DATE,
    anio           INT,
    trimestre      INT,
    mes            INT,
    mes_nombre     TEXT,
    dia            INT,
    dia_semana_iso INT,
    dia_nombre     TEXT,
    es_fin_semana  BOOLEAN
);

INSERT INTO gold.dim_fecha
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT AS date_sk,
    d::DATE                     AS fecha,
    EXTRACT(YEAR FROM d)::INT   AS anio,
    EXTRACT(QUARTER FROM d)::INT AS trimestre,
    EXTRACT(MONTH FROM d)::INT  AS mes,
    TRIM(TO_CHAR(d, 'TMMonth')) AS mes_nombre,
    EXTRACT(DAY FROM d)::INT    AS dia,
    EXTRACT(ISODOW FROM d)::INT AS dia_semana_iso,
    TRIM(TO_CHAR(d, 'TMDay'))   AS dia_nombre,
    EXTRACT(ISODOW FROM d) IN (6, 7) AS es_fin_semana
FROM generate_series('2019-01-01'::date, '2028-12-31'::date, interval '1 day') AS d;
