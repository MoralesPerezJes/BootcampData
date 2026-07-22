DROP TABLE IF EXISTS gold.fact_invoices CASCADE;

CREATE TABLE gold.fact_invoices (
    invoice_id      TEXT PRIMARY KEY,
    cliente_sk       INT REFERENCES gold.dim_cliente (cliente_sk),
    issued_date_sk   INT REFERENCES gold.dim_fecha (date_sk),
    due_date_sk      INT REFERENCES gold.dim_fecha (date_sk),
    status           TEXT,
    currency         TEXT,
    total            NUMERIC(12, 2),
    dias_vencido     INT
);

INSERT INTO gold.fact_invoices
    (invoice_id, cliente_sk, issued_date_sk, due_date_sk, status, currency, total, dias_vencido)
SELECT
    i.invoice_id,
    cl.cliente_sk,
    TO_CHAR(i.issued_at::date, 'YYYYMMDD')::INT,
    TO_CHAR(i.due_at::date, 'YYYYMMDD')::INT,
    i.status,
    i.currency,
    i.total,
    CASE WHEN i.status = 'paid' THEN 0
         ELSE GREATEST((CURRENT_DATE - i.due_at::date), 0)
    END
FROM staging.invoices i
LEFT JOIN gold.dim_cliente cl ON cl.customer_id = i.customer_id;


DROP TABLE IF EXISTS gold.fact_invoice_items CASCADE;

CREATE TABLE gold.fact_invoice_items (
    invoice_item_id TEXT PRIMARY KEY,
    invoice_id      TEXT REFERENCES gold.fact_invoices (invoice_id),
    cliente_sk       INT REFERENCES gold.dim_cliente (cliente_sk),
    producto_sk      INT REFERENCES gold.dim_producto (producto_sk),
    issued_date_sk   INT REFERENCES gold.dim_fecha (date_sk),
    quantity         INT,
    unit_price       NUMERIC(10, 2),
    line_total       NUMERIC(12, 2)
);

INSERT INTO gold.fact_invoice_items
    (invoice_item_id, invoice_id, cliente_sk, producto_sk, issued_date_sk, quantity, unit_price, line_total)
SELECT
    ii.invoice_item_id,
    ii.invoice_id,
    fi.cliente_sk,
    p.producto_sk,
    fi.issued_date_sk,
    ii.quantity,
    ii.unit_price,
    ii.line_total
FROM staging.invoice_items ii
JOIN gold.fact_invoices fi ON fi.invoice_id = ii.invoice_id
LEFT JOIN gold.dim_producto p ON p.product_id = ii.product_id;


DROP TABLE IF EXISTS gold.fact_payments CASCADE;

CREATE TABLE gold.fact_payments (
    payment_id      TEXT PRIMARY KEY,
    invoice_id      TEXT REFERENCES gold.fact_invoices (invoice_id),
    cliente_sk       INT REFERENCES gold.dim_cliente (cliente_sk),
    paid_date_sk     INT REFERENCES gold.dim_fecha (date_sk),
    method           TEXT,
    amount           NUMERIC(12, 2)
);

INSERT INTO gold.fact_payments (payment_id, invoice_id, cliente_sk, paid_date_sk, method, amount)
SELECT
    pay.payment_id,
    pay.invoice_id,
    fi.cliente_sk,
    TO_CHAR(pay.paid_at::date, 'YYYYMMDD')::INT,
    pay.method,
    pay.amount
FROM staging.payments pay
JOIN gold.fact_invoices fi ON fi.invoice_id = pay.invoice_id;

DROP TABLE IF EXISTS gold.fact_subscription_monthly CASCADE;

CREATE TABLE gold.fact_subscription_monthly (
    subscription_id TEXT,
    mes_date_sk      INT REFERENCES gold.dim_fecha (date_sk),
    cliente_sk       INT REFERENCES gold.dim_cliente (cliente_sk),
    producto_sk      INT REFERENCES gold.dim_producto (producto_sk),
    status           TEXT,
    mrr_amount       NUMERIC(10, 2),
    PRIMARY KEY (subscription_id, mes_date_sk)
);

INSERT INTO gold.fact_subscription_monthly (subscription_id, mes_date_sk, cliente_sk, producto_sk, status, mrr_amount)
SELECT
    s.subscription_id,
    TO_CHAR(mes, 'YYYYMMDD')::INT,
    cl.cliente_sk,
    p.producto_sk,
    s.status,
    p_price.monthly_price
FROM staging.subscriptions s
LEFT JOIN gold.dim_cliente cl ON cl.customer_id = s.customer_id
LEFT JOIN gold.dim_producto p ON p.product_id = s.product_id
LEFT JOIN staging.products p_price ON p_price.product_id = s.product_id
CROSS JOIN LATERAL generate_series(
    DATE_TRUNC('month', s.start_date::date),
    DATE_TRUNC('month', s.end_date::date),
    interval '1 month'
) AS mes;
