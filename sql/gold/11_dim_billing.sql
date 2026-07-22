DROP TABLE IF EXISTS gold.dim_producto CASCADE;

CREATE TABLE gold.dim_producto (
    producto_sk   SERIAL PRIMARY KEY,
    product_id    TEXT UNIQUE,
    sku           TEXT,
    name          TEXT,
    category      TEXT,
    monthly_price NUMERIC(10, 2),
    active        BOOLEAN
);

INSERT INTO gold.dim_producto (product_id, sku, name, category, monthly_price, active)
SELECT product_id, sku, name, category, monthly_price, active
FROM staging.products;


DROP TABLE IF EXISTS gold.dim_cliente CASCADE;

CREATE TABLE gold.dim_cliente (
    cliente_sk    SERIAL PRIMARY KEY,
    customer_id   TEXT UNIQUE,
    first_name    TEXT,
    last_name     TEXT,
    email         TEXT,
    pais_sk       INT REFERENCES gold.dim_pais (pais_sk),
    segment       TEXT,
    created_at    DATE,
    student_id    TEXT,
    es_estudiante BOOLEAN
);

INSERT INTO gold.dim_cliente (customer_id, first_name, last_name, email, pais_sk, segment, created_at, student_id, es_estudiante)
SELECT
    c.customer_id, c.first_name, c.last_name, c.email,
    pa.pais_sk,
    c.segment, c.created_at::date,
    c.external_ref,
    c.external_ref IS NOT NULL
FROM staging.customers c
LEFT JOIN gold.dim_pais pa ON pa.pais = c.country;
