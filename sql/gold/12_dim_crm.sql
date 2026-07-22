DROP TABLE IF EXISTS gold.dim_cuenta CASCADE;

CREATE TABLE gold.dim_cuenta (
    cuenta_sk      SERIAL PRIMARY KEY,
    account_id     TEXT UNIQUE,
    name           TEXT,
    industry       TEXT,
    pais_sk        INT REFERENCES gold.dim_pais (pais_sk),
    annual_revenue NUMERIC(14, 2),
    employees      INT,
    created_at     DATE
);

INSERT INTO gold.dim_cuenta (account_id, name, industry, pais_sk, annual_revenue, employees, created_at)
SELECT
    a.account_id, a.name, a.industry,
    pa.pais_sk,
    a.annual_revenue, a.employees, a.created_at::date
FROM staging.accounts a
LEFT JOIN gold.dim_pais pa ON pa.pais = a.country;


DROP TABLE IF EXISTS gold.dim_contacto CASCADE;

CREATE TABLE gold.dim_contacto (
    contacto_sk SERIAL PRIMARY KEY,
    contact_id  TEXT UNIQUE,
    first_name  TEXT,
    last_name   TEXT,
    email       TEXT,
    phone       TEXT,
    title       TEXT,
    cuenta_sk   INT REFERENCES gold.dim_cuenta (cuenta_sk),
    created_at  DATE
);

INSERT INTO gold.dim_contacto (contact_id, first_name, last_name, email, phone, title, cuenta_sk, created_at)
SELECT
    c.contact_id, c.first_name, c.last_name, c.email, c.phone, c.title,
    cu.cuenta_sk,
    c.created_at::date
FROM staging.contacts c
LEFT JOIN gold.dim_cuenta cu ON cu.account_id = c.account_id;
