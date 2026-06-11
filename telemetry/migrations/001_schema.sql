CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE IF NOT EXISTS order_events (
  time           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  submission_id  TEXT NOT NULL,
  bot_id         INTEGER,
  order_id       TEXT,
  latency_ms     DOUBLE PRECISION,
  status_code    INTEGER,
  order_type     TEXT,
  side           TEXT,
  price          DOUBLE PRECISION,
  quantity       INTEGER,
  accepted       BOOLEAN DEFAULT TRUE
);

SELECT create_hypertable('order_events', 'time', if_not_exists => TRUE);

CREATE INDEX IF NOT EXISTS idx_submission ON order_events (submission_id, time DESC);

CREATE OR REPLACE VIEW latency_stats AS
SELECT
  submission_id,
  COUNT(*)                                                          AS total_orders,
  ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p50_ms,
  ROUND(percentile_cont(0.90) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p90_ms,
  ROUND(percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms)::numeric, 2) AS p99_ms,
  ROUND((COUNT(*) / EXTRACT(EPOCH FROM (MAX(time) - MIN(time))))::numeric, 2)  AS tps,
  ROUND((SUM(CASE WHEN accepted THEN 1 ELSE 0 END)::numeric / COUNT(*) * 100), 2) AS correctness_pct
FROM order_events
GROUP BY submission_id;
