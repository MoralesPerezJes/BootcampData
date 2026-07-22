DROP TABLE IF EXISTS gold.dim_pais CASCADE;

CREATE TABLE gold.dim_pais (
    pais_sk SERIAL PRIMARY KEY,
    pais    TEXT UNIQUE
);

INSERT INTO gold.dim_pais (pais)
SELECT DISTINCT country
FROM (
    SELECT country FROM staging.students
    UNION
    SELECT country FROM staging.customers
    UNION
    SELECT country FROM staging.accounts
) paises
WHERE country IS NOT NULL
ORDER BY 1;
