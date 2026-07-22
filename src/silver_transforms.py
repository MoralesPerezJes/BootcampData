from decimal import Decimal, ROUND_HALF_UP

import pandas as pd

def to_money(valor):
    return Decimal(str(valor)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

def registrar_incidencia(ctx, tabla, columna, regla, afectadas, totales):
    pct = round(100 * afectadas / totales, 4) if totales > 0 else 0
    descripcion = (
        f"{afectadas}/{totales} filas afectadas ({pct}) pipe_id:({ctx['run_id']}) ejecutado:({ctx['ejecutado_at'].isoformat()})"

    )
    ctx["incidencias"].append(
        {
            "capa": "silver",
            "tabla": tabla,
            "columna": columna,
            "regla": regla,
            "descripcion": descripcion,
        }
    )

def transform_contacts(contacts, ctx):
    # Situacion 1: emails duplicados, se dejan igual pero se registra
    duplicados = contacts["email"].duplicated(keep=False)
    n = int(duplicados.sum())
    if n > 0:
        registrar_incidencia(
            ctx, "crm.contacts", "email", "email_duplicado_detectado", n, len(contacts),
        )
    return contacts

def transform_subscriptions(subscriptions, ctx):
    # Situacion 2: intercambiar fechas si end_date < start_date
    df = subscriptions.copy()
    inicio = pd.to_datetime(df["start_date"])
    fin = pd.to_datetime(df["end_date"])
    mal = fin < inicio
    n = int(mal.sum())

    if n > 0:
        df.loc[mal, "start_date"] = fin[mal].dt.strftime("%Y-%m-%d")
        df.loc[mal, "end_date"] = inicio[mal].dt.strftime("%Y-%m-%d")
        registrar_incidencia(
            ctx, "billing.subscriptions", "start_date,end_date",
            "intercambio_fechas_invertidas", n, len(df),
        )
    return df


def transform_invoice_items(invoice_items, ctx):
    # Situacion 3: recalcular line_total con Decimal
    df = invoice_items.copy()
    n = 0

    for i in df.index:
        qty = Decimal(str(df.at[i, "quantity"]))
        price = Decimal(str(df.at[i, "unit_price"]))
        nuevo = float((qty * price).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
        viejo = df.at[i, "line_total"]

        if to_money(viejo) != to_money(nuevo) or Decimal(str(viejo)) != Decimal(str(nuevo)):
            n += 1
        df.at[i, "line_total"] = nuevo

    if n > 0:
        registrar_incidencia(
            ctx, "billing.invoice_items", "line_total",
            "recalculo_line_total_decimal", n, len(df),
        )
    return df


def transform_billing(invoices, invoice_items, payments, ctx):
    df = invoices.copy()

    # Situacion 4: total = suma de items
    suma_items = invoice_items.groupby("invoice_id")["line_total"].sum()
    n_total = 0
    for i in df.index:
        inv_id = df.at[i, "invoice_id"]
        if inv_id not in suma_items.index:
            continue
        suma = float(to_money(suma_items[inv_id]))
        if to_money(df.at[i, "total"]) != to_money(suma):
            df.at[i, "total"] = suma
            n_total += 1

    if n_total > 0:
        registrar_incidencia(
            ctx, "billing.invoices", "total",
            "recalculo_total_desde_items", n_total, len(invoices),
        )

    # Situacion 5: quitar facturas sin items
    ids_con_items = set(invoice_items["invoice_id"])
    sin_items = ~df["invoice_id"].isin(ids_con_items)
    n_sin_items = int(sin_items.sum())
    if n_sin_items > 0:
        registrar_incidencia(
            ctx, "billing.invoices", None,
            "exclusion_facturas_sin_items", n_sin_items, len(df),
        )
    df = df[df["invoice_id"].isin(ids_con_items)].copy()

    ids_validos = set(df["invoice_id"])
    invoice_items = invoice_items[invoice_items["invoice_id"].isin(ids_validos)].copy()
    payments = payments[payments["invoice_id"].isin(ids_validos)].copy()

    # Situacion 6: ajustar pagos para no pasar el total
    payments = payments.sort_values(["invoice_id", "paid_at", "payment_id"]).copy()
    totales = df.set_index("invoice_id")["total"].to_dict()
    n_pagos = 0

    for inv_id, grupo in payments.groupby("invoice_id"):
        restante = to_money(totales.get(inv_id, 0))
        for idx in grupo.index:
            monto = to_money(payments.at[idx, "amount"])
            if restante <= 0:
                nuevo = Decimal("0.00")
            elif monto > restante:
                nuevo = restante
            else:
                nuevo = monto

            if nuevo != monto:
                n_pagos += 1
            payments.at[idx, "amount"] = float(nuevo)
            restante -= nuevo

    if n_pagos > 0:
        registrar_incidencia(
            ctx, "billing.payments", "amount",
            "tope_suma_pagos_por_factura", n_pagos, len(payments),
        )

    # Situacion 7: paid pero pago < total -> pending
    pagado = payments.groupby("invoice_id")["amount"].sum()
    n_status = 0
    for i in df.index:
        inv_id = df.at[i, "invoice_id"]
        total = to_money(df.at[i, "total"])
        pago = to_money(pagado.get(inv_id, 0))

        if df.at[i, "status"] == "paid" and pago < total:
            df.at[i, "status"] = "pending"
            n_status += 1

    if n_status > 0:
        registrar_incidencia(
            ctx, "billing.invoices", "status",
            "correccion_status_paid_subpagado", n_status, len(df),
        )

    return df, invoice_items, payments


def transform_grades(grades, ctx):
    # Situacion 8: weights deben sumar 1 por enrollment
    df = grades.copy()
    n = 0

    for _, grupo in df.groupby("enrollment_id"):
        suma = sum(Decimal(str(w)) for w in grupo["weight"])
        if suma == Decimal("1") or suma == Decimal("0"):
            continue

        for idx in grupo.index:
            peso_viejo = df.at[idx, "weight"]
            peso_nuevo = float(Decimal(str(peso_viejo)) / suma)
            if Decimal(str(peso_viejo)) != Decimal(str(peso_nuevo)):
                n += 1
            df.at[idx, "weight"] = peso_nuevo

    if n > 0:
        registrar_incidencia(
            ctx, "university.grades", "weight",
            "renormalizacion_weight_por_enrollment", n, len(df),
        )
    return df


def apply_transforms(tables, ctx):
    tables[("crm", "contacts")] = transform_contacts(
        tables[("crm", "contacts")], ctx,
    )

    tables[("billing", "subscriptions")] = transform_subscriptions(
        tables[("billing", "subscriptions")], ctx,
    )

    tables[("billing", "invoice_items")] = transform_invoice_items(
        tables[("billing", "invoice_items")], ctx,
    )

    invoices, invoice_items, payments = transform_billing(
        tables[("billing", "invoices")],
        tables[("billing", "invoice_items")],
        tables[("billing", "payments")],
        ctx,
    )
    tables[("billing", "invoices")] = invoices
    tables[("billing", "invoice_items")] = invoice_items
    tables[("billing", "payments")] = payments

    tables[("university", "grades")] = transform_grades(
        tables[("university", "grades")], ctx,
    )
    return tables
