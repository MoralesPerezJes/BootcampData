-- Hechos del dominio academico: grano inscripcion (resumen) y grano evaluacion (detalle).
-- nota_final usa el weight ya renormalizado por Silver, sin recalcular desde Bronze:
-- Gold no reabre esa decision, solo agrega el modelo dimensional sobre el dato de Silver.

DROP TABLE IF EXISTS gold.fact_enrollment CASCADE;

CREATE TABLE gold.fact_enrollment (
    enrollment_id     TEXT PRIMARY KEY,
    estudiante_sk      INT REFERENCES gold.dim_estudiante (estudiante_sk),
    curso_sk           INT REFERENCES gold.dim_curso (curso_sk),
    semestre_sk        INT REFERENCES gold.dim_semestre (semestre_sk),
    matricula_date_sk   INT REFERENCES gold.dim_fecha (date_sk),
    status             TEXT,
    nota_final         NUMERIC(5, 2),
    n_evaluaciones     INT
);

WITH resumen_notas AS (
    SELECT
        enrollment_id,
        SUM(score * weight) AS nota_final,
        COUNT(*)            AS n_evaluaciones
    FROM staging.grades
    GROUP BY enrollment_id
)
INSERT INTO gold.fact_enrollment
    (enrollment_id, estudiante_sk, curso_sk, semestre_sk, matricula_date_sk, status,
     nota_final, n_evaluaciones)
SELECT
    e.enrollment_id,
    es.estudiante_sk,
    cu.curso_sk,
    se.semestre_sk,
    TO_CHAR(e.enrolled_at::date, 'YYYYMMDD')::INT,
    e.status,
    rn.nota_final,
    COALESCE(rn.n_evaluaciones, 0)
FROM staging.enrollments e
LEFT JOIN gold.dim_estudiante es ON es.student_id = e.student_id
LEFT JOIN gold.dim_curso cu ON cu.course_id = e.course_id
LEFT JOIN gold.dim_semestre se ON se.semester_id = e.semester_id
LEFT JOIN resumen_notas rn ON rn.enrollment_id = e.enrollment_id;


DROP TABLE IF EXISTS gold.fact_grades CASCADE;

CREATE TABLE gold.fact_grades (
    grade_id       TEXT PRIMARY KEY,
    enrollment_id  TEXT REFERENCES gold.fact_enrollment (enrollment_id),
    estudiante_sk   INT REFERENCES gold.dim_estudiante (estudiante_sk),
    curso_sk        INT REFERENCES gold.dim_curso (curso_sk),
    semestre_sk     INT REFERENCES gold.dim_semestre (semestre_sk),
    graded_date_sk  INT REFERENCES gold.dim_fecha (date_sk),
    assessment      TEXT,
    score           NUMERIC(5, 2),
    weight          NUMERIC(6, 5)
);

INSERT INTO gold.fact_grades
    (grade_id, enrollment_id, estudiante_sk, curso_sk, semestre_sk, graded_date_sk, assessment, score, weight)
SELECT
    g.grade_id,
    g.enrollment_id,
    fe.estudiante_sk,
    fe.curso_sk,
    fe.semestre_sk,
    TO_CHAR(g.graded_at::date, 'YYYYMMDD')::INT,
    g.assessment,
    g.score,
    g.weight
FROM staging.grades g
JOIN gold.fact_enrollment fe ON fe.enrollment_id = g.enrollment_id;
