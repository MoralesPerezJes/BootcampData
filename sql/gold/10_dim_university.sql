DROP TABLE IF EXISTS gold.dim_profesor CASCADE;

CREATE TABLE gold.dim_profesor (
    profesor_sk  SERIAL PRIMARY KEY,
    professor_id TEXT UNIQUE,
    first_name   TEXT,
    last_name    TEXT,
    email        TEXT,
    department   TEXT,
    hired_at     DATE
);

INSERT INTO gold.dim_profesor (professor_id, first_name, last_name, email, department, hired_at)
SELECT professor_id, first_name, last_name, email, department, hired_at::date
FROM staging.professors;


DROP TABLE IF EXISTS gold.dim_curso CASCADE;

CREATE TABLE gold.dim_curso (
    curso_sk    SERIAL PRIMARY KEY,
    course_id   TEXT UNIQUE,
    code        TEXT,
    name        TEXT,
    credits     INT,
    department  TEXT,
    profesor_sk INT REFERENCES gold.dim_profesor (profesor_sk)
);

INSERT INTO gold.dim_curso (course_id, code, name, credits, department, profesor_sk)
SELECT
    c.course_id, c.code, c.name, c.credits, c.department,
    p.profesor_sk
FROM staging.courses c
LEFT JOIN gold.dim_profesor p ON p.professor_id = c.professor_id;


DROP TABLE IF EXISTS gold.dim_semestre CASCADE;

CREATE TABLE gold.dim_semestre (
    semestre_sk SERIAL PRIMARY KEY,
    semester_id TEXT UNIQUE,
    code        TEXT,
    year        INT,
    half        INT,
    start_date  DATE,
    end_date    DATE
);

INSERT INTO gold.dim_semestre (semester_id, code, year, half, start_date, end_date)
SELECT semester_id, code, year, half, start_date::date, end_date::date
FROM staging.semesters;


DROP TABLE IF EXISTS gold.dim_estudiante CASCADE;

CREATE TABLE gold.dim_estudiante (
    estudiante_sk SERIAL PRIMARY KEY,
    student_id    TEXT UNIQUE,
    first_name    TEXT,
    last_name     TEXT,
    email         TEXT,
    birth_date    DATE,
    enrolled_at   DATE,
    pais_sk       INT REFERENCES gold.dim_pais (pais_sk)
);

INSERT INTO gold.dim_estudiante (student_id, first_name, last_name, email, birth_date, enrolled_at, pais_sk)
SELECT
    s.student_id, s.first_name, s.last_name, s.email,
    s.birth_date::date, s.enrolled_at::date,
    pa.pais_sk
FROM staging.students s
LEFT JOIN gold.dim_pais pa ON pa.pais = s.country;
