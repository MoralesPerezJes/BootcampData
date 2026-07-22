DROP TABLE IF EXISTS gold.dim_hora CASCADE;

CREATE TABLE gold.dim_hora (
    hour_sk         INT PRIMARY KEY,
    hora            INT,
    periodo_dia     TEXT,
    es_hora_laboral BOOLEAN
);

INSERT INTO gold.dim_hora (hour_sk, hora, periodo_dia, es_hora_laboral)
SELECT
    h AS hour_sk,
    h AS hora,
    CASE
        WHEN h BETWEEN 6 AND 11  THEN 'manana'
        WHEN h BETWEEN 12 AND 17 THEN 'tarde'
        WHEN h BETWEEN 18 AND 21 THEN 'noche'
        ELSE 'madrugada'
    END AS periodo_dia,
    h BETWEEN 9 AND 17 AS es_hora_laboral
FROM generate_series(0, 23) AS h;
