-- theme_preview.sql — SQL syntax showcase
-- Covers: DDL, DML, CTEs, window functions, JSON operators,
--         stored procedures, triggers, indexes, views

-- ── Schema ────────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS themepreview;
SET search_path TO themepreview;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ── Enum types ────────────────────────────────────────────────────────────────
CREATE TYPE user_role    AS ENUM ('admin', 'editor', 'viewer');
CREATE TYPE theme_status AS ENUM ('draft', 'published', 'archived', 'flagged');

-- ── Tables ────────────────────────────────────────────────────────────────────
CREATE TABLE users (
    id           UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    email        VARCHAR(320) NOT NULL UNIQUE,
    display_name VARCHAR(100) NOT NULL,
    role         user_role    NOT NULL DEFAULT 'viewer',
    password_hash TEXT        NOT NULL,
    metadata     JSONB        NOT NULL DEFAULT '{}',
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

    CONSTRAINT email_format CHECK (email ~* '^[^@]+@[^@]+\.[^@]+$')
);

CREATE TABLE themes (
    id           UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
    author_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name         VARCHAR(100) NOT NULL,
    slug         VARCHAR(110) NOT NULL UNIQUE,
    description  TEXT,
    palette      JSONB        NOT NULL DEFAULT '[]',
    colors       JSONB        NOT NULL DEFAULT '{}',
    status       theme_status NOT NULL DEFAULT 'draft',
    install_count INTEGER      NOT NULL DEFAULT 0,
    rating       NUMERIC(3,2)          CHECK (rating BETWEEN 0 AND 5),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,

    CONSTRAINT slug_format CHECK (slug ~ '^[a-z0-9][a-z0-9\-]*[a-z0-9]$')
);

CREATE TABLE reviews (
    id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    theme_id   UUID        NOT NULL REFERENCES themes(id)  ON DELETE CASCADE,
    user_id    UUID        NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    rating     SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    body       TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (theme_id, user_id)
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX idx_themes_author       ON themes (author_id);
CREATE INDEX idx_themes_status       ON themes (status) WHERE status = 'published';
CREATE INDEX idx_themes_rating       ON themes (rating DESC NULLS LAST);
CREATE INDEX idx_themes_palette_gin  ON themes USING GIN (palette);
CREATE INDEX idx_users_metadata_gin  ON users  USING GIN (metadata);
CREATE INDEX idx_reviews_theme       ON reviews (theme_id, created_at DESC);

-- ── View ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW published_themes AS
SELECT
    t.id,
    t.slug,
    t.name,
    t.description,
    t.install_count,
    t.rating,
    t.palette,
    u.display_name AS author_name,
    u.id           AS author_id,
    t.published_at,
    COUNT(r.id)    AS review_count
FROM   themes t
JOIN   users  u ON u.id = t.author_id
LEFT   JOIN reviews r ON r.theme_id = t.id
WHERE  t.status = 'published'
GROUP  BY t.id, u.id;

-- ── CTEs & window functions ───────────────────────────────────────────────────
WITH monthly_installs AS (
    SELECT
        date_trunc('month', created_at) AS month,
        author_id,
        SUM(install_count)              AS total_installs
    FROM themes
    WHERE status = 'published'
      AND created_at >= NOW() - INTERVAL '12 months'
    GROUP BY 1, 2
),
ranked AS (
    SELECT
        month,
        author_id,
        total_installs,
        RANK() OVER (PARTITION BY month ORDER BY total_installs DESC) AS rank,
        LAG(total_installs)  OVER (PARTITION BY author_id ORDER BY month) AS prev_month,
        LEAD(total_installs) OVER (PARTITION BY author_id ORDER BY month) AS next_month
    FROM monthly_installs
)
SELECT
    to_char(r.month, 'YYYY-MM')                              AS month,
    u.display_name,
    r.total_installs,
    r.rank,
    r.total_installs - COALESCE(r.prev_month, 0)            AS month_delta,
    ROUND(100.0 * (r.total_installs - COALESCE(r.prev_month, 0))
          / NULLIF(r.prev_month, 0), 1)                     AS pct_change
FROM   ranked r
JOIN   users u ON u.id = r.author_id
WHERE  r.rank <= 5
ORDER  BY r.month DESC, r.rank;

-- ── Stored procedure ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION publish_theme(
    p_theme_id  UUID,
    p_author_id UUID
)
RETURNS SETOF published_themes
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_palette_len INT;
    v_theme       themes%ROWTYPE;
BEGIN
    SELECT * INTO v_theme FROM themes WHERE id = p_theme_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Theme % not found', p_theme_id USING ERRCODE = 'P0002';
    END IF;
    IF v_theme.author_id <> p_author_id THEN
        RAISE EXCEPTION 'Permission denied' USING ERRCODE = '42501';
    END IF;
    IF v_theme.status <> 'draft' THEN
        RAISE EXCEPTION 'Theme is already %', v_theme.status USING ERRCODE = 'P0003';
    END IF;

    SELECT jsonb_array_length(v_theme.palette) INTO v_palette_len;
    IF v_palette_len < 2 THEN
        RAISE EXCEPTION 'Palette must have at least 2 colors, got %', v_palette_len;
    END IF;

    UPDATE themes
    SET    status       = 'published',
           published_at = NOW(),
           updated_at   = NOW()
    WHERE  id = p_theme_id;

    RETURN QUERY SELECT * FROM published_themes WHERE id = p_theme_id;
END;
$$;

-- ── Trigger ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION refresh_theme_rating()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE themes
    SET    rating     = (SELECT AVG(rating)::NUMERIC(3,2) FROM reviews WHERE theme_id = NEW.theme_id),
           updated_at = NOW()
    WHERE  id = NEW.theme_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_refresh_rating
    AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW EXECUTE FUNCTION refresh_theme_rating();

-- ── JSON queries ──────────────────────────────────────────────────────────────
-- Themes whose palette contains exactly the hex colour #09fbd3
SELECT name, palette
FROM   themes
WHERE  palette @> '["#09fbd3"]'::jsonb
   AND status = 'published';

-- Extract first palette colour and rename
SELECT
    name,
    palette -> 0               AS primary_color,
    palette ->> 0              AS primary_color_text,
    jsonb_array_length(palette) AS color_count,
    colors -> 'editor.background' AS editor_bg
FROM themes
WHERE jsonb_array_length(palette) >= 6
ORDER BY install_count DESC
LIMIT 20;

-- ── DML ───────────────────────────────────────────────────────────────────────
INSERT INTO users (email, display_name, role, password_hash, metadata)
VALUES
    ('alice@example.com',  'Alice',  'admin',  crypt('s3cret!', gen_salt('bf')), '{"verified": true}'),
    ('bob@example.com',    'Bob',    'editor', crypt('p4ssw0rd', gen_salt('bf')), '{}'),
    ('carol@example.com',  'Carol',  'viewer', crypt('hunter2', gen_salt('bf')),  '{"beta": true}')
ON CONFLICT (email) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        updated_at   = NOW();

-- Bulk install-count increment with optimistic locking
UPDATE themes
SET    install_count = install_count + 1,
       updated_at    = NOW()
WHERE  id = ANY(ARRAY[
    'a1b2c3d4-e5f6-7890-abcd-ef1234567890'::UUID,
    'b2c3d4e5-f6a7-8901-bcde-f01234567891'::UUID
])
  AND status = 'published';
