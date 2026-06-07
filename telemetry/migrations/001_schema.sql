 
CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE order_events (
  time          TIMESTAMPTZ NOT NULL,
  submission_id TEXT,
  bot_id        INT,
  order_id      TEXT,
  latency_ms    FLOAT,
  status_code   INT,
  order_type    TEXT,
  accepted      BOOLEAN
);

SELECT create_hypertable('order_events', 'time');

-- Latency percentiles query
CREATE VIEW latency_stats AS
SELECT
  submission_id,
  percentile_cont(0.50) WITHIN GROUP (ORDER BY latency_ms) AS p50,
  percentile_cont(0.90) WITHIN GROUP (ORDER BY latency_ms) AS p90,
  percentile_cont(0.99) WITHIN GROUP (ORDER BY latency_ms) AS p99,
  COUNT(*) AS total_orders
FROM order_events
GROUP BY submission_id;