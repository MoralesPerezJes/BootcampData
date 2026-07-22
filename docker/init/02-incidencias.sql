-- Registro de transformaciones y situaciones detectadas por el pipeline
CREATE TABLE IF NOT EXISTS incidencias (
    id SERIAL PRIMARY KEY,
    capa VARCHAR(50) NOT NULL,
    tabla VARCHAR(150) NOT NULL,
    columna VARCHAR(150),
    regla VARCHAR(255) NOT NULL,
    descripcion TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_incidencias_capa ON incidencias (capa);
CREATE INDEX IF NOT EXISTS idx_incidencias_tabla ON incidencias (tabla);
CREATE INDEX IF NOT EXISTS idx_incidencias_pipeline_run
    ON incidencias ((split_part(descripcion, '|', 4)));
