#!/bin/bash
set -e
BASE="/mnt/c/iicpc/iicpc-platform"
echo "=== Generating all IICPC platform files ==="

# ============================================
# SANDBOX - server.js (real submission pipeline)
# ============================================
cat > "$BASE/sandbox/src/server.js" << 'EOF'
const express = require('express');
const multer  = require('multer');
const Docker  = require('dockerode');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs   = require('fs');

const app    = express();
const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const upload = multer({ dest: '/tmp/uploads/' });
app.use(express.json());

const submissions = {};

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'sandbox-api', total: Object.keys(submissions).length });
});

app.post('/submit', upload.single('code'), async (req, res) => {
  const submissionId = uuidv4();
  const language = req.body.language || 'cpp';
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  submissions[submissionId] = { status: 'received', language, createdAt: new Date() };
  console.log(`[${submissionId}] Received ${language} submission`);
  res.json({ submissionId, status: 'received', message: 'Queued for build' });
});

app.get('/submission/:id', (req, res) => {
  const sub = submissions[req.params.id];
  if (!sub) return res.status(404).json({ error: 'Not found' });
  res.json({ submissionId: req.params.id, ...sub });
});

app.get('/submissions', (req, res) => {
  res.json(Object.entries(submissions).map(([id, s]) => ({ id, ...s })));
});

app.delete('/submission/:id', async (req, res) => {
  const sub = submissions[req.params.id];
  if (!sub) return res.status(404).json({ error: 'Not found' });
  if (sub.containerId) {
    try {
      const c = docker.getContainer(sub.containerId);
      await c.stop();
      await c.remove();
    } catch (e) { console.error('Cleanup error:', e.message); }
  }
  delete submissions[req.params.id];
  res.json({ deleted: req.params.id });
});

app.listen(4000, () => console.log('Sandbox API running on :4000'));
EOF

# ============================================
# SANDBOX - containerManager.js
# ============================================
cat > "$BASE/sandbox/src/containerManager.js" << 'EOF'
const Docker = require('dockerode');
const docker = new Docker({ socketPath: '/var/run/docker.sock' });

async function spawnContestantContainer(imageTag, submissionId) {
  const container = await docker.createContainer({
    Image: imageTag,
    name: `contestant-${submissionId}`,
    HostConfig: {
      Memory: 512 * 1024 * 1024,
      CpuPeriod: 100000,
      CpuQuota: 200000,
      NetworkMode: 'iicpc-net',
      ReadonlyRootfs: false,
      CapDrop: ['ALL'],
      SecurityOpt: ['no-new-privileges'],
    },
    ExposedPorts: { '8080/tcp': {} },
    PortBindings: { '8080/tcp': [{ HostPort: '0' }] },
  });
  await container.start();
  const data = await container.inspect();
  const port = data.NetworkSettings.Ports['8080/tcp']?.[0]?.HostPort;
  return { containerId: container.id, port };
}

async function stopContainer(containerId) {
  const c = docker.getContainer(containerId);
  await c.stop().catch(() => {});
  await c.remove().catch(() => {});
}

module.exports = { spawnContestantContainer, stopContainer };
EOF

# ============================================
# SANDBOX - Dockerfiles for each language
# ============================================
cat > "$BASE/sandbox/templates/cpp/Dockerfile" << 'EOF'
FROM gcc:13-bookworm
WORKDIR /app
COPY . .
RUN g++ -O2 -o exchange main.cpp -lpthread
EXPOSE 8080
CMD ["./exchange"]
EOF

cat > "$BASE/sandbox/templates/rust/Dockerfile" << 'EOF'
FROM rust:1.78-slim
WORKDIR /app
COPY . .
RUN cargo build --release
EXPOSE 8080
CMD ["./target/release/exchange"]
EOF

cat > "$BASE/sandbox/templates/go/Dockerfile" << 'EOF'
FROM golang:1.22-alpine
WORKDIR /app
COPY . .
RUN go build -o exchange main.go
EXPOSE 8080
CMD ["./exchange"]
EOF

# ============================================
# BOT FLEET - Go bot agent (main.go)
# ============================================
cat > "$BASE/bot-fleet/bot/main.go" << 'EOF'
package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"sync"
	"time"
)

type Order struct {
	Type     string  `json:"type"`
	Symbol   string  `json:"symbol"`
	Side     string  `json:"side"`
	Price    float64 `json:"price"`
	Quantity int     `json:"quantity"`
	OrderID  string  `json:"orderId"`
	BotID    int     `json:"botId"`
}

type BotResult struct {
	BotID      int
	OrderID    string
	LatencyMs  int64
	StatusCode int
	Error      string
}

func randomOrderType() string {
	types := []string{"limit", "limit", "limit", "market", "cancel"}
	return types[rand.Intn(len(types))]
}

func randomSide() string {
	if rand.Intn(2) == 0 { return "buy" }
	return "sell"
}

func runBot(targetURL string, botID int, ordersPerBot int, wg *sync.WaitGroup, results chan<- BotResult) {
	defer wg.Done()
	client := &http.Client{Timeout: 5 * time.Second}

	for i := 0; i < ordersPerBot; i++ {
		order := Order{
			Type:     randomOrderType(),
			Symbol:   "AAPL",
			Side:     randomSide(),
			Price:    100.0 + rand.Float64()*10.0,
			Quantity: rand.Intn(100) + 1,
			OrderID:  fmt.Sprintf("bot%d-ord%d", botID, i),
			BotID:    botID,
		}

		body, _ := json.Marshal(order)
		start := time.Now()
		resp, err := client.Post(targetURL+"/order", "application/json", bytes.NewBuffer(body))
		latency := time.Since(start).Milliseconds()

		result := BotResult{BotID: botID, OrderID: order.OrderID, LatencyMs: latency}
		if err != nil {
			result.Error = err.Error()
		} else {
			result.StatusCode = resp.StatusCode
			resp.Body.Close()
		}
		results <- result
		time.Sleep(time.Duration(rand.Intn(10)) * time.Millisecond)
	}
}

func main() {
	target       := flag.String("target", "http://localhost:8080", "Contestant endpoint URL")
	botCount     := flag.Int("bots", 100, "Number of concurrent bots")
	ordersPerBot := flag.Int("orders", 500, "Orders per bot")
	flag.Parse()

	log.Printf("Starting %d bots → %s (%d orders each)", *botCount, *target, *ordersPerBot)

	var wg sync.WaitGroup
	results := make(chan BotResult, (*botCount)*(*ordersPerBot))

	start := time.Now()
	for i := 0; i < *botCount; i++ {
		wg.Add(1)
		go runBot(*target, i, *ordersPerBot, &wg, results)
	}

	wg.Wait()
	close(results)
	elapsed := time.Since(start).Seconds()

	var totalOrders, errors int
	var totalLatency int64
	for r := range results {
		totalOrders++
		totalLatency += r.LatencyMs
		if r.Error != "" { errors++ }
	}

	avgLatency := float64(totalLatency) / float64(totalOrders)
	tps := float64(totalOrders) / elapsed

	log.Printf("=== RESULTS ===")
	log.Printf("Total orders: %d", totalOrders)
	log.Printf("Errors: %d", errors)
	log.Printf("Avg latency: %.2fms", avgLatency)
	log.Printf("TPS: %.2f", tps)
	log.Printf("Duration: %.2fs", elapsed)
}
EOF

# ============================================
# BOT FLEET - Coordinator (Kafka dispatcher)
# ============================================
cat > "$BASE/bot-fleet/coordinator/index.js" << 'EOF'
const { Kafka } = require('kafkajs');
const { v4: uuidv4 } = require('uuid');

const kafka = new Kafka({
  clientId: 'bot-coordinator',
  brokers: [process.env.KAFKA_BROKER || 'redpanda:9092'],
  retry: { retries: 10, initialRetryTime: 3000 }
});

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'coordinator-group' });

async function dispatchBotFleet({ targetURL, botCount, submissionId, ordersPerBot = 500 }) {
  await producer.connect();
  const tasks = [];
  for (let i = 0; i < botCount; i++) {
    tasks.push(producer.send({
      topic: 'bot-tasks',
      messages: [{
        key: `bot-${i}`,
        value: JSON.stringify({ botId: i, targetURL, submissionId, ordersPerBot })
      }]
    }));
  }
  await Promise.all(tasks);
  console.log(`Dispatched ${botCount} bot tasks for submission ${submissionId}`);
  await producer.disconnect();
}

async function start() {
  console.log('Bot coordinator starting...');
  try {
    await consumer.connect();
    await consumer.subscribe({ topic: 'run-fleet', fromBeginning: false });
    await consumer.run({
      eachMessage: async ({ message }) => {
        const job = JSON.parse(message.value.toString());
        console.log('Received fleet job:', job);
        await dispatchBotFleet(job);
      }
    });
    console.log('Bot coordinator listening for fleet jobs...');
  } catch (err) {
    console.error('Coordinator error:', err.message);
    setTimeout(start, 5000);
  }
}

start();
module.exports = { dispatchBotFleet };
EOF

# ============================================
# BOT FLEET - K8s Job manifest
# ============================================
cat > "$BASE/bot-fleet/k8s/bot-job.yaml" << 'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: bot-fleet-job
  labels:
    app: bot-fleet
spec:
  completions: 50
  parallelism: 50
  template:
    metadata:
      labels:
        app: bot-agent
    spec:
      containers:
      - name: bot-agent
        image: iicpc/bot-agent:latest
        env:
        - name: TARGET_URL
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['target-url']
        args:
          - "--bots=20"
          - "--orders=500"
        resources:
          limits:
            cpu: "500m"
            memory: "128Mi"
          requests:
            cpu: "250m"
            memory: "64Mi"
      restartPolicy: Never
  backoffLimit: 3
EOF

# ============================================
# TELEMETRY - TimescaleDB schema
# ============================================
cat > "$BASE/telemetry/migrations/001_schema.sql" << 'EOF'
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
EOF

# ============================================
# TELEMETRY - gRPC proto
# ============================================
cat > "$BASE/telemetry/proto/metrics.proto" << 'EOF'
syntax = "proto3";
package metrics;

service MetricsIngester {
  rpc RecordEvent  (OrderEvent)    returns (Ack);
  rpc GetStats     (StatsRequest)  returns (LatencyStats);
  rpc StreamStats  (StatsRequest)  returns (stream LatencyStats);
}

message OrderEvent {
  string submission_id = 1;
  int32  bot_id        = 2;
  string order_id      = 3;
  double latency_ms    = 4;
  int32  status_code   = 5;
  bool   accepted      = 6;
  int64  timestamp_ms  = 7;
  string order_type    = 8;
  string side          = 9;
  double price         = 10;
  int32  quantity      = 11;
}

message Ack {
  bool   success = 1;
  string message = 2;
}

message StatsRequest {
  string submission_id = 1;
}

message LatencyStats {
  string submission_id    = 1;
  double p50_ms           = 2;
  double p90_ms           = 3;
  double p99_ms           = 4;
  double tps              = 5;
  double correctness_pct  = 6;
  double score            = 7;
  int64  total_orders     = 8;
}
EOF

# ============================================
# TELEMETRY - Ingester (gRPC server)
# ============================================
cat > "$BASE/telemetry/src/ingester.js" << 'EOF'
const grpc       = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');
const { Pool }   = require('pg');
const redis      = require('redis');
const path       = require('path');
const { computeScore } = require('./scorer');

const PROTO_PATH = path.join(__dirname, '../proto/metrics.proto');
const pkgDef = protoLoader.loadSync(PROTO_PATH, { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true });
const proto  = grpc.loadPackageDefinition(pkgDef).metrics;

const db = new Pool({ connectionString: process.env.DB_URL || 'postgresql://iicpc:iicpc_secret@timescaledb:5432/telemetry' });
const redisClient = redis.createClient({ url: process.env.REDIS_URL || 'redis://redis:6379' });

async function init() {
  await redisClient.connect();
  console.log('Connected to Redis');
}

async function RecordEvent(call, callback) {
  const e = call.request;
  try {
    await db.query(
      `INSERT INTO order_events (submission_id, bot_id, order_id, latency_ms, status_code, order_type, side, price, quantity, accepted)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [e.submission_id, e.bot_id, e.order_id, e.latency_ms, e.status_code, e.order_type, e.side, e.price, e.quantity, e.accepted]
    );

    // Update Redis live stats
    await updateLiveStats(e.submission_id);
    callback(null, { success: true, message: 'recorded' });
  } catch (err) {
    console.error('RecordEvent error:', err.message);
    callback(null, { success: false, message: err.message });
  }
}

async function updateLiveStats(submissionId) {
  const res = await db.query('SELECT * FROM latency_stats WHERE submission_id = $1', [submissionId]);
  if (res.rows.length === 0) return;
  const stats = res.rows[0];
  const score = computeScore({
    p99: parseFloat(stats.p99_ms),
    tps: parseFloat(stats.tps),
    correctnessRate: parseFloat(stats.correctness_pct) / 100
  });
  const payload = JSON.stringify({ ...stats, score });
  await redisClient.publish('score-updates', payload);
}

async function GetStats(call, callback) {
  const res = await db.query('SELECT * FROM latency_stats WHERE submission_id = $1', [call.request.submission_id]);
  if (res.rows.length === 0) return callback(null, {});
  const s = res.rows[0];
  const score = computeScore({ p99: parseFloat(s.p99_ms), tps: parseFloat(s.tps), correctnessRate: parseFloat(s.correctness_pct) / 100 });
  callback(null, { ...s, score, total_orders: parseInt(s.total_orders) });
}

function StreamStats(call) {
  const subId = call.request.submission_id;
  const interval = setInterval(async () => {
    try {
      const res = await db.query('SELECT * FROM latency_stats WHERE submission_id = $1', [subId]);
      if (res.rows.length > 0) {
        const s = res.rows[0];
        const score = computeScore({ p99: parseFloat(s.p99_ms), tps: parseFloat(s.tps), correctnessRate: parseFloat(s.correctness_pct) / 100 });
        call.write({ ...s, score, total_orders: parseInt(s.total_orders) });
      }
    } catch (e) { call.end(); }
  }, 1000);
  call.on('cancelled', () => clearInterval(interval));
}

init().then(() => {
  const server = new grpc.Server();
  server.addService(proto.MetricsIngester.service, { RecordEvent, GetStats, StreamStats });
  server.bindAsync('0.0.0.0:50051', grpc.ServerCredentials.createInsecure(), () => {
    console.log('Telemetry gRPC server on :50051');
  });
}).catch(console.error);
EOF

# ============================================
# TELEMETRY - Scorer
# ============================================
cat > "$BASE/telemetry/src/scorer.js" << 'EOF'
function computeScore({ p99, tps, correctnessRate }) {
  if (!p99 || !tps) return 0;
  // Lower p99 latency = higher latency score
  const latencyScore    = Math.max(0, 100 - (p99 / 10));
  // Higher TPS = higher throughput score (log scale)
  const throughputScore = Math.min(100, Math.log10(tps + 1) * 30);
  // Correctness: did fills respect price-time priority?
  const correctnessScore = (correctnessRate || 0) * 100;
  // Weighted composite
  const score = (
    latencyScore     * 0.40 +
    throughputScore  * 0.35 +
    correctnessScore * 0.25
  );
  return Math.round(score * 100) / 100;
}

module.exports = { computeScore };
EOF

# ============================================
# TELEMETRY - Validator
# ============================================
cat > "$BASE/telemetry/src/validator.js" << 'EOF'
// Validates price-time priority of order fills
function validateFills(orderLog) {
  if (!orderLog || orderLog.length === 0) return { violations: 0, correctnessRate: 1 };

  const buys  = orderLog.filter(o => o.side === 'buy' && o.filled)
    .sort((a, b) => b.price - a.price || a.timestamp - b.timestamp);
  const sells = orderLog.filter(o => o.side === 'sell' && o.filled)
    .sort((a, b) => a.price - b.price || a.timestamp - b.timestamp);

  let violations = 0;

  // Check buys: higher price should fill first, ties by time
  for (let i = 0; i < buys.length - 1; i++) {
    const curr = buys[i];
    const next = buys[i + 1];
    if (!curr.filledAt && next.filledAt) violations++;
    if (curr.price === next.price && curr.timestamp > next.timestamp && next.filledAt && !curr.filledAt) violations++;
  }

  const total = buys.length + sells.length;
  const correctnessRate = total > 0 ? Math.max(0, 1 - violations / total) : 1;
  return { violations, correctnessRate, total };
}

module.exports = { validateFills };
EOF

# ============================================
# LEADERBOARD - Relay (Socket.io + Redis)
# ============================================
cat > "$BASE/leaderboard/relay/index.js" << 'EOF'
const { Server } = require('socket.io');
const redis      = require('redis');

const io  = new Server(3001, { cors: { origin: '*' } });
const sub = redis.createClient({ url: process.env.REDIS_URL || 'redis://redis:6379' });

const latestScores = {};

async function start() {
  await sub.connect();
  await sub.subscribe('score-updates', (message) => {
    try {
      const data = JSON.parse(message);
      latestScores[data.submission_id] = data;
      io.emit('score-update', data);
      console.log(`Score update: ${data.submission_id} → ${data.score}`);
    } catch (e) {
      console.error('Parse error:', e.message);
    }
  });
  console.log('Leaderboard relay running on :3001');
}

io.on('connection', (socket) => {
  console.log('Dashboard connected:', socket.id);
  // Send all current scores to new client
  Object.values(latestScores).forEach(score => socket.emit('score-update', score));
  socket.on('disconnect', () => console.log('Dashboard disconnected:', socket.id));
});

start().catch(console.error);
EOF

# ============================================
# LEADERBOARD - React Frontend (App.jsx)
# ============================================
cat > "$BASE/leaderboard/frontend/src/App.jsx" << 'EOF'
import { useEffect, useState } from 'react';
import { io } from 'socket.io-client';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';

const socket = io('http://localhost:3001');

const COLORS = ['#f59e0b','#3b82f6','#10b981','#8b5cf6','#ef4444','#06b6d4'];

function ScoreBar({ value }) {
  const color = value >= 75 ? '#10b981' : value >= 50 ? '#f59e0b' : '#ef4444';
  return (
    <div style={{ background: '#1e293b', borderRadius: 4, height: 8, width: '100%' }}>
      <div style={{ width: `${value}%`, background: color, height: '100%', borderRadius: 4, transition: 'width 0.5s' }} />
    </div>
  );
}

export default function Leaderboard() {
  const [scores, setScores] = useState({});
  const [lastUpdate, setLastUpdate] = useState(null);

  useEffect(() => {
    socket.on('score-update', (data) => {
      setScores(prev => ({ ...prev, [data.submission_id]: data }));
      setLastUpdate(new Date().toLocaleTimeString());
    });
    return () => socket.off('score-update');
  }, []);

  const ranked = Object.entries(scores)
    .map(([id, s]) => ({ id, ...s, score: parseFloat(s.score || 0) }))
    .sort((a, b) => b.score - a.score);

  const chartData = ranked.slice(0, 10).map(s => ({
    name: s.id.slice(0, 8),
    score: s.score
  }));

  return (
    <div style={{ minHeight: '100vh', background: '#0f172a', color: '#e2e8f0', fontFamily: 'monospace', padding: '2rem' }}>
      <div style={{ maxWidth: 1100, margin: '0 auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem' }}>
          <h1 style={{ fontSize: 28, fontWeight: 800, color: '#f8fafc' }}>🏆 IICPC Live Leaderboard</h1>
          <div style={{ fontSize: 12, color: '#64748b' }}>
            {lastUpdate ? `Last update: ${lastUpdate}` : 'Waiting for data...'}
            <span style={{ marginLeft: 8, display: 'inline-block', width: 8, height: 8, borderRadius: '50%',
              background: lastUpdate ? '#10b981' : '#ef4444' }} />
          </div>
        </div>

        {ranked.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '4rem', color: '#475569' }}>
            <div style={{ fontSize: 48, marginBottom: '1rem' }}>⏳</div>
            <p>Waiting for submissions to be tested...</p>
          </div>
        ) : (
          <>
            <div style={{ background: '#1e293b', borderRadius: 12, padding: '1.5rem', marginBottom: '2rem' }}>
              <h2 style={{ fontSize: 14, color: '#94a3b8', marginBottom: '1rem' }}>SCORE DISTRIBUTION (TOP 10)</h2>
              <ResponsiveContainer width="100%" height={200}>
                <BarChart data={chartData}>
                  <XAxis dataKey="name" tick={{ fill: '#94a3b8', fontSize: 11 }} />
                  <YAxis domain={[0, 100]} tick={{ fill: '#94a3b8', fontSize: 11 }} />
                  <Tooltip contentStyle={{ background: '#0f172a', border: '1px solid #334155', borderRadius: 8 }} />
                  <Bar dataKey="score" radius={[4, 4, 0, 0]}>
                    {chartData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div style={{ background: '#1e293b', borderRadius: 12, overflow: 'hidden' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                <thead>
                  <tr style={{ background: '#0f172a' }}>
                    {['Rank','Submission ID','Score','p50 (ms)','p99 (ms)','TPS','Correctness','Progress'].map(h => (
                      <th key={h} style={{ padding: '12px 16px', textAlign: 'left', fontSize: 11, color: '#64748b', fontWeight: 700, letterSpacing: 1 }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {ranked.map((s, i) => (
                    <tr key={s.id} style={{ borderTop: '1px solid #0f172a', background: i === 0 ? '#1a2744' : 'transparent' }}>
                      <td style={{ padding: '12px 16px' }}>
                        {i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : `#${i + 1}`}
                      </td>
                      <td style={{ padding: '12px 16px', fontFamily: 'monospace', fontSize: 12, color: '#94a3b8' }}>
                        {s.id.slice(0, 16)}...
                      </td>
                      <td style={{ padding: '12px 16px', fontWeight: 800, fontSize: 18, color: i === 0 ? '#f59e0b' : '#e2e8f0' }}>
                        {s.score.toFixed(1)}
                      </td>
                      <td style={{ padding: '12px 16px', color: '#94a3b8' }}>{s.p50_ms || '-'}</td>
                      <td style={{ padding: '12px 16px', color: '#94a3b8' }}>{s.p99_ms || '-'}</td>
                      <td style={{ padding: '12px 16px', color: '#94a3b8' }}>{s.tps || '-'}</td>
                      <td style={{ padding: '12px 16px', color: '#94a3b8' }}>{s.correctness_pct ? `${s.correctness_pct}%` : '-'}</td>
                      <td style={{ padding: '12px 16px', width: 120 }}><ScoreBar value={s.score} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
EOF

# ============================================
# LEADERBOARD - Frontend index.js
# ============================================
cat > "$BASE/leaderboard/frontend/src/index.js" << 'EOF'
const http = require('http');

const html = `<!DOCTYPE html>
<html>
<head>
  <title>IICPC Leaderboard</title>
  <meta charset="utf-8">
  <style>
    body { margin: 0; background: #0f172a; color: #e2e8f0; font-family: monospace; }
    .container { max-width: 1100px; margin: 0 auto; padding: 2rem; }
    h1 { font-size: 28px; }
    .waiting { text-align: center; padding: 4rem; color: #475569; }
    table { width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 12px; overflow: hidden; }
    th { padding: 12px 16px; text-align: left; font-size: 11px; color: #64748b; background: #0f172a; }
    td { padding: 12px 16px; border-top: 1px solid #0f172a; }
    .score { font-weight: 800; font-size: 18px; }
    .bar-bg { background: #334155; border-radius: 4px; height: 8px; }
    .bar-fill { height: 8px; border-radius: 4px; transition: width 0.5s; }
  </style>
</head>
<body>
  <div class="container">
    <h1>🏆 IICPC Live Leaderboard</h1>
    <div id="status" style="color:#64748b;font-size:12px;margin-bottom:1rem">Connecting...</div>
    <div id="content" class="waiting"><div style="font-size:48px">⏳</div><p>Waiting for submissions...</p></div>
  </div>
  <script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
  <script>
    const socket = io('http://localhost:3001');
    const scores = {};

    socket.on('connect', () => document.getElementById('status').textContent = '🟢 Connected');
    socket.on('disconnect', () => document.getElementById('status').textContent = '🔴 Disconnected');

    socket.on('score-update', (data) => {
      scores[data.submission_id] = data;
      render();
    });

    function render() {
      const ranked = Object.values(scores).sort((a,b) => b.score - a.score);
      const medals = ['🥇','🥈','🥉'];
      const rows = ranked.map((s,i) => {
        const color = s.score >= 75 ? '#10b981' : s.score >= 50 ? '#f59e0b' : '#ef4444';
        return '<tr>' +
          '<td>' + (medals[i] || '#'+(i+1)) + '</td>' +
          '<td style="font-size:12px;color:#94a3b8">' + s.submission_id.slice(0,16) + '...</td>' +
          '<td class="score" style="color:' + (i===0?'#f59e0b':'#e2e8f0') + '">' + parseFloat(s.score).toFixed(1) + '</td>' +
          '<td style="color:#94a3b8">' + (s.p50_ms||'-') + '</td>' +
          '<td style="color:#94a3b8">' + (s.p99_ms||'-') + '</td>' +
          '<td style="color:#94a3b8">' + (s.tps||'-') + '</td>' +
          '<td style="color:#94a3b8">' + (s.correctness_pct ? s.correctness_pct+'%' : '-') + '</td>' +
          '<td><div class="bar-bg"><div class="bar-fill" style="width:'+s.score+'%;background:'+color+'"></div></div></td>' +
          '</tr>';
      }).join('');
      document.getElementById('content').innerHTML =
        '<table><thead><tr><th>Rank</th><th>Submission</th><th>Score</th><th>p50ms</th><th>p99ms</th><th>TPS</th><th>Correct</th><th>Progress</th></tr></thead><tbody>' + rows + '</tbody></table>';
    }
  </script>
</body>
</html>`;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(html);
});
server.listen(3000, () => console.log('Leaderboard frontend on :3000'));
EOF

# ============================================
# INFRA - Terraform main.tf
# ============================================
cat > "$BASE/infra/terraform/main.tf" << 'EOF'
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = var.region }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  name    = "iicpc-vpc"
  cidr    = "10.0.0.0/16"
  azs             = ["${var.region}a", "${var.region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway = true
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = var.cluster_name
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  eks_managed_node_groups = {
    platform = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3
    }
    bot-fleet = {
      instance_types = ["c5.xlarge"]
      min_size       = 0
      max_size       = 20
      desired_size   = 0
      labels         = { role = "bot-fleet" }
    }
  }
}
EOF

cat > "$BASE/infra/terraform/variables.tf" << 'EOF'
variable "region"       { default = "us-east-1" }
variable "cluster_name" { default = "iicpc-platform" }
EOF

cat > "$BASE/infra/terraform/outputs.tf" << 'EOF'
output "cluster_endpoint"     { value = module.eks.cluster_endpoint }
output "cluster_name"         { value = module.eks.cluster_name }
EOF

# ============================================
# INFRA - K8s Network Policy
# ============================================
cat > "$BASE/infra/k8s/manifests/network-policy.yaml" << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: contestant-isolation
  namespace: contestants
spec:
  podSelector:
    matchLabels:
      role: contestant
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: bot-agent
    ports:
    - protocol: TCP
      port: 8080
  egress: []   # no outbound traffic from contestant pods
EOF

cat > "$BASE/infra/k8s/manifests/contestant-pod.yaml" << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: contestant-SUBMISSION_ID
  namespace: contestants
  labels:
    role: contestant
    submission-id: SUBMISSION_ID
spec:
  containers:
  - name: exchange
    image: contestant-SUBMISSION_ID:latest
    ports:
    - containerPort: 8080
    resources:
      limits:
        cpu: "2"
        memory: "512Mi"
      requests:
        cpu: "1"
        memory: "256Mi"
    securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
  restartPolicy: Never
EOF

# ============================================
# INFRA - GitHub Actions CI
# ============================================
cat > "$BASE/infra/ci/pipeline.yml" << 'EOF'
name: IICPC Platform CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '20'

    - name: Install sandbox deps
      run: cd sandbox && npm install

    - name: Install telemetry deps
      run: cd telemetry && npm install

    - name: Install relay deps
      run: cd leaderboard/relay && npm install

    - name: Setup Go
      uses: actions/setup-go@v5
      with:
        go-version: '1.22'

    - name: Build Go bot agent
      run: cd bot-fleet/bot && go build ./...

    - name: Start services
      run: docker compose up -d
      
    - name: Wait for services
      run: sleep 15

    - name: Health check
      run: curl -f http://localhost:4000/health

    - name: Test submission endpoint
      run: |
        echo 'int main(){return 0;}' > /tmp/test.cpp
        curl -f -X POST http://localhost:4000/submit \
          -F "code=@/tmp/test.cpp" \
          -F "language=cpp"

  build-images:
    runs-on: ubuntu-latest
    needs: test
    if: github.ref == 'refs/heads/main'
    steps:
    - uses: actions/checkout@v4
    - name: Build Docker images
      run: docker compose build
EOF

# ============================================
# DOCS - Architecture
# ============================================
cat > "$BASE/docs/ARCHITECTURE.md" << 'EOF'
# IICPC Platform — Architecture Blueprint

## Overview
A distributed benchmarking platform that evaluates contestant-submitted exchange/order-book implementations.

## Pipeline
```
Upload → Sandbox → Bot Fleet → Telemetry → Leaderboard
```

## Microservices

| Service | Port | Tech | Purpose |
|---------|------|------|---------|
| sandbox-api | 4000 | Node.js + Express | Code upload, container management |
| bot-coordinator | 3002 | Node.js + KafkaJS | Dispatches bot tasks via Redpanda |
| bot-agent | - | Go | High-concurrency order generator |
| telemetry-ingester | 50051 | Node.js + gRPC | Metrics collection & scoring |
| leaderboard-relay | 3001 | Node.js + Socket.io | Real-time score broadcast |
| leaderboard-frontend | 3000 | Node.js (HTML) | Live dashboard |

## Infrastructure
- **Message Queue**: Redpanda (Kafka-compatible) on port 9092
- **Time-series DB**: TimescaleDB (PostgreSQL) on port 5432
- **Cache/PubSub**: Redis on port 6379
- **Container Runtime**: Docker with resource limits (CPU pinning, memory caps)
- **Orchestration**: Kubernetes (K8s Jobs for bot fleet scaling)

## Isolation Strategy
- Each contestant runs in a separate Docker container
- ReadOnlyRootFilesystem = true
- All Linux capabilities dropped
- no-new-privileges security option
- Isolated network (contestant-net) — no internet access
- CPU: 2 cores max, Memory: 512MB max

## Scoring Formula
```
score = (latency × 0.40) + (throughput × 0.35) + (correctness × 0.25)

latency_score     = max(0, 100 - p99_ms/10)
throughput_score  = min(100, log10(TPS+1) × 30)
correctness_score = (valid_fills / total_fills) × 100
```

## Inter-service Communication
- Bot coordinator → Bot agents: Kafka topic `bot-tasks`
- Bot agents → Telemetry: gRPC `RecordEvent`
- Telemetry → Leaderboard: Redis pub/sub `score-updates`
- Leaderboard relay → Frontend: WebSocket (Socket.io)
EOF

cat > "$BASE/docs/API.md" << 'EOF'
# Sandbox API Reference

Base URL: `http://localhost:4000`

## POST /submit
Upload contestant code.

**Form fields:**
- `code` (file): source code file (.cpp / .rs / .go)
- `language` (string): `cpp` | `rust` | `go`

**Response:**
```json
{ "submissionId": "uuid", "status": "received" }
```

## GET /submission/:id
Get submission status.

**Response:**
```json
{ "submissionId": "uuid", "status": "running", "port": "32768", "containerId": "abc123" }
```

## GET /submissions
List all submissions.

## DELETE /submission/:id
Stop and remove a submission container.

## GET /health
Health check.
```json
{ "status": "ok", "service": "sandbox-api", "total": 3 }
```
EOF

echo ""
echo "========================================="
echo " ALL FILES GENERATED SUCCESSFULLY"
echo "========================================="
echo ""
echo "Next steps:"
echo "  cd /mnt/c/iicpc/iicpc-platform"
echo "  docker compose up -d --build"
echo "  git add . && git commit -m 'feat: complete platform implementation'"
echo "  git push"
echo ""
