
DROP TABLE IF EXISTS gold.fact_opportunities CASCADE;

CREATE TABLE gold.fact_opportunities (
    opportunity_id    TEXT PRIMARY KEY,
    cuenta_sk          INT REFERENCES gold.dim_cuenta (cuenta_sk),
    created_date_sk    INT REFERENCES gold.dim_fecha (date_sk),
    close_date_sk      INT REFERENCES gold.dim_fecha (date_sk),
    name               TEXT,
    stage              TEXT,
    amount             NUMERIC(12, 2),
    is_closed          BOOLEAN,
    is_won             BOOLEAN,
    ciclo_venta_dias   INT
);

INSERT INTO gold.fact_opportunities
    (opportunity_id, cuenta_sk, created_date_sk, close_date_sk, name, stage, amount,
     is_closed, is_won, ciclo_venta_dias)
SELECT
    o.opportunity_id,
    cu.cuenta_sk,
    TO_CHAR(o.created_at::date, 'YYYYMMDD')::INT,
    TO_CHAR(o.close_date::date, 'YYYYMMDD')::INT,
    o.name,
    o.stage,
    o.amount,
    o.stage IN ('won', 'lost'),
    o.stage = 'won',
    CASE WHEN o.stage IN ('won', 'lost')
         THEN (o.close_date::date - o.created_at::date)
    END
FROM staging.opportunities o
LEFT JOIN gold.dim_cuenta cu ON cu.account_id = o.account_id;


DROP TABLE IF EXISTS gold.fact_activities CASCADE;

CREATE TABLE gold.fact_activities (
    activity_id        TEXT PRIMARY KEY,
    contacto_sk         INT REFERENCES gold.dim_contacto (contacto_sk),
    opportunity_id      TEXT REFERENCES gold.fact_opportunities (opportunity_id),
    occurred_date_sk    INT REFERENCES gold.dim_fecha (date_sk),
    occurred_hour_sk    INT REFERENCES gold.dim_hora (hour_sk),
    type                TEXT,
    subject             TEXT
);

INSERT INTO gold.fact_activities (
    activity_id, contacto_sk, opportunity_id, occurred_date_sk, occurred_hour_sk, type, subject
)
SELECT
    a.activity_id,
    co.contacto_sk,
    fo.opportunity_id,
    TO_CHAR(a.occurred_at::date, 'YYYYMMDD')::INT,
    EXTRACT(HOUR FROM a.occurred_at::timestamp)::INT,
    a.type,
    a.subject
FROM staging.activities a
LEFT JOIN gold.dim_contacto co ON co.contact_id = a.contact_id
LEFT JOIN gold.fact_opportunities fo ON fo.opportunity_id = a.opportunity_id;


-- Leads no comparten llave con accounts/contacts en el origen: quedan como hecho standalone
-- (embudo pre-venta), sin FK a dim_cuenta/dim_contacto.
DROP TABLE IF EXISTS gold.fact_leads CASCADE;

CREATE TABLE gold.fact_leads (
    lead_id           TEXT PRIMARY KEY,
    created_date_sk    INT REFERENCES gold.dim_fecha (date_sk),
    created_hour_sk    INT REFERENCES gold.dim_hora (hour_sk),
    source             TEXT,
    status             TEXT,
    score              INT
);

INSERT INTO gold.fact_leads (lead_id, created_date_sk, created_hour_sk, source, status, score)
SELECT
    lead_id,
    TO_CHAR(created_at::date, 'YYYYMMDD')::INT,
    EXTRACT(HOUR FROM created_at::timestamp)::INT,
    source,
    status,
    score
FROM staging.leads;


DROP TABLE IF EXISTS gold.bridge_opportunity_contacts CASCADE;

CREATE TABLE gold.bridge_opportunity_contacts (
    opportunity_id TEXT REFERENCES gold.fact_opportunities (opportunity_id),
    contacto_sk     INT REFERENCES gold.dim_contacto (contacto_sk),
    role            TEXT,
    PRIMARY KEY (opportunity_id, contacto_sk)
);

INSERT INTO gold.bridge_opportunity_contacts (opportunity_id, contacto_sk, role)
SELECT oc.opportunity_id, co.contacto_sk, oc.role
FROM staging.opportunity_contacts oc
JOIN gold.fact_opportunities fo ON fo.opportunity_id = oc.opportunity_id
LEFT JOIN gold.dim_contacto co ON co.contact_id = oc.contact_id;
